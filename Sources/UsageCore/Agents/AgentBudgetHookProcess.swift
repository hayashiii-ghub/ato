import Darwin
import Foundation

enum AgentBudgetHookProcess {
    static func isExecutableFile(_ url: URL) -> Bool {
        var info = stat()
        // Normal managed CLI symlinks are supported; only state files require NOFOLLOW.
        return stat(url.path, &info) == 0 && info.st_mode & S_IFMT == S_IFREG && access(url.path, X_OK) == 0
    }

    static func readInput(descriptor: Int32, limit: Int, timeout: TimeInterval) -> Data? {
        let originalFlags = fcntl(descriptor, F_GETFL)
        guard originalFlags >= 0, fcntl(descriptor, F_SETFL, originalFlags | O_NONBLOCK) == 0 else { return nil }
        defer { _ = fcntl(descriptor, F_SETFL, originalFlags) }
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        var result = Data()
        var buffer = [UInt8](repeating: 0, count: 4_096)
        while ProcessInfo.processInfo.systemUptime < deadline {
            let count = read(descriptor, &buffer, buffer.count)
            if count == 0 { return result }
            if count > 0 {
                guard result.count + count <= limit else { return nil }
                result.append(contentsOf: buffer.prefix(count))
                continue
            }
            if errno == EINTR { continue }
            guard errno == EAGAIN || errno == EWOULDBLOCK else { return nil }
            var item = pollfd(fd: descriptor, events: Int16(POLLIN | POLLHUP), revents: 0)
            let remaining = Int32(max(1, min(50, (deadline - ProcessInfo.processInfo.systemUptime) * 1_000)))
            if poll(&item, 1, remaining) < 0 && errno != EINTR { return nil }
        }
        return nil
    }

    static func report(cli: URL, provider: String, timeout: TimeInterval = 2) -> Data? {
        guard AgentBudgetHook.absolutePath(cli.path), isExecutableFile(cli),
              ["codex", "claude", "cursor", "gemini"].contains(provider) else { return nil }
        var descriptors: [Int32] = [-1, -1]
        guard pipe(&descriptors) == 0 else { return nil }
        defer { close(descriptors[0]); if descriptors[1] >= 0 { close(descriptors[1]) } }
        guard descriptors.allSatisfy({ $0 > STDERR_FILENO }),
              fcntl(descriptors[0], F_SETFD, FD_CLOEXEC) == 0,
              fcntl(descriptors[1], F_SETFD, FD_CLOEXEC) == 0,
              fcntl(descriptors[0], F_SETFL, O_NONBLOCK) == 0 else { return nil }
        var actions: posix_spawn_file_actions_t?
        var attributes: posix_spawnattr_t?
        guard posix_spawn_file_actions_init(&actions) == 0 else { return nil }
        defer { posix_spawn_file_actions_destroy(&actions) }
        guard posix_spawnattr_init(&attributes) == 0 else { return nil }
        defer { posix_spawnattr_destroy(&attributes) }
        let setup = [
            posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_CLOEXEC_DEFAULT)),
            posix_spawn_file_actions_addopen(&actions, STDIN_FILENO, "/dev/null", O_RDONLY, 0),
            posix_spawn_file_actions_adddup2(&actions, descriptors[1], STDOUT_FILENO),
            posix_spawn_file_actions_addopen(&actions, STDERR_FILENO, "/dev/null", O_WRONLY, 0),
            posix_spawn_file_actions_addchdir(&actions, "/")
        ]
        guard setup.allSatisfy({ $0 == 0 }) else { return nil }
        let arguments = [cli.path, "status", "--json", "--provider", provider]
        let environment = [
            "HOME=\(FileManager.default.homeDirectoryForCurrentUser.path)",
            "TMPDIR=\(FileManager.default.temporaryDirectory.path)", "LANG=en_US.UTF-8"
        ]
        let argv = arguments.map { strdup($0) } + [nil]
        let envp = environment.map { strdup($0) } + [nil]
        defer { argv.forEach { free($0) }; envp.forEach { free($0) } }
        guard argv.dropLast().allSatisfy({ $0 != nil }), envp.dropLast().allSatisfy({ $0 != nil }) else { return nil }
        var pid: pid_t = 0
        let spawned = argv.withUnsafeBufferPointer { argv in
            envp.withUnsafeBufferPointer { envp in
                posix_spawn(&pid, cli.path, &actions, &attributes, argv.baseAddress!, envp.baseAddress!)
            }
        }
        guard spawned == 0 else { return nil }
        close(descriptors[1]); descriptors[1] = -1
        var reaped = false
        defer {
            if !reaped {
                // Only the directly spawned, still-owned CLI child is stopped on timeout/overflow.
                _ = kill(pid, SIGKILL)
                var status: Int32 = 0
                while waitpid(pid, &status, 0) < 0 && errno == EINTR {}
            }
        }
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        var output = Data(), eof = false, status: Int32 = 0
        var buffer = [UInt8](repeating: 0, count: 4_096)
        while ProcessInfo.processInfo.systemUptime < deadline {
            if !eof {
                let count = read(descriptors[0], &buffer, buffer.count)
                if count > 0 {
                    guard output.count + count <= AgentBudgetHook.maximumInputBytes else { return nil }
                    output.append(contentsOf: buffer.prefix(count))
                    continue
                }
                if count == 0 { eof = true }
                else if errno == EINTR { continue }
                else if errno != EAGAIN && errno != EWOULDBLOCK { return nil }
            }
            if !reaped {
                let result = waitpid(pid, &status, WNOHANG)
                if result == pid { reaped = true }
                else if result < 0 && errno != EINTR {
                    if errno == ECHILD { reaped = true }
                    return nil
                }
            }
            if reaped && eof { return status == 0 ? output : nil }
            if eof {
                usleep(1_000)
            } else {
                var item = pollfd(fd: descriptors[0], events: Int16(POLLIN | POLLHUP), revents: 0)
                if poll(&item, 1, 10) < 0 && errno != EINTR { return nil }
            }
        }
        return nil
    }
}
