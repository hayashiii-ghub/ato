import Foundation
import Testing
import UsageCore
@testable import UsageRings

@MainActor
struct MonitoringConsentTests {
    @Test func newAndLegacyPreferencesCannotReadAccountsBeforeConsent() async throws {
        for previous in [nil, false, true] as [Bool?] {
            let name = "UsageRingsConsentTests.\(UUID().uuidString)"
            let defaults = try #require(UserDefaults(suiteName: name))
            defer { defaults.removePersistentDomain(forName: name) }
            if let previous { defaults.set(previous, forKey: "usageMonitoringEnabled") }
            let probe = FetchProbe()
            let store = UsageStore(defaults: defaults, fetch: { await probe.fetch($0) }, onPublish: {})
            #expect(store.needsConsent)
            #expect(!store.isEnabled)
            store.setEnabled(true) // An ordinary toggle cannot bypass the explanation's enable action.
            await store.refresh()  // Menu refresh and deep links use this same guarded method.
            #expect(await probe.count == 0)
            #expect(store.snapshot == .empty)
            #expect(defaults.object(forKey: "usageMonitoringConsentVersion") == nil)
            #expect((defaults.object(forKey: "usageMonitoringEnabled") as? Bool) == previous)
        }
    }

    @Test func explicitEnableIsRememberedAndAnOffChoiceSurvivesRelaunch() async throws {
        let name = "UsageRingsConsentTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let probe = FetchProbe()
        let store = UsageStore(defaults: defaults, fetch: { await probe.fetch($0) }, onPublish: {})
        store.enableAfterConsent()
        defer { store.setEnabled(false) }
        try await waitForFetches(probe)
        #expect(!store.needsConsent)
        #expect(store.isEnabled)
        #expect(defaults.integer(forKey: "usageMonitoringConsentVersion") == 1)
        let enabledRelaunch = UsageStore(defaults: defaults, fetch: { await probe.fetch($0) }, onPublish: {})
        #expect(enabledRelaunch.isEnabled)
        #expect(!enabledRelaunch.needsConsent)
        store.setEnabled(false)
        let offRelaunch = UsageStore(defaults: defaults, fetch: { await probe.fetch($0) }, onPublish: {})
        #expect(!offRelaunch.isEnabled)
        #expect(!offRelaunch.needsConsent)
        await offRelaunch.refresh()
        #expect(await probe.count == 4)
    }

    @Test func disablingWhileAReadIsInFlightCannotRestoreDisplayData() async throws {
        let name = "UsageRingsConsentTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let probe = FetchProbe(blocked: true)
        let store = UsageStore(defaults: defaults, fetch: { await probe.fetch($0) }, onPublish: {})
        store.enableAfterConsent()
        try await waitForFetches(probe)
        store.setEnabled(false)
        await probe.release()
        for _ in 0..<1_000 where store.isRefreshing { try await Task.sleep(for: .milliseconds(1)) }
        #expect(!store.isRefreshing)
        #expect(store.snapshot == .empty)
        await store.refresh()
        #expect(await probe.count == 4)
    }

    @Test func unknownConsentVersionDoesNotAuthorizeFutureConnections() async throws {
        let name = "UsageRingsConsentTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(999, forKey: "usageMonitoringConsentVersion")
        defaults.set(true, forKey: "usageMonitoringEnabled")
        let probe = FetchProbe()
        let store = UsageStore(defaults: defaults, fetch: { await probe.fetch($0) }, onPublish: {})
        #expect(store.needsConsent)
        #expect(!store.isEnabled)
        await store.refresh()
        #expect(await probe.count == 0)
    }

    private func waitForFetches(_ probe: FetchProbe) async throws {
        for _ in 0..<1_000 {
            if await probe.count == 4 { return }
            try await Task.sleep(for: .milliseconds(1))
        }
        Issue.record("The explicitly enabled store did not fetch the four providers")
    }
}

private actor FetchProbe {
    private(set) var count = 0
    private var blocked: Bool
    private var continuations: [CheckedContinuation<Void, Never>] = []

    init(blocked: Bool = false) { self.blocked = blocked }

    func fetch(_ service: UsageService) async -> ServiceUsage {
        count += 1
        if blocked { await withCheckedContinuation { continuations.append($0) } }
        return ServiceUsage(service: service, state: .ready, windows: [
            UsageWindow(id: "test", title: "Test", usedPercent: 40, resetsAt: nil)
        ], updatedAt: Date())
    }

    func release() {
        blocked = false
        for continuation in continuations { continuation.resume() }
        continuations.removeAll()
    }
}
