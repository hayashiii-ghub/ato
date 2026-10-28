import Foundation
import Testing
import UsageCore

struct CursorPeriodUsageTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let weeklyResetMilliseconds: Int64 = 1_800_345_600_123
    private let monthlyResetMilliseconds: Int64 = 1_802_678_400_000

    @Test func verifiedMonthlyPlansKeepTheirTotalAndSamePeriodBreakdowns() throws {
        let result = try UsageResponseParser.cursor(
            usage(total: 40, auto: 95, other: 100),
            planInfo: plan(period: "INCLUDED_USAGE_PERIOD_MONTHLY", billingEnd: "1802592000000"), now: now
        )
        #expect(result.service == .cursor)
        #expect(result.state == .ready)
        #expect(result.updatedAt == now)
        #expect(result.windows.map(\.id) == ["total", "cursor", "other"])
        #expect(result.windows.map(\.title) == ["This month", "Cursor models", "Other models"])
        #expect(result.windows.allSatisfy { $0.period == nil })
        #expect(result.windows.allSatisfy { $0.resetsAt == milliseconds(monthlyResetMilliseconds) })
        #expect(result.headline?.id == "total")
        #expect(result.remainingPercent(at: now) == 60)
    }

    @Test func monthlyPlansUseMetadataResetWhenTheCurrentResponseHasNone() throws {
        let result = try UsageResponseParser.cursor(
            usage(reset: nil, auto: nil, other: nil),
            planInfo: plan(period: 1, billingEnd: "1802592000000"), now: now
        )
        #expect(result.windows.count == 1)
        #expect(result.headline?.resetsAt == milliseconds(1_802_592_000_000))
        #expect(result.headline?.title == "This month")
    }

    @Test func weeklyPlansExposeOnlyTheSharedTotalAndItsServerReset() throws {
        let result = try UsageResponseParser.cursor(
            usage(total: 25, auto: 95, other: 100, extras: ["limit": 0]),
            planInfo: plan(billingEnd: "1802592000000"), now: now
        )
        #expect(result.service == .cursor)
        #expect(result.windows.map(\.id) == ["total"])
        #expect(result.headline?.title == "Week")
        #expect(result.headline?.period == .week)
        #expect(result.headline?.resetsAt == milliseconds(weeklyResetMilliseconds))
        #expect(result.remainingPercent(at: now) == 75)
    }

    @Test func numericAndExactSymbolicPeriodEnumsHaveTheSameMeaning() throws {
        for value in [1, "INCLUDED_USAGE_PERIOD_MONTHLY"] as [Any] {
            let result = try UsageResponseParser.cursor(usage(), planInfo: plan(period: value), now: now)
            #expect(result.headline?.title == "This month")
            #expect(result.headline?.period == nil)
        }
        for value in [2, "INCLUDED_USAGE_PERIOD_WEEKLY"] as [Any] {
            let result = try UsageResponseParser.cursor(usage(), planInfo: plan(period: value), now: now)
            #expect(result.headline?.title == "Week")
            #expect(result.headline?.period == .week)
        }
        for value in [0, 3, 1.5, "1", "2", "monthly", "WEEKLY", "INCLUDED_USAGE_PERIOD_UNSPECIFIED", NSNull()] as [Any] {
            #expect(throws: (any Error).self) {
                try UsageResponseParser.cursor(usage(), planInfo: plan(period: value), now: now)
            }
        }
    }

    @Test func rpcInt64ResetValuesAcceptNumbersAndStringsInMilliseconds() throws {
        for value in [weeklyResetMilliseconds, String(weeklyResetMilliseconds)] as [Any] {
            let result = try UsageResponseParser.cursor(usage(), planInfo: plan(reset: value), now: now)
            let reset = try #require(result.headline?.resetsAt)
            #expect(abs(reset.timeIntervalSince1970 - 1_800_345_600.123) < 0.001)
        }
        for value in [monthlyResetMilliseconds, String(monthlyResetMilliseconds)] as [Any] {
            let result = try UsageResponseParser.cursor(usage(reset: value), planInfo: plan(period: 1), now: now)
            #expect(result.headline?.resetsAt == milliseconds(monthlyResetMilliseconds))
            let metadataOnly = try UsageResponseParser.cursor(
                usage(reset: nil), planInfo: plan(period: 1, billingEnd: value), now: now
            )
            #expect(metadataOnly.headline?.resetsAt == milliseconds(monthlyResetMilliseconds))
        }
    }

    @Test func weeklyMetadataCannotFallBackToAValidMonthlyReset() throws {
        for reset in [nil, NSNull(), 0, -1, "invalid", "1800345600123.5", 1_800_345_600_123.5] as [Any?] {
            #expect(throws: (any Error).self) {
                try UsageResponseParser.cursor(
                    usage(), planInfo: plan(reset: reset, billingEnd: "1802592000000"), now: now
                )
            }
        }
        for metadata in [try plan(period: nil), Data("{}".utf8)] {
            #expect(throws: (any Error).self) {
                try UsageResponseParser.cursor(usage(), planInfo: metadata, now: now)
            }
        }
        #expect(throws: (any Error).self) {
            try UsageResponseParser.cursor(
                usage(reset: nil), planInfo: plan(period: 1, billingEnd: nil), now: now
            )
        }
    }

    @Test func usageRequiresAnEnabledPlanAndAnExplicitValidPercentage() throws {
        for enabled in [nil, false, NSNull(), "true", 1] as [Any?] {
            #expect(throws: (any Error).self) {
                try UsageResponseParser.cursor(usage(enabled: enabled), planInfo: plan(), now: now)
            }
        }
        for total in [nil, NSNull(), -1, true, "25"] as [Any?] {
            #expect(throws: (any Error).self) {
                try UsageResponseParser.cursor(
                    usage(total: total, extras: ["used": 0, "limit": 2000, "remaining": 2000]),
                    planInfo: plan(), now: now
                )
            }
        }
        for data in [Data("{}".utf8), Data(#"{"enabled":true}"#.utf8)] {
            #expect(throws: (any Error).self) {
                try UsageResponseParser.cursor(data, planInfo: plan(), now: now)
            }
        }
        let unused = try UsageResponseParser.cursor(usage(total: 0), planInfo: plan(), now: now)
        #expect(unused.remainingPercent(at: now) == 100)
        let overdrawn = try UsageResponseParser.cursor(usage(total: 105), planInfo: plan(), now: now)
        #expect(overdrawn.remainingPercent(at: now) == 0)
    }

    @Test func weeklyTotalsRemainMainWindowsForReportsAlertsAndWidgetSnapshots() throws {
        let result = try UsageResponseParser.cursor(usage(total: 85), planInfo: plan(), now: now)
        let snapshot = UsageSnapshot(services: [result])
        let report = UsageStatusReport(snapshot: snapshot, provider: .cursor, now: now)
        let service = try #require(report.services.first)
        #expect(service.provider == "cursor")
        #expect(service.state == "ready")
        #expect(service.limitingRemainingPercent == 15)
        #expect(service.windows.map(\.isMain) == [true])
        #expect(service.windows.map(\.period) == [.week])
        #expect(report.alerts.map(\.provider) == ["cursor"])
        #expect(report.alerts.map(\.windowId) == ["total"])
        #expect(report.alerts.map(\.remainingPercent) == [15])
        #expect(report.alerts.first?.resetsAt == milliseconds(weeklyResetMilliseconds))
        let encoded = try JSONEncoder().encode(snapshot)
        #expect(try JSONDecoder().decode(UsageSnapshot.self, from: encoded) == snapshot)
    }

    @Test func resetBoundariesAndTwentyMinuteAgeNeverInventFreshAllowance() throws {
        let result = try UsageResponseParser.cursor(usage(total: 40), planInfo: plan(), now: now)
        #expect(result.remainingPercent(at: now.addingTimeInterval(1199)) == 60)
        #expect(result.remainingPercent(at: now.addingTimeInterval(1200)) == nil)
        let stale = UsageStatusReport(snapshot: UsageSnapshot(services: [result]), provider: .cursor,
                                      now: now.addingTimeInterval(1200))
        #expect(stale.services.first?.state == "stale")
        #expect(stale.services.first?.limitingRemainingPercent == nil)

        let nearReset = Int64((now.timeIntervalSince1970 + 60) * 1000)
        let expiring = try UsageResponseParser.cursor(usage(total: 40), planInfo: plan(reset: nearReset), now: now)
        #expect(expiring.remainingPercent(at: now.addingTimeInterval(59)) == 60)
        #expect(expiring.remainingPercent(at: now.addingTimeInterval(60)) == nil)
        for timestamp in [Int64(now.timeIntervalSince1970 * 1000), Int64((now.timeIntervalSince1970 - 60) * 1000)] {
            let expired = try UsageResponseParser.cursor(usage(total: 40), planInfo: plan(reset: timestamp), now: now)
            #expect(expired.headline?.resetsAt == milliseconds(timestamp))
            #expect(expired.remainingPercent(at: now) == nil)
        }
    }

    private func usage(enabled: Any? = true, total: Any? = 25, reset: Any? = "1802678400000",
                       auto: Any? = 10, other: Any? = 40, extras: [String: Any] = [:]) throws -> Data {
        var plan = extras
        if let total { plan["totalPercentUsed"] = total }
        if let auto { plan["autoPercentUsed"] = auto }
        if let other { plan["apiPercentUsed"] = other }
        var response: [String: Any] = ["planUsage": plan]
        if let enabled { response["enabled"] = enabled }
        if let reset { response["billingCycleEnd"] = reset }
        return try JSONSerialization.data(withJSONObject: response)
    }

    private func plan(period: Any? = "INCLUDED_USAGE_PERIOD_WEEKLY", reset: Any? = "1800345600123",
                      billingEnd: Any? = nil) throws -> Data {
        var plan: [String: Any] = [:]
        if let period { plan["includedUsagePeriod"] = period }
        if let reset { plan["includedUsageResetsAt"] = reset }
        if let billingEnd { plan["billingCycleEnd"] = billingEnd }
        return try JSONSerialization.data(withJSONObject: ["planInfo": plan])
    }

    private func milliseconds(_ value: Int64) -> Date {
        Date(timeIntervalSince1970: Double(value) / 1000)
    }
}
