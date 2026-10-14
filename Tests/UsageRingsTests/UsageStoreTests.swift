import Combine
import Foundation
import Testing
import UsageCore
@testable import UsageRings

struct UsageStoreTests {
    @Test(.timeLimit(.minutes(1))) @MainActor func reenabledMonitoringStartsBeforeAnOldRefreshFinishes() async throws {
        let suite = "UsageStoreTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(1, forKey: "usageMonitoringConsentVersion")
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
        defaults.set(1, forKey: "usageMonitoringConsentVersion")
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
