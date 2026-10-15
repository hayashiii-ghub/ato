import Foundation

public enum UsageReadError: Error {
    case missingSession, expiredSession, invalidResponse, requestFailed
}

public enum UsageResponseParser {
    public static func codex(_ data: Data, now: Date = Date()) throws -> ServiceUsage {
        let response = try JSONDecoder().decode(CodexResponse.self, from: data)
        let limits = response.rateLimitsByLimitId?["codex"] ?? response.rateLimits
        guard limits.limitId == nil || limits.limitId == "codex" else { throw UsageReadError.invalidResponse }
        let pairs = [("primary", limits.primary), ("secondary", limits.secondary)]
        let windows = try pairs.compactMap { id, raw -> UsageWindow? in
            guard let raw else { return nil }
            let title: String
            let period: UsagePeriod?
            switch raw.windowDurationMins {
            case 300: title = UsagePeriod.fiveHours.title; period = .fiveHours
            case 10_080: title = UsagePeriod.week.title; period = .week
            case let minutes? where minutes > 0 && minutes % 1_440 == 0:
                title = "\(minutes / 1_440) days"; period = nil
            case let minutes? where minutes > 0 && minutes % 60 == 0:
                title = "\(minutes / 60) hours"; period = nil
            default: title = id == "primary" ? "Current window" : "Other window"; period = nil
            }
            return UsageWindow(id: id, title: title, usedPercent: try percent(raw.usedPercent),
                               resetsAt: raw.resetsAt.map { Date(timeIntervalSince1970: TimeInterval($0)) }, period: period)
        }
        guard !windows.isEmpty else { throw UsageReadError.invalidResponse }
        return ServiceUsage(service: .codex, state: .ready, windows: windows, updatedAt: now)
    }

    public static func cursor(_ data: Data, now: Date = Date()) throws -> ServiceUsage {
        let response = try JSONDecoder().decode(CursorResponse.self, from: data)
        guard let plan = response.individualUsage?.plan, plan.enabled != false,
              let total = plan.totalPercentUsed else { throw UsageReadError.invalidResponse }
        let reset = response.billingCycleEnd.flatMap(parseDate)
        var windows = [UsageWindow(id: "total", title: "This month", usedPercent: try percent(total), resetsAt: reset)]
        for (id, title, value) in [("cursor", "Cursor models", plan.autoPercentUsed), ("other", "Other models", plan.apiPercentUsed)] {
            if let value {
                windows.append(UsageWindow(id: id, title: title, usedPercent: try percent(value), resetsAt: reset))
            }
        }
        return ServiceUsage(service: .cursor, state: .ready, windows: windows, updatedAt: now)
    }

    public static func grokBot(_ data: Data, now: Date = Date()) throws -> ServiceUsage {
        let response = try JSONDecoder().decode(GrokBotResponse.self, from: data)
        guard response.usesPooledEnterpriseAllowance != true,
              response.hasNonZeroIncludedLimit == true,
              let used = response.usagePercent,
              let timestamp = response.nextResetTimestampUtc,
              let reset = parseDate(timestamp) else { throw UsageReadError.invalidResponse }
        let window = UsageWindow(id: "week", title: "Week", usedPercent: try percent(used), resetsAt: reset, period: .week)
        return ServiceUsage(service: .grokBot, state: .ready, windows: [window], updatedAt: now)
    }

    private static func percent(_ value: Double) throws -> Double {
        guard value.isFinite, value >= 0 else { throw UsageReadError.invalidResponse }
        return min(value, 100)
    }

    private static func parseDate(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }
}

private struct GrokBotResponse: Decodable {
    let usagePercent: Double?
    let nextResetTimestampUtc: String?
    let hasNonZeroIncludedLimit: Bool?
    let usesPooledEnterpriseAllowance: Bool?
}

private struct CodexResponse: Decodable {
    let rateLimits: Limits
    let rateLimitsByLimitId: [String: Limits]?
    struct Limits: Decodable {
        let limitId: String?
        let primary: Window?
        let secondary: Window?
    }
    struct Window: Decodable {
        let usedPercent: Double
        let windowDurationMins: Int?
        let resetsAt: Int64?
    }
}

private struct CursorResponse: Decodable {
    let billingCycleEnd: String?
    let individualUsage: Individual?
    struct Individual: Decodable { let plan: Plan? }
    struct Plan: Decodable {
        let enabled: Bool?
        let totalPercentUsed: Double?
        let autoPercentUsed: Double?
        let apiPercentUsed: Double?
    }
}
