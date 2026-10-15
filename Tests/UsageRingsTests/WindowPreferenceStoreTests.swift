import Foundation
import Testing
import UsageCore
@testable import UsageRings

@MainActor
struct WindowPreferenceStoreTests {
    @Test func preferencesPersistWithoutReadingAccountsBeforeConsentAndAutoRemovesTheChoice() async throws {
        let name = "WindowPreferenceStoreTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let probe = ReadProbe()
        let store = UsageStore(defaults: defaults, fetch: { await probe.fetch($0) }, onPublish: {})
        store.setPreferredPeriod(.fiveHours, for: .codex)
        store.setPreferredPeriod(.week, for: .gemini)
        #expect(store.preferredPeriods == [.codex: .fiveHours, .gemini: .week])
        #expect(store.snapshot.usage(for: .codex).preferredPeriod == .fiveHours)
        #expect(store.snapshot.usage(for: .gemini).preferredPeriod == .week)
        #expect(store.snapshot.services.allSatisfy { $0.state == .disabled })
        #expect(defaults.dictionary(forKey: "usagePreferredPeriods") as? [String: String]
                == ["codex": "fiveHours", "gemini": "week"])

        store.setEnabled(true)
        await store.refresh()
        #expect(await probe.reads.isEmpty)
        let relaunched = UsageStore(defaults: defaults, onPublish: {})
        #expect(relaunched.needsConsent && !relaunched.isEnabled)
        #expect(relaunched.preferredPeriods == store.preferredPeriods)
        #expect(relaunched.snapshot.usage(for: .gemini).preferredPeriod == .week)
        store.setPreferredPeriod(nil, for: .codex)
        #expect(store.preferredPeriods[.codex] == nil)
        #expect(store.snapshot.usage(for: .codex).preferredPeriod == nil)
        #expect(defaults.dictionary(forKey: "usagePreferredPeriods") as? [String: String] == ["gemini": "week"])
    }

    @Test func invalidSavedProvidersPeriodsAndValueTypesAreIgnored() throws {
        let name = "WindowPreferenceStoreTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let saved: [String: Any] = [
            "codex": "fiveHours", "claude": "week", "gemini": "future-period",
            "future-provider": "week", "cursor": true, "grokBot": 42
        ]
        defaults.set(saved, forKey: "usagePreferredPeriods")
        let store = UsageStore(defaults: defaults, onPublish: {})
        #expect(store.preferredPeriods == [.codex: .fiveHours, .claude: .week])
        #expect(store.snapshot.usage(for: .codex).preferredPeriod == .fiveHours)
        #expect(store.snapshot.usage(for: .claude).preferredPeriod == .week)
        #expect(store.snapshot.usage(for: .gemini).preferredPeriod == nil)
        #expect(store.snapshot.usage(for: .cursor).preferredPeriod == nil)
    }

    @Test func changingPeriodsDoesNotReadAgainAndTheChoiceFollowsTheProvider() async throws {
        let name = "WindowPreferenceStoreTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(1, forKey: "usageMonitoringConsentVersion")
        defaults.set(true, forKey: "usageMonitoringEnabled")
        let probe = ReadProbe()
        var publications = 0
        let store = UsageStore(defaults: defaults, fetch: { await probe.fetch($0) }, onPublish: { publications += 1 })
        defer { store.setEnabled(false) }
        await store.refresh()
        let previous = store.snapshot.usage(for: .codex)
        #expect(await probe.reads.count == 4)
        let publishedBefore = publications
        store.setPreferredPeriod(.week, for: .codex)
        #expect(publications == publishedBefore + 1)
        #expect(store.snapshot.usage(for: .codex).preferredPeriod == .week)
        #expect(store.snapshot.usage(for: .codex).windows == previous.windows)
        #expect(store.snapshot.usage(for: .codex).updatedAt == previous.updatedAt)
        #expect(await probe.reads.count == 4)
        store.moveRing(from: 0, to: 3)
        #expect(store.ringOrder[3] == .codex)
        #expect(store.snapshot.usage(for: .codex).preferredPeriod == .week)

        store.setEnabled(false)
        #expect(store.snapshot.usage(for: .codex).preferredPeriod == .week)
        store.selectRing(.gemini, at: 3)
        #expect(store.snapshot.usage(for: .codex).state == .disabled)
        #expect(store.preferredPeriods[.codex] == .week)
        store.selectRing(.codex, at: 3)
        #expect(store.snapshot.usage(for: .codex).preferredPeriod == .week)
        #expect(await probe.reads.count == 4)
    }

    @Test(.timeLimit(.minutes(1))) func pendingReadsUseTheLatestPreferenceWithoutCancellationOrAnotherRead() async throws {
        let name = "WindowPreferenceStoreTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(1, forKey: "usageMonitoringConsentVersion")
        defaults.set(true, forKey: "usageMonitoringEnabled")
        let probe = ReadProbe(blocked: true)
        let store = UsageStore(defaults: defaults, fetch: { await probe.fetch($0) }, onPublish: {})
        defer { store.setEnabled(false) }
        let refresh = Task { await store.refresh() }
        await probe.waitForReads(4)
        store.setPreferredPeriod(.week, for: .codex)
        store.setPreferredPeriod(.fiveHours, for: .claude)
        store.setPreferredPeriod(nil, for: .claude)
        store.moveRing(from: 0, to: 3)
        #expect(store.isRefreshing)
        #expect(await probe.reads.count == 4)
        await probe.release()
        await refresh.value

        #expect(!store.isRefreshing)
        #expect(store.snapshot.services.allSatisfy { $0.state == .ready })
        #expect(store.snapshot.usage(for: .codex).preferredPeriod == .week)
        #expect(store.snapshot.usage(for: .claude).preferredPeriod == nil)
        #expect(store.snapshot.ringOrder == store.ringOrder)
        #expect(await probe.reads.count == 4)
    }

    private actor ReadProbe {
        private let blocked: Bool
        private(set) var reads: [UsageService] = []
        private var pending: [(UsageService, CheckedContinuation<ServiceUsage, Never>)] = []
        private var waiters: [(Int, CheckedContinuation<Void, Never>)] = []

        init(blocked: Bool = false) { self.blocked = blocked }

        func fetch(_ service: UsageService) async -> ServiceUsage {
            reads.append(service)
            for (count, waiter) in waiters where count <= reads.count { waiter.resume() }
            waiters.removeAll { $0.0 <= reads.count }
            if !blocked { return reading(service) }
            return await withCheckedContinuation { pending.append((service, $0)) }
        }

        func waitForReads(_ count: Int) async {
            if reads.count < count { await withCheckedContinuation { waiters.append((count, $0)) } }
        }

        func release() {
            let readings = pending
            pending.removeAll()
            for (service, continuation) in readings { continuation.resume(returning: reading(service)) }
        }

        private func reading(_ service: UsageService) -> ServiceUsage {
            ServiceUsage(service: service, state: .ready, windows: [
                UsageWindow(id: "primary", title: "5 hours", usedPercent: 20, resetsAt: nil),
                UsageWindow(id: "secondary", title: "Week", usedPercent: 80, resetsAt: nil)
            ], updatedAt: Date(), preferredPeriod: .fiveHours)
        }
    }
}
