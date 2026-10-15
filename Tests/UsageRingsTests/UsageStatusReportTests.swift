import Foundation
import Testing
import UsageCore

struct UsageStatusReportTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func reportIncludesAllProvidersAndIgnoresTheRingsSelectedPeriod() {
        let windows = [
            UsageWindow(id: "primary", title: "5 hours", usedPercent: 10, resetsAt: nil, period: .fiveHours),
            UsageWindow(id: "secondary", title: "Week", usedPercent: 80, resetsAt: nil, period: .week)
        ]
        let usage = ServiceUsage(service: .codex, state: .ready, windows: windows, updatedAt: now,
                                 preferredPeriod: .fiveHours)
        #expect(usage.remainingPercent(at: now) == 90)
        let snapshot = UsageSnapshot(services: [usage], ringOrder: [.grokBot, .cursor, .claude, .codex])
        let report = UsageStatusReport(snapshot: snapshot, now: now)
        #expect(report.services.map(\.provider) == ["codex", "claude", "cursor", "grok", "gemini"])
        #expect(report.schemaVersion == 1)
        #expect(report.generatedAt == now)
        #expect(report.pollIntervalSeconds == 300)
        #expect(report.maxAgeSeconds == 1200)
        #expect(report.thresholdPercent == 20)
        #expect(report.alerts.isEmpty)
        #expect(report.services[0].limitingRemainingPercent == 20)
        #expect(report.services[0].windows.map(\.remainingPercent) == [90, 20])
        #expect(report.services[0].windows.map(\.period) == [.fiveHours, .week])
        #expect(report.services.dropFirst().allSatisfy { $0.state == "disabled" && $0.limitingRemainingPercent == nil })
    }

    @Test func anExpiredMainWindowMakesTheServicePartialWithoutHidingFreshWindows() {
        let usage = ServiceUsage(service: .codex, state: .ready, windows: [
            UsageWindow(id: "primary", title: "5 hours", usedPercent: 10,
                        resetsAt: now.addingTimeInterval(600), period: .fiveHours),
            UsageWindow(id: "secondary", title: "Week", usedPercent: 80, resetsAt: now, period: .week)
        ], updatedAt: now, preferredPeriod: .fiveHours)
        let service = status(usage)
        #expect(service.state == "partial")
        #expect(service.limitingRemainingPercent == nil)
        #expect(service.windows[0].state == "ready")
        #expect(service.windows[0].remainingPercent == 90)
        #expect(service.windows[0].validUntil == now.addingTimeInterval(600))
        #expect(service.windows[1].state == "stale")
        #expect(service.windows[1].remainingPercent == nil)
        #expect(service.windows[1].validUntil == now)
    }

    @Test func exhaustedAndOverdrawnAllowancesAreZeroWhileMissingDataIsUnknown() {
        let usage = ServiceUsage(service: .grokBot, state: .ready, windows: [
            UsageWindow(id: "week", title: "Week", usedPercent: 105, resetsAt: nil, period: .week)
        ], updatedAt: now)
        let report = UsageStatusReport(snapshot: UsageSnapshot(services: [usage]), provider: .grokBot, now: now)
        #expect(report.services.count == 1)
        #expect(report.services[0].provider == "grok")
        #expect(report.services[0].state == "ready")
        #expect(report.services[0].limitingRemainingPercent == 0)
        #expect(report.services[0].windows[0].remainingPercent == 0)
        #expect(report.services[0].windows[0].validUntil == now.addingTimeInterval(1200))
        let missing = status(ServiceUsage(service: .codex, state: .ready, updatedAt: now))
        #expect(missing.state == "unavailable")
        #expect(missing.limitingRemainingPercent == nil)
        #expect(missing.windows.isEmpty)
    }

    @Test func failedRefreshesNeverExposePreviouslySuccessfulNumbers() {
        let usage = ServiceUsage(service: .codex, state: .unavailable, windows: [
            UsageWindow(id: "primary", title: "5 hours", usedPercent: 0, resetsAt: now.addingTimeInterval(600))
        ], updatedAt: now)
        let service = status(usage)
        #expect(service.state == "unavailable")
        #expect(service.observedAt == now)
        #expect(service.ageSeconds == 0)
        #expect(service.limitingRemainingPercent == nil)
        #expect(service.windows[0].state == "unavailable")
        #expect(service.windows[0].remainingPercent == nil)
        #expect(service.windows[0].validUntil == nil)
    }

    @Test func oldAndFutureDatedReadingsCannotReportFreshAllowance() {
        let window = UsageWindow(id: "primary", title: "5 hours", usedPercent: 25,
                                 resetsAt: now.addingTimeInterval(3600), period: .fiveHours)
        var usage = ServiceUsage(service: .codex, state: .ready, windows: [window],
                                 updatedAt: now.addingTimeInterval(-1200))
        let stale = status(usage)
        #expect(stale.state == "stale")
        #expect(stale.ageSeconds == 1200)
        #expect(stale.limitingRemainingPercent == nil)
        #expect(stale.windows[0].remainingPercent == nil)
        #expect(stale.windows[0].validUntil == now)
        usage.updatedAt = now.addingTimeInterval(61)
        let future = status(usage)
        #expect(future.state == "unavailable")
        #expect(future.ageSeconds == nil)
        #expect(future.windows[0].remainingPercent == nil)
        usage.updatedAt = now.addingTimeInterval(60)
        let tolerated = status(usage)
        #expect(tolerated.state == "ready")
        #expect(tolerated.ageSeconds == 0)
        #expect(tolerated.limitingRemainingPercent == 75)
    }

    @Test func cursorBreakdownsStayVisibleButDoNotReduceTheMainAllowance() {
        let usage = ServiceUsage(service: .cursor, state: .ready, windows: [
            UsageWindow(id: "total", title: "This month", usedPercent: 40, resetsAt: nil),
            UsageWindow(id: "cursor", title: "Cursor models", usedPercent: 95, resetsAt: nil),
            UsageWindow(id: "other", title: "Other models", usedPercent: 100, resetsAt: nil)
        ], updatedAt: now, preferredPeriod: .week)
        let service = status(usage)
        #expect(service.state == "ready")
        #expect(service.windows.map(\.isMain) == [true, false, false])
        #expect(service.windows.map(\.remainingPercent) == [60, 5, 0])
        #expect(service.limitingRemainingPercent == 60)
        let missingTotal = ServiceUsage(service: .cursor, state: .ready,
                                        windows: Array(usage.windows.dropFirst()), updatedAt: now)
        #expect(status(missingTotal).state == "partial")
        #expect(status(missingTotal).limitingRemainingPercent == nil)
    }

    @Test func claudeAuxiliaryWindowsDoNotConstrainItsKnownMainPeriods() {
        let usage = ServiceUsage(service: .claude, state: .ready, windows: [
            UsageWindow(id: "five_hour", title: "5 hours", usedPercent: 10, resetsAt: nil),
            UsageWindow(id: "seven_day", title: "Week", usedPercent: 40, resetsAt: nil),
            UsageWindow(id: "spend_limit", title: "Spend limit", usedPercent: 99, resetsAt: now)
        ], updatedAt: now)
        let service = status(usage)
        #expect(service.state == "partial")
        #expect(service.windows.map(\.isMain) == [true, true, false])
        #expect(service.windows.map(\.period) == [.fiveHours, .week, nil])
        #expect(service.windows[2].state == "stale")
        #expect(service.limitingRemainingPercent == 60)
    }

    @Test func invalidPercentagesAreUnknownAndNeverBreakJSONEncoding() throws {
        let windows = [Double.nan, -.infinity, -1, 105].enumerated().map { index, used in
            UsageWindow(id: "window-\(index)", title: "Usage", usedPercent: used, resetsAt: nil)
        }
        let usage = ServiceUsage(service: .codex, state: .ready, windows: windows, updatedAt: now)
        let report = UsageStatusReport(snapshot: UsageSnapshot(services: [usage]), provider: .codex, now: now)
        let service = report.services[0]
        #expect(service.state == "partial")
        #expect(service.windows.map(\.state) == ["unavailable", "unavailable", "unavailable", "ready"])
        #expect(service.windows.map(\.remainingPercent) == [nil, nil, nil, 0])
        #expect(service.limitingRemainingPercent == nil)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        #expect(throws: Never.self) { _ = try encoder.encode(report) }
    }

    @Test func JSONUsesAnExplicitPublicSchemaWithNullUnknownsAndNoAccountOrLayoutFields() throws {
        let source = try JSONSerialization.data(withJSONObject: [
            "services": [[
                "service": "codex", "state": "ready", "token": "synthetic-private-token",
                "account": ["email": "synthetic-private@example.com"], "preferredPeriod": "fiveHours",
                "windows": [["id": "primary", "title": "Usage", "usedPercent": 0,
                             "private_metadata": "synthetic-private-window"]]
            ]],
            "ringOrder": ["grokBot", "gemini", "claude", "codex"],
            "workspace": "synthetic-private-project"
        ])
        let snapshot = try JSONDecoder().decode(UsageSnapshot.self, from: source)
        let report = UsageStatusReport(snapshot: snapshot, provider: .codex, now: now)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let encoded = try encoder.encode(report)
        let json = try #require(try JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        #expect(Set(json.keys) == ["schemaVersion", "generatedAt", "pollIntervalSeconds", "maxAgeSeconds", "thresholdPercent", "services", "alerts"])
        #expect(json["generatedAt"] as? String == "2027-01-15T08:00:00Z")
        let services = try #require(json["services"] as? [[String: Any]])
        let service = try #require(services.first)
        #expect(Set(service.keys) == ["provider", "state", "observedAt", "ageSeconds", "limitingRemainingPercent", "windows"])
        #expect(service["observedAt"] is NSNull)
        #expect(service["ageSeconds"] is NSNull)
        #expect(service["limitingRemainingPercent"] is NSNull)
        let windows = try #require(service["windows"] as? [[String: Any]])
        let window = try #require(windows.first)
        #expect(Set(window.keys) == ["id", "title", "period", "isMain", "state", "remainingPercent", "resetsAt", "validUntil"])
        for key in ["period", "remainingPercent", "resetsAt", "validUntil"] { #expect(window[key] is NSNull) }
        #expect(!String(decoding: encoded, as: UTF8.self).contains("synthetic-private"))
    }

    @Test func alertsUseTheConfiguredStrictThresholdWithoutRememberingPreviousChecks() {
        let observed = now.addingTimeInterval(-30)
        let usage = ServiceUsage(service: .codex, state: .ready, windows: [
            UsageWindow(id: "primary", title: "5 hours", usedPercent: 90,
                        resetsAt: now.addingTimeInterval(90), period: .fiveHours),
            UsageWindow(id: "secondary", title: "Week", usedPercent: 80, resetsAt: nil, period: .week),
            UsageWindow(id: "other", title: "Other window", usedPercent: 75, resetsAt: nil)
        ], updatedAt: observed)
        let snapshot = UsageSnapshot(services: [usage])
        let standard = UsageStatusReport(snapshot: snapshot, now: now)
        #expect(standard.thresholdPercent == 20)
        #expect(standard.alerts.map(\.windowId) == ["primary"])
        #expect(standard.alerts[0].remainingPercent == 10)
        #expect(standard.alerts[0].observedAt == observed)
        #expect(standard.alerts[0].resetsAt == now.addingTimeInterval(90))
        #expect(standard.alerts[0].secondsUntilReset == 90)
        let custom = UsageStatusReport(snapshot: snapshot, now: now, thresholdPercent: 25)
        #expect(custom.thresholdPercent == 25)
        #expect(custom.alerts.map(\.windowId) == ["primary", "secondary"])
        #expect(UsageStatusReport(snapshot: snapshot, now: now).alerts.map(\.windowId) == ["primary"])
    }

    @Test func onlyFreshMainWindowsAlertEvenWhenAnotherMainWindowHasExpired() {
        let codex = ServiceUsage(service: .codex, state: .ready, windows: [
            UsageWindow(id: "primary", title: "5 hours", usedPercent: 95, resetsAt: nil, period: .fiveHours),
            UsageWindow(id: "secondary", title: "Week", usedPercent: 100, resetsAt: now, period: .week),
            UsageWindow(id: "invalid", title: "Other window", usedPercent: .nan, resetsAt: nil)
        ], updatedAt: now, preferredPeriod: .week)
        let cursor = ServiceUsage(service: .cursor, state: .ready, windows: [
            UsageWindow(id: "total", title: "This month", usedPercent: 10, resetsAt: nil),
            UsageWindow(id: "cursor", title: "Cursor models", usedPercent: 100, resetsAt: nil)
        ], updatedAt: now)
        let claude = ServiceUsage(service: .claude, state: .ready, windows: [
            UsageWindow(id: "five_hour", title: "5 hours", usedPercent: 10, resetsAt: nil),
            UsageWindow(id: "spend_limit", title: "Spend limit", usedPercent: 100, resetsAt: nil)
        ], updatedAt: now)
        let gemini = ServiceUsage(service: .gemini, state: .unavailable, windows: [
            UsageWindow(id: "gemini-5h", title: "5 hours", usedPercent: 100, resetsAt: nil, period: .fiveHours)
        ], updatedAt: now)
        let grok = ServiceUsage(service: .grokBot, state: .ready, windows: [
            UsageWindow(id: "week", title: "Week", usedPercent: 100, resetsAt: nil, period: .week)
        ], updatedAt: now.addingTimeInterval(-1200))
        let report = UsageStatusReport(snapshot: UsageSnapshot(services: [codex, cursor, claude, gemini, grok]), now: now)
        #expect(report.services[0].state == "partial")
        #expect(report.services[0].limitingRemainingPercent == nil)
        #expect(report.alerts.map(\.provider) == ["codex"])
        #expect(report.alerts.map(\.windowId) == ["primary"])
        #expect(report.alerts[0].remainingPercent == 5)
    }

    @Test func exhaustedAlertsUseThePublicProviderIDAndExplicitNullWhenResetIsUnknown() throws {
        let usage = ServiceUsage(service: .grokBot, state: .ready, windows: [
            UsageWindow(id: "week", title: "Week", usedPercent: 100, resetsAt: nil, period: .week)
        ], updatedAt: now)
        let report = UsageStatusReport(snapshot: UsageSnapshot(services: [usage]), provider: .grokBot, now: now)
        #expect(report.alerts.count == 1)
        #expect(report.alerts[0].provider == "grok")
        #expect(report.alerts[0].remainingPercent == 0)
        #expect(report.alerts[0].resetsAt == nil)
        #expect(report.alerts[0].secondsUntilReset == nil)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let json = try #require(try JSONSerialization.jsonObject(with: encoder.encode(report)) as? [String: Any])
        let alerts = try #require(json["alerts"] as? [[String: Any]])
        let alert = try #require(alerts.first)
        #expect(Set(alert.keys) == ["provider", "windowId", "title", "remainingPercent", "observedAt", "resetsAt", "secondsUntilReset"])
        #expect(alert["observedAt"] as? String == "2027-01-15T08:00:00Z")
        #expect(alert["resetsAt"] is NSNull)
        #expect(alert["secondsUntilReset"] is NSNull)
    }

    private func status(_ usage: ServiceUsage) -> UsageStatusReport.ServiceStatus {
        UsageStatusReport(snapshot: UsageSnapshot(services: [usage]), provider: usage.service, now: now).services[0]
    }
}
