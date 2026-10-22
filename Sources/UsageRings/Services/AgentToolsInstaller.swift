import CryptoKit
import Darwin
import Foundation

enum AgentToolClient: String, CaseIterable, Identifiable, Sendable {
    case codex, claude, cursor, antigravity
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .codex: "Codex"
        case .claude: "Claude Code"
        case .cursor: "Cursor Agent"
        case .antigravity: "Antigravity"
        }
    }
    fileprivate var configuration: String {
        switch self {
        case .codex: ".codex/hooks.json"
        case .claude: ".claude/settings.json"
        case .cursor: ".cursor/hooks.json"
        case .antigravity: ".gemini/config/hooks.json"
        }
    }
    fileprivate var skillDirectories: [String] {
        switch self {
        case .codex: [".agents/skills/usage-rings-budget"]
        case .claude: [".claude/skills/usage-rings-budget"]
        case .cursor: [".cursor/skills/usage-rings-budget"]
        case .antigravity: [".gemini/antigravity-cli/skills/usage-rings-budget", ".gemini/config/skills/usage-rings-budget"]
        }
    }
}

enum AgentToolsComponentState: Sendable { case installed, notInstalled, outdated, conflict }

struct AgentToolsComponentReport: Sendable {
    let state: AgentToolsComponentState
    let path: String
    let message: String
}

struct AgentToolsReport: Sendable {
    let client: AgentToolClient
    let cli: AgentToolsComponentReport
    let skill: AgentToolsComponentReport
    let hook: AgentToolsComponentReport
    let canRemove: Bool
    var requiresTrustReview: Bool { client == .codex }
    var isInstalled: Bool { [cli, skill, hook].allSatisfy { $0.state == .installed } }
    var hasConflict: Bool { [cli, skill, hook].contains { $0.state == .conflict } }
    var needsUpdate: Bool { [cli, skill, hook].contains { $0.state == .outdated } }
}

/// Installs only bundled tools and the selected assistant's skill/hook. It never runs a tool.
struct AgentToolsInstaller: Sendable {
    let appURL: URL
    let homeURL: URL
    private static let lock = NSLock()
    private static let manifestPath = "Library/Application Support/Usage Rings/agent-tools-v1.json"
    private static let cliPath = ".local/bin/usage-rings"

    init(appURL: URL, homeURL: URL) {
        self.appURL = appURL.standardizedFileURL
        self.homeURL = homeURL.resolvingSymlinksInPath().standardizedFileURL
    }

    func check(client: AgentToolClient) -> AgentToolsReport {
        Self.lock.lock()
        defer { Self.lock.unlock() }
        do { return try inspect(client: client).report }
        catch {
            let message = error.localizedDescription
            return AgentToolsReport(client: client,
                cli: component(.conflict, Self.cliPath, message),
                skill: component(.conflict, client.skillDirectories.joined(separator: ", "), message),
                hook: component(.conflict, client.configuration, message), canRemove: false)
        }
    }

    @discardableResult func install(client: AgentToolClient) throws -> AgentToolsReport {
        try change(client: client, removing: false)
    }

    @discardableResult func remove(client: AgentToolClient) throws -> AgentToolsReport {
        try change(client: client, removing: true)
    }

    private var cliTarget: String { appURL.appendingPathComponent("Contents/Helpers/usage-rings").path }
    private var hookTarget: String { appURL.appendingPathComponent("Contents/Helpers/UsageRingsBudgetHook").path }
    private var sourceSkill: URL { appURL.appendingPathComponent("Contents/Resources/Skills/usage-rings-budget", isDirectory: true) }
    private func command(_ client: AgentToolClient) -> String {
        quote(hookTarget) + " --client " + client.rawValue + " --cli " + quote(cliTarget)
    }
    private func component(_ state: AgentToolsComponentState, _ path: String, _ message: String) -> AgentToolsComponentReport {
        AgentToolsComponentReport(state: state, path: path.hasPrefix("/") ? path : homeURL.appendingPathComponent(path).path, message: message)
    }

