import Foundation
import Testing
import UsageCore
@testable import UsageRings

struct AntigravityDisabledUsageTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func disabledBucketIgnoresObsoleteFieldsAndKeepsActiveWeeklyQuota() throws {
        let quota = #""gemini-5h":{"disabled":true,"remaining_fraction":"obsolete","reset_time":{}},"gemini-weekly":{"disabled":false,"remaining_fraction":0.4,"reset_time":"2027-02-01T12:00:00Z"}"#
        let observation = try AntigravityUsageParser.parseObservation(payload(quota), now: now)
        #expect(observation.disabledWindowIDs == ["gemini-5h"])
        #expect(observation.usage.state == .ready)
        #expect(observation.usage.windows.map(\.id) == ["gemini-weekly"])
        #expect(observation.usage.remainingPercent(at: now) == 40)
    }

    @Test func explicitlyEnabledBucketsRemainAvailable() throws {
        let quota = #""gemini-5h":{"disabled":false,"remaining_fraction":0.9,"reset_time":"2027-02-01T12:00:00Z"},"gemini-weekly":{"remaining_fraction":0.4,"reset_time":"2027-02-01T12:00:00Z"}"#
        let observation = try AntigravityUsageParser.parseObservation(payload(quota), now: now)
        #expect(observation.disabledWindowIDs.isEmpty)
        #expect(observation.usage.windows.count == 2)
        #expect(observation.usage.remainingPercent(at: now) == 40)
    }

    @Test func allDisabledImmediatelyInvalidatesOldAllowanceAndBlocksItsReplay() async throws {
        let fixture = Fixture()
        defer { fixture.remove() }
        let active = try save(weekly(0.8), at: now, to: fixture.location)
        #expect(active.usage.remainingPercent(at: now) == 80)

        let disabledTime = now.addingTimeInterval(10)
        let disabled = try save(allDisabled, at: disabledTime, to: fixture.location)
        #expect(disabled.version == 1)
        #expect(disabled.usage.state == .unavailable)
        #expect(disabled.usage.windows.isEmpty)
        #expect(disabled.usage.updatedAt == disabledTime)
        #expect(disabled.usage.remainingPercent(at: disabledTime) == nil)
        #expect(AntigravityStatuslineFile.read(from: fixture.location) == disabled)
        #expect(await AntigravityUsageClient.fetch(from: fixture.location) == disabled.usage)

        let replay = try save(weekly(0.8), at: now.addingTimeInterval(20), to: fixture.location)
        #expect(replay.usage == disabled.usage)
        #expect(replay.quotaMarkers.contains(active.quotaMarkers[0]))

        let resumedTime = now.addingTimeInterval(30)
        let resumed = try save(weekly(0.7), at: resumedTime, to: fixture.location)
        #expect(resumed.usage.state == .ready)
        #expect(resumed.usage.remainingPercent(at: resumedTime) == 70)
        #expect(resumed.usage.updatedAt == resumedTime)
    }

    @Test func repeatingAnEarlierDisableStillInvalidatesANewAllowance() throws {
        let fixture = Fixture()
        defer { fixture.remove() }
        try save(weekly(0.8), at: now, to: fixture.location)
        try save(allDisabled, at: now.addingTimeInterval(10), to: fixture.location)
        try save(weekly(0.7), at: now.addingTimeInterval(20), to: fixture.location)

        let disabledTime = now.addingTimeInterval(30)
        let disabled = try save(allDisabled, at: disabledTime, to: fixture.location)
        #expect(disabled.usage.state == .unavailable)
        #expect(disabled.usage.windows.isEmpty)
        #expect(disabled.usage.updatedAt == disabledTime)
        let repeated = try save(allDisabled, at: now.addingTimeInterval(40), to: fixture.location)
        #expect(repeated.usage == disabled.usage)
        #expect(Set(repeated.quotaMarkers).count == repeated.quotaMarkers.count)
        #expect(repeated.quotaMarkers.count <= 256)
    }

    @Test func mixedDisableRemovesTheWindowWhileKeepingFresherUnchangedAllowance() throws {
        let fixture = Fixture()
        defer { fixture.remove() }
        try save(weekly(0.8), at: now, to: fixture.location)
        let latestTime = now.addingTimeInterval(10)
        let twoWindows = #""gemini-5h":{"remaining_fraction":0.5,"reset_time":"2027-02-01T12:00:00Z"},"gemini-weekly":{"remaining_fraction":0.4,"reset_time":"2027-02-01T12:00:00Z"}"#
        try save(twoWindows, at: latestTime, to: fixture.location)
        let disabledWithReplay = #""gemini-5h":{"disabled":true},"gemini-weekly":{"remaining_fraction":0.8,"reset_time":"2027-02-01T12:00:00Z"}"#
        let after = try save(disabledWithReplay, at: now.addingTimeInterval(20), to: fixture.location)
        #expect(after.usage.windows.map(\.id) == ["gemini-weekly"])
        #expect(after.usage.remainingPercent(at: now.addingTimeInterval(20)) == 40)
        #expect(after.usage.updatedAt == latestTime)
        #expect(AntigravityStatuslineFile.read(from: fixture.location)?.usage == after.usage)

        let redrawTime = now.addingTimeInterval(1300)
        let redraw = try save(disabledWithReplay, at: redrawTime, to: fixture.location)
        #expect(redraw.usage == after.usage)
        #expect(redraw.usage.remainingPercent(at: redrawTime) == nil)
    }

    @Test func delayedDisabledWriterDoesNotEraseNewerQuota() throws {
        let fixture = Fixture()
        defer { fixture.remove() }
        let latest = try save(weekly(0.4), at: now.addingTimeInterval(10), to: fixture.location)
        let delayed = try save(allDisabled, at: now, to: fixture.location)
        #expect(delayed.usage == latest.usage)
    }

    @Test func malformedDisabledFlagsNeverBecomeAllowances() {
        for disabled in [#""true""#, "1", "{}", "[]"] {
            let quota = "\"gemini-weekly\":{\"disabled\":\(disabled),\"remaining_fraction\":0.9,\"reset_time\":\"2027-02-01T12:00:00Z\"}"
            #expect(throws: (any Error).self) {
                try AntigravityUsageParser.parse(payload(quota), now: now)
            }
        }
        for invalid in [
            #""gemini-weekly":{"disabled":false,"remaining_fraction":"obsolete","reset_time":"2027-02-01T12:00:00Z"}"#,
            #""gemini-weekly":{"disabled":false,"remaining_fraction":0.9,"reset_time":"invalid"}"#
        ] {
            #expect(throws: (any Error).self) {
                try AntigravityUsageParser.parse(payload(invalid), now: now)
            }
        }
    }

    @Test func unavailableCacheAcceptsOnlyEmptyGeminiWindows() throws {
        let fixture = Fixture()
        defer { fixture.remove() }
        let disabled = try save(allDisabled, at: now, to: fixture.location)
        let original = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(disabled)) as? [String: Any])
        let originalUsage = try #require(original["usage"] as? [String: Any])
        let availableWindow = try AntigravityUsageParser.parse(payload(weekly(0.8)), now: now).windows[0]
        var invalidUsages: [[String: Any]] = []
        var withWindows = originalUsage
        withWindows["windows"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode([availableWindow]))
        invalidUsages.append(withWindows)
        for state in ["ready", "disabled", "setupRequired", "signInRequired"] {
            var usage = originalUsage
            usage["state"] = state
            invalidUsages.append(usage)
        }
        var otherProvider = originalUsage
        otherProvider["service"] = "codex"
        invalidUsages.append(otherProvider)
        for usage in invalidUsages {
            var invalid = original
            invalid["usage"] = usage
            try JSONSerialization.data(withJSONObject: invalid).write(to: fixture.location)
            #expect(AntigravityStatuslineFile.read(from: fixture.location) == nil)
        }
    }

    private var allDisabled: String {
        #""gemini-5h":{"disabled":true},"gemini-weekly":{"disabled":true,"remaining_fraction":0.9,"reset_time":"2027-02-01T12:00:00Z"}"#
    }

    private func weekly(_ fraction: Double) -> String {
        "\"gemini-weekly\":{\"remaining_fraction\":\(fraction),\"reset_time\":\"2027-02-01T12:00:00Z\"}"
    }

    private func payload(_ quota: String) -> Data {
        Data("{\"product\":\"antigravity\",\"quota\":{\(quota)}}".utf8)
    }

    @discardableResult
    private func save(_ quota: String, at date: Date, to location: URL) throws -> AntigravityStatuslineCache {
        let observation = try AntigravityUsageParser.parseObservation(payload(quota), now: date)
        return try AntigravityStatuslineFile.write(observation.usage, disabling: observation.disabledWindowIDs, to: location)
    }

    private struct Fixture {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("usage-rings-gemini-disabled-\(UUID().uuidString)")
        var location: URL { folder.appendingPathComponent("usage.json") }
        func remove() { try? FileManager.default.removeItem(at: folder) }
    }
}
