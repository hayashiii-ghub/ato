import Darwin
import Foundation
import UsageCore

enum AntigravityUsageError: Error, Equatable {
    case cliUnavailable, unsupportedCLI, invalidResponse, requestFailed, timedOut

    var state: UsageState {
        switch self {
        case .cliUnavailable, .unsupportedCLI: return .setupRequired
        case .invalidResponse, .requestFailed, .timedOut: return .unavailable
        }
    }
}

enum AntigravityUsageClient {
    static let usageArguments = ["--print", "/usage", "--output-format", "json", "--log-file", "/dev/null"]

    static func executable(home: URL = FileManager.default.homeDirectoryForCurrentUser,
                           isExecutable: (String) -> Bool = FileManager.default.isExecutableFile(atPath:)) -> URL? {
        ["/opt/homebrew/bin/agy", "/usr/local/bin/agy", home.appendingPathComponent(".local/bin/agy").path]
            .first(where: isExecutable).map { URL(fileURLWithPath: $0).resolvingSymlinksInPath() }
    }

    static func fetch() async -> ServiceUsage {
        guard let executable = executable() else { return ServiceUsage(service: .gemini, state: .setupRequired) }
        do {
            return try await read(executable: executable)
        } catch let error as AntigravityUsageError {
            return ServiceUsage(service: .gemini, state: error.state)
        } catch {
            return ServiceUsage(service: .gemini, state: .unavailable)
        }
    }

    static func read(executable: URL, arguments: [String] = usageArguments,
                     versionArguments: [String] = ["--version"], timeout: TimeInterval = 20) async throws -> ServiceUsage {
        // Earlier versions could send /usage to the agent instead of answering it themselves.
        // https://github.com/google-antigravity/antigravity-cli/blob/main/CHANGELOG.md#1111
        let version = try await run(executable, arguments: versionArguments, timeout: min(timeout, 3))
        guard supportedVersion(version) else { throw AntigravityUsageError.unsupportedCLI }
        let data = try await run(executable, arguments: arguments, timeout: timeout)
        return try AntigravityUsageParser.parse(data)
    }

    static func supportedVersion(_ data: Data) -> Bool {
        guard let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) else { return false }
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3, parts.allSatisfy({ !$0.isEmpty && $0.utf8.allSatisfy({ (48...57).contains($0) }) }),
              let major = Int(parts[0]), let minor = Int(parts[1]), let patch = Int(parts[2]) else { return false }
        return major > 1 || (major == 1 && (minor > 1 || (minor == 1 && patch >= 11)))
    }

    private static func run(_ executable: URL, arguments: [String], timeout: TimeInterval) async throws -> Data {
        let process = AntigravityUsageProcess(executable: executable, arguments: arguments, timeout: timeout)
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await process.read()
        } onCancel: { process.cancel() }
    }
}

private final class AntigravityUsageProcess: @unchecked Sendable {
    private let queue = DispatchQueue(label: "UsageRings.AntigravityUsage")
    private let executable: URL
    private let arguments: [String]
    private let timeout: TimeInterval
    private var continuation: CheckedContinuation<Data, Error>?
    private var outcome: Result<Data, Error>?
    private var cancelled = false
    private var pid: pid_t = 0
    private var outputFD: Int32 = -1
    private var outputSource: DispatchSourceRead?
    private var processSource: DispatchSourceProcess?
    private var timer: DispatchSourceTimer?
    private var directory: URL?
    private var buffer = Data()

    init(executable: URL, arguments: [String], timeout: TimeInterval) {
        self.executable = executable
        self.arguments = arguments
        self.timeout = max(0.01, min(timeout, 60))
    }

