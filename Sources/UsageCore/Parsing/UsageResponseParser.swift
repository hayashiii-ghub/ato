import Foundation

public enum UsageReadError: Error {
    case missingSession, expiredSession, invalidResponse, requestFailed, keychainAccessRequired
}

public enum UsageResponseParser {
    public static func codex(_ data: Data, now: Date = Date()) throws -> ServiceUsage {
        let response = try JSONDecoder().decode(CodexResponse.self, from: data)
        let limits = response.rateLimitsByLimitId?["codex"] ?? response.rateLimits
        guard limits.limitId == nil || limits.limitId == "codex" else { throw UsageReadError.invalidResponse }
        let primaryDuration = limits.defaultPrimaryDuration
        let pairs = [("primary", limits.primary, primaryDuration),
                     ("secondary", limits.secondary, primaryDuration == 300 ? 10_080 : nil)]
        var windows = try pairs.compactMap { id, raw, fallbackDuration -> UsageWindow? in
            guard let raw else { return nil }
            let title: String
            let period: UsagePeriod?
            switch raw.windowDurationMins ?? fallbackDuration {
            case 300: title = UsagePeriod.fiveHours.title; period = .fiveHours
            case 10_080: title = UsagePeriod.week.title; period = .week
            case 43_200: title = "This month"; period = nil
            case let minutes? where minutes > 0 && minutes % 1_440 == 0:
                title = "\(minutes / 1_440) days"; period = nil
            case let minutes? where minutes > 0 && minutes % 60 == 0:
                title = "\(minutes / 60) hours"; period = nil
            default: title = id == "primary" ? "Current window" : "Other window"; period = nil
            }
            return UsageWindow(id: id, title: title, usedPercent: try percent(raw.usedPercent),
                               resetsAt: raw.resetsAt.map { Date(timeIntervalSince1970: TimeInterval($0)) }, period: period)
        }
        if let credit = limits.individualLimit, credit.remainingPercent.isFinite,
           credit.remainingPercent <= 100, credit.resetsAt > 0 {
            windows.append(UsageWindow(id: UsageWindow.codexMonthlyCreditID, title: "Monthly credits",
                                       usedPercent: 100 - max(0, credit.remainingPercent),
                                       resetsAt: Date(timeIntervalSince1970: TimeInterval(credit.resetsAt))))
        }
        guard !windows.isEmpty else { throw UsageReadError.invalidResponse }
        return ServiceUsage(service: .codex, state: .ready, windows: windows, updatedAt: now)
    }

    public static func grokBuild(_ data: Data, now: Date = Date()) throws -> ServiceUsage {
        let response = try JSONDecoder().decode(GrokBuildResponse.self, from: data)
        let period = response.config?.currentPeriod
        let weekly = period?.type == "USAGE_PERIOD_TYPE_WEEKLY" || period?.type == "WEEKLY"
        let monthly = period?.type == "USAGE_PERIOD_TYPE_MONTHLY" || period?.type == "MONTHLY"
        let start = period?.start.flatMap(parseGrokBoundary)
        let reset = period?.end.flatMap(parseGrokBoundary)
        var used = response.config?.creditUsagePercent
        // Grok omits a zero percentage while still supplying the complete subscription period.
        if used == nil, weekly || monthly, let start, let reset, start <= now, now < reset {
            used = 0
        }
        guard let used else { throw UsageReadError.invalidResponse }
        let title = weekly ? UsagePeriod.week.title : monthly ? "This month" : "Subscription"
        let window = UsageWindow(id: "subscription", title: title, usedPercent: try percent(used),
                                 resetsAt: reset, period: weekly ? .week : nil)
        return ServiceUsage(service: .grokBot, state: .ready, windows: [window], updatedAt: now)
    }

    private static func percent(_ value: Double) throws -> Double {
        guard value.isFinite, value >= 0 else { throw UsageReadError.invalidResponse }
        return min(value, 100)
    }

    public static func parseDate(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }

    private static func parseGrokBoundary(_ value: String) -> Date? {
        // Foundation can normalize impossible calendar dates when parsing ISO timestamps.
        let parts = value.prefix(10).split(separator: "-", omittingEmptySubsequences: false)
        let numbers = parts.compactMap { Int($0) }
        guard parts.map(\.count) == [4, 2, 2], numbers.count == 3,
              value.range(of: #"^\d{4}-\d{2}-\d{2}T(?:[01]\d|2[0-3]):[0-5]\d(?::[0-5]\d(?:\.\d+)?)?(?:Z|[+-]\d{2}:\d{2})$"#,
                          options: .regularExpression) != nil else { return nil }
        let calendar = Calendar(identifier: .gregorian)
        let date = DateComponents(calendar: calendar, year: numbers[0], month: numbers[1], day: numbers[2])
        return date.isValidDate ? parseDate(value) : nil
    }
}

private struct GrokBuildResponse: Decodable {
    let config: Configuration?

    struct Configuration: Decodable {
        let creditUsagePercent: Double?
        let currentPeriod: Period?
    }

    struct Period: Decodable {
        let type: String?
        let start: String?
        let end: String?

        private enum CodingKeys: String, CodingKey { case type, start, end }

        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            type = try values.decodeIfPresent(String.self, forKey: .type)
            start = try? values.decode(String.self, forKey: .start)
            end = try values.decodeIfPresent(String.self, forKey: .end)
        }
    }
}

private struct CodexResponse: Decodable {
    let rateLimits: Limits
    let rateLimitsByLimitId: [String: Limits]?
    struct Limits: Decodable {
        let limitId: String?
        let planType: String?
        let primary: Window?
        let secondary: Window?
        let individualLimit: IndividualLimit?

        private enum CodingKeys: String, CodingKey { case limitId, planType, primary, secondary, individualLimit }

        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            limitId = try values.decodeIfPresent(String.self, forKey: .limitId)
            primary = try values.decodeIfPresent(Window.self, forKey: .primary)
            secondary = try values.decodeIfPresent(Window.self, forKey: .secondary)
            // Invalid optional plan and credit metadata must not discard existing allowance windows.
            planType = try? values.decode(String.self, forKey: .planType)
            individualLimit = try? values.decode(IndividualLimit.self, forKey: .individualLimit)
        }

        var defaultPrimaryDuration: Int? {
            switch planType {
            case "free", "go": return 43_200
            case "plus", "pro", "prolite", "promax", "team", "business", "enterprise", "edu": return 300
            default: return nil
            }
        }
    }
    struct IndividualLimit: Decodable {
        let remainingPercent: Double
        let resetsAt: Int64
    }
    struct Window: Decodable {
        let usedPercent: Double
        let windowDurationMins: Int?
        let resetsAt: Int64?
    }
}
