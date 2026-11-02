import CryptoKit
import Darwin
import Foundation
import OSLog
import UsageCore
import WidgetKit

struct UsageWidgetProcess: Equatable, Sendable {
    let pid: pid_t
    let userID: uid_t
    let startedAt: String
    let executablePath: String

    static func parse(_ output: String, pid: pid_t) -> Self? {
        let lines = output.split(whereSeparator: \.isNewline)
        guard pid > 0, lines.count == 1 else { return nil }
        let fields = lines[0].split(maxSplits: 6, whereSeparator: \.isWhitespace)
        guard fields.count == 7, let userID = uid_t(fields[0]) else { return nil }
        let path = fields[6].trimmingCharacters(in: .whitespaces)
        guard path.hasPrefix("/"), !path.contains("\0") else { return nil }
        return Self(pid: pid, userID: userID, startedAt: fields[1...5].joined(separator: " "),
                    executablePath: path)
    }
}

protocol UsageWidgetRecoveryClient: Sendable {
    func candidatePIDs() async throws -> [pid_t]
    func inspect(_ pid: pid_t) async throws -> UsageWidgetProcess?
    func terminate(_ pid: pid_t) async throws
}

@MainActor
final class UsageWidgetRecovery {
    private static let historyKey = "usageWidgetRecoveryBuilds"
    private static let log = Logger(subsystem: "work.hayashigoto.UsageRings", category: "WidgetRecovery")
    private let defaults: UserDefaults
    private let client: any UsageWidgetRecoveryClient
    private let userID: uid_t
    private let executablePath: String
    private let installationKey: String
    private let build: String?
    private let exitTimeout: Duration
    private let reload: @MainActor () -> Void
    private var isRunning = false

    init(defaults: UserDefaults = .standard, appURL: URL = Bundle.main.bundleURL,
         version: String? = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
         build: String? = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String,
         userID: uid_t = geteuid(), client: (any UsageWidgetRecoveryClient)? = nil,
         exitTimeout: Duration = .seconds(1),
         reload: @escaping @MainActor () -> Void = { WidgetCenter.shared.reloadTimelines(ofKind: UsageSnapshot.widgetKind) }) {
        self.defaults = defaults
        self.client = client ?? SystemUsageWidgetRecoveryClient()
        self.userID = userID
        self.exitTimeout = exitTimeout
        self.reload = reload
        let appURL = appURL.standardizedFileURL.resolvingSymlinksInPath()
        executablePath = appURL.appendingPathComponent("Contents/PlugIns/UsageRingsWidget.appex/Contents/MacOS/UsageRingsWidget").path
        installationKey = SHA256.hash(data: Data(appURL.path.utf8)).map { String(format: "%02x", $0) }.joined()
        if appURL.pathExtension == "app", let version, !version.isEmpty, let build, !build.isEmpty {
            self.build = "\(version) (\(build))"
        } else { self.build = nil }
    }

    func recoverIfNeeded() async {
        guard !isRunning, let build,
              defaults.dictionary(forKey: Self.historyKey)?[installationKey] as? String != build else { return }
        isRunning = true
        defer { isRunning = false }
        do {
            let clock = ContinuousClock()
            let deadline = clock.now.advanced(by: .seconds(5))
            let pids = try await client.candidatePIDs()
            guard pids.count <= 64 else { throw WidgetRecoveryFailure.invalidOutput }
            for pid in Set(pids).sorted() {
                guard clock.now < deadline else { throw WidgetRecoveryFailure.timedOut }
                guard pid > 0, let candidate = try await client.inspect(pid), matches(candidate, pid: pid) else { continue }
                // Recheck identity immediately before signaling; a reused PID must not target another process.
                guard try await client.inspect(pid) == candidate else { continue }
                guard clock.now < deadline else { throw WidgetRecoveryFailure.timedOut }
                try await client.terminate(pid)
                let exitDeadline = min(deadline, clock.now.advanced(by: exitTimeout))
                var didExit = false
                while clock.now < exitDeadline {
                    if try await client.inspect(pid) != candidate { didExit = true; break }
                    try await Task.sleep(for: .milliseconds(25))
                }
                guard didExit else { throw WidgetRecoveryFailure.timedOut }
            }
            reload()
            var history = defaults.dictionary(forKey: Self.historyKey) as? [String: String] ?? [:]
            history[installationKey] = build
            defaults.set(history, forKey: Self.historyKey)
        } catch {
            Self.log.warning("Widget update recovery did not complete; it will retry on the next launch.")
        }
    }