    private struct Ownership: Codable {
        var version = 1
        var cliTarget: String?
        var clients: [String: Registration] = [:]
    }
    private struct Registration: Codable {
        var skillDirectories: [String]
        var skillHashes: [String: String]
        var hookHash: String
        var command: String
    }
    private struct Inspection {
        let home: AgentToolsSafeHome
        let manifestData: Data?
        var ownership: Ownership
        let source: [String: Data]
        let skillDirectories: [String]
        let skillFiles: [[String: Data]]
        let cli: AgentToolsSafeHome.Node?
        let configurationData: Data?
        let hook: HookDocument
        let report: AgentToolsReport
    }

    private func inspect(client: AgentToolClient) throws -> Inspection {
        let home = try AgentToolsSafeHome(homeURL)
        let manifestData = try home.read(Self.manifestPath)
        var ownership = Ownership()
        if let manifestData {
            do { ownership = try JSONDecoder().decode(Ownership.self, from: manifestData) }
            catch { throw Failure("ato? setup records need review before changing files.") }
            guard ownership.version == 1,
                  ownership.clients.keys.allSatisfy({ AgentToolClient(rawValue: $0) != nil }) else {
                throw Failure("ato? setup records use an unsupported format.")
            }
        }
        let registration = ownership.clients[client.rawValue]
        let source = try sourceFiles()
        let skillDirectories = try selectedSkillDirectories(client, home: home, registration: registration)
        let desiredHashes = source.mapValues(hash)
        let sourceReady = FileManager.default.isExecutableFile(atPath: cliTarget)
            && FileManager.default.isExecutableFile(atPath: hookTarget)
        let cli = try home.node(Self.cliPath)
        let cliState: AgentToolsComponentState
        let cliMessage: String
        if !sourceReady {
            cliState = .conflict; cliMessage = "This app bundle is missing executable AI tools."
        } else if let cli {
            if case .link(let target) = cli, target == cliTarget {
                cliState = ownership.cliTarget == target ? .installed : .notInstalled
                cliMessage = ownership.cliTarget == target ? "CLI configured." : "The matching CLI can be adopted by Set Up."
            } else if case .link(let target) = cli, target == ownership.cliTarget {
                cliState = .outdated; cliMessage = "Update the CLI link for this app."
            } else {
                cliState = .conflict; cliMessage = "An existing CLI file needs review."
            }
        } else {
            cliState = .notInstalled; cliMessage = "CLI is not configured."
        }
        var skillFiles: [[String: Data]] = []
        var skillStates: [AgentToolsComponentState] = []
        for directory in skillDirectories {
            let files = try home.tree(directory)
            skillFiles.append(files)
            let current = files.mapValues(hash)
            if files.isEmpty {
                skillStates.append(.notInstalled)
            } else if let registration, current == registration.skillHashes {
                skillStates.append(current == desiredHashes ? .installed : .outdated)
            } else if registration == nil, current == desiredHashes {
                skillStates.append(.notInstalled)
            } else {
                skillStates.append(.conflict)
            }
        }
        let skillState: AgentToolsComponentState = skillStates.contains(.conflict) ? .conflict
            : skillStates.contains(.outdated) ? .outdated
            : skillStates.contains(.notInstalled) ? .notInstalled : .installed
        let skillMessage: String
        switch skillState {
        case .installed: skillMessage = "Skill configured."
        case .notInstalled: skillMessage = "Set Up installs or adopts an identical bundled skill."
        case .outdated: skillMessage = "Update the bundled skill."
        case .conflict: skillMessage = "An existing or edited skill needs review."
        }
        let configurationData = try home.read(client.configuration)
        let hook = try HookDocument(data: configurationData, client: client, registration: registration, desiredCommand: command(client))
        let report = AgentToolsReport(client: client,
            cli: component(cliState, Self.cliPath, cliMessage),
            skill: component(skillState, skillDirectories.joined(separator: ", "), skillMessage),
            hook: component(hook.state, client.configuration, hook.message),
            canRemove: registration != nil && ![cliState, skillState, hook.state].contains(.conflict))
        return Inspection(home: home, manifestData: manifestData, ownership: ownership, source: source,
                          skillDirectories: skillDirectories, skillFiles: skillFiles, cli: cli, configurationData: configurationData, hook: hook, report: report)
    }

