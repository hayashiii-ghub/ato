import Foundation
import Testing
import UsageCore
@testable import UsageRings

@MainActor
struct CursorAccessConsentTests {
    @Test func cursorAuthorizationRequiresMonitoringConsentAndASelectedSetupState() async throws {
        for scenario in ["new", "off", "ready"] {
            let suite = "CursorAccessConsentTests.\(UUID().uuidString)"
            let defaults = try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            if scenario != "new" {
                defaults.set(1, forKey: "usageMonitoringConsentVersion")
                defaults.set(scenario == "ready", forKey: "usageMonitoringEnabled")
            }
            let probe = CursorAccessProbe(states: [.codex: .setupRequired])
            let store = UsageStore(defaults: defaults, fetch: { await probe.fetch($0) },
                                   authorizeCursor: { await probe.authorize() }, onPublish: {})
            defer { store.setEnabled(false) }
            if scenario == "ready" { await store.refresh() }

            #expect(!store.needsCursorAuthorization)
            await store.authorizeCursorAccess()

            #expect(await probe.authorizationCount == 0)
            #expect(await probe.fetchCount == (scenario == "ready" ? 4 : 0))
            #expect(!store.isAuthorizingCursor)
        }
    }

    @Test func deniedAccessStaysSetupRequiredWithoutAutomaticAuthorizationRetries() async throws {
        let suite = "CursorAccessConsentTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(1, forKey: "usageMonitoringConsentVersion")
        defaults.set(true, forKey: "usageMonitoringEnabled")
        let probe = CursorAccessProbe(states: [.grokBot: .setupRequired])
        let store = UsageStore(defaults: defaults, fetch: { await probe.fetch($0) },
                               authorizeCursor: { await probe.authorize() }, onPublish: {})
        defer { store.setEnabled(false) }
        await store.refresh()
        #expect(store.needsCursorAuthorization)

        await store.authorizeCursorAccess()
        #expect(store.snapshot.usage(for: .grokBot).state == .setupRequired)
        #expect(store.needsCursorAuthorization)
        #expect(!store.isAuthorizingCursor)
        #expect(await probe.authorizationCount == 1)
        #expect(await probe.fetchCount == 8)

        await store.refresh()
        await store.refresh()
        #expect(await probe.authorizationCount == 1)
        #expect(store.snapshot.usage(for: .grokBot).state == .setupRequired)
    }

    @Test(.timeLimit(.minutes(1))) func concurrentAuthorizationAndRefreshDoNotRepeatThePermissionRequest() async throws {
        let suite = "CursorAccessConsentTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(1, forKey: "usageMonitoringConsentVersion")
        defaults.set(true, forKey: "usageMonitoringEnabled")
        let probe = CursorAccessProbe(states: [.grokBot: .setupRequired], blocksAuthorization: true)
        let store = UsageStore(defaults: defaults, fetch: { await probe.fetch($0) },
                               authorizeCursor: { await probe.authorize() }, onPublish: {})
        defer { store.setEnabled(false) }
        await store.refresh()

        let authorization = Task { await store.authorizeCursorAccess() }
        await probe.waitForAuthorization()
        #expect(store.isAuthorizingCursor)
        await store.authorizeCursorAccess()
        await store.refresh()
        #expect(await probe.authorizationCount == 1)
        #expect(await probe.fetchCount == 4)

        await probe.releaseAuthorization()
        await authorization.value
        #expect(!store.isAuthorizingCursor)
        #expect(await probe.authorizationCount == 1)
        #expect(await probe.fetchCount == 8)
    }

    @Test(.timeLimit(.minutes(1))) func disablingDuringAuthorizationCannotResumeReadsOrRestoreUsage() async throws {
        let suite = "CursorAccessConsentTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(1, forKey: "usageMonitoringConsentVersion")
        defaults.set(true, forKey: "usageMonitoringEnabled")
        let probe = CursorAccessProbe(states: [.grokBot: .setupRequired], blocksAuthorization: true)
        let store = UsageStore(defaults: defaults, fetch: { await probe.fetch($0) },
                               authorizeCursor: { await probe.authorize() }, onPublish: {})
        await store.refresh()

        let authorization = Task { await store.authorizeCursorAccess() }
        await probe.waitForAuthorization()
        store.setEnabled(false)
        await probe.releaseAuthorization()
        await authorization.value

        #expect(!store.isEnabled)
        #expect(!store.isAuthorizingCursor)
        #expect(!store.needsCursorAuthorization)
        #expect(store.snapshot == .empty)
        #expect(await probe.authorizationCount == 1)
        #expect(await probe.fetchCount == 4)
    }
}

private actor CursorAccessProbe {
    private let states: [UsageService: UsageState]
    private var blocksAuthorization: Bool
    private var pendingAuthorization: CheckedContinuation<Void, Never>?
    private var authorizationWaiters: [CheckedContinuation<Void, Never>] = []
    private(set) var authorizationCount = 0
    private(set) var fetchCount = 0

    init(states: [UsageService: UsageState], blocksAuthorization: Bool = false) {
        self.states = states
        self.blocksAuthorization = blocksAuthorization
    }

    func fetch(_ service: UsageService) -> ServiceUsage {
        fetchCount += 1
        let state = states[service] ?? .ready
        return ServiceUsage(service: service, state: state, windows: state == .ready ? [
            UsageWindow(id: "test", title: "Test", usedPercent: 20, resetsAt: nil)
        ] : [], updatedAt: state == .ready ? Date() : nil)
    }

    func authorize() async {
        authorizationCount += 1
        for waiter in authorizationWaiters { waiter.resume() }
        authorizationWaiters.removeAll()
        if blocksAuthorization {
            await withCheckedContinuation { pendingAuthorization = $0 }
        }
    }

    func waitForAuthorization() async {
        guard authorizationCount == 0 else { return }
        await withCheckedContinuation { authorizationWaiters.append($0) }
    }

    func releaseAuthorization() {
        blocksAuthorization = false
        pendingAuthorization?.resume()
        pendingAuthorization = nil
    }
}
