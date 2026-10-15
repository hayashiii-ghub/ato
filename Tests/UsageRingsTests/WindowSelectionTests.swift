import Foundation
import Testing
import UsageCore

struct WindowSelectionTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private var fiveHours: UsageWindow {
        UsageWindow(id: "primary", title: "5 hours", usedPercent: 10,
                    resetsAt: now.addingTimeInterval(600), period: .fiveHours)
    }

    private var week: UsageWindow {
        UsageWindow(id: "secondary", title: "Week", usedPercent: 80,
                    resetsAt: now.addingTimeInterval(3600), period: .week)
    }

    @Test func choosingAPeriodUsesThatAllowanceAndAutoKeepsTheMostConstrainedWindow() {
        var usage = ServiceUsage(service: .codex, state: .ready, windows: [fiveHours, week], updatedAt: now)
        #expect(usage.headline?.id == "secondary")
        #expect(usage.remainingPercent(at: now) == 20)
        usage.preferredPeriod = .fiveHours
        #expect(usage.headline?.id == "primary")
        #expect(usage.remainingPercent(at: now) == 90)
        usage.preferredPeriod = .week
        #expect(usage.remainingPercent(at: now) == 20)
        usage.preferredPeriod = nil
        #expect(usage.headline?.id == "secondary")
    }

    @Test func absentOrUnidentifiedPeriodsNeverBecomeAnotherWindowOrFullAllowance() {
        let weeklyOnly = ServiceUsage(service: .codex, state: .ready, windows: [week], updatedAt: now,
                                      preferredPeriod: .fiveHours)
        #expect(weeklyOnly.hasFreshReading(at: now))
        #expect(weeklyOnly.headline == nil)
        #expect(!weeklyOnly.isCurrent(at: now))
        #expect(weeklyOnly.remainingPercent(at: now) == nil)
        #expect(weeklyOnly.remainingPercent(for: week, at: now) == 20)
        let unidentified = UsageWindow(id: "primary", title: "5 hours", usedPercent: 0, resetsAt: nil)
        let unknown = ServiceUsage(service: .codex, state: .ready, windows: [unidentified], updatedAt: now,
                                   preferredPeriod: .fiveHours)
        #expect(unknown.headline == nil)
        #expect(unknown.remainingPercent(at: now) == nil)
    }

    @Test func manualSelectionAndDetailRowsIgnoreOnlyOtherWindowsResets() {
        let expiredWeek = UsageWindow(id: "secondary", title: "Week", usedPercent: 80,
                                     resetsAt: now, period: .week)
        var usage = ServiceUsage(service: .codex, state: .ready, windows: [fiveHours, expiredWeek], updatedAt: now)
        #expect(usage.hasFreshReading(at: now))
        #expect(usage.remainingPercent(at: now) == nil)
        #expect(usage.remainingPercent(for: fiveHours, at: now) == 90)
        #expect(usage.remainingPercent(for: expiredWeek, at: now) == nil)
        usage.preferredPeriod = .fiveHours
        #expect(usage.isCurrent(at: now))
        #expect(usage.remainingPercent(at: now) == 90)
        #expect(usage.remainingPercent(at: now.addingTimeInterval(600)) == nil)
        usage.preferredPeriod = .week
        #expect(!usage.isCurrent(at: now))
        #expect(usage.remainingPercent(at: now) == nil)
    }

    @Test func manualRingsAndDetailRowsStillRequireACurrentSuccessfulReading() {
        var usage = ServiceUsage(service: .codex, state: .ready, windows: [fiveHours],
                                 updatedAt: now.addingTimeInterval(-UsageSnapshot.maximumAge),
                                 preferredPeriod: .fiveHours)
        #expect(!usage.hasFreshReading(at: now))
        #expect(usage.remainingPercent(at: now) == nil)
        #expect(usage.remainingPercent(for: fiveHours, at: now) == nil)
        usage.updatedAt = now.addingTimeInterval(61)
        #expect(!usage.hasFreshReading(at: now))
        usage.updatedAt = now
        usage.state = .unavailable
        #expect(usage.remainingPercent(for: fiveHours, at: now) == nil)
        usage.state = .ready
        #expect(usage.remainingPercent(for: week, at: now) == nil)
        #expect(!ServiceUsage(service: .codex, state: .ready, updatedAt: now).hasFreshReading(at: now))
    }

    @Test func legacyClaudeStatuslineCacheRemainsSelectableWithoutPeriodMetadata() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        let location = folder.appendingPathComponent("claude.json")
        let legacyUsage: [String: Any] = [
            "service": "claude", "state": "ready", "updatedAt": now.timeIntervalSinceReferenceDate,
            "windows": [
                ["id": "five_hour", "title": "5 hours", "usedPercent": 10,
                 "resetsAt": now.addingTimeInterval(600).timeIntervalSinceReferenceDate],
                ["id": "seven_day", "title": "Week", "usedPercent": 80,
                 "resetsAt": now.addingTimeInterval(3600).timeIntervalSinceReferenceDate]
            ]
        ]
        let data = try JSONSerialization.data(withJSONObject: [
            "usage": legacyUsage, "responseMarkers": ["synthetic-marker"], "version": 1
        ])
        try data.write(to: location)
        var usage = try #require(ClaudeStatuslineFile.read(from: location)).usage
        #expect(usage.preferredPeriod == nil)
        #expect(usage.windows.allSatisfy { $0.period == nil })
        #expect(usage.remainingPercent(at: now) == 20)
        usage.preferredPeriod = .fiveHours
        #expect(usage.headline?.id == "five_hour")
        #expect(usage.remainingPercent(at: now) == 90)
        usage.preferredPeriod = .week
        #expect(usage.headline?.id == "seven_day")
        let sameIDsFromAnotherService = ServiceUsage(service: .codex, state: .ready, windows: usage.windows,
                                                     updatedAt: now, preferredPeriod: .week)
        #expect(sameIDsFromAnotherService.headline == nil)
    }

    @Test func selectedPeriodAndWindowMetadataRoundTripThroughTheSanitizedWidgetCache() throws {
        let usage = ServiceUsage(service: .codex, state: .ready, windows: [fiveHours, week], updatedAt: now,
                                 preferredPeriod: .fiveHours)
        let snapshot = UsageSnapshot(services: [usage], ringOrder: [.codex, .gemini, .claude, .grokBot])
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let location = folder.appendingPathComponent("usage.json")
        try UsageSnapshotFile.write(snapshot, to: location)
        let restored = UsageSnapshotFile.read(from: location)
        #expect(restored == snapshot)
        #expect(restored.usage(for: .codex).preferredPeriod == .fiveHours)
        #expect(restored.usage(for: .codex).remainingPercent(at: now) == 90)
        let object = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: location)) as? [String: Any])
        #expect(Set(object.keys) == ["services", "ringOrder"])
        let services = try #require(object["services"] as? [[String: Any]])
        #expect(Set(services[0].keys) == ["service", "state", "windows", "updatedAt", "preferredPeriod"])
        #expect((services[0]["preferredPeriod"] as? String) == "fiveHours")
        let windows = try #require(services[0]["windows"] as? [[String: Any]])
        #expect(windows.map { $0["period"] as? String } == ["fiveHours", "week"])
    }

    @Test func codexPeriodsFollowReportedDurationInsteadOfPrimaryAndSecondaryIDs() throws {
        let data = Data(#"{"rateLimits":{"primary":{"usedPercent":60,"windowDurationMins":10080},"secondary":{"usedPercent":20,"windowDurationMins":300}}}"#.utf8)
        var usage = try UsageResponseParser.codex(data, now: now)
        #expect(usage.windows.map(\.period) == [.week, .fiveHours])
        usage.preferredPeriod = .week
        #expect(usage.headline?.id == "primary")
        usage.preferredPeriod = .fiveHours
        #expect(usage.headline?.id == "secondary")
        let unknown = try UsageResponseParser.codex(Data(#"{"rateLimits":{"primary":{"usedPercent":0,"windowDurationMins":1200}}}"#.utf8), now: now)
        #expect(unknown.windows[0].period == nil)
    }

    @Test func knownProviderBucketsCarryPeriodsAndCursorMonthlyUsageStaysUnclassified() throws {
        let claude = try JSONSerialization.data(withJSONObject: [
            "session_id": "synthetic-session", "cost": ["total_api_duration_ms": 1],
            "rate_limits": [
                "five_hour": ["used_percentage": 10, "resets_at": now.timeIntervalSince1970 + 600],
                "seven_day": ["used_percentage": 80, "resets_at": now.timeIntervalSince1970 + 3600]
            ]
        ])
        #expect(try ClaudeStatusline.parse(claude, now: now)?.usage.windows.map(\.period) == [.fiveHours, .week])
        let gemini = Data(#"""
        {"status":"SUCCESS","num_turns":0,"usage":{"input_tokens":0,"output_tokens":0,"thinking_tokens":0,"cache_read_tokens":0,"total_tokens":0},"command":{"name":"usage","data":{"groups":[{"name":"Gemini Models","buckets":[{"id":"gemini-5h","window":"5h","remaining_fraction":0.9,"reset_time":"2027-02-01T12:00:00Z"},{"id":"gemini-weekly","window":"weekly","remaining_fraction":0.3,"reset_time":"2027-02-01T12:00:00Z"}]}]}}}
        """#.utf8)
        #expect(try AntigravityUsageParser.parse(gemini, now: now).windows.map(\.period) == [.fiveHours, .week])
        let grok = Data(#"{"usagePercent":25,"nextResetTimestampUtc":"2027-02-01T12:00:00Z","hasNonZeroIncludedLimit":true}"#.utf8)
        #expect(try UsageResponseParser.grokBot(grok, now: now).windows.first?.period == .week)
        let cursor = Data(#"{"individualUsage":{"plan":{"totalPercentUsed":25}}}"#.utf8)
        #expect(try UsageResponseParser.cursor(cursor, now: now).windows.allSatisfy { $0.period == nil })
    }
}