    private func change(client: AgentToolClient, removing: Bool) throws -> AgentToolsReport {
        Self.lock.lock()
        defer { Self.lock.unlock() }
        let lockingHome = try AgentToolsSafeHome(homeURL)
        let fileLock = try lockingHome.acquireLock("Library/Application Support/Usage Rings/agent-tools.lock")
        defer { flock(fileLock, LOCK_UN); close(fileLock) }
        var inspection = try inspect(client: client)
        var result = inspection.report
        guard !inspection.report.hasConflict else {
            throw Failure("Existing or edited files need review. No setup files were changed.")
        }
        let oldRegistration = inspection.ownership.clients[client.rawValue]
        if removing && oldRegistration == nil { return inspection.report }
        let transaction = FileTransaction(home: inspection.home)
        do {
            // The shared record is checked before every transaction and written last.
            try inspection.home.require(Self.manifestPath, equals: inspection.manifestData)
            for (index, directory) in inspection.skillDirectories.enumerated() {
                let previous = inspection.skillFiles[index]
                let desired: [String: Data] = removing ? [:] : inspection.source
                for file in Set(previous.keys).union(desired.keys).sorted() {
                    try transaction.file(directory + "/" + file, previous: previous[file], desired: desired[file], backup: false)
                }
            }
            let nextConfiguration = try inspection.hook.updated(removing: removing)
            if nextConfiguration != inspection.configurationData {
                try transaction.file(client.configuration, previous: inspection.configurationData, desired: nextConfiguration, backup: true)
            }
            if removing {
                inspection.ownership.clients.removeValue(forKey: client.rawValue)
                if inspection.ownership.clients.isEmpty {
                    if let target = inspection.ownership.cliTarget,
                       inspection.cli == .link(target) {
                        try transaction.link(Self.cliPath, previous: inspection.cli, desired: nil)
                    }
                    inspection.ownership.cliTarget = nil
                }
            } else {
                try transaction.link(Self.cliPath, previous: inspection.cli, desired: cliTarget)
                inspection.ownership.cliTarget = cliTarget
                inspection.ownership.clients[client.rawValue] = Registration(
                    skillDirectories: inspection.skillDirectories, skillHashes: inspection.source.mapValues(hash),
                    hookHash: hash(try canonical(hookHandler(client, command(client)))), command: command(client))
            }
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
            let manifest = try encoder.encode(inspection.ownership)
            try transaction.file(Self.manifestPath, previous: inspection.manifestData, desired: manifest, backup: false)
            let readback = try inspect(client: client)
            if removing {
                guard readback.ownership.clients[client.rawValue] == nil,
                      readback.report.skill.state == .notInstalled,
                      readback.configurationData == nextConfiguration, !readback.hook.hasBudgetCommand,
                      readback.report.cli.state != .conflict else {
                    throw Failure("The removed setup could not be verified. Earlier changes were restored.")
                }
            } else {
                guard readback.report.isInstalled && !readback.report.hasConflict else {
                    throw Failure("The new setup could not be verified. Earlier changes were restored.")
                }
            }
            result = readback.report
            transaction.finish()
        } catch {
            let restored = transaction.rollback()
            if !restored { throw Failure("Setup stopped after a file changed concurrently. Review ato? setup files before retrying.") }
            throw error
        }
        return result
    }

    private func selectedSkillDirectories(_ client: AgentToolClient, home: AgentToolsSafeHome, registration: Registration?) throws -> [String] {
        if client != .codex {
            guard registration == nil || registration?.skillDirectories == client.skillDirectories else {
                throw Failure("ato? setup records contain an unsupported skill location.")
            }
            return client.skillDirectories
        }
        let legacy = ".codex/skills/usage-rings-budget"
        let standard = client.skillDirectories[0]
        let legacyFiles = try home.tree(legacy)
        let standardFiles = try home.tree(standard)
        if let registration {
            guard registration.skillDirectories == [legacy] || registration.skillDirectories == [standard] else {
                throw Failure("ato? setup records contain an unsupported skill location.")
            }
            let alternate = registration.skillDirectories == [legacy] ? standardFiles : legacyFiles
            guard alternate.isEmpty else { throw Failure("Multiple Codex budget skills need review before setup.") }
            return registration.skillDirectories
        }
        if !legacyFiles.isEmpty {
            guard standardFiles.isEmpty else { throw Failure("Multiple Codex budget skills need review before setup.") }
            return [legacy]
        }
        return [standard]
    }