    func read() async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                self.continuation = continuation
                if self.cancelled { self.stop(CancellationError()); return }
                self.start()
            }
        }
    }

    func cancel() {
        queue.async {
            self.cancelled = true
            if self.continuation != nil { self.stop(CancellationError()) }
        }
    }

    private func start() {
        do {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("usage-rings-agy-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false,
                                                    attributes: [.posixPermissions: 0o700])
            self.directory = directory
            try spawn(in: directory)
            let output = DispatchSource.makeReadSource(fileDescriptor: outputFD, queue: queue)
            output.setEventHandler { [weak self] in self?.drainOutput() }
            outputSource = output
            output.resume()
            let child = DispatchSource.makeProcessSource(identifier: pid, eventMask: .exit, queue: queue)
            child.setEventHandler { [weak self] in self?.childExited() }
            processSource = child
            child.resume()
            let deadline = DispatchSource.makeTimerSource(queue: queue)
            deadline.schedule(deadline: .now() + timeout)
            deadline.setEventHandler { [weak self] in self?.stop(AntigravityUsageError.timedOut) }
            timer = deadline
            deadline.resume()
        } catch { stop(error) }
    }

    private func spawn(in directory: URL) throws {
        var output: [Int32] = [-1, -1]
        guard pipe(&output) == 0 else { throw AntigravityUsageError.requestFailed }
        defer {
            close(output[1])
            if pid == 0 { close(output[0]) }
        }
        var actions: posix_spawn_file_actions_t?
        var attributes: posix_spawnattr_t?
        guard posix_spawn_file_actions_init(&actions) == 0 else { throw AntigravityUsageError.requestFailed }
        defer { posix_spawn_file_actions_destroy(&actions) }
        guard posix_spawnattr_init(&attributes) == 0 else { throw AntigravityUsageError.requestFailed }
        defer { posix_spawnattr_destroy(&attributes) }
        let setup = [
            posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_CLOEXEC_DEFAULT)),
            posix_spawnattr_setpgroup(&attributes, 0),
            posix_spawn_file_actions_addopen(&actions, STDIN_FILENO, "/dev/null", O_RDONLY, 0),
            posix_spawn_file_actions_adddup2(&actions, output[1], STDOUT_FILENO),
            posix_spawn_file_actions_addopen(&actions, STDERR_FILENO, "/dev/null", O_WRONLY, 0),
            posix_spawn_file_actions_addchdir(&actions, directory.path),
            fcntl(output[0], F_SETFL, O_NONBLOCK)
        ]
        guard setup.allSatisfy({ $0 == 0 }) else { throw AntigravityUsageError.requestFailed }
        let environment = [
            "HOME=\(FileManager.default.homeDirectoryForCurrentUser.path)",
            "PATH=/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin",
            "TMPDIR=\(FileManager.default.temporaryDirectory.path)", "LANG=en_US.UTF-8",
            "AGY_CLI_DISABLE_AUTO_UPDATE=true"
        ]
        let argv = ([executable.path] + arguments).map { strdup($0) } + [nil]
        let envp = environment.map { strdup($0) } + [nil]
        defer { argv.forEach { free($0) }; envp.forEach { free($0) } }
        let result = argv.withUnsafeBufferPointer { argv in
            envp.withUnsafeBufferPointer { envp in
                posix_spawn(&pid, executable.path, &actions, &attributes, argv.baseAddress!, envp.baseAddress!)
            }
        }
        guard result == 0 else {
            pid = 0
            throw result == ENOENT || result == EACCES ? AntigravityUsageError.cliUnavailable : .requestFailed
        }
        outputFD = output[0]
    }

    private func drainOutput() {
        guard outcome == nil, outputFD >= 0 else { return }
        var bytes = [UInt8](repeating: 0, count: 8_192)
        while outcome == nil {
            let count = Darwin.read(outputFD, &bytes, bytes.count)
            if count == 0 { outputSource?.cancel(); outputSource = nil; return }
            if count < 0 {
                if errno == EAGAIN || errno == EWOULDBLOCK { return }
                if errno == EINTR { continue }
                stop(AntigravityUsageError.requestFailed); return
            }
            guard buffer.count + count <= 65_536 else { stop(AntigravityUsageError.invalidResponse); return }
            buffer.append(contentsOf: bytes.prefix(count))
        }
    }

    private func stop(_ error: Error) {
        guard outcome == nil else { return }
        outcome = .failure(error)
        timer?.cancel(); timer = nil
        guard pid > 0 else { finish(); return }
        let group = pid
        _ = kill(-group, SIGTERM)
        queue.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self, self.pid == group else { return }
            _ = kill(-group, SIGKILL)
        }
    }

    private func childExited() {
        guard pid > 0 else { return }
        if outcome == nil { drainOutput() }
        _ = kill(-pid, SIGKILL)
        var status: Int32 = 0
        var result: pid_t
        repeat { result = waitpid(pid, &status, 0) } while result < 0 && errno == EINTR
        pid = 0
        if outcome == nil {
            outcome = result > 0 && status == 0 ? .success(buffer) : .failure(AntigravityUsageError.requestFailed)
        }
        finish()
    }

    private func finish() {
        timer?.cancel(); timer = nil
        outputSource?.cancel(); outputSource = nil
        processSource?.cancel(); processSource = nil
        if outputFD >= 0 { close(outputFD); outputFD = -1 }
        buffer.removeAll(keepingCapacity: false)
        if let directory { try? FileManager.default.removeItem(at: directory) }
        directory = nil
        guard let continuation else { return }
        self.continuation = nil
        continuation.resume(with: outcome ?? .failure(AntigravityUsageError.requestFailed))
    }
}
