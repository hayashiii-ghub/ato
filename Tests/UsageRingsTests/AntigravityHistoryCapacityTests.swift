import Foundation
import Testing
import UsageCore

struct AntigravityHistoryCapacityTests {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func weeklyQuotaContinuesUpdatingBeyondTheHistoryCapacity() throws {
        let fixture = Fixture()
        defer { fixture.remove() }

        let weeklyReset = start.addingTimeInterval(7 * 24 * 3600)
        let observationCount = 528
        let finalObservation = start.addingTimeInterval(Double(observationCount - 1) * 5)
        #expect(finalObservation < weeklyReset)

        for index in 1...observationCount {
            let observedAt = start.addingTimeInterval(Double(index - 1) * 5)
            let fraction = 1 - Double(index) / 1000
            let reading = try usage(fraction: fraction, reset: weeklyReset, observedAt: observedAt)
            let written = try AntigravityStatuslineFile.write(reading, to: fixture.location)

            if index == 256 || index == 257 || index == observationCount {
                let persisted = try #require(AntigravityStatuslineFile.read(from: fixture.location))
                #expect(written.usage == reading)
                #expect(persisted.usage == reading)
                #expect(persisted.usage.updatedAt == observedAt)
                #expect(persisted.quotaMarkers.count <= 256)
                #expect(try Data(contentsOf: fixture.location).count <= 65_536)
            }
        }

        let finalCache = try #require(AntigravityStatuslineFile.read(from: fixture.location))
        #expect(finalCache.usage.updatedAt == finalObservation)
        #expect(finalCache.usage.remainingPercent(at: finalObservation) != nil)
    }

    @Test func delayedUnseenWritersCannotMakeTheCurrentQuotaRedrawFresh() throws {
        let fixture = Fixture()
        defer { fixture.remove() }
        let weeklyReset = start.addingTimeInterval(7 * 24 * 3600)
        let currentTime = start.addingTimeInterval(1000)
        let current = try usage(fraction: 0.5, reset: weeklyReset, observedAt: currentTime)
        try AntigravityStatuslineFile.write(current, to: fixture.location)

        for index in 0..<300 {
            let delayed = try usage(fraction: 0.9 - Double(index) / 1000, reset: weeklyReset,
                                    observedAt: start.addingTimeInterval(Double(index)))
            try AntigravityStatuslineFile.write(delayed, to: fixture.location)
        }
        #expect(AntigravityStatuslineFile.read(from: fixture.location)?.usage == current)

        let replayTime = currentTime.addingTimeInterval(1300)
        let redraw = try usage(fraction: 0.5, reset: weeklyReset, observedAt: replayTime)
        let after = try AntigravityStatuslineFile.write(redraw, to: fixture.location)
        let persisted = try #require(AntigravityStatuslineFile.read(from: fixture.location))
        #expect(after.usage == current)
        #expect(persisted.usage == current)
        #expect(persisted.usage.updatedAt == currentTime)
        #expect(persisted.usage.remainingPercent(at: replayTime) == nil)
    }

    @Test func replayingAQuotaInsideTheRecentHistoryCannotRestoreAnEarlierValue() throws {
        let fixture = Fixture()
        defer { fixture.remove() }
        let weeklyReset = start.addingTimeInterval(7 * 24 * 3600)
        for index in 1...300 {
            let reading = try usage(fraction: 1 - Double(index) / 1000, reset: weeklyReset,
                                    observedAt: start.addingTimeInterval(Double(index)))
            try AntigravityStatuslineFile.write(reading, to: fixture.location)
        }
        let latestTime = start.addingTimeInterval(300)
        let latest = try usage(fraction: 1 - Double(300) / 1000, reset: weeklyReset, observedAt: latestTime)
        let replayTime = latestTime.addingTimeInterval(1300)
        let replay = try usage(fraction: 0.75, reset: weeklyReset, observedAt: replayTime)
        let after = try AntigravityStatuslineFile.write(replay, to: fixture.location)
        let persisted = try #require(AntigravityStatuslineFile.read(from: fixture.location))
        #expect(after.usage == latest)
        #expect(persisted.usage == latest)
        #expect(persisted.usage.updatedAt == latestTime)
        #expect(persisted.usage.remainingPercent(at: replayTime) == nil)
    }

    @Test func anEvictedQuotaIsOutsideTheReplayGuarantee() throws {
        let fixture = Fixture()
        defer { fixture.remove() }
        let weeklyReset = start.addingTimeInterval(7 * 24 * 3600)
        let original = try usage(fraction: 0.9, reset: weeklyReset, observedAt: start)
        let first = try AntigravityStatuslineFile.write(original, to: fixture.location)
        let originalMarker = try #require(first.quotaMarkers.first)
        for index in 1...256 {
            let reading = try usage(fraction: 0.8 - Double(index) / 1000, reset: weeklyReset,
                                    observedAt: start.addingTimeInterval(Double(index)))
            try AntigravityStatuslineFile.write(reading, to: fixture.location)
        }
        let previous = try #require(AntigravityStatuslineFile.read(from: fixture.location))
        #expect(!previous.quotaMarkers.contains(originalMarker))

        // Without a source timestamp, an evicted quota cannot be distinguished from a new reading.
        let receivedAt = start.addingTimeInterval(1600)
        let replay = try usage(fraction: 0.9, reset: weeklyReset, observedAt: receivedAt)
        let after = try AntigravityStatuslineFile.write(replay, to: fixture.location)
        #expect(after.usage == replay)
        #expect(after.quotaMarkers.count == 256)
    }

    @Test func anExplicitAllowanceIncreaseIsAccepted() throws {
        let fixture = Fixture()
        defer { fixture.remove() }
        let weeklyReset = start.addingTimeInterval(7 * 24 * 3600)
        for index in 1...300 {
            let reading = try usage(fraction: 1 - Double(index) / 1000, reset: weeklyReset,
                                    observedAt: start.addingTimeInterval(Double(index)))
            try AntigravityStatuslineFile.write(reading, to: fixture.location)
        }

        let observedAt = start.addingTimeInterval(310)
        let increased = try usage(fraction: 0.8001, reset: weeklyReset, observedAt: observedAt)
        let after = try AntigravityStatuslineFile.write(increased, to: fixture.location)
        let persisted = try #require(AntigravityStatuslineFile.read(from: fixture.location))
        #expect(after.usage == increased)
        #expect(persisted.usage == increased)
        #expect(persisted.usage.updatedAt == observedAt)
        #expect(abs((persisted.usage.remainingPercent(at: observedAt) ?? 0) - 80.01) < 0.000_001)
    }

    private func usage(fraction: Double, reset: Date, observedAt: Date) throws -> ServiceUsage {
        let resetTimestamp = ISO8601DateFormatter().string(from: reset)
        let payload = Data("""
        {"product":"antigravity","quota":{"gemini-weekly":{"remaining_fraction":\(fraction),"reset_time":"\(resetTimestamp)"}}}
        """.utf8)
        return try AntigravityUsageParser.parse(payload, now: observedAt)
    }

    private struct Fixture {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("usage-rings-gemini-history-\(UUID().uuidString)")
        var location: URL { folder.appendingPathComponent("usage.json") }
        func remove() { try? FileManager.default.removeItem(at: folder) }
    }
}
