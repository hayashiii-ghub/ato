import Foundation
import Testing
import UsageCore

struct ClaudeStatuslineTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func payload(duration: Double = 1000, session: String = "private-session",
                         windows: [String: Any]? = nil) throws -> Data {
        try JSONSerialization.data(withJSONObject: [
            "session_id": session,
            "cost": ["total_api_duration_ms": duration],
            "rate_limits": windows ?? [
                "five_hour": ["used_percentage": 12.5, "resets_at": now.timeIntervalSince1970 + 3600],
                "seven_day": ["used_percentage": 43, "resets_at": now.timeIntervalSince1970 + 604800],
                "spend_limit": ["used_percentage": 99, "resets_at": now.timeIntervalSince1970 + 3600]
            ],
            "transcript_path": "/private/conversation.jsonl",
            "workspace": ["current_dir": "/private/workspace"],
            "extra_secret": "must-not-be-copied"
        ])
    }

    @Test func officialMainWindowsDetermineRemainingUsage() throws {
        let input = try #require(try ClaudeStatusline.parse(payload(), now: now))
        #expect(input.usage.windows.count == 2)
        #expect(input.usage.windows.first?.remainingPercent == 87.5)
        #expect(input.usage.headline?.id == "seven_day")
        #expect(input.usage.remainingPercent(at: now) == 57)
        #expect(input.usage.windows.first?.resetsAt == now.addingTimeInterval(3600))
        #expect(input.usage.remainingPercent(at: now.addingTimeInterval(UsageSnapshot.maximumAge)) == nil)
        #expect(input.usage.remainingPercent(at: now.addingTimeInterval(3600)) == nil)
    }

    @Test func absentWindowsAndFirstResponseAreNotInventedAsFullQuota() throws {
        #expect(try ClaudeStatusline.parse(Data("{}".utf8), now: now) == nil)
        #expect(try ClaudeStatusline.parse(payload(duration: 0), now: now) == nil)
        #expect(try ClaudeStatusline.parse(payload(windows: [:]), now: now) == nil)
        let week = ["seven_day": ["used_percentage": 0.5, "resets_at": now.timeIntervalSince1970 + 600]]
        #expect(try ClaudeStatusline.parse(payload(windows: week), now: now)?.usage.remainingPercent(at: now) == 99.5)
        let expired = ["five_hour": ["used_percentage": 90, "resets_at": now.timeIntervalSince1970 - 1]]
        #expect(try ClaudeStatusline.parse(payload(windows: expired), now: now) == nil)
    }

    @Test func malformedUsageIsRejected() throws {
        for value in [-1.0, 101.0] {
            let windows = ["five_hour": ["used_percentage": value, "resets_at": now.timeIntervalSince1970 + 600]]
            #expect(throws: (any Error).self) { try ClaudeStatusline.parse(payload(windows: windows), now: now) }
        }
        for invalid in [#"{"used_percentage":true,"resets_at":1800001000}"#,
                        #"{"used_percentage":10}"#, #"{"used_percentage":10,"resets_at":"tomorrow"}"#] {
            let json = "{\"session_id\":\"test\",\"cost\":{\"total_api_duration_ms\":1},\"rate_limits\":{\"five_hour\":\(invalid)}}"
            #expect(throws: (any Error).self) { try ClaudeStatusline.parse(Data(json.utf8), now: now) }
        }
    }

    @Test func onlyUsageDataIsSavedAndRepeatedUIEventsDoNotRenewFreshness() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let location = folder.appendingPathComponent("usage.json")
        let first = try #require(try ClaudeStatusline.parse(payload(), now: now))
        try ClaudeStatuslineFile.write(first, to: location)
        let repeated = try #require(try ClaudeStatusline.parse(payload(), now: now.addingTimeInterval(1300)))
        try ClaudeStatuslineFile.write(repeated, to: location)
        #expect(ClaudeStatuslineFile.read(from: location)?.usage.updatedAt == now)
        #expect(ClaudeStatuslineFile.read(from: location)?.usage.remainingPercent(at: now.addingTimeInterval(1300)) == nil)

        let second = try #require(try ClaudeStatusline.parse(payload(session: "other-session"), now: now.addingTimeInterval(10)))
        try ClaudeStatuslineFile.write(second, to: location)
        #expect(ClaudeStatuslineFile.read(from: location)?.usage.updatedAt == now)
        let otherResponse = try #require(try ClaudeStatusline.parse(payload(duration: 2000, session: "other-session"),
                                                                   now: now.addingTimeInterval(15)))
        try ClaudeStatuslineFile.write(otherResponse, to: location)
        try ClaudeStatuslineFile.write(repeated, to: location)
        #expect(ClaudeStatuslineFile.read(from: location)?.usage.updatedAt == now.addingTimeInterval(15))
        let newResponse = try #require(try ClaudeStatusline.parse(payload(duration: 2000), now: now.addingTimeInterval(20)))
        try ClaudeStatuslineFile.write(newResponse, to: location)
        #expect(ClaudeStatuslineFile.read(from: location)?.usage.updatedAt == now.addingTimeInterval(20))
        let saved = try String(contentsOf: location, encoding: .utf8)
        for forbidden in ["private-session", "other-session", "transcript", "workspace", "must-not-be-copied", "spend_limit"] {
            #expect(!saved.contains(forbidden))
        }
        let attributes = try FileManager.default.attributesOfItem(atPath: location.path)
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
    }

    @Test func missingCorruptOrWrongProviderCacheIsUnavailable() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let location = folder.appendingPathComponent("usage.json")
        #expect(ClaudeStatuslineFile.read(from: location) == nil)
        let input = try #require(try ClaudeStatusline.parse(payload(), now: now))
        try ClaudeStatuslineFile.write(input, to: location)
        let saved = try String(contentsOf: location, encoding: .utf8)
        try saved.replacingOccurrences(of: "claude", with: "codex").write(to: location, atomically: true, encoding: .utf8)
        #expect(ClaudeStatuslineFile.read(from: location) == nil)
        try Data("broken".utf8).write(to: location)
        #expect(ClaudeStatuslineFile.read(from: location) == nil)
    }

    @Test func delayedWriterDoesNotReplaceNewerUsageOrRenewFreshnessWhenRepeated() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let location = folder.appendingPathComponent("usage.json")
        let earlierWindows = ["five_hour": ["used_percentage": 90, "resets_at": now.timeIntervalSince1970 + 600]]
        let earlier = try #require(try ClaudeStatusline.parse(payload(duration: 1000, windows: earlierWindows), now: now))
        let later = try #require(try ClaudeStatusline.parse(payload(duration: 2000), now: now.addingTimeInterval(10)))
        try ClaudeStatuslineFile.write(later, to: location)
        let cache = try ClaudeStatuslineFile.write(earlier, to: location)
        #expect(cache.usage == later.usage)
        #expect(cache.responseMarkers.contains(earlier.responseMarker))

        let repeated = try #require(try ClaudeStatusline.parse(payload(duration: 1000), now: now.addingTimeInterval(1300)))
        try ClaudeStatuslineFile.write(repeated, to: location)
        #expect(ClaudeStatuslineFile.read(from: location)?.usage == later.usage)
    }

    @Test func anIdleSessionCannotReviveOldUsageAfterItsResponseMarkerIsEvicted() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let location = folder.appendingPathComponent("usage.json")
        let idle = try #require(try ClaudeStatusline.parse(payload(session: "idle-session"), now: now))
        try ClaudeStatuslineFile.write(idle, to: location)
        let activeWindows = ["five_hour": ["used_percentage": 95, "resets_at": now.timeIntervalSince1970 + 3600]]
        for index in 1...256 {
            let active = try #require(try ClaudeStatusline.parse(
                payload(duration: Double(index), session: "active-session", windows: activeWindows),
                now: now.addingTimeInterval(Double(index))
            ))
            try ClaudeStatuslineFile.write(active, to: location)
        }
        let latest = try #require(ClaudeStatuslineFile.read(from: location))
        #expect(latest.responseMarkers.count == 256)
        #expect(!latest.responseMarkers.contains(idle.responseMarker))
        let repeated = try #require(try ClaudeStatusline.parse(payload(session: "idle-session"),
                                                              now: now.addingTimeInterval(1300)))
        let after = try ClaudeStatuslineFile.write(repeated, to: location)
        #expect(after.usage == latest.usage)
        #expect(after.usage.updatedAt == now.addingTimeInterval(256))
        #expect(after.usage.remainingPercent(at: now.addingTimeInterval(1300)) == 5)
    }

    @Test func aLegacyCacheBaselinesAnUnknownSessionWithoutRenewingOldUsage() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let location = folder.appendingPathComponent("usage.json")
        let first = try #require(try ClaudeStatusline.parse(payload(), now: now))
        let original = try ClaudeStatuslineFile.write(first, to: location)
        var legacy = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [String: Any])
        legacy.removeValue(forKey: "sessionProgress")
        try JSONSerialization.data(withJSONObject: legacy).write(to: location)
        #expect(ClaudeStatuslineFile.read(from: location)?.sessionProgress == nil)

        let baseline = try #require(try ClaudeStatusline.parse(payload(session: "unrecorded-session"),
                                                              now: now.addingTimeInterval(1300)))
        let migrated = try ClaudeStatuslineFile.write(baseline, to: location)
        #expect(migrated.usage == original.usage)
        #expect(migrated.usage.remainingPercent(at: now.addingTimeInterval(1300)) == nil)
        #expect(migrated.sessionProgress?[baseline.sessionMarker]?.apiDurationMilliseconds == 1000)
        let next = try #require(try ClaudeStatusline.parse(payload(duration: 2000, session: "unrecorded-session"),
                                                          now: now.addingTimeInterval(1310)))
        #expect(try ClaudeStatuslineFile.write(next, to: location).usage == next.usage)
    }

    @Test func sessionCapacityFailsClosedAndExpiredRecordsCanBeReplaced() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let location = folder.appendingPathComponent("usage.json")
        let windows = ["five_hour": ["used_percentage": 25, "resets_at": now.timeIntervalSince1970 + 600]]
        for index in 0..<256 {
            let input = try #require(try ClaudeStatusline.parse(payload(session: "session-\(index)", windows: windows), now: now))
            try ClaudeStatuslineFile.write(input, to: location)
        }
        let full = try #require(ClaudeStatuslineFile.read(from: location))
        #expect(full.sessionProgress?.count == 256)
        #expect(try Data(contentsOf: location).count <= 65_536)
        let unknown = try #require(try ClaudeStatusline.parse(payload(session: "extra-session"), now: now.addingTimeInterval(10)))
        #expect(try ClaudeStatuslineFile.write(unknown, to: location) == full)
        let known = try #require(try ClaudeStatusline.parse(payload(duration: 2000, session: "session-0", windows: windows),
                                                           now: now.addingTimeInterval(20)))
        #expect(try ClaudeStatuslineFile.write(known, to: location).usage == known.usage)

        let afterReset = try #require(try ClaudeStatusline.parse(payload(session: "extra-session"), now: now.addingTimeInterval(601)))
        let baseline = try ClaudeStatuslineFile.write(afterReset, to: location)
        #expect(baseline.sessionProgress?.count == 1)
        #expect(baseline.usage == known.usage)
        let next = try #require(try ClaudeStatusline.parse(payload(duration: 2000, session: "extra-session"),
                                                          now: now.addingTimeInterval(602)))
        #expect(try ClaudeStatuslineFile.write(next, to: location).usage == next.usage)
    }
}