    private func matches(_ process: UsageWidgetProcess, pid: pid_t) -> Bool {
        process.pid == pid && process.userID == userID && process.executablePath == executablePath
    }
}

private enum WidgetRecoveryFailure: Error { case commandFailed, invalidOutput, timedOut, terminationFailed }

private struct SystemUsageWidgetRecoveryClient: UsageWidgetRecoveryClient {
    func candidatePIDs() async throws -> [pid_t] {
        let result = try await command("/usr/bin/pgrep", ["-x", "UsageRingsWidget"])
        guard result.status == 0 || result.status == 1 else { throw WidgetRecoveryFailure.commandFailed }
        if result.status == 1 { return [] }
        let lines = result.output.split(whereSeparator: \.isNewline)
        let pids = lines.compactMap { pid_t($0) }.filter { $0 > 0 }
        guard pids.count == lines.count else { throw WidgetRecoveryFailure.invalidOutput }
        return pids
    }

    func inspect(_ pid: pid_t) async throws -> UsageWidgetProcess? {
        guard pid > 0 else { return nil }
        let result = try await command("/bin/ps", ["-ww", "-p", String(pid), "-o", "uid=", "-o", "lstart=", "-o", "comm="])
        if result.status == 1 && result.output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return nil }
        guard result.status == 0 else { throw WidgetRecoveryFailure.commandFailed }
        guard let process = UsageWidgetProcess.parse(result.output, pid: pid) else { throw WidgetRecoveryFailure.invalidOutput }
        return process
    }

    func terminate(_ pid: pid_t) async throws {
        guard pid > 0 else { throw WidgetRecoveryFailure.terminationFailed }
        if kill(pid, SIGTERM) != 0 && errno != ESRCH { throw WidgetRecoveryFailure.terminationFailed }
    }

    private func command(_ executable: String, _ arguments: [String]) async throws -> WidgetRecoveryCommandResult {
        try await Task.detached(priority: .utility) {
            try WidgetRecoveryCommandResult.run(executable: executable, arguments: arguments)
        }.value
    }
}

private struct WidgetRecoveryCommandResult: Sendable {
    let status: Int32
    let output: String

    static func run(executable: String, arguments: [String]) throws -> Self {
        let process = Process()
        let pipe = Pipe()
        defer {
            try? pipe.fileHandleForReading.close()
            try? pipe.fileHandleForWriting.close()
        }
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.environment = ["LC_ALL": "C", "PATH": "/usr/bin:/bin"]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try process.run()
        try? pipe.fileHandleForWriting.close()
        defer { if process.isRunning { process.terminate() } }
        let descriptor = pipe.fileHandleForReading.fileDescriptor
        guard fcntl(descriptor, F_SETFL, O_NONBLOCK) >= 0 else { throw WidgetRecoveryFailure.commandFailed }
        let deadline = ProcessInfo.processInfo.systemUptime + 1
        var data = Data()
        var bytes = [UInt8](repeating: 0, count: 4_096)
        var reachedEOF = false
        while ProcessInfo.processInfo.systemUptime < deadline {
            let count = read(descriptor, &bytes, bytes.count)
            if count > 0 {
                data.append(contentsOf: bytes.prefix(count))
                guard data.count <= 16_384 else { throw WidgetRecoveryFailure.invalidOutput }
                continue
            }
            if count == 0 { reachedEOF = true; break }
            if errno == EINTR { continue }
            guard errno == EAGAIN || errno == EWOULDBLOCK else { throw WidgetRecoveryFailure.commandFailed }
            var item = pollfd(fd: descriptor, events: Int16(POLLIN | POLLHUP), revents: 0)
            if poll(&item, 1, 25) < 0 && errno != EINTR { throw WidgetRecoveryFailure.commandFailed }
        }
        while process.isRunning && ProcessInfo.processInfo.systemUptime < deadline { usleep(5_000) }
        guard reachedEOF, !process.isRunning else { throw WidgetRecoveryFailure.timedOut }
        guard let output = String(data: data, encoding: .utf8) else { throw WidgetRecoveryFailure.invalidOutput }
        return Self(status: process.terminationStatus, output: output)
    }
}