    private func sourceFiles() throws -> [String: Data] {
        let home = try AgentToolsSafeHome(sourceSkill, requireOwnership: false)
        let files = try home.tree("")
        guard files["SKILL.md"] != nil, !files.isEmpty else { throw Failure("The bundled skill is missing.") }
        return files
    }

    private struct HookDocument {
        let client: AgentToolClient
        var root: [String: Any]
        let originalData: Data?
        let desiredCommand: String
        let registration: Registration?
        var location: (group: Int, handler: Int)?
        var state: AgentToolsComponentState = .notInstalled
        var message = "Budget hook is not configured."

        init(data: Data?, client: AgentToolClient, registration: Registration?, desiredCommand: String) throws {
            self.client = client
            self.originalData = data
            self.desiredCommand = desiredCommand
            self.registration = registration
            if let data {
                guard data.count <= 4 * 1024 * 1024, Self.hasSafeDepth(data),
                      let object = try? JSONSerialization.jsonObject(with: data),
                      let root = object as? [String: Any] else {
                    throw Failure("The assistant hook settings are not a supported JSON object.")
                }
                self.root = root
            } else { self.root = [:] }
            if client == .cursor, let version = root["version"],
               !(version is NSNumber && (version as? NSNumber)?.compare(NSNumber(value: 1)) == .orderedSame && CFGetTypeID(version as CFTypeRef) != CFBooleanGetTypeID()) {
                throw Failure("The Cursor hook settings use an unsupported version.")
            }
            let groups = try self.groups()
            var candidateCount = 0
            for (groupIndex, group) in groups.enumerated() {
                let handlers = try self.handlers(group)
                for (handlerIndex, handler) in handlers.enumerated() {
                    guard let command = handler["command"] as? String,
                          Self.isBudgetCommand(command) else { continue }
                    candidateCount += 1
                    guard let registration,
                          command == registration.command,
                          hash(try canonical(handler)) == registration.hookHash,
                          client == .cursor || client == .antigravity || group["matcher"] as? String == ".*" else {
                        state = .conflict; message = "An existing or edited budget hook needs review."; continue
                    }
                    location = (groupIndex, handlerIndex)
                }
            }
            // A misplaced/legacy hook is a conflict, so Set Up cannot produce duplicate notices.
            let allCandidates = Self.budgetCommandCount(root)
            if candidateCount > 1 || allCandidates != candidateCount || (client == .antigravity && root["ato-budget"] != nil && candidateCount == 0) {
                state = .conflict; message = "An existing budget hook needs review."
            }
            if state != .conflict, location != nil {
                state = registration?.command == desiredCommand ? .installed : .outdated
                message = state == .installed ? "Budget hook configured." : "Update the budget hook for this app."
            }
        }

        var hasBudgetCommand: Bool { Self.budgetCommandCount(root) > 0 }

