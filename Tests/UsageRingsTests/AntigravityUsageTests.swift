import Foundation
import Testing
import UsageCore
@testable import UsageRings

struct AntigravityUsageTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func officialStatuslineQuotaUsesTheMostConstrainedGeminiWindow() throws {
        let usage = try AntigravityUsageParser.parse(payload(), now: now)
        #expect(usage.service == .gemini)
        #expect(usage.windows.map(\.period) == [.fiveHours, .week])
        #expect(usage.headline?.title == "Week")
        #expect(abs((usage.remainingPercent(at: now) ?? 0) - 45.6) < 0.000_001)
        #expect(usage.updatedAt == now)
        #expect(usage.remainingPercent(at: now.addingTimeInterval(UsageSnapshot.maximumAge)) == nil)
    }

    @Test func passedResetDoesNotRestoreEvenAnExplicitFullBucket() throws {
        let quota = #""gemini-5h":{"remaining_fraction":1,"reset_time":"2027-01-15T07:59:59Z"}"#
        let usage = try AntigravityUsageParser.parse(payload(quota: quota), now: now)
        #expect(usage.windows.count == 1)
        #expect(usage.remainingPercent(at: now) == nil)
    }

    @Test func missingDisabledMalformedAndThirdPartyQuotasNeverBecomeFullGemini() throws {
        for quota in [
            "",
            #""gemini-weekly":{}"#,
            #""gemini-weekly":{"remaining_fraction":null}"#,
            #""gemini-weekly":{"remaining_fraction":-0.1,"reset_time":"2027-02-01T12:00:00Z"}"#,
            #""gemini-weekly":{"remaining_fraction":1.1,"reset_time":"2027-02-01T12:00:00Z"}"#,
            #""gemini-weekly":{"remaining_fraction":true,"reset_time":"2027-02-01T12:00:00Z"}"#,
            #""gemini-weekly":{"remaining_fraction":0.5,"reset_time":"invalid"}"#,
            #""gemini-weekly":{"remaining_fraction":0.5}"#,
            #""gemini-weekly":{"remaining_fraction":0.5,"reset_in_seconds":3600}"#,
            #""gemini-unknown":{"remaining_fraction":1,"reset_time":"2027-02-01T12:00:00Z"}"#,
            #""3p-weekly":{"remaining_fraction":0.5,"reset_time":"2027-02-01T12:00:00Z"}"#
        ] {
            #expect(throws: (any Error).self) { try AntigravityUsageParser.parse(payload(quota: quota), now: now) }
        }
        for invalid in ["{}", #"{"product":"other","quota":{}}"#,
                        #"{"product":"antigravity","quota":null}"#] {
            #expect(throws: (any Error).self) { try AntigravityUsageParser.parse(Data(invalid.utf8), now: now) }
        }
        let wrongProduct = String(decoding: payload(), as: UTF8.self)
            .replacingOccurrences(of: #""product":"antigravity""#, with: #""product":"other""#)
        #expect(throws: (any Error).self) { try AntigravityUsageParser.parse(Data(wrongProduct.utf8), now: now) }
    }

    @Test func activeWeeklyQuotaSurvivesADisabledFiveHourBucketAndUnknownFields() throws {
        let quota = #""gemini-weekly":{"remaining_fraction":0,"reset_time":"2027-02-01T12:00:00.125Z"},"gemini-5h":{},"3p-weekly":{"remaining_fraction":0.99},"future-quota":"unknown""#
        let usage = try AntigravityUsageParser.parse(payload(quota: quota), now: now)
        #expect(usage.windows.count == 1)
        #expect(usage.remainingPercent(at: now) == 0)
        #expect(usage.headline?.resetsAt == Date(timeIntervalSince1970: 1_801_483_200.125))
    }

    @Test func passiveClientReadsOnlyItsCacheAndMissingCacheRequiresSetup() async throws {
        let fixture = Fixture()
        defer { fixture.remove() }
        let missing = await AntigravityUsageClient.fetch(from: fixture.location)
        #expect(missing.service == .gemini && missing.state == .setupRequired && missing.windows.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: fixture.folder.path))

        let usage = try AntigravityUsageParser.parse(payload(), now: now)
        try AntigravityStatuslineFile.write(usage, to: fixture.location)
        #expect(await AntigravityUsageClient.fetch(from: fixture.location) == usage)
    }

    @Test func cacheDropsPrivateMetadataAndUsesOwnerOnlyPermissions() throws {
        let fixture = Fixture()
        defer { fixture.remove() }
        let usage = try AntigravityUsageParser.parse(payload(), now: now)
        try AntigravityStatuslineFile.write(usage, to: fixture.location)
        let saved = try String(contentsOf: fixture.location, encoding: .utf8)
        for forbidden in ["synthetic-private", "conversation", "session", "email", "workspace", "transcript",
                          "context_window", "total_input_tokens", "reset_in_seconds", "credits", "3p-", "product"] {
            #expect(!saved.contains(forbidden))
        }
        let fileAttributes = try FileManager.default.attributesOfItem(atPath: fixture.location.path)
        let folderAttributes = try FileManager.default.attributesOfItem(atPath: fixture.folder.path)
        #expect((fileAttributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
        #expect((folderAttributes[.posixPermissions] as? NSNumber)?.intValue == 0o700)
    }

    @Test func uiRedrawsSessionChangesAndCountdownsDoNotRenewOldQuota() throws {
        let fixture = Fixture()
        defer { fixture.remove() }
        let first = try AntigravityUsageParser.parse(payload(), now: now)
        try AntigravityStatuslineFile.write(first, to: fixture.location)
        let redraw = String(decoding: payload(), as: UTF8.self)
            .replacingOccurrences(of: "synthetic-private-session", with: "another-private-session")
            .replacingOccurrences(of: #""reset_in_seconds":3600"#, with: #""reset_in_seconds":2300"#)
            .replacingOccurrences(of: #""total_input_tokens":1"#, with: #""total_input_tokens":2000"#)
            .replacingOccurrences(of: #""agent_state":"idle""#, with: #""agent_state":"working""#)
        let repeated = try AntigravityUsageParser.parse(Data(redraw.utf8), now: now.addingTimeInterval(1300))
        let after = try AntigravityStatuslineFile.write(repeated, to: fixture.location)
        #expect(after.usage == first)
        #expect(after.usage.remainingPercent(at: now.addingTimeInterval(1300)) == nil)
    }

    @Test func replayingAnEarlierQuotaCannotUndoOrRenewTheLatestReading() throws {
        let fixture = Fixture()
        defer { fixture.remove() }
        let first = try AntigravityUsageParser.parse(payload(), now: now)
        try AntigravityStatuslineFile.write(first, to: fixture.location)
        let changed = String(decoding: payload(), as: UTF8.self)
            .replacingOccurrences(of: "0.456", with: "0.25")
        let second = try AntigravityUsageParser.parse(Data(changed.utf8), now: now.addingTimeInterval(10))
        try AntigravityStatuslineFile.write(second, to: fixture.location)
        let replay = try AntigravityUsageParser.parse(payload(), now: now.addingTimeInterval(1300))
        let after = try AntigravityStatuslineFile.write(replay, to: fixture.location)
        #expect(after.usage == second)
        #expect(after.usage.remainingPercent(at: now.addingTimeInterval(1300)) == nil)
    }

    @Test func aDelayedUnseenWriterCannotReplaceNewerUsage() throws {
        let fixture = Fixture()
        defer { fixture.remove() }
        let newest = try AntigravityUsageParser.parse(payload(), now: now.addingTimeInterval(10))
        try AntigravityStatuslineFile.write(newest, to: fixture.location)
        let delayedPayload = String(decoding: payload(), as: UTF8.self).replacingOccurrences(of: "0.456", with: "0.9")
        let delayed = try AntigravityUsageParser.parse(Data(delayedPayload.utf8), now: now)
        #expect(try AntigravityStatuslineFile.write(delayed, to: fixture.location).usage == newest)
        let redraw = try AntigravityUsageParser.parse(Data(delayedPayload.utf8), now: now.addingTimeInterval(1300))
        let after = try AntigravityStatuslineFile.write(redraw, to: fixture.location)
        #expect(after.usage == newest)
        #expect(after.usage.remainingPercent(at: now.addingTimeInterval(1300)) == nil)
    }

    @Test func aResetNeedsAnExplicitNewQuotaReading() throws {
        let fixture = Fixture()
        defer { fixture.remove() }
        let oldQuota = #""gemini-5h":{"remaining_fraction":0,"reset_time":"2027-01-15T08:00:10Z"}"#
        let exhausted = try AntigravityUsageParser.parse(payload(quota: oldQuota), now: now)
        try AntigravityStatuslineFile.write(exhausted, to: fixture.location)
        #expect(AntigravityStatuslineFile.read(from: fixture.location)?.usage.remainingPercent(at: now.addingTimeInterval(11)) == nil)

        let newQuota = #""gemini-5h":{"remaining_fraction":0.8,"reset_time":"2027-01-15T13:00:10Z"}"#
        let observed = try AntigravityUsageParser.parse(payload(quota: newQuota), now: now.addingTimeInterval(11))
        let cache = try AntigravityStatuslineFile.write(observed, to: fixture.location)
        #expect(abs((cache.usage.remainingPercent(at: now.addingTimeInterval(11)) ?? 0) - 80) < 0.000_001)
        #expect(cache.usage.updatedAt == now.addingTimeInterval(11))
    }

    @Test func malformedOversizedAndWrongProviderCachesRequireSetup() async throws {
        let fixture = Fixture()
        defer { fixture.remove() }
        let usage = try AntigravityUsageParser.parse(payload(), now: now)
        let cache = try AntigravityStatuslineFile.write(usage, to: fixture.location)
        let original = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(cache)) as? [String: Any])
        var invalidObjects: [[String: Any]] = []
        var wrongProvider = original
        var wrongUsage = try #require(original["usage"] as? [String: Any])
        wrongUsage["service"] = "codex"
        wrongProvider["usage"] = wrongUsage
        invalidObjects.append(wrongProvider)
        var wrongVersion = original
        wrongVersion["version"] = 2
        invalidObjects.append(wrongVersion)
        var excessiveMarkers = original
        excessiveMarkers["quotaMarkers"] = Array(repeating: String(repeating: "a", count: 64), count: 257)
        invalidObjects.append(excessiveMarkers)
        var malformedMarker = original
        malformedMarker["quotaMarkers"] = ["synthetic-private"]
        invalidObjects.append(malformedMarker)
        var badWindow = original
        var invalidUsage = try #require(original["usage"] as? [String: Any])
        var windows = try #require(invalidUsage["windows"] as? [[String: Any]])
        windows[0]["usedPercent"] = 101
        invalidUsage["windows"] = windows
        badWindow["usage"] = invalidUsage
        invalidObjects.append(badWindow)

        let invalidData = try invalidObjects.map { try JSONSerialization.data(withJSONObject: $0) }
            + [Data("broken".utf8), Data(repeating: 0x20, count: 65_537)]
        for data in invalidData {
            try data.write(to: fixture.location)
            #expect(AntigravityStatuslineFile.read(from: fixture.location) == nil)
            #expect(await AntigravityUsageClient.fetch(from: fixture.location).state == .setupRequired)
        }
    }

    @Test func concurrentWritersPreserveTheLatestObservation() async throws {
        let fixture = Fixture()
        defer { fixture.remove() }
        let readings = try (0..<24).map { index in
            let quota = "\"gemini-weekly\":{\"remaining_fraction\":\(Double(index) / 100),\"reset_time\":\"2027-02-01T12:00:00Z\"}"
            return try AntigravityUsageParser.parse(payload(quota: quota), now: now.addingTimeInterval(Double(index)))
        }
        try await withThrowingTaskGroup(of: Void.self) { group in
            for usage in readings.reversed() {
                group.addTask { _ = try AntigravityStatuslineFile.write(usage, to: fixture.location) }
            }
            try await group.waitForAll()
        }
        #expect(AntigravityStatuslineFile.read(from: fixture.location)?.usage == readings.last)
    }

    @Test func fullHistoryKeepsAcceptingQuotasBeforeAndAfterTheirReset() throws {
        let fixture = Fixture()
        defer { fixture.remove() }
        let reset = now.addingTimeInterval(3600)
        var latest: ServiceUsage?
        for index in 0..<260 {
            let reading = try usage(fraction: Double(index) / 1000, reset: reset,
                                    observedAt: now.addingTimeInterval(Double(index)))
            try AntigravityStatuslineFile.write(reading, to: fixture.location)
            latest = reading
        }
        let cache = try #require(AntigravityStatuslineFile.read(from: fixture.location))
        #expect(cache.usage == latest)
        #expect(cache.quotaMarkers.count == 256)
        #expect(cache.usage.remainingPercent(at: now.addingTimeInterval(1600)) == nil)
        #expect(try Data(contentsOf: fixture.location).count <= 65_536)

        let renewed = try usage(fraction: 0.8, reset: reset.addingTimeInterval(3600),
                                observedAt: reset.addingTimeInterval(1))
        let afterReset = try AntigravityStatuslineFile.write(renewed, to: fixture.location)
        #expect(afterReset.usage == renewed)
        #expect(afterReset.quotaMarkers.count == 256)
    }

    @Test func fullHistoryAcceptsNewQuotasAcrossDifferentResetHorizons() throws {
        let fixture = Fixture()
        defer { fixture.remove() }
        let hourReset = now.addingTimeInterval(3600)
        let weekReset = now.addingTimeInterval(7 * 24 * 3600)
        let weekly = try usage(fraction: 0.5, reset: weekReset, observedAt: now)
        try AntigravityStatuslineFile.write(weekly, to: fixture.location)
        for index in 1..<256 {
            let reading = try usage(id: "gemini-5h", fraction: Double(index) / 1000, reset: hourReset,
                                    observedAt: now.addingTimeInterval(Double(index)))
            try AntigravityStatuslineFile.write(reading, to: fixture.location)
        }
        #expect(AntigravityStatuslineFile.read(from: fixture.location)?.quotaHistoryExpiresAt == weekReset)

        let afterHour = try usage(id: "gemini-5h", fraction: 0.6, reset: hourReset.addingTimeInterval(3600),
                                  observedAt: hourReset.addingTimeInterval(1))
        #expect(try AntigravityStatuslineFile.write(afterHour, to: fixture.location).usage == afterHour)

        let extendedReset = weekReset.addingTimeInterval(24 * 3600)
        let extended = try usage(fraction: 0.7, reset: extendedReset, observedAt: hourReset.addingTimeInterval(3))
        let afterExtension = try AntigravityStatuslineFile.write(extended, to: fixture.location)
        #expect(afterExtension.usage == extended)
        #expect(afterExtension.quotaHistoryExpiresAt == extendedReset)
        let redraw = try usage(fraction: 0.7, reset: extendedReset, observedAt: weekReset.addingTimeInterval(1))
        let afterRedraw = try AntigravityStatuslineFile.write(redraw, to: fixture.location)
        #expect(afterRedraw.usage == extended)
        #expect(afterRedraw.usage.remainingPercent(at: weekReset.addingTimeInterval(1)) == nil)

        let renewed = try usage(fraction: 0.9, reset: extendedReset.addingTimeInterval(7 * 24 * 3600),
                                observedAt: extendedReset.addingTimeInterval(1))
        let afterReset = try AntigravityStatuslineFile.write(renewed, to: fixture.location)
        #expect(afterReset.usage == renewed)
        #expect(afterReset.quotaMarkers.count == 256)
    }

    private func usage(id: String = "gemini-weekly", fraction: Double, reset: Date,
                       observedAt: Date) throws -> ServiceUsage {
        let timestamp = ISO8601DateFormatter().string(from: reset)
        let quota = "\"\(id)\":{\"remaining_fraction\":\(fraction),\"reset_time\":\"\(timestamp)\"}"
        return try AntigravityUsageParser.parse(payload(quota: quota), now: observedAt)
    }

    private func payload(quota: String = #""gemini-weekly":{"remaining_fraction":0.456,"reset_time":"2027-02-01T12:00:00Z","reset_in_seconds":3600},"gemini-5h":{"remaining_fraction":0.9,"reset_time":"2027-02-01T12:00:00Z"},"3p-weekly":{"remaining_fraction":0.01,"reset_time":"2027-02-01T12:00:00Z"}"#) -> Data {
        Data("""
        {"product":"antigravity","quota":{\(quota)},"conversation_id":"synthetic-private-conversation","session_id":"synthetic-private-session","email":"synthetic-private@example.com","workspace":{"current_dir":"/synthetic-private/workspace"},"transcript_path":"/synthetic-private/transcript.jsonl","context_window":{"total_input_tokens":1},"credits":"synthetic-private-credit","agent_state":"idle"}
        """.utf8)
    }

    private struct Fixture: Sendable {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("usage-rings-gemini-statusline-\(UUID().uuidString)")
        var location: URL { folder.appendingPathComponent("usage.json") }
        func remove() { try? FileManager.default.removeItem(at: folder) }
    }
}
