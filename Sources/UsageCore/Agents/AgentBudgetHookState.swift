import Darwin
import Foundation

struct AgentBudgetHookBoundary: Codable {
    let reset: TimeInterval?
    let stage: Int
}

struct AgentBudgetHookWindow: Codable {
    let observed: TimeInterval
    let notices: [AgentBudgetHookBoundary]
}

struct AgentBudgetHookSession: Codable {
    let checkedAt: TimeInterval
    let observed: TimeInterval?
    var windows: [String: AgentBudgetHookWindow]
}

/// An isolated, bounded cache. It stores only hashes, timestamps, and noticed numeric stages.
final class AgentBudgetHookState {
    enum Failure: Error { case missing, unsafeState, oversizedState, invalidState, io }

    private struct FileState: Codable {
        let version: Int
        let sessions: [String: AgentBudgetHookSession]
    }

    private let directory: Int32
    private let lock: Int32

    init(directory url: URL) throws {
        guard AgentBudgetHook.absolutePath(url.path) else { throw Failure.unsafeState }
        if mkdir(url.path, 0o700) != 0 && errno != EEXIST { throw Failure.io }
        let directory = open(url.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard directory >= 0 else { throw Failure.unsafeState }
        do {
            var info = stat()
            guard fstat(directory, &info) == 0, info.st_uid == getuid(),
                  info.st_mode & 0o7777 == 0o700 else { throw Failure.unsafeState }
            let lock = try Self.secureFile(directory, name: "lock", flags: O_RDWR | O_CREAT)
            guard flock(lock, LOCK_EX | LOCK_NB) == 0 else {
                close(lock)
                throw Failure.unsafeState
            }
            self.directory = directory
            self.lock = lock
        } catch {
            close(directory)
            throw error
        }
    }

    deinit {
        close(lock)
        close(directory)
    }

    func load() throws -> [String: AgentBudgetHookSession] {
        let descriptor: Int32
        do {
            descriptor = try Self.secureFile(directory, name: "state.json", flags: O_RDONLY)
        } catch Failure.missing { return [:] }
        defer { close(descriptor) }
        var info = stat()
        guard fstat(descriptor, &info) == 0, info.st_size <= off_t(AgentBudgetHook.maximumStateBytes) else {
            throw Failure.oversizedState
        }
        var data = Data()
        var bytes = [UInt8](repeating: 0, count: 8_192)
        while true {
            let count = read(descriptor, &bytes, bytes.count)
            if count == 0 { break }
            if count < 0 {
                if errno == EINTR { continue }
                throw Failure.io
            }
            data.append(contentsOf: bytes.prefix(count))
            guard data.count <= AgentBudgetHook.maximumStateBytes else { throw Failure.oversizedState }
        }
        guard AgentBudgetHook.boundedJSONDepth(data),
              let file = try? JSONDecoder().decode(FileState.self, from: data), file.version == 1 else {
            throw Failure.invalidState
        }
        return file.sessions.reduce(into: [:]) { sessions, entry in
            let (key, value) = entry
            guard AgentBudgetHook.validHash(key), value.checkedAt.isFinite,
                  value.observed?.isFinite != false else { return }
            let windows = value.windows.sorted { $0.key < $1.key }.reduce(into: [String: AgentBudgetHookWindow]()) { result, entry in
                guard result.count < AgentBudgetHook.maximumWindows, AgentBudgetHook.validHash(entry.key),
                      entry.value.observed.isFinite else { return }
                let boundaries = entry.value.notices.filter {
                    [5, 10, 20].contains($0.stage) && $0.reset?.isFinite != false
                }.suffix(AgentBudgetHook.maximumBoundaries)
                result[entry.key] = AgentBudgetHookWindow(observed: entry.value.observed, notices: Array(boundaries))
            }
            sessions[key] = AgentBudgetHookSession(checkedAt: value.checkedAt, observed: value.observed, windows: windows)
        }
    }

    func save(_ sessions: [String: AgentBudgetHookSession]) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(FileState(version: 1, sessions: sessions))
        guard data.count <= AgentBudgetHook.maximumStateBytes else { throw Failure.oversizedState }
        let temporary = ".state-" + UUID().uuidString
        defer { _ = unlinkat(directory, temporary, 0) }
        let descriptor = try Self.secureFile(directory, name: temporary, flags: O_WRONLY | O_CREAT | O_EXCL)
        do {
            try data.withUnsafeBytes { buffer in
                var offset = 0
                while offset < buffer.count {
                    let count = write(descriptor, buffer.baseAddress!.advanced(by: offset), buffer.count - offset)
                    if count < 0 {
                        if errno == EINTR { continue }
                        throw Failure.io
                    }
                    guard count > 0 else { throw Failure.io }
                    offset += count
                }
            }
            guard fsync(descriptor) == 0 else { throw Failure.io }
        } catch {
            close(descriptor)
            throw error
        }
        guard close(descriptor) == 0,
              renameat(directory, temporary, directory, "state.json") == 0 else { throw Failure.io }
        _ = fsync(directory)
    }

    private static func secureFile(_ directory: Int32, name: String, flags: Int32) throws -> Int32 {
        let descriptor = openat(directory, name, flags | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK, 0o600)
        guard descriptor >= 0 else { throw errno == ENOENT ? Failure.missing : Failure.unsafeState }
        var info = stat()
        guard fstat(descriptor, &info) == 0, info.st_mode & S_IFMT == S_IFREG,
              info.st_uid == getuid(), info.st_mode & 0o7777 == 0o600, info.st_nlink == 1 else {
            close(descriptor)
            throw Failure.unsafeState
        }
        return descriptor
    }
}