        private func groups() throws -> [[String: Any]] {
            if client == .antigravity {
                guard let section = root["ato-budget"] else { return [] }
                guard let section = section as? [String: Any] else { throw Failure("The existing ato-budget hook needs review.") }
                guard let handlers = section["PreInvocation"] else { return [] }
                guard let array = handlers as? [[String: Any]] else { throw Failure("The existing ato-budget hook needs review.") }
                return [["hooks": array]]
            }
            guard let hooks = root["hooks"] else { return [] }
            guard let hooks = hooks as? [String: Any] else { throw Failure("The assistant hook settings need review.") }
            let event = client == .cursor ? "postToolUse" : "PostToolUse"
            guard let value = hooks[event] else { return [] }
            guard let array = value as? [[String: Any]] else { throw Failure("The assistant tool hook settings need review.") }
            return client == .cursor ? [["hooks": array]] : array
        }
        private func handlers(_ group: [String: Any]) throws -> [[String: Any]] {
            guard let handlers = group["hooks"] as? [[String: Any]] else { throw Failure("The assistant tool hook settings need review.") }
            return handlers
        }
        func updated(removing: Bool) throws -> Data? {
            var root = self.root
            var groups = try self.groups()
            if let location {
                var group = groups[location.group]
                var handlers = try self.handlers(group)
                if removing { handlers.remove(at: location.handler) }
                else { handlers[location.handler] = hookHandler(client, desiredCommand) }
                group["hooks"] = handlers
                if handlers.isEmpty && Set(group.keys).isSubset(of: ["matcher", "hooks"]) { groups.remove(at: location.group) }
                else { groups[location.group] = group }
            } else if !removing {
                if client == .cursor || client == .antigravity {
                    var handlers = groups.first?["hooks"] as? [[String: Any]] ?? []
                    handlers.append(hookHandler(client, desiredCommand))
                    groups = [["hooks": handlers]]
                } else {
                    groups.append(["matcher": ".*", "hooks": [hookHandler(client, desiredCommand)]])
                }
            } else { return originalData }
            if client == .antigravity {
                var section = root["ato-budget"] as? [String: Any] ?? [:]
                let handlers = groups.first?["hooks"] as? [[String: Any]] ?? []
                if handlers.isEmpty { section.removeValue(forKey: "PreInvocation") }
                else { section["PreInvocation"] = handlers }
                if section.isEmpty { root.removeValue(forKey: "ato-budget") }
                else { root["ato-budget"] = section }
            } else {
                var hooks = root["hooks"] as? [String: Any] ?? [:]
                let event = client == .cursor ? "postToolUse" : "PostToolUse"
                let eventValue = client == .cursor ? (groups.first?["hooks"] as? [[String: Any]] ?? []) : groups
                if eventValue.isEmpty { hooks.removeValue(forKey: event) }
                else { hooks[event] = eventValue }
                if hooks.isEmpty { root.removeValue(forKey: "hooks") }
                else { root["hooks"] = hooks }
                if client == .cursor && !removing && root["version"] == nil { root["version"] = 1 }
            }
            return try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys]) + Data([10])
        }
        private static func hasSafeDepth(_ data: Data) -> Bool {
            var depth = 0
            var quoted = false
            var escaped = false
            for byte in data {
                if quoted {
                    if escaped { escaped = false }
                    else if byte == 92 { escaped = true }
                    else if byte == 34 { quoted = false }
                } else if byte == 34 { quoted = true }
                else if byte == 123 || byte == 91 {
                    depth += 1
                    if depth > 64 { return false }
                } else if byte == 125 || byte == 93 { depth -= 1 }
            }
            return true
        }
        private static func isBudgetCommand(_ value: String) -> Bool {
            value.contains("usage_hook.py") || value.contains("UsageRingsBudgetHook") || value.contains("usage-rings-budget")
        }
        private static func budgetCommandCount(_ value: Any) -> Int {
            if let dictionary = value as? [String: Any] {
                return dictionary.reduce(0) { count, entry in
                    count + (entry.key == "command" && (entry.value as? String).map(isBudgetCommand) == true ? 1 : budgetCommandCount(entry.value))
                }
            }
            if let array = value as? [Any] { return array.reduce(0) { $0 + budgetCommandCount($1) } }
            return 0
        }
    }
}

