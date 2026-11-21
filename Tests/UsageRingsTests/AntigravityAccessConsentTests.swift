import Foundation
import Testing
import UsageCore
@testable import UsageRings

@MainActor
struct AntigravityAccessConsentTests {
    @Test func antigravityAuthorizationRequiresMonitoringConsentAndASelectedSetupState() async throws {
        for scenario in ["new", "off", "ready"] {
            let suite = "AntigravityAccessConsentTests.\(UUID().uuidString)"
            let defaults = try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            if scenario != "new" {
                defaults.set(2, forKey: "usageMonitoringConsentVersion")
                defaults.set(scenario == "ready", forKey: "usageMonitoringEnabled")
            }
            let probe = AntigravityAccessProbe(states: [.codex: .setupRequired])
            let store = UsageStore(defaults: defaults, fetch: { await probe.fetch($0) },
                                   authorizeAntigravity: { await probe.authorize() }, onPublish: {})
            defer { store.setEnabled(false) }
            if scenario == "ready" { await store.refresh() }

            #expect(!store.needsAntigravityAuthorization)
            await store.authorizeAntigravityAccess()

            #expect(await probe.authorizationCount == 0)
            #expect(await probe.fetchCount == (scenario == "ready" ? 4 : 0))
            #expect(!store.isAuthorizingAntigravity)
        }
    }

    @Test func deniedAccessStaysSetupRequiredWithoutAutomaticAuthorizationRetries() async throws {
        let suite = "AntigravityAccessConsentTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(2, forKey: "usageMonitoringConsentVersion")
        defaults.set(true, forKey: "usageMonitoringEnabled")
        let probe = AntigravityAccessProbe(states: [.gemini: .setupRequired])
        let store = UsageStore(defaults: defaults, fetch: { await probe.fetch($0) },
                               authorizeAntigravity: { await probe.authorize() }, onPublish: {})
        defer { store.setEnabled(false) }
        await store.refresh()
        #expect(store.needsAntigravityAuthorization)

        await store.authorizeAntigravityAccess()
        #expect(store.snapshot.usage(for: .gemini).state == .setupRequired)
        #expect(store.needsAntigravityAuthorization)
        #expect(!store.isAuthorizingAntigravity)
        #expect(await probe.authorizationCount == 1)
        #expect(await probe.fetchCount == 8)

        await store.refresh()
        await store.refresh()
        #expect(await probe.authorizationCount == 1)
        #expect(store.snapshot.usage(for: .gemini).state == .setupRequired)
    }

    @Test(.timeLimit(.minutes(1))) func concurrentAuthorizationAndRefreshDoNotRepeatThePermissionRequest() async throws {
        let suite = "AntigravityAccessConsentTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(2, forKey: "usageMonitoringConsentVersion")
        defaults.set(true, forKey: "usageMonitoringEnabled")
        let probe = AntigravityAccessProbe(states: [.gemini: .setupRequired], blocksAuthorization: true)
        let store = UsageStore(defaults: defaults, fetch: { await probe.fetch($0) },
                               authorizeAntigravity: { await probe.authorize() }, onPublish: {})
        defer { store.setEnabled(false) }
        await store.refresh()

        let authorization = Task { await store.authorizeAntigravityAccess() }
        await probe.waitForAuthorization()
        #expect(store.isAuthorizingAntigravity)
        await store.authorizeAntigravityAccess()
        await store.refresh()
        #expect(await probe.authorizationCount == 1)
        #expect(await probe.fetchCount == 4)

        await probe.releaseAuthorization()
        await authorization.value
        #expect(!store.isAuthorizingAntigravity)
        #expect(await probe.authorizationCount == 1)
        #expect(await probe.fetchCount == 8)
    }

    @Test(.timeLimit(.minutes(1))) func disablingDuringAuthorizationCannotResumeReadsOrRestoreUsage() async throws {
        let suite = "AntigravityAccessConsentTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(2, forKey: "usageMonitoringConsentVersion")
        defaults.set(true, forKey: "usageMonitoringEnabled")
        let probe = AntigravityAccessProbe(states: [.gemini: .setupRequired], blocksAuthorization: true)
        let store = UsageStore(defaults: defaults, fetch: { await probe.fetch($0) },
                               authorizeAntigravity: { await probe.authorize() }, onPublish: {})
        await store.refresh()

        let authorization = Task { await store.authorizeAntigravityAccess() }
        await probe.waitForAuthorization()
        store.setEnabled(false)
        await probe.releaseAuthorization()
        await authorization.value

        #expect(!store.isEnabled)
        #expect(!store.isAuthorizingAntigravity)
        #expect(!store.needsAntigravityAuthorization)
        #expect(store.snapshot == .empty)
        #expect(await probe.authorizationCount == 1)
        #expect(await probe.fetchCount == 4)
    }
}

private actor AntigravityAccessProbe {
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
