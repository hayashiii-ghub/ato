import Foundation

extension UsageResponseParser {
    public static func cursor(_ data: Data, planInfo: Data, now: Date = Date()) throws -> ServiceUsage {
        let usage = try JSONDecoder().decode(CursorPeriodUsageResponse.self, from: data)
        let metadata = try JSONDecoder().decode(CursorPlanInfoResponse.self, from: planInfo)
        guard usage.enabled == true, let plan = usage.planUsage, let total = plan.totalPercentUsed,
              let info = metadata.planInfo, let period = info.includedUsagePeriod else {
            throw UsageReadError.invalidResponse
        }

        let reset: Date
        let title: String
        let usagePeriod: UsagePeriod?
        switch period {
        case .weekly:
            guard let timestamp = info.includedUsageResetsAt else { throw UsageReadError.invalidResponse }
            reset = try timestamp.date()
            title = UsagePeriod.week.title
            usagePeriod = .week
        case .monthly:
            guard let timestamp = usage.billingCycleEnd ?? info.billingCycleEnd else {
                throw UsageReadError.invalidResponse
            }
            reset = try timestamp.date()
            title = "This month"
            usagePeriod = nil
        }

        var windows = [UsageWindow(id: "total", title: title, usedPercent: try cursorPercent(total),
                                   resetsAt: reset, period: usagePeriod)]
        // The weekly ring displays the shared total allowance.
        if period == .monthly {
            for (id, title, value) in [("cursor", "Cursor models", plan.autoPercentUsed),
                                       ("other", "Other models", plan.apiPercentUsed)] {
                if let value {
                    windows.append(UsageWindow(id: id, title: title, usedPercent: try cursorPercent(value),
                                               resetsAt: reset))
                }
            }
        }
        return ServiceUsage(service: .cursor, state: .ready, windows: windows, updatedAt: now)
    }

    private static func cursorPercent(_ value: Double) throws -> Double {
        guard value.isFinite, value >= 0 else { throw UsageReadError.invalidResponse }
        return min(value, 100)
    }
}

private struct CursorPeriodUsageResponse: Decodable {
    let enabled: Bool?
    let billingCycleEnd: CursorMilliseconds?
    let planUsage: Plan?

    struct Plan: Decodable {
        let totalPercentUsed: Double?
        let autoPercentUsed: Double?
        let apiPercentUsed: Double?
    }
}

private struct CursorPlanInfoResponse: Decodable {
    let planInfo: Plan?

    struct Plan: Decodable {
        let includedUsagePeriod: CursorIncludedUsagePeriod?
        let includedUsageResetsAt: CursorMilliseconds?
        let billingCycleEnd: CursorMilliseconds?
    }
}

private enum CursorIncludedUsagePeriod: Decodable {
    case monthly, weekly

    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer()
        if let number = try? value.decode(Int.self) {
            switch number {
            case 1: self = .monthly
            case 2: self = .weekly
            default: throw UsageReadError.invalidResponse
            }
        } else {
            switch try value.decode(String.self) {
            case "INCLUDED_USAGE_PERIOD_MONTHLY": self = .monthly
            case "INCLUDED_USAGE_PERIOD_WEEKLY": self = .weekly
            default: throw UsageReadError.invalidResponse
            }
        }
    }
}

private struct CursorMilliseconds: Decodable {
    let value: Int64

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let number = try? container.decode(Int64.self) {
            value = number
        } else {
            guard let number = Int64(try container.decode(String.self)) else {
                throw UsageReadError.invalidResponse
            }
            value = number
        }
    }

    func date() throws -> Date {
        guard value > 0 else { throw UsageReadError.invalidResponse }
        return Date(timeIntervalSince1970: Double(value) / 1000)
    }
}