private func hookHandler(_ client: AgentToolClient, _ command: String) -> [String: Any] {
    var handler: [String: Any] = ["command": command, "timeout": 5]
    if client != .cursor { handler["type"] = "command" }
    if client == .codex { handler["async"] = true; handler["additionalContextLimit"] = 256 }
    return handler
}
private func canonical(_ object: Any) throws -> Data { try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) }
private func hash(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
private func quote(_ string: String) -> String { "'" + string.replacingOccurrences(of: "'", with: "'\\''") + "'" }
private struct Failure: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

/// Every destination is resolved from an open home directory, rejecting symlinks below it.
final class AgentToolsSafeHome {
    typealias RenameItem = (Int32, String, Int32, String, UInt32) -> Int32
    enum Node: Equatable { case file(Data), link(String) }
    let descriptor: Int32
    let requireOwnership: Bool
    private let renameItem: RenameItem
    init(_ url: URL, requireOwnership: Bool = true,
         renameItem: @escaping RenameItem = { renameatx_np($0, $1, $2, $3, $4) }) throws {
        self.requireOwnership = requireOwnership
        self.renameItem = renameItem
        descriptor = open(url.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { throw Failure("The setup folder is missing or unsafe.") }
    }
    deinit { close(descriptor) }
    private func parent(_ path: String, create: Bool = false) throws -> (Int32, String) {
        let pieces = path.split(separator: "/").map(String.init)
        guard !pieces.isEmpty, !path.hasPrefix("/"), pieces.allSatisfy({ $0 != "." && $0 != ".." }) else {
            throw Failure("An invalid setup path was rejected.")
        }
        var directory = dup(descriptor)
        do {
            for piece in pieces.dropLast() {
                var next = openat(directory, piece, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
                if next < 0 && errno == ENOENT && create {
                    guard mkdirat(directory, piece, 0o700) == 0 || errno == EEXIST else { throw Failure("A setup folder could not be created.") }
                    next = openat(directory, piece, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
                }
                guard next >= 0 else {
                    if errno == ENOENT { close(directory); return (-1, pieces.last!) }
                    throw Failure("A setup folder is a symlink or cannot be accessed safely.")
                }
                close(directory); directory = next
            }
            return (directory, pieces.last!)
        } catch { close(directory); throw error }
    }
    func acquireLock(_ path: String) throws -> Int32 {
        let (directory, name) = try parent(path, create: true)
        guard directory >= 0 else { throw Failure("The setup lock folder is unavailable.") }
        defer { close(directory) }
        let file = openat(directory, name, O_RDWR | O_CREAT | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC, 0o600)
        guard file >= 0 else { throw Failure("The setup lock is a symlink or unavailable.") }
        var information = stat()
        guard fstat(file, &information) == 0, information.st_mode & S_IFMT == S_IFREG,
              information.st_uid == getuid(), information.st_nlink == 1 else {
            close(file); throw Failure("The setup lock needs review.")
        }
        guard flock(file, LOCK_EX | LOCK_NB) == 0 else {
            close(file); throw Failure("Another app copy is configuring AI tools. Try again when it finishes.")
        }
        return file
    }
    func node(_ path: String) throws -> Node? {
        let (directory, name) = try parent(path)
        guard directory >= 0 else { return nil }
        defer { close(directory) }
        return try node(directory: directory, name: name)
    }
    private func node(directory: Int32, name: String) throws -> Node? {
        var information = stat()
        guard fstatat(directory, name, &information, AT_SYMLINK_NOFOLLOW) == 0 else {
            if errno == ENOENT { return nil }
            throw Failure("A setup file cannot be inspected safely.")
        }
        if information.st_mode & S_IFMT == S_IFLNK {
            var buffer = [CChar](repeating: 0, count: Int(PATH_MAX) + 1)
            let count = readlinkat(directory, name, &buffer, buffer.count - 1)
            guard count >= 0, count < buffer.count - 1 else { throw Failure("An existing link cannot be inspected safely.") }
            return .link(String(decoding: buffer.prefix(Int(count)).map { UInt8(bitPattern: $0) }, as: UTF8.self))
        }
        guard information.st_mode & S_IFMT == S_IFREG, information.st_nlink == 1,
              (!requireOwnership || information.st_uid == getuid()), information.st_size <= 8 * 1024 * 1024 else {
            throw Failure("An existing setup file is not a safe regular file.")
        }
        let file = openat(directory, name, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard file >= 0 else { throw Failure("A setup file cannot be read safely.") }
        defer { close(file) }
        var opened = stat()
        guard fstat(file, &opened) == 0, opened.st_dev == information.st_dev, opened.st_ino == information.st_ino else {
            throw Failure("A setup file changed while it was being inspected.")
        }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 16384)
        while true {
            let count = Darwin.read(file, &buffer, buffer.count)
            if count == 0 { break }
            guard count > 0, data.count + count <= 8 * 1024 * 1024 else { throw Failure("A setup file cannot be read safely.") }
            data.append(contentsOf: buffer.prefix(count))
        }
        return .file(data)
    }
    func read(_ path: String) throws -> Data? {
        guard let node = try node(path) else { return nil }
        guard case .file(let data) = node else { throw Failure("A setup file is a symlink and needs review.") }
        return data
    }
    func require(_ path: String, equals expected: Data?) throws {
        guard try read(path) == expected else { throw Failure("A setup file changed concurrently. No newer content was overwritten.") }
    }
    func tree(_ path: String) throws -> [String: Data] {
        let directory: Int32
        if path.isEmpty { directory = dup(descriptor) }
        else {
            let (parent, name) = try self.parent(path)
            guard parent >= 0 else { return [:] }
            defer { close(parent) }
            directory = openat(parent, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            if directory < 0 && errno == ENOENT { return [:] }
        }
        guard directory >= 0 else { throw Failure("An existing skill folder is a symlink or needs review.") }
        defer { close(directory) }
        var result: [String: Data] = [:]
        var entries = 0
        func walk(_ fd: Int32, prefix: String, depth: Int = 0) throws {
            guard depth <= 32 else { throw Failure("The skill folder is too deeply nested.") }
            guard let stream = fdopendir(dup(fd)) else { throw Failure("The skill folder cannot be inspected.") }
            defer { closedir(stream) }
            while let entry = readdir(stream) {
                let name = withUnsafePointer(to: &entry.pointee.d_name) { pointer in
                    pointer.withMemoryRebound(to: CChar.self, capacity: Int(entry.pointee.d_namlen) + 1) { String(cString: $0) }
                }
                guard name != ".", name != ".." else { continue }
                entries += 1
                guard entries <= 2048 else { throw Failure("The skill folder contains too many entries.") }
                var info = stat()
                guard fstatat(fd, name, &info, AT_SYMLINK_NOFOLLOW) == 0 else { throw Failure("The skill folder changed while being inspected.") }
                let key = prefix + name
                if info.st_mode & S_IFMT == S_IFDIR {
                    let child = openat(fd, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
                    guard child >= 0 else { throw Failure("The skill folder changed while being inspected.") }
                    do { try walk(child, prefix: key + "/", depth: depth + 1); close(child) }
                    catch { close(child); throw error }
                } else {
                    guard case .file(let data) = try node(directory: fd, name: name) else { throw Failure("The skill contains an unsafe file or symlink.") }
                    result[key] = data
                }
                guard result.count <= 1024 else { throw Failure("The skill folder contains too many files.") }
            }
        }
        try walk(directory, prefix: "")
        return result
    }
    private func secureRecovery(directory: Int32, name: String) throws {
        var information = stat()
        if fstatat(directory, name, &information, AT_SYMLINK_NOFOLLOW) != 0 {
            if errno == ENOENT { return }
            throw Failure("Recovery content was preserved, but its permissions need review.")
        }
        // Links contain a destination only; never follow one while securing recovery content.
        guard information.st_mode & S_IFMT == S_IFREG else { return }
        let file = openat(directory, name, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard file >= 0 else { throw Failure("Recovery content was preserved, but its permissions need review.") }
        defer { close(file) }
        var opened = stat()
        guard fstat(file, &opened) == 0, opened.st_dev == information.st_dev,
              opened.st_ino == information.st_ino, opened.st_uid == getuid(), opened.st_nlink == 1,
              fchmod(file, 0o600) == 0 else {
            throw Failure("Recovery content was preserved, but its permissions need review.")
        }
    }

    func replace(_ path: String, previous: Node?, desired: Node?) throws {
        let (directory, name) = try parent(path, create: desired != nil)
        guard directory >= 0 else {
            if previous == nil && desired == nil { return }
            throw Failure("A setup folder changed concurrently.")
        }
        defer { close(directory) }
        guard try node(directory: directory, name: name) == previous else {
            throw Failure("A setup file changed concurrently. No newer content was overwritten.")
        }
        let temporary = ".ato-setup-" + UUID().uuidString
        var removeTemporary = true
        defer { if removeTemporary { unlinkat(directory, temporary, 0) } }
        guard let desired else {
            guard renameItem(directory, name, directory, temporary, UInt32(RENAME_EXCL)) == 0 else {
                throw Failure("A setup file changed or could not be removed.")
            }
            if (try? node(directory: directory, name: temporary)) != previous {
                // Keep captured content even when another editor retains an open descriptor to it.
                removeTemporary = false
                _ = renameItem(directory, temporary, directory, name, UInt32(RENAME_EXCL))
                try secureRecovery(directory: directory, name: temporary)
                throw Failure("Concurrent changes were preserved. Review the settings and any .ato-setup recovery file before retrying.")
            }
            return
        }
        switch desired {
        case .file(let data):
            let file = openat(directory, temporary, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
            guard file >= 0 else { throw Failure("A setup file could not be prepared.") }
            do {
                try data.withUnsafeBytes { bytes in
                    var offset = 0
                    while offset < bytes.count {
                        let written = Darwin.write(file, bytes.baseAddress!.advanced(by: offset), bytes.count - offset)
                        guard written > 0 else { throw Failure("A setup file could not be written.") }
                        offset += written
                    }
                }
                guard fsync(file) == 0 else { throw Failure("A setup file could not be saved.") }
                close(file)
            } catch { close(file); throw error }
        case .link(let target):
            guard symlinkat(target, directory, temporary) == 0 else { throw Failure("The CLI link could not be prepared.") }
        }
        guard try node(directory: directory, name: name) == previous else { throw Failure("A setup file changed concurrently. No newer content was overwritten.") }
        if previous == nil {
            guard renameItem(directory, temporary, directory, name, UInt32(RENAME_EXCL)) == 0 else {
                throw Failure("A setup file changed or could not be saved.")
            }
        } else {
            // Exchange captures the previous destination atomically, including an editor's last-moment save.
            guard renameItem(directory, temporary, directory, name, UInt32(RENAME_SWAP)) == 0 else {
                throw Failure("A setup file changed or could not be saved.")
            }
            if (try? node(directory: directory, name: temporary)) != previous {
                // A second save can arrive during restoration, and an editor can still write through
                // an open descriptor afterwards. Never unlink an inode captured by this recovery path.
                removeTemporary = false
                if (try? node(directory: directory, name: name)) == desired {
                    _ = renameItem(directory, temporary, directory, name, UInt32(RENAME_SWAP))
                }
                try secureRecovery(directory: directory, name: temporary)
                throw Failure("Concurrent changes were preserved in a .ato-setup recovery file beside the settings. Review it before retrying.")
            }
        }
    }
}

private final class FileTransaction {
    let home: AgentToolsSafeHome
    var changes: [(String, AgentToolsSafeHome.Node?, AgentToolsSafeHome.Node?)] = []
    init(home: AgentToolsSafeHome) { self.home = home }
    func file(_ path: String, previous: Data?, desired: Data?, backup: Bool) throws {
        guard previous != desired else { return }
        if backup, let previous {
            try home.replace(path + ".ato-backup-" + UUID().uuidString, previous: nil, desired: .file(previous))
        }
        let before = previous.map(AgentToolsSafeHome.Node.file), after = desired.map(AgentToolsSafeHome.Node.file)
        try home.replace(path, previous: before, desired: after)
        changes.append((path, before, after))
    }
    func link(_ path: String, previous: AgentToolsSafeHome.Node?, desired: String?) throws {
        let after = desired.map(AgentToolsSafeHome.Node.link)
        guard previous != after else { return }
        try home.replace(path, previous: previous, desired: after)
        changes.append((path, previous, after))
    }
    func finish() { changes.removeAll() }
    func rollback() -> Bool {
        var complete = true
        for (path, before, after) in changes.reversed() {
            do { try home.replace(path, previous: after, desired: before) }
            catch { complete = false }
        }
        changes.removeAll()
        return complete
    }
}
