import Foundation
import Testing
import UsageCore

struct RingLayoutTests {
    @Test func legacySnapshotsKeepTheExistingFourRings() throws {
        let usage = ServiceUsage(service: .claude, state: .ready, windows: [
            UsageWindow(id: "five_hour", title: "5 hours", usedPercent: 40, resetsAt: nil)
        ], updatedAt: Date(timeIntervalSince1970: 1_800_000_000))
        let services = try JSONEncoder().encode([usage])
        let legacy = Data("{\"services\":\(String(decoding: services, as: UTF8.self))}".utf8)
        let snapshot = try JSONDecoder().decode(UsageSnapshot.self, from: legacy)
        #expect(snapshot.ringOrder == [.codex, .claude, .cursor, .grokBot])
        #expect(snapshot.services == [usage])
        #expect(UsageSnapshot.empty.ringOrder == snapshot.ringOrder)
    }

    @Test func invalidOrdersKeepFourDistinctKnownProviders() throws {
        #expect(UsageSnapshot.normalizedRingOrder([]) == UsageSnapshot.defaultRingOrder)
        #expect(UsageSnapshot.normalizedRingOrder([.gemini, .gemini, .grokBot])
                == [.gemini, .grokBot, .codex, .claude])
        #expect(UsageSnapshot.normalizedRingOrder([.gemini, .cursor, .grokBot, .claude, .codex])
                == [.gemini, .cursor, .grokBot, .claude])
        #expect(UsageSnapshot(services: [], ringOrder: [.gemini, .gemini]).ringOrder
                == [.gemini, .codex, .claude, .cursor])
        let data = Data(#"{"services":[],"ringOrder":["future-provider","gemini","gemini","cursor"]}"#.utf8)
        let snapshot = try JSONDecoder().decode(UsageSnapshot.self, from: data)
        #expect(snapshot.ringOrder == [.gemini, .cursor, .codex, .claude])
        let unknownOnly = Data(#"{"services":[],"ringOrder":["future-provider"]}"#.utf8)
        #expect(try JSONDecoder().decode(UsageSnapshot.self, from: unknownOnly).ringOrder
                == UsageSnapshot.defaultRingOrder)
    }

    @Test func selectedOrderAndGeminiUsageRoundTripThroughTheWidgetCache() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let usage = ServiceUsage(service: .gemini, state: .ready, windows: [
            UsageWindow(id: "model", title: "Gemini", usedPercent: 30, resetsAt: now.addingTimeInterval(600))
        ], updatedAt: now)
        let order: [UsageService] = [.grokBot, .gemini, .claude, .codex]
        let snapshot = UsageSnapshot(services: [usage], ringOrder: order)
        let data = try JSONEncoder().encode(snapshot)
        #expect(try JSONDecoder().decode(UsageSnapshot.self, from: data) == snapshot)
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(Set(json.keys) == ["services", "ringOrder"])
        #expect((json["ringOrder"] as? [String]) == ["grokBot", "gemini", "claude", "codex"])

        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("usage.json")
        try UsageSnapshotFile.write(snapshot, to: url)
        #expect(UsageSnapshotFile.read(from: url) == snapshot)
        #expect(UsageSnapshotFile.read(from: url).usage(for: .gemini).remainingPercent(at: now) == 70)
        #expect(snapshot.usage(for: .cursor).state == .disabled)
    }
}
