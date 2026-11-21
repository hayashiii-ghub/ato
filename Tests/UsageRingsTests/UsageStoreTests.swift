import Combine
import Foundation
import Testing
import UsageCore
@testable import UsageRings

struct UsageStoreTests {
    @Test @MainActor func ringLayoutFollowsTheLastSuccessfulRefreshAcrossPlanChanges() async throws {
        let suite = "UsageStoreTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(2, forKey: "usageMonitoringConsentVersion")
        defaults.set(true, forKey: "usageMonitoringEnabled")
        let now = Date()
        let fiveHours = UsageWindow(id: "primary", title: "5 hours", usedPercent: 20, resetsAt: nil,
                                    period: .fiveHours)
        let week = UsageWindow(id: "secondary", title: "Week", usedPercent: 30, resetsAt: nil, period: .week)
        let both = ServiceUsage(service: .codex, state: .ready, windows: [fiveHours, week], updatedAt: now)
        let weekly = ServiceUsage(service: .codex, state: .ready, windows: [week], updatedAt: now)
        let failure = ServiceUsage(service: .codex, state: .unavailable)
        let usage = [both, failure, weekly, failure, both]
        let expected: [UsageRingValues] = [
            .split(top: .init(title: "5h", remaining: 80), bottom: .init(title: "Week", remaining: 70)),
            .split(top: .init(title: "5h", remaining: nil), bottom: .init(title: "Week", remaining: nil)),
            .single(.init(title: "Week", remaining: 70)),
            .single(.init(title: "Week", remaining: nil)),
            .split(top: .init(title: "5h", remaining: 80), bottom: .init(title: "Week", remaining: 70))
        ]
        let source = RefreshSequence(usage)
        let store = UsageStore(defaults: defaults, fetch: { service in
            guard service == .codex else { return ServiceUsage(service: service, state: .unavailable) }
            return await source.next()
        }, onPublish: {})

        for layout in expected {
            await store.refresh()
            #expect(store.snapshot.usage(for: .codex).ringValues(at: now) == layout)
        }
    }

    @Test(.timeLimit(.minutes(1))) @MainActor func reenabledMonitoringStartsBeforeAnOldRefreshFinishes() async throws {
        let suite = "UsageStoreTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(2, forKey: "usageMonitoringConsentVersion")
        defaults.set(true, forKey: "usageMonitoringEnabled")
        let gate = FetchGate()
        let store = UsageStore(defaults: defaults, fetch: { await gate.fetch($0) }, onPublish: {})
        defer { store.setEnabled(false) }
        let firstRefresh = Task { await store.refresh() }
        await gate.waitForRequests(4)
        #expect(store.isRefreshing)

        store.setEnabled(false)
        #expect(!store.isRefreshing)
        #expect(store.snapshot == .empty)
        store.setEnabled(true)
        await gate.waitForRequests(8)
        #expect(store.isRefreshing)

        await gate.finishBatch(usedPercent: 80)
        await firstRefresh.value
        #expect(store.isRefreshing)
        #expect(store.snapshot == .empty)

        await gate.finishBatch(usedPercent: 20)
        for await snapshot in store.$snapshot.values {
            if snapshot != .empty {
                #expect(snapshot.services.count == 4)
                #expect(snapshot.services.allSatisfy { $0.windows.first?.usedPercent == 20 })
                break
            }
        }
    }

    @Test(.timeLimit(.minutes(1))) @MainActor func assigningTheExistingEnabledValueKeepsTheActiveRefresh() async throws {
        let suite = "UsageStoreTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(2, forKey: "usageMonitoringConsentVersion")
        defaults.set(true, forKey: "usageMonitoringEnabled")
        let gate = FetchGate()
        let store = UsageStore(defaults: defaults, fetch: { await gate.fetch($0) }, onPublish: {})
        defer { store.setEnabled(false) }
        let refresh = Task { await store.refresh() }
        await gate.waitForRequests(4)
        store.setEnabled(true)
        await gate.finishBatch(usedPercent: 20)
        await refresh.value

        #expect(!store.isRefreshing)
        #expect(store.snapshot.services.count == 4)
        #expect(store.snapshot.services.allSatisfy { $0.windows.first?.usedPercent == 20 })
        #expect(await gate.receivedCount == 4)
    }

    private actor RefreshSequence {
        private var readings: ArraySlice<ServiceUsage>

        init(_ readings: [ServiceUsage]) { self.readings = readings[...] }

        func next() -> ServiceUsage {
            readings.popFirst() ?? ServiceUsage(service: .codex, state: .unavailable)
        }
    }

    private actor FetchGate {
        private struct Request {
            let service: UsageService
            let continuation: CheckedContinuation<ServiceUsage, Never>
        }

        private var requests: [Request] = []
        private var waiters: [(Int, CheckedContinuation<Void, Never>)] = []
        private(set) var receivedCount = 0

        func fetch(_ service: UsageService) async -> ServiceUsage {
            await withCheckedContinuation { continuation in
                requests.append(Request(service: service, continuation: continuation))
                receivedCount += 1
                for (count, waiter) in waiters where count <= receivedCount { waiter.resume() }
                waiters.removeAll { $0.0 <= receivedCount }
            }
        }

        func waitForRequests(_ count: Int) async {
            guard receivedCount < count else { return }
            await withCheckedContinuation { waiters.append((count, $0)) }
        }

        func finishBatch(usedPercent: Double) {
            let batch = Array(requests.prefix(4))
            requests.removeFirst(batch.count)
            for request in batch {
                request.continuation.resume(returning: ServiceUsage(
                    service: request.service, state: .ready,
                    windows: [UsageWindow(id: "test", title: "Test", usedPercent: usedPercent, resetsAt: nil)],
                    updatedAt: Date()
                ))
            }
        }
    }
}
