import Combine
import Foundation
import Testing
import UsageCore
@testable import UsageRings

@MainActor
struct RingPreferencesTests {
    @Test func selectionAndOrderPersistWhileMonitoringIsOff() async throws {
        let name = "RingPreferencesTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let probe = ReadProbe()
        let store = UsageStore(defaults: defaults, fetch: { await probe.fetch($0) }, onPublish: {})
        store.selectRing(.gemini, at: 0)
        store.moveRing(from: 3, to: 0)
        store.selectRing(.cursor, at: 1)
        let expected: [UsageService] = [.grokBot, .cursor, .claude, .gemini]
        #expect(store.ringOrder == expected)
        #expect(store.snapshot.ringOrder == expected)
        #expect(store.snapshot.services.allSatisfy { $0.state == .disabled })
        #expect(defaults.stringArray(forKey: "usageRingOrder") == expected.map(\.rawValue))

        store.setEnabled(true)
        await store.refresh()
        #expect(await probe.reads.isEmpty)

        let relaunched = UsageStore(defaults: defaults, onPublish: {})
        #expect(relaunched.ringOrder == expected)
        #expect(relaunched.snapshot.ringOrder == expected)
        #expect(relaunched.needsConsent)
        #expect(!relaunched.isEnabled)
    }

    @Test func onlySelectedServicesAreReadAndMovingRingsDoesNotReadAgain() async throws {
        let name = "RingPreferencesTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(1, forKey: "usageMonitoringConsentVersion")
        defaults.set(true, forKey: "usageMonitoringEnabled")
        let order: [UsageService] = [.gemini, .claude, .cursor, .codex]
        defaults.set(order.map(\.rawValue), forKey: "usageRingOrder")
        let probe = ReadProbe()
        let store = UsageStore(defaults: defaults, fetch: { await probe.fetch($0) }, onPublish: {})
        defer { store.setEnabled(false) }
        await store.refresh()
        #expect(Set(await probe.reads) == Set(order))
        #expect(await probe.reads.count == 4)
        #expect(store.snapshot.usage(for: .grokBot).state == .disabled)
        store.moveRing(from: 0, to: 3)
        #expect(store.snapshot.ringOrder == [.claude, .cursor, .codex, .gemini])
        #expect(await probe.reads.count == 4)
        store.setEnabled(false)
        #expect(store.snapshot.ringOrder == store.ringOrder)
        #expect(store.snapshot.services.allSatisfy { $0.state == .disabled })
    }

    @Test(.timeLimit(.minutes(1))) func aPendingReadCannotRestoreAServiceRemovedFromTheLayout() async throws {
        let name = "RingPreferencesTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(1, forKey: "usageMonitoringConsentVersion")
        defaults.set(true, forKey: "usageMonitoringEnabled")
        let probe = ReadProbe(blocked: true)
        let store = UsageStore(defaults: defaults, fetch: { await probe.fetch($0) }, onPublish: {})
        defer { store.setEnabled(false) }
        let previousRead = Task { await store.refresh() }
        await probe.waitForReads(4)
        store.selectRing(.gemini, at: 0)
        await probe.waitForReads(8)
        store.moveRing(from: 0, to: 3)
        await probe.releaseBatch()
        await previousRead.value
        #expect(store.isRefreshing)
        #expect(store.snapshot.usage(for: .codex).state == .disabled)
        await probe.releaseBatch()
        for await snapshot in store.$snapshot.values {
            if snapshot.usage(for: .gemini).state == .ready {
                #expect(snapshot.ringOrder == [.claude, .cursor, .grokBot, .gemini])
                #expect(snapshot.usage(for: .codex).state == .disabled)
                #expect(snapshot.services.count == 4)
                break
            }
        }
        #expect(await probe.reads.count == 8)
    }

    @Test func oldAndInvalidPreferencesRestoreFourDistinctRings() throws {
        let name = "RingPreferencesTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        #expect(UsageStore(defaults: defaults, onPublish: {}).ringOrder == UsageSnapshot.defaultRingOrder)
        defaults.set(["future-service", "gemini", "gemini"], forKey: "usageRingOrder")
        #expect(UsageStore(defaults: defaults, onPublish: {}).ringOrder == [.gemini, .codex, .claude, .cursor])
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

        func releaseBatch() {
            let batch = Array(pending.prefix(4))
            pending.removeFirst(batch.count)
            for (service, continuation) in batch { continuation.resume(returning: reading(service)) }
        }

        private func reading(_ service: UsageService) -> ServiceUsage {
            ServiceUsage(service: service, state: .ready, windows: [
                UsageWindow(id: "test", title: "Test", usedPercent: 20, resetsAt: nil)
            ], updatedAt: Date())
        }
    }
}
