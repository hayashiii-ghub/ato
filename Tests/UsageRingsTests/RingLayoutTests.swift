import Foundation
import Testing
@testable import UsageCore

struct RingLayoutTests {
    @Test func legacySnapshotsKeepTheExistingFourRings() throws {
        let usage = ServiceUsage(service: .claude, state: .ready, windows: [
            UsageWindow(id: "five_hour", title: "5 hours", usedPercent: 40, resetsAt: nil)
        ], updatedAt: Date(timeIntervalSince1970: 1_800_000_000))
        let services = try JSONEncoder().encode([usage])
        let legacy = Data("{\"services\":\(String(decoding: services, as: UTF8.self))}".utf8)
        let snapshot = try JSONDecoder().decode(UsageSnapshot.self, from: legacy)
        #expect(snapshot.ringOrder == [.codex, .claude, .grokBot, .gemini])
        #expect(snapshot.services == [usage])
        #expect(UsageSnapshot.empty.ringOrder == snapshot.ringOrder)
    }

    @Test func invalidOrdersKeepFourDistinctKnownProviders() throws {
        #expect(UsageSnapshot.normalizedRingOrder([]) == UsageSnapshot.defaultRingOrder)
        #expect(UsageSnapshot.normalizedRingOrder([.gemini, .gemini, .grokBot])
                == [.gemini, .grokBot, .codex, .claude])
        #expect(UsageSnapshot.normalizedRingOrder([.gemini, .grokBot, .claude, .codex, .gemini])
                == [.gemini, .grokBot, .claude, .codex])
        #expect(UsageSnapshot(services: [], ringOrder: [.gemini, .gemini]).ringOrder
                == [.gemini, .codex, .claude, .grokBot])
        let data = Data(#"{"services":[],"ringOrder":["future-provider","gemini","gemini","cursor"]}"#.utf8)
        let snapshot = try JSONDecoder().decode(UsageSnapshot.self, from: data)
        #expect(snapshot.ringOrder == [.gemini, .codex, .claude, .grokBot])
        let unknownOnly = Data(#"{"services":[],"ringOrder":["future-provider"]}"#.utf8)
        #expect(try JSONDecoder().decode(UsageSnapshot.self, from: unknownOnly).ringOrder
                == UsageSnapshot.defaultRingOrder)
    }

    @Test func selectedOrderAndGeminiUsageRoundTripThroughTheWidgetCache() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let usage = ServiceUsage(service: .gemini, state: .ready, windows: [
            UsageWindow(id: "gemini-quota", title: "Gemini", usedPercent: 30, resetsAt: now.addingTimeInterval(600))
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
        #expect(snapshot.usage(for: .grokBot).state == .disabled)
    }

    @Test func oldCursorReadingDoesNotDiscardTheOtherWidgetReadings() throws {
        let legacy = Data(#"""
        {"services":[{"service":"cursor","state":"ready","windows":[]},
                     {"service":"grokBot","state":"ready","windows":[]}],
         "ringOrder":["codex","claude","cursor","grokBot"]}
        """#.utf8)
        let snapshot = try JSONDecoder().decode(UsageSnapshot.self, from: legacy)
        #expect(snapshot.services.map(\.service) == [.grokBot])
        #expect(snapshot.ringOrder == [.codex, .claude, .grokBot, .gemini])
    }

    @Test func splitRingIncludesBothPeriodsDespiteAnOldSelectionAndExpiresEachArcIndependently() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let fiveHours = UsageWindow(id: "primary", title: "5 hours", usedPercent: 20,
                                    resetsAt: now.addingTimeInterval(200), period: .fiveHours)
        let week = UsageWindow(id: "secondary", title: "Week", usedPercent: 40,
                                resetsAt: now.addingTimeInterval(400), period: .week)
        let usage = ServiceUsage(service: .codex, state: .ready, windows: [week, fiveHours],
                                 updatedAt: now, preferredPeriod: .week)
        #expect(usage.ringValues(at: now) == .split(top: .init(title: "5h", remaining: 80),
                                                 bottom: .init(title: "Week", remaining: 60)))
        #expect(usage.ringValues(at: now.addingTimeInterval(200)) == .split(
            top: .init(title: "5h", remaining: nil), bottom: .init(title: "Week", remaining: 60)
        ))
        #expect(usage.ringValues(at: now.addingTimeInterval(400)) == .split(
            top: .init(title: "5h", remaining: nil), bottom: .init(title: "Week", remaining: nil)
        ))
    }

    @Test func exhaustedWeekBlocksTheTopArcUntilARefreshConfirmsRecovery() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let session = UsageWindow(id: "five_hour", title: "5 hours", usedPercent: 20, resetsAt: nil)
        let week = UsageWindow(id: "seven_day", title: "Week", usedPercent: 100, resetsAt: now.addingTimeInterval(60))
        let usage = ServiceUsage(service: .claude, state: .ready, windows: [session, week], updatedAt: now)
        #expect(usage.ringValues(at: now) == .split(top: .init(title: "5h", remaining: 0),
                                                 bottom: .init(title: "Week", remaining: 0)))
        #expect(usage.isFiveHourArcBlocked(at: now))
        #expect(usage.ringValues(at: now.addingTimeInterval(60)) == .split(
            top: .init(title: "5h", remaining: nil), bottom: .init(title: "Week", remaining: nil)
        ))
    }

    @Test func aSingleMainWindowUsesTheFullRingRegardlessOfPeriod() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var usage = ServiceUsage(service: .grokBot, state: .ready, windows: [
            UsageWindow(id: "subscription", title: "Week", usedPercent: 20, resetsAt: nil, period: .week)
        ], updatedAt: now)
        #expect(usage.ringValues(at: now) == .single(.init(title: "Week", remaining: 80)))
        #expect(usage.ringValues(at: now.addingTimeInterval(UsageSnapshot.maximumAge))
                == .single(.init(title: "Week", remaining: nil)))
        usage.windows = [UsageWindow(id: "subscription", title: "This month", usedPercent: 20, resetsAt: nil)]
        #expect(usage.ringValues(at: now) == .single(.init(title: "This month", remaining: 80)))
        let claude = ServiceUsage(service: .claude, state: .ready, windows: [
            UsageWindow(id: "five_hour", title: "5 hours", usedPercent: 20, resetsAt: nil)
        ], updatedAt: now)
        #expect(claude.ringValues(at: now) == .single(.init(title: "5h", remaining: 80)))
    }

    @Test func twoMainWindowsKeepTheirLabelsWhenOneUsesAnotherPeriod() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let usage = ServiceUsage(service: .codex, state: .ready, windows: [
            UsageWindow(id: "secondary", title: "This month", usedPercent: 30, resetsAt: nil),
            UsageWindow(id: "primary", title: "Week", usedPercent: 20, resetsAt: nil, period: .week)
        ], updatedAt: now)
        #expect(usage.ringValues(at: now) == .split(top: .init(title: "Week", remaining: 80),
                                                 bottom: .init(title: "This month", remaining: 70)))
        #expect(ServiceUsage(service: .codex, state: .unavailable).ringValues(at: now) == .unknown)
    }

    @Test func widgetMarkersStayShortForEveryParsedWindowTitle() {
        let markers = ["5h", "Week", "This month", "Monthly credits", "30 days", "12 hours", "Gemini · Week",
                       "Subscription", "Current window", "Other window", "Gemini · Reported quota"]
            .map { UsageRingValues.Reading(title: $0, remaining: 50).widgetMarker }
        #expect(markers == ["5h", "W", "M", "M", "30d", "12h", "W", "?", "?", "?", "?"])
    }
}
