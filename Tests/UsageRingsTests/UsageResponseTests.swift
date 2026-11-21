import UsageCore
import Foundation
import Testing
@testable import UsageRings

struct UsageResponseTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func codexWeeklyOnlyPrimaryIsNotCalledFiveHours() throws {
        let data = Data(#"{"rateLimits":{"primary":{"usedPercent":54,"windowDurationMins":10080,"resetsAt":1800003600},"secondary":null}}"#.utf8)
        let usage = try UsageResponseParser.codex(data, now: now)
        #expect(usage.windows.count == 1)
        #expect(usage.headline?.title == "Week")
        #expect(usage.remainingPercent(at: now) == 46)
    }

    @Test func codexShowsTheMostConstrainedWindow() throws {
        let data = Data(#"{"rateLimits":{"primary":{"usedPercent":10,"windowDurationMins":300},"secondary":{"usedPercent":82,"windowDurationMins":10080}}}"#.utf8)
        let usage = try UsageResponseParser.codex(data, now: now)
        #expect(usage.headline?.title == "Week")
        #expect(usage.remainingPercent(at: now) == 18)
    }

    @Test func missingPercentageDoesNotBecomeAFullRing() {
        #expect(throws: (any Error).self) { try UsageResponseParser.codex(Data(#"{"rateLimits":{}}"#.utf8)) }
    }

    @Test func passedResetAndOldReadingAreUnknown() {
        let usage = ServiceUsage(service: .codex, state: .ready, windows: [
            UsageWindow(id: "week", title: "Week", usedPercent: 80, resetsAt: now.addingTimeInterval(60))
        ], updatedAt: now)
        #expect(usage.remainingPercent(at: now) == 20)
        #expect(usage.remainingPercent(at: now.addingTimeInterval(60)) == nil)
        let noReset = ServiceUsage(service: .grokBot, state: .ready, windows: [
            UsageWindow(id: "total", title: "This month", usedPercent: 40, resetsAt: nil)
        ], updatedAt: now)
        #expect(noReset.remainingPercent(at: now.addingTimeInterval(UsageSnapshot.maximumAge)) == nil)
    }

    @Test func failedRefreshNeverDisplaysOldDataAsCurrent() {
        let usage = ServiceUsage(service: .grokBot, state: .unavailable, windows: [
            UsageWindow(id: "total", title: "This month", usedPercent: 40, resetsAt: nil)
        ], updatedAt: now)
        #expect(usage.remainingPercent(at: now) == nil)
    }

    @Test func timelineStillExpiresWhenTheSystemDefersItsRequestedReload() {
        let expiry = now.addingTimeInterval(UsageSnapshot.maximumAge)
        let reset = now.addingTimeInterval(60)
        let snapshot = UsageSnapshot(services: [ServiceUsage(service: .codex, state: .ready, windows: [
            UsageWindow(id: "primary", title: "5 hours", usedPercent: 20, resetsAt: reset)
        ], updatedAt: now)])
        #expect(snapshot.validityBoundaries(after: now) == [reset, expiry])
        #expect(snapshot.validityBoundaries(after: now.addingTimeInterval(900)).contains(expiry))
    }

    @Test func widgetSnapshotRoundTripsWithoutCredentials() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("usage.json")
        try UsageSnapshotFile.write(.empty, to: url)
        #expect(UsageSnapshotFile.read(from: url) == .empty)
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
        let text = try String(contentsOf: url, encoding: .utf8)
        #expect(!text.contains("token"))
        #expect(!text.contains("account"))
        try Data("broken".utf8).write(to: url)
        #expect(UsageSnapshotFile.read(from: url) == .empty)
    }

    @Test func bridgeOnlyAcceptsItsReadOnlyLocalRequest() {
        let valid = "GET /v1/usage HTTP/1.1\r\nHost: 127.0.0.1:\(UsageSnapshot.bridgePort)\r\nX-Usage-Rings-Widget: 1\r\n\r\n"
        #expect(UsageSnapshotServer.accepts(Data(valid.utf8)))
        for invalid in [
            valid.replacingOccurrences(of: "GET", with: "POST"),
            valid.replacingOccurrences(of: "/v1/usage", with: "/credentials"),
            valid.replacingOccurrences(of: "127.0.0.1", with: "example.com"),
            valid.replacingOccurrences(of: "X-Usage-Rings-Widget: 1", with: "X-Usage-Rings-Widget: 0"),
            valid.replacingOccurrences(of: "X-Usage-Rings-Widget: 1", with: "X-Usage-Rings-Widget: 1\r\nOrigin: https://example.com"),
            valid.replacingOccurrences(of: "X-Usage-Rings-Widget: 1", with: "X-Usage-Rings-Widget: 1\r\nX-Usage-Rings-Widget: 1")
        ] { #expect(!UsageSnapshotServer.accepts(Data(invalid.utf8))) }
    }
}
