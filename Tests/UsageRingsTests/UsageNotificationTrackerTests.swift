import Foundation
import Testing
import UsageCore

struct UsageNotificationTrackerTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func inclusiveStagesAreNotRepeatedAfterRecoveryOrRestart() throws {
        var tracker = UsageNotificationTracker()
        #expect(delivered(&tracker, report: report(remaining: 21)).isEmpty)
        #expect(delivered(&tracker, report: report(remaining: 20, seconds: 1)).map(\.thresholdPercent) == [20])
        #expect(delivered(&tracker, report: report(remaining: 15, seconds: 2)).isEmpty)
        #expect(delivered(&tracker, report: report(remaining: 10, seconds: 3)).map(\.thresholdPercent) == [10])
        #expect(delivered(&tracker, report: report(remaining: 0, seconds: 4)).isEmpty)
        #expect(delivered(&tracker, report: report(remaining: 80, seconds: 5)).isEmpty)
        tracker = try JSONDecoder().decode(UsageNotificationTracker.self, from: JSONEncoder().encode(tracker))
        #expect(delivered(&tracker, report: report(remaining: 8, seconds: 6)).isEmpty)
    }

    @Test func anInitialLowReadingEmitsOnlyTheLowestStageAndANewResetRearmsIt() {
        var tracker = UsageNotificationTracker()
        let first = delivered(&tracker, report: report(remaining: 8))
        #expect(first.count == 1)
        #expect(first.first?.service == .codex)
        #expect(first.first?.thresholdPercent == 10)
        #expect(first.first?.remainingPercent == 8)
        #expect(first.first?.observedAt == now)
        #expect(first.first?.resetsAt == now.addingTimeInterval(3_600))
        #expect(delivered(&tracker, report: report(remaining: 8, seconds: 1, resetSeconds: 7_200))
            .map(\.thresholdPercent) == [10])
        #expect(delivered(&tracker, report: report(remaining: 8, seconds: 2)).isEmpty)
    }

    @Test func sameOrOlderObservationsCannotIntroduceALowerStageOrANewReset() {
        var tracker = UsageNotificationTracker()
        #expect(delivered(&tracker, report: report(remaining: 20)).count == 1)
        #expect(delivered(&tracker, report: report(remaining: 5)).isEmpty)
        #expect(delivered(&tracker, report: report(remaining: 5, seconds: -1, resetSeconds: 7_200)).isEmpty)
        #expect(delivered(&tracker, report: report(remaining: 10, seconds: 1)).map(\.thresholdPercent) == [10])
    }

    @Test func failedDeliveryRetriesTheSameObservationAndAcknowledgementsDoNotRewindIt() {
        var tracker = UsageNotificationTracker()
        let firstReport = report(remaining: 20)
        let first = tracker.notices(for: firstReport)
        #expect(tracker.notices(for: firstReport) == first)
        #expect(tracker.notices(for: report(remaining: 5)).isEmpty)
        #expect(tracker.notices(for: report(remaining: 5, seconds: -1)).isEmpty)
        let newerReport = report(remaining: 10, seconds: 1)
        let newer = tracker.notices(for: newerReport)
        #expect(newer.map(\.thresholdPercent) == [10])
        first.forEach { tracker.markDelivered($0) }
        #expect(tracker.notices(for: firstReport).isEmpty)
        #expect(tracker.notices(for: newerReport) == newer)
        newer.forEach { tracker.markDelivered($0) }
        #expect(tracker.notices(for: newerReport).isEmpty)
    }

    @Test func partialDeliveryRetriesOnlyTheUndeliveredWindow() {
        var tracker = UsageNotificationTracker()
        let usage = ServiceUsage(service: .codex, state: .ready, windows: [
            window(remaining: 20),
            UsageWindow(id: "secondary", title: "Week", usedPercent: 90,
                        resetsAt: now.addingTimeInterval(604_800), period: .week)
        ], updatedAt: now)
        let current = UsageStatusReport(snapshot: UsageSnapshot(services: [usage]), now: now)
        let notices = tracker.notices(for: current)
        #expect(notices.count == 2)
        if let first = notices.first { tracker.markDelivered(first) }
        #expect(tracker.notices(for: current) == Array(notices.dropFirst()))
    }

    @Test func unavailableExpiredAndInvalidReadingsStayQuietWithoutClearingHistory() {
        var tracker = UsageNotificationTracker()
        #expect(delivered(&tracker, report: report(remaining: 20)).count == 1)
        for usage in [
            ServiceUsage(service: .codex, state: .unavailable, windows: [window(remaining: 5)], updatedAt: now),
            ServiceUsage(service: .codex, state: .ready, windows: [window(remaining: 5)],
                         updatedAt: now.addingTimeInterval(-1_200)),
            ServiceUsage(service: .codex, state: .ready, windows: [window(remaining: 5, resetSeconds: 0)], updatedAt: now),
            ServiceUsage(service: .codex, state: .ready, windows: [window(remaining: .nan)], updatedAt: now),
            ServiceUsage(service: .codex, state: .ready, windows: [window(remaining: 5)],
                         updatedAt: now.addingTimeInterval(61))
        ] {
            #expect(delivered(&tracker, report: UsageStatusReport(snapshot: UsageSnapshot(services: [usage]), now: now)).isEmpty)
        }
        #expect(delivered(&tracker, report: report(remaining: 20, seconds: 1)).isEmpty)
        #expect(delivered(&tracker, report: report(remaining: 10, seconds: 2)).map(\.thresholdPercent) == [10])
    }

    @Test func eachMainWindowIsIndependentAndCursorBreakdownsAreIgnored() {
        var tracker = UsageNotificationTracker()
        let cursor = ServiceUsage(service: .cursor, state: .ready, windows: [
            UsageWindow(id: "total", title: "This month", usedPercent: 10, resetsAt: nil),
            UsageWindow(id: "other", title: "Other models", usedPercent: 99, resetsAt: nil)
        ], updatedAt: now)
        let codex = ServiceUsage(service: .codex, state: .ready, windows: [
            window(remaining: 20),
            UsageWindow(id: "secondary", title: "Week", usedPercent: 90,
                        resetsAt: now.addingTimeInterval(604_800), period: .week)
        ], updatedAt: now, preferredPeriod: .fiveHours)
        let notices = delivered(&tracker, report: UsageStatusReport(snapshot: UsageSnapshot(services: [cursor, codex]), now: now))
        #expect(notices.map(\.service) == [.codex, .codex])
        #expect(notices.map(\.windowID) == ["primary", "secondary"])
        #expect(notices.map(\.thresholdPercent) == [20, 10])
    }

    @Test func persistedHistoryHasBoundedWindowsAndResetPeriods() throws {
        var tracker = UsageNotificationTracker()
        for index in 0..<100 {
            let usage = ServiceUsage(service: .codex, state: .ready, windows: [
                UsageWindow(id: "window-\(index)", title: "Unpersisted title", usedPercent: 90,
                            resetsAt: now.addingTimeInterval(10_000))
            ], updatedAt: now.addingTimeInterval(Double(index)))
            _ = delivered(&tracker, report: UsageStatusReport(snapshot: UsageSnapshot(services: [usage]),
                                                       now: now.addingTimeInterval(Double(index))))
        }
        for index in 100..<120 {
            _ = delivered(&tracker, report: report(remaining: 10, seconds: Double(index), resetSeconds: Double(index + 10_000)))
        }
        let data = try JSONEncoder().encode(tracker)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let windows = try #require(object["windows"] as? [String: [String: Any]])
        #expect(windows.count == 64)
        #expect(windows.keys.allSatisfy { $0.count == 64 })
        #expect(windows.values.allSatisfy { ($0["boundaries"] as? [Any])?.count ?? 0 <= 8 })
        #expect(!String(decoding: data, as: UTF8.self).contains("Unpersisted title"))
        let restored = try JSONDecoder().decode(UsageNotificationTracker.self, from: data)
        #expect(try JSONEncoder().encode(restored).count == data.count)
    }

    private func report(remaining: Double, seconds: TimeInterval = 0, resetSeconds: TimeInterval = 3_600) -> UsageStatusReport {
        let observedAt = now.addingTimeInterval(seconds)
        let usage = ServiceUsage(service: .codex, state: .ready,
                                 windows: [window(remaining: remaining, resetSeconds: resetSeconds)], updatedAt: observedAt)
        return UsageStatusReport(snapshot: UsageSnapshot(services: [usage]), now: observedAt)
    }

    private func delivered(_ tracker: inout UsageNotificationTracker, report: UsageStatusReport) -> [UsageNotificationTracker.Notice] {
        let notices = tracker.notices(for: report)
        notices.forEach { tracker.markDelivered($0) }
        return notices
    }

    private func window(remaining: Double, resetSeconds: TimeInterval = 3_600) -> UsageWindow {
        UsageWindow(id: "primary", title: "5 hours", usedPercent: 100 - remaining,
                    resetsAt: now.addingTimeInterval(resetSeconds), period: .fiveHours)
    }
}
