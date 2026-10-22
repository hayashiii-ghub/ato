import Darwin
import Foundation
import Testing
@testable import UsageRings

struct AgentToolsInstallerTests {
    private final class Fixture {
        let root: URL
        let home: URL
        let app: URL
        let manager = FileManager.default
        init() throws {
            root = manager.temporaryDirectory.appendingPathComponent("ato-agent-tools-" + UUID().uuidString)
            home = root.appendingPathComponent("home")
            app = root.appendingPathComponent("ato's app $(never-run).app")
            try manager.createDirectory(at: home, withIntermediateDirectories: true)
            try bundle(app, skill: "bundled skill")
        }
        deinit { try? manager.removeItem(at: root) }
        var installer: AgentToolsInstaller { AgentToolsInstaller(appURL: app, homeURL: home) }
        func bundle(_ app: URL, skill: String) throws {
            for name in ["usage-rings", "UsageRingsBudgetHook"] {
                let file = app.appendingPathComponent("Contents/Helpers/" + name)
                try manager.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
                try Data("not executed".utf8).write(to: file)
                try manager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path)
            }
            let skillDirectory = app.appendingPathComponent("Contents/Resources/Skills/usage-rings-budget")
            try manager.createDirectory(at: skillDirectory.appendingPathComponent("scripts"), withIntermediateDirectories: true)
            try Data(skill.utf8).write(to: skillDirectory.appendingPathComponent("SKILL.md"))
            try Data("source runner".utf8).write(to: skillDirectory.appendingPathComponent("scripts/usage_hook.py"))
        }
        func write(_ path: String, _ string: String) throws {
            let file = home.appendingPathComponent(path)
            try manager.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(string.utf8).write(to: file)
        }
        func data(_ path: String) throws -> Data { try Data(contentsOf: home.appendingPathComponent(path)) }
        func json(_ path: String) throws -> [String: Any] {
            try #require(JSONSerialization.jsonObject(with: data(path)) as? [String: Any])
        }
        func exists(_ path: String) -> Bool { manager.fileExists(atPath: home.appendingPathComponent(path).path) }
    }

    @Test(arguments: AgentToolClient.allCases) func installIsIdempotentAndRemovalKeepsUnrelatedSettings(_ client: AgentToolClient) throws {
        let f = try Fixture()
        let configuration: String
        switch client {
        case .codex: configuration = ".codex/hooks.json"
        case .claude: configuration = ".claude/settings.json"
        case .cursor: configuration = ".cursor/hooks.json"
        case .antigravity: configuration = ".gemini/config/hooks.json"
        }
        try f.write(configuration, "{\"unrelated\":{\"keep\":true},\"statusLine\":{\"command\":\"existing helper\"}}")
        let original = try f.data(configuration)
        let initial = f.installer.check(client: client)
        #expect(!initial.isInstalled && !initial.hasConflict && !initial.canRemove)
        let installed = try f.installer.install(client: client)
        #expect(installed.isInstalled && installed.canRemove)
        #expect(installed.requiresTrustReview == (client == .codex))
        #expect(try f.json(configuration)["unrelated"] as? [String: Bool] == ["keep": true])
        #expect(try f.json(configuration)["statusLine"] as? [String: String] == ["command": "existing helper"])
        let firstConfig = try f.data(configuration)
        let firstManifest = try f.data("Library/Application Support/Usage Rings/agent-tools-v1.json")
        #expect(try f.installer.install(client: client).isInstalled)
        #expect(try f.data(configuration) == firstConfig)
        #expect(try f.data("Library/Application Support/Usage Rings/agent-tools-v1.json") == firstManifest)
        let removed = try f.installer.remove(client: client)
        #expect(!removed.isInstalled && !removed.canRemove && !removed.hasConflict)
        #expect(try f.json(configuration)["unrelated"] as? [String: Bool] == ["keep": true])
        #expect(try f.json(configuration)["statusLine"] as? [String: String] == ["command": "existing helper"])
        #expect(!f.exists(".local/bin/usage-rings"))
        let backupNames = try f.manager.contentsOfDirectory(at: f.home.appendingPathComponent(configuration).deletingLastPathComponent(), includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.contains(".ato-backup-") }
        #expect(try backupNames.contains { try Data(contentsOf: $0) == original })
        for backup in backupNames {
            let mode = try f.manager.attributesOfItem(atPath: backup.path)[.posixPermissions] as? NSNumber
            #expect(mode?.intValue == 0o600)
        }
    }

    @Test func sharedCLIStaysUntilTheLastAssistantIsRemoved() throws {
        let f = try Fixture()
        try f.installer.install(client: .codex)
        try f.installer.install(client: .claude)
        try f.installer.remove(client: .codex)
        #expect(f.exists(".local/bin/usage-rings"))
        #expect(f.installer.check(client: .claude).isInstalled)
        try f.installer.remove(client: .claude)
        #expect(!f.exists(".local/bin/usage-rings"))
    }

    @Test func anEditedOrExtraSkillFilePreventsAllChanges() throws {
        let f = try Fixture()
        try f.installer.install(client: .claude)
        let config = try f.data(".claude/settings.json")
        try f.write(".claude/skills/usage-rings-budget/SKILL.md", "user edited")
        #expect(f.installer.check(client: .claude).skill.state == .conflict)
        #expect(throws: (any Error).self) { try f.installer.install(client: .claude) }
        #expect(throws: (any Error).self) { try f.installer.remove(client: .claude) }
        #expect(try f.data(".claude/settings.json") == config)
        #expect(try String(data: f.data(".claude/skills/usage-rings-budget/SKILL.md"), encoding: .utf8) == "user edited")
    }

    @Test func identicalUnownedSkillIsAdoptedButExtraFilesAreProtected() throws {
        let f = try Fixture()
        let source = f.app.appendingPathComponent("Contents/Resources/Skills/usage-rings-budget")
        let destination = f.home.appendingPathComponent(".claude/skills/usage-rings-budget")
        try f.manager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try f.manager.copyItem(at: source, to: destination)
        #expect(!f.installer.check(client: .claude).hasConflict)
        try f.write(".claude/skills/usage-rings-budget/extra.txt", "keep me")
        #expect(f.installer.check(client: .claude).hasConflict)
        #expect(throws: (any Error).self) { try f.installer.install(client: .claude) }
        try f.manager.removeItem(at: destination.appendingPathComponent("extra.txt"))
        #expect(try f.installer.install(client: .claude).isInstalled)
    }

    @Test func codexUsesAgentsForNewSkillsAndProtectsAnExistingLegacySkill() throws {
        let f = try Fixture()
        try f.installer.install(client: .codex)
        #expect(f.exists(".agents/skills/usage-rings-budget/SKILL.md"))
        #expect(!f.exists(".codex/skills/usage-rings-budget/SKILL.md"))
        try f.installer.remove(client: .codex)
        try f.write(".codex/skills/usage-rings-budget/SKILL.md", "legacy customization")
        #expect(f.installer.check(client: .codex).hasConflict)
        #expect(throws: (any Error).self) { try f.installer.install(client: .codex) }
        #expect(!f.exists(".agents/skills/usage-rings-budget/SKILL.md"))
    }

    @Test func antigravityInstallsBothSkillSurfacesAndNamedHook() throws {
        let f = try Fixture()
        try f.write(".gemini/config/hooks.json", "{\"other-hook\":{\"PostInvocation\":[]}}")
        try f.installer.install(client: .antigravity)
        #expect(f.exists(".gemini/config/skills/usage-rings-budget/SKILL.md"))
        #expect(f.exists(".gemini/antigravity-cli/skills/usage-rings-budget/SKILL.md"))
        let json = try f.json(".gemini/config/hooks.json")
        #expect(json["hooks"] == nil)
        let own = try #require(json["ato-budget"] as? [String: Any])
        #expect((own["PreInvocation"] as? [[String: Any]])?.count == 1)
        try f.installer.remove(client: .antigravity)
        #expect(try f.json(".gemini/config/hooks.json")["other-hook"] != nil)
    }

    @Test func cursorPreservesExistingHandlersOnInstallAndRemove() throws {
        let f = try Fixture()
        try f.write(".cursor/hooks.json", "{\"version\":1,\"hooks\":{\"postToolUse\":[{\"command\":\"my helper\",\"timeout\":3}],\"stop\":[{\"command\":\"stop helper\"}]}}")
        try f.installer.install(client: .cursor)
        var hooks = try #require(f.json(".cursor/hooks.json")["hooks"] as? [String: Any])
        #expect((hooks["postToolUse"] as? [[String: Any]])?.count == 2)
        try f.installer.remove(client: .cursor)
        hooks = try #require(f.json(".cursor/hooks.json")["hooks"] as? [String: Any])
        #expect((hooks["postToolUse"] as? [[String: Any]])?.first?["command"] as? String == "my helper")
        #expect((hooks["stop"] as? [[String: Any]])?.first?["command"] as? String == "stop helper")
    }

    @Test(arguments: ["python3 /old/usage-rings-budget/scripts/usage_hook.py --client claude", "/old/UsageRingsBudgetHook --client claude"])
    func unownedBudgetHooksAreConflicts(_ command: String) throws {
        let f = try Fixture()
        let root: [String: Any] = ["hooks": ["PostToolUse": [["matcher": ".*", "hooks": [["type": "command", "command": command]]]]]]
        try f.write(".claude/settings.json", String(decoding: JSONSerialization.data(withJSONObject: root), as: UTF8.self))
        let original = try f.data(".claude/settings.json")
        #expect(f.installer.check(client: .claude).hasConflict)
        #expect(throws: (any Error).self) { try f.installer.install(client: .claude) }
        #expect(try f.data(".claude/settings.json") == original)
        #expect(!f.exists(".local/bin/usage-rings"))
    }

    @Test func changedOwnedHandlerIsProtectedAndOtherHandlersSurviveDisconnect() throws {
        let f = try Fixture()
        try f.installer.install(client: .claude)
        var root = try f.json(".claude/settings.json")
        var hooks = try #require(root["hooks"] as? [String: Any])
        var groups = try #require(hooks["PostToolUse"] as? [[String: Any]])
        var handlers = try #require(groups[0]["hooks"] as? [[String: Any]])
        let original = handlers[0]
        handlers[0]["timeout"] = 99
        groups[0]["hooks"] = handlers; hooks["PostToolUse"] = groups; root["hooks"] = hooks
        try f.write(".claude/settings.json", String(decoding: JSONSerialization.data(withJSONObject: root), as: UTF8.self))
        #expect(f.installer.check(client: .claude).hasConflict)
        handlers = [original, ["command": "other helper", "type": "command"]]
        groups[0]["hooks"] = handlers; hooks["PostToolUse"] = groups; root["hooks"] = hooks
        try f.write(".claude/settings.json", String(decoding: JSONSerialization.data(withJSONObject: root), as: UTF8.self))
        try f.installer.remove(client: .claude)
        let remaining = try #require(f.json(".claude/settings.json")["hooks"] as? [String: Any])
        let remainingGroups = try #require(remaining["PostToolUse"] as? [[String: Any]])
        #expect((remainingGroups[0]["hooks"] as? [[String: Any]])?.first?["command"] as? String == "other helper")
    }

    @Test func appMoveAndBundledSkillUpdateAreSafeManagedUpdates() throws {
        let f = try Fixture()
        try f.installer.install(client: .claude)
        let nextApp = f.root.appendingPathComponent("Updated ato.app")
        try f.bundle(nextApp, skill: "updated skill")
        let updatedInstaller = AgentToolsInstaller(appURL: nextApp, homeURL: f.home)
        let report = updatedInstaller.check(client: .claude)
        #expect(report.needsUpdate && !report.hasConflict)
        #expect(report.cli.state == .outdated && report.skill.state == .outdated && report.hook.state == .outdated)
        #expect(try updatedInstaller.install(client: .claude).isInstalled)
        #expect(try String(data: f.data(".claude/skills/usage-rings-budget/SKILL.md"), encoding: .utf8) == "updated skill")
        #expect(try f.manager.destinationOfSymbolicLink(atPath: f.home.appendingPathComponent(".local/bin/usage-rings").path) == nextApp.appendingPathComponent("Contents/Helpers/usage-rings").path)
    }

    @Test func unrelatedCLISymlinkAndSymlinkedConfigurationAreNeverFollowed() throws {
        let f = try Fixture()
        let cli = f.home.appendingPathComponent(".local/bin/usage-rings")
        try f.manager.createDirectory(at: cli.deletingLastPathComponent(), withIntermediateDirectories: true)
        try f.manager.createSymbolicLink(atPath: cli.path, withDestinationPath: "/unrelated/cli")
        #expect(f.installer.check(client: .claude).cli.state == .conflict)
        #expect(throws: (any Error).self) { try f.installer.install(client: .claude) }
        try f.manager.removeItem(at: cli)
        let outside = f.root.appendingPathComponent("outside-settings.json")
        try Data("{\"private\":\"leave unchanged\"}".utf8).write(to: outside)
        try f.manager.createDirectory(at: f.home.appendingPathComponent(".claude"), withIntermediateDirectories: true)
        try f.manager.createSymbolicLink(at: f.home.appendingPathComponent(".claude/settings.json"), withDestinationURL: outside)
        #expect(f.installer.check(client: .claude).hasConflict)
        #expect(throws: (any Error).self) { try f.installer.install(client: .claude) }
        #expect(try String(contentsOf: outside, encoding: .utf8) == "{\"private\":\"leave unchanged\"}")
    }

    @Test func symlinkedParentAndSkillAreRejectedBeforeMutation() throws {
        let f = try Fixture()
        let outside = f.root.appendingPathComponent("outside")
        try f.manager.createDirectory(at: outside, withIntermediateDirectories: true)
        try f.manager.createSymbolicLink(at: f.home.appendingPathComponent(".claude"), withDestinationURL: outside)
        #expect(f.installer.check(client: .claude).hasConflict)
        #expect(throws: (any Error).self) { try f.installer.install(client: .claude) }
        #expect(try f.manager.contentsOfDirectory(atPath: outside.path).isEmpty)
        #expect(!f.exists(".local/bin/usage-rings"))
    }

    @Test func malformedJSONAndUnsupportedCursorVersionDoNotChangeFiles() throws {
        let f = try Fixture()
        try f.write(".claude/settings.json", "malformed")
        #expect(f.installer.check(client: .claude).hasConflict)
        #expect(throws: (any Error).self) { try f.installer.install(client: .claude) }
        #expect(try String(data: f.data(".claude/settings.json"), encoding: .utf8) == "malformed")
        try f.write(".cursor/hooks.json", "{\"version\":true}")
        #expect(f.installer.check(client: .cursor).hasConflict)
        #expect(throws: (any Error).self) { try f.installer.install(client: .cursor) }
    }

    @Test func laterCLIFailureRollsBackSkillAndHook() throws {
        let f = try Fixture()
        try f.write(".claude/settings.json", "{\"keep\":true}")
        let binaryDirectory = f.home.appendingPathComponent(".local/bin")
        try f.manager.createDirectory(at: binaryDirectory, withIntermediateDirectories: true)
        try f.manager.setAttributes([.posixPermissions: 0o500], ofItemAtPath: binaryDirectory.path)
        defer { try? f.manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: binaryDirectory.path) }
        #expect(throws: (any Error).self) { try f.installer.install(client: .claude) }
        #expect(try String(data: f.data(".claude/settings.json"), encoding: .utf8) == "{\"keep\":true}")
        #expect(!f.exists(".local/bin/usage-rings"))
        #expect(!f.exists(".claude/skills/usage-rings-budget/SKILL.md"))
    }
    @Test func checkIsReadOnlyAndOnlyInspectsTheSelectedAssistant() throws {
        let f = try Fixture()
        #expect(try f.manager.contentsOfDirectory(atPath: f.home.path).isEmpty)
        #expect(!f.installer.check(client: .claude).hasConflict)
        #expect(try f.manager.contentsOfDirectory(atPath: f.home.path).isEmpty)
        try f.manager.createSymbolicLink(atPath: f.home.appendingPathComponent(".codex").path, withDestinationPath: "/not-read")
        #expect(try f.installer.install(client: .claude).isInstalled)
        #expect(!f.exists(".gemini"))
        #expect(!f.exists(".cursor"))
    }

    @Test func setupLockPreventsConcurrentAppCopiesWithoutChangingAssistantFiles() throws {
        let f = try Fixture()
        let directory = f.home.appendingPathComponent("Library/Application Support/Usage Rings")
        try f.manager.createDirectory(at: directory, withIntermediateDirectories: true)
        let lockURL = directory.appendingPathComponent("agent-tools.lock")
        let descriptor = open(lockURL.path, O_CREAT | O_RDWR, 0o600)
        #expect(descriptor >= 0)
        defer { flock(descriptor, LOCK_UN); close(descriptor) }
        #expect(flock(descriptor, LOCK_EX | LOCK_NB) == 0)
        #expect(throws: (any Error).self) { try f.installer.install(client: .claude) }
        #expect(!f.exists(".claude"))
        #expect(!f.exists(".local"))
        #expect(!f.exists("Library/Application Support/Usage Rings/agent-tools-v1.json"))
    }

    @Test func deepJSONAndFractionalCursorVersionsAreRejectedWithoutWrites() throws {
        let f = try Fixture()
        let deepJSON = "{\"unrelated\":" + String(repeating: "[", count: 80) + "0" + String(repeating: "]", count: 80) + "}"
        try f.write(".claude/settings.json", deepJSON)
        #expect(f.installer.check(client: .claude).hasConflict)
        #expect(throws: (any Error).self) { try f.installer.install(client: .claude) }
        #expect(try String(data: f.data(".claude/settings.json"), encoding: .utf8) == deepJSON)
        try f.write(".cursor/hooks.json", "{\"version\":1.5}")
        #expect(f.installer.check(client: .cursor).hasConflict)
        #expect(throws: (any Error).self) { try f.installer.install(client: .cursor) }
        #expect(!f.exists(".local/bin/usage-rings"))
    }

    @Test func shellMetacharactersAreQuotedInTheHookButNeverExecuted() throws {
        let f = try Fixture()
        try f.installer.install(client: .claude)
        let root = try f.json(".claude/settings.json")
        let hooks = try #require(root["hooks"] as? [String: Any])
        let groups = try #require(hooks["PostToolUse"] as? [[String: Any]])
        let handlers = try #require(groups[0]["hooks"] as? [[String: Any]])
        let command = try #require(handlers[0]["command"] as? String)
        #expect(command.contains("'\\''"))
        #expect(command.contains("$(never-run)"))
        #expect(command.contains(" --client claude --cli '"))
        #expect(!f.exists("never-run"))
    }

    @Test(arguments: [false, true])
    func repeatedEditorSavesAndOpenDescriptorsPreserveRecoveryContent(_ writesAfterRestore: Bool) throws {
        let f = try Fixture()
        let path = "settings.json"
        let previous = Data("original".utf8)
        let desired = Data("ato change".utf8)
        let firstEditor = Data("first editor save".utf8)
        let latestEditor = Data("latest editor save".utf8)
        try f.write(path, String(decoding: previous, as: UTF8.self))
        var swaps = 0
        var editorDescriptor: Int32 = -1
        var injectionFailure: Error?
        defer { if editorDescriptor >= 0 { close(editorDescriptor) } }
        let home = try AgentToolsSafeHome(f.home, renameItem: { fromDirectory, from, toDirectory, to, flags in
            if flags == UInt32(RENAME_SWAP) {
                swaps += 1
                do {
                    if swaps == 1 {
                        try firstEditor.write(to: f.home.appendingPathComponent(path), options: .atomic)
                    } else if writesAfterRestore {
                        // This editor keeps a descriptor to the inode moved into the recovery filename.
                        editorDescriptor = openat(toDirectory, to, O_WRONLY | O_NOFOLLOW)
                    } else {
                        // A second save arrives after the restore branch has compared the destination.
                        try latestEditor.write(to: f.home.appendingPathComponent(path), options: .atomic)
                    }
                } catch { injectionFailure = error; return -1 }
            }
            return renameatx_np(fromDirectory, from, toDirectory, to, flags)
        })
        #expect(throws: (any Error).self) {
            try home.replace(path, previous: .file(previous), desired: .file(desired))
        }
        #expect(injectionFailure == nil)
        #expect(swaps == 2)
        if writesAfterRestore {
            #expect(editorDescriptor >= 0)
            #expect(ftruncate(editorDescriptor, 0) == 0)
            let written = latestEditor.withUnsafeBytes { Darwin.write(editorDescriptor, $0.baseAddress, $0.count) }
            #expect(written == latestEditor.count)
        }
        #expect(try f.data(path) == firstEditor)
        let recovery = try f.manager.contentsOfDirectory(at: f.home, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix(".ato-setup-") }
        #expect(recovery.count == 1)
        if let file = recovery.first {
            #expect(try Data(contentsOf: file) == latestEditor)
            let mode = try f.manager.attributesOfItem(atPath: file.path)[.posixPermissions] as? NSNumber
            #expect(mode?.intValue == 0o600)
        }
    }

    @Test func antigravityDisconnectPreservesAddedHandlersAndInitialNameCollisionProtection() throws {
        let f = try Fixture()
        try f.installer.install(client: .antigravity)
        var root = try f.json(".gemini/config/hooks.json")
        var section = try #require(root["ato-budget"] as? [String: Any])
        var handlers = try #require(section["PreInvocation"] as? [[String: Any]])
        handlers.append(["type": "command", "command": "other helper", "timeout": 4])
        section["PreInvocation"] = handlers
        section["PostInvocation"] = [["type": "command", "command": "another helper"]]
        root["ato-budget"] = section
        root["unrelated"] = ["keep": true]
        try f.write(".gemini/config/hooks.json", String(decoding: JSONSerialization.data(withJSONObject: root), as: UTF8.self))
        let removed = try f.installer.remove(client: .antigravity)
        #expect(!removed.canRemove && !removed.isInstalled)
        #expect(!f.exists(".gemini/config/skills/usage-rings-budget/SKILL.md"))
        #expect(!f.exists(".gemini/antigravity-cli/skills/usage-rings-budget/SKILL.md"))
        #expect(!f.exists(".local/bin/usage-rings"))
        root = try f.json(".gemini/config/hooks.json")
        section = try #require(root["ato-budget"] as? [String: Any])
        handlers = try #require(section["PreInvocation"] as? [[String: Any]])
        #expect(handlers.count == 1)
        #expect(handlers[0]["command"] as? String == "other helper")
        #expect((section["PostInvocation"] as? [[String: Any]])?.first?["command"] as? String == "another helper")
        #expect(root["unrelated"] as? [String: Bool] == ["keep": true])
        // The remaining user-owned name still requires review before a future Set Up can claim it.
        #expect(f.installer.check(client: .antigravity).hasConflict)
        let disconnectedConfig = try f.data(".gemini/config/hooks.json")
        #expect(throws: (any Error).self) { try f.installer.install(client: .antigravity) }
        #expect(try f.data(".gemini/config/hooks.json") == disconnectedConfig)
    }

}
