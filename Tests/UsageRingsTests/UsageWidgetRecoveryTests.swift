import Darwin
import Foundation
import Testing
@testable import UsageRings

@MainActor
struct UsageWidgetRecoveryTests {
    private let appURL = URL(fileURLWithPath: "/Applications/Usage Rings.app")
    private let userID: uid_t = 501

    @Test func aNewBuildStopsOnlyThisInstallationsWidgetAndDoesNotRepeatOnRelaunch() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let client = Client(processes: [process(101), process(102, userID: 502),
                                        process(103, appURL: URL(fileURLWithPath: "/Applications/Other/Usage Rings.app")),
                                        process(104, pathSuffix: ".other")])
        var reloads = 0
        func recovery(build: String = "86") -> UsageWidgetRecovery {
            UsageWidgetRecovery(defaults: fixture.defaults, appURL: appURL, version: "0.2.10", build: build,
                                userID: userID, client: client, reload: { reloads += 1 })
        }
        await recovery().recoverIfNeeded()
        #expect(await client.terminatedPIDs == [101])
        #expect(reloads == 1)
        #expect(await client.enumerations == 1)
        await recovery().recoverIfNeeded()
        #expect(await client.enumerations == 1)
        #expect(reloads == 1)
        await recovery(build: "87").recoverIfNeeded()
        #expect(await client.enumerations == 2)
        #expect(reloads == 2)
    }

    @Test func aPIDWhoseIdentityChangedIsNotSignaled() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let original = process(101)
        let replacement = UsageWidgetProcess(pid: original.pid, userID: original.userID,
                                             startedAt: "Mon Nov 2 12:45:00 2026", executablePath: original.executablePath)
        let client = Client(processes: [original], replacementsBeforeTermination: [101: replacement])
        var reloads = 0
        let recovery = UsageWidgetRecovery(defaults: fixture.defaults, appURL: appURL, version: "0.2.10", build: "86",
                                           userID: userID, client: client, reload: { reloads += 1 })
        await recovery.recoverIfNeeded()
        #expect(await client.terminatedPIDs.isEmpty)
        #expect(reloads == 1)
    }

    @Test func aWidgetThatDoesNotExitIsNotSignaledAgainOrMarkedRecovered() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let client = Client(processes: [process(101)], exitsAfterTermination: false)
        var reloads = 0
        let recovery = UsageWidgetRecovery(defaults: fixture.defaults, appURL: appURL, version: "0.2.10", build: "86",
                                           userID: userID, client: client, exitTimeout: .milliseconds(1), reload: { reloads += 1 })
        await recovery.recoverIfNeeded()
        #expect(await client.terminatedPIDs == [101])
        #expect(reloads == 0)
        await client.allowExitAfterTermination()
        await recovery.recoverIfNeeded()
        #expect(await client.terminatedPIDs == [101, 101])
        #expect(reloads == 1)
    }

    @Test func enumerationAndTerminationFailuresCanRetryOnTheNextLaunch() async throws {
        for failure in [Client.Failure.enumeration, .termination] {
            let fixture = try Fixture()
            defer { fixture.cleanUp() }
            let client = Client(processes: [process(101)], failure: failure)
            var reloads = 0
            func recovery() -> UsageWidgetRecovery {
                UsageWidgetRecovery(defaults: fixture.defaults, appURL: appURL, version: "0.2.10", build: "86",
                                    userID: userID, client: client, reload: { reloads += 1 })
            }
            await recovery().recoverIfNeeded()
            #expect(reloads == 0)
            await client.clearFailure()
            await recovery().recoverIfNeeded()
            #expect(await client.enumerations == 2)
            #expect(reloads == 1)
        }
    }

    @Test func installingTheSameBuildAtAnotherPathHasItsOwnRecoveryHistory() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let firstClient = Client(processes: [])
        let secondClient = Client(processes: [])
        var reloads = 0
        let first = UsageWidgetRecovery(defaults: fixture.defaults, appURL: appURL, version: "0.2.10", build: "86",
                                        userID: userID, client: firstClient, reload: { reloads += 1 })
        let second = UsageWidgetRecovery(defaults: fixture.defaults,
                                         appURL: URL(fileURLWithPath: "/Users/example/Applications/Usage Rings.app"),
                                         version: "0.2.10", build: "86", userID: userID,
                                         client: secondClient, reload: { reloads += 1 })
        await first.recoverIfNeeded()
        await second.recoverIfNeeded()
        #expect(await firstClient.enumerations == 1)
        #expect(await secondClient.enumerations == 1)
        #expect(reloads == 2)
    }

    @Test func psParsingPreservesSpacesAndRejectsAmbiguousOrInvalidRows() {
        let path = appURL.appendingPathComponent("Contents/PlugIns/UsageRingsWidget.appex/Contents/MacOS/UsageRingsWidget").path
        let parsed = UsageWidgetProcess.parse("  501 Mon Nov  2 12:01:30 2026 \(path)\n", pid: 101)
        #expect(parsed?.userID == 501)
        #expect(parsed?.executablePath == path)
        #expect(parsed?.startedAt == "Mon Nov 2 12:01:30 2026")
        #expect(UsageWidgetProcess.parse("501 \(path)", pid: 101) == nil)
        #expect(UsageWidgetProcess.parse("501 Mon Nov 2 12:01:30 2026 relative/path", pid: 101) == nil)
        #expect(UsageWidgetProcess.parse("501 Mon Nov 2 12:01:30 2026 \(path)\n501 Mon Nov 2 12:01:30 2026 \(path)", pid: 101) == nil)
        #expect(UsageWidgetProcess.parse("501 Mon Nov 2 12:01:30 2026 \(path)", pid: 0) == nil)
    }

    private func process(_ pid: pid_t, userID: uid_t? = nil, appURL: URL? = nil, pathSuffix: String = "") -> UsageWidgetProcess {
        UsageWidgetProcess(pid: pid, userID: userID ?? self.userID, startedAt: "Mon Nov 2 12:01:30 2026",
                           executablePath: (appURL ?? self.appURL)
                            .appendingPathComponent("Contents/PlugIns/UsageRingsWidget.appex/Contents/MacOS/UsageRingsWidget").path + pathSuffix)
    }

    private final class Fixture {
        let name = "UsageWidgetRecoveryTests.\(UUID().uuidString)"
        let defaults: UserDefaults
        init() throws { defaults = try #require(UserDefaults(suiteName: name)) }
        func cleanUp() { defaults.removePersistentDomain(forName: name) }
    }

    private actor Client: UsageWidgetRecoveryClient {
        enum Failure: Error, Equatable { case enumeration, termination }
        var enumerations = 0
        var terminatedPIDs: [pid_t] = []
        private var processes: [pid_t: UsageWidgetProcess]
        private var inspections: [pid_t: Int] = [:]
        private var replacementsBeforeTermination: [pid_t: UsageWidgetProcess]
        private var exitsAfterTermination: Bool
        private var failure: Failure?

        init(processes: [UsageWidgetProcess], replacementsBeforeTermination: [pid_t: UsageWidgetProcess] = [:],
             exitsAfterTermination: Bool = true, failure: Failure? = nil) {
            self.processes = Dictionary(uniqueKeysWithValues: processes.map { ($0.pid, $0) })
            self.replacementsBeforeTermination = replacementsBeforeTermination
            self.exitsAfterTermination = exitsAfterTermination
            self.failure = failure
        }

        func candidatePIDs() throws -> [pid_t] {
            enumerations += 1
            if failure == .enumeration { throw Failure.enumeration }
            return processes.keys.sorted()
        }

        func inspect(_ pid: pid_t) -> UsageWidgetProcess? {
            inspections[pid, default: 0] += 1
            if inspections[pid] == 2, let replacement = replacementsBeforeTermination[pid] { processes[pid] = replacement }
            return processes[pid]
        }

        func terminate(_ pid: pid_t) throws {
            if failure == .termination { throw Failure.termination }
            terminatedPIDs.append(pid)
            if exitsAfterTermination { processes.removeValue(forKey: pid) }
        }

        func clearFailure() { failure = nil }
        func allowExitAfterTermination() { exitsAfterTermination = true }
    }
}
