import Foundation

public enum UsageService: String, Codable, CaseIterable, Identifiable, Sendable {
    case codex, claude, grokBot, gemini

    public var id: String { rawValue }
    public var name: String {
        switch self {
        case .codex: return "Codex"
        case .claude: return "Claude"
        case .grokBot: return "Grok"
        case .gemini: return "Gemini"
        }
    }
}

public enum UsageState: String, Codable, Sendable {
    case ready, disabled, setupRequired, signInRequired, unavailable
}

public enum UsagePeriod: String, Codable, CaseIterable, Identifiable, Sendable {
    case fiveHours, week

    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .fiveHours: return "5 hours"
        case .week: return "Week"
        }
    }
}

public struct UsageWindow: Codable, Equatable, Identifiable, Sendable {
    static let codexMonthlyCreditID = "individual"

    public let id: String
    public let title: String
    public let usedPercent: Double
    public let resetsAt: Date?
    public let period: UsagePeriod?

    public var remainingPercent: Double { max(0, min(100, 100 - usedPercent)) }

    public init(id: String, title: String, usedPercent: Double, resetsAt: Date?, period: UsagePeriod? = nil) {
        self.id = id
        self.title = title
        self.usedPercent = usedPercent
        self.resetsAt = resetsAt
        self.period = period
    }
}

public struct ServiceUsage: Codable, Equatable, Identifiable, Sendable {
    public let service: UsageService
    public var state: UsageState
    public var windows: [UsageWindow]
    public var updatedAt: Date?
    public var preferredPeriod: UsagePeriod?

    public var id: UsageService { service }

    public init(service: UsageService, state: UsageState, windows: [UsageWindow] = [], updatedAt: Date? = nil,
                preferredPeriod: UsagePeriod? = nil) {
        self.service = service
        self.state = state
        self.windows = windows
        self.updatedAt = updatedAt
        self.preferredPeriod = preferredPeriod
    }

    public var headline: UsageWindow? {
        if let preferredPeriod {
            return windows.filter { period(for: $0) == preferredPeriod && (service != .gemini || isMainWindow($0)) }
                .min { $0.remainingPercent < $1.remainingPercent }
        }
        return windows.filter(isMainWindow).min { $0.remainingPercent < $1.remainingPercent }
    }

    public func isMainWindow(_ window: UsageWindow) -> Bool {
        switch service {
        case .claude: return window.id == "five_hour" || window.id == "seven_day"
        case .gemini: return ["gemini-5h", "gemini-weekly", "gemini-quota"].contains(window.id)
        case .codex where window.id == UsageWindow.codexMonthlyCreditID:
            // Monthly credits are supplemental when the account has included plan windows.
            return !windows.contains { $0.id == "primary" || $0.id == "secondary" }
        default: return true
        }
    }

    public var ringWindow: UsageWindow? {
        guard let headline else { return nil }
        return preferredPeriod == .fiveHours ? exhaustedWeeklyWindow ?? headline : headline
    }

    public func isRingBlockedByWeeklyLimit(at date: Date) -> Bool {
        ringWindow?.id != headline?.id && isCurrent(at: date)
    }

    var exhaustedWeeklyWindow: UsageWindow? {
        guard service == .codex || service == .claude else { return nil }
        // Keep the blocker through its reset until a new reading confirms the allowance.
        return windows.first {
            isMainWindow($0) && period(for: $0) == .week && $0.usedPercent.isFinite && $0.usedPercent >= 100
        }
    }

    public func period(for window: UsageWindow) -> UsagePeriod? {
        if let period = window.period { return period }
        // Legacy Claude status-line caches predate period metadata; these main IDs are stable.
        guard service == .claude else { return nil }
        switch window.id {
        case "five_hour": return .fiveHours
        case "seven_day": return .week
        default: return nil
        }
    }

    public func hasFreshReading(at date: Date) -> Bool {
        guard state == .ready, let updatedAt, !windows.isEmpty else { return false }
        return date.timeIntervalSince(updatedAt) < UsageSnapshot.maximumAge
            && updatedAt <= date.addingTimeInterval(60)
    }

    public func isCurrent(at date: Date) -> Bool {
        guard hasFreshReading(at: date) else { return false }
        if preferredPeriod != nil {
            guard let ringWindow else { return false }
            return remainingPercent(for: ringWindow, at: date) != nil
        }
        // A passed reset requires a new server reading, not an assumed full allowance.
        return !windows.contains { window in
            let isRelevant = (service != .codex && service != .gemini) || isMainWindow(window)
            return isRelevant && (window.resetsAt.map { $0 <= date } ?? false)
        }
    }

    public func remainingPercent(for window: UsageWindow, at date: Date) -> Double? {
        guard hasFreshReading(at: date), windows.contains(window),
              window.usedPercent.isFinite, window.usedPercent >= 0,
              window.resetsAt.map({ $0.timeIntervalSinceReferenceDate.isFinite && $0 > date }) ?? true else { return nil }
        return window.remainingPercent
    }

    public func remainingPercent(at date: Date) -> Double? {
        isCurrent(at: date) ? ringWindow?.remainingPercent : nil
    }
}

public struct UsageSnapshot: Codable, Equatable, Sendable {
    public static let maximumAge: TimeInterval = 20 * 60
    public static let widgetKind = "UsageRings"
    public static let bridgePort: UInt16 = 52388
    public static let bridgeURL = URL(string: "http://127.0.0.1:\(bridgePort)/v1/usage")!
    public static let defaultRingOrder: [UsageService] = [.codex, .claude, .grokBot, .gemini]
    public static let empty = UsageSnapshot(services: UsageService.allCases.map {
        ServiceUsage(service: $0, state: .disabled)
    })

    public var services: [ServiceUsage]
    public let ringOrder: [UsageService]

    public init(services: [ServiceUsage], ringOrder: [UsageService] = UsageSnapshot.defaultRingOrder) {
        self.services = services
        self.ringOrder = Self.normalizedRingOrder(ringOrder)
    }

    public static func normalizedRingOrder(_ order: [UsageService]) -> [UsageService] {
        var result: [UsageService] = []
        for service in order + defaultRingOrder where !result.contains(service) {
            result.append(service)
            if result.count == 4 { break }
        }
        return result
    }

    private enum CodingKeys: String, CodingKey { case services, ringOrder }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let services = try values.decode([CachedService].self, forKey: .services).compactMap(\.usage)
        // Older caches have no order; a future provider ID must not hide known rings.
        let identifiers = try values.decodeIfPresent([String].self, forKey: .ringOrder)
        let order = identifiers?.compactMap { UsageService(rawValue: $0) } ?? Self.defaultRingOrder
        self.init(services: services, ringOrder: order)
    }

    private struct CachedService: Decodable {
        let usage: ServiceUsage?

        private enum CodingKeys: String, CodingKey { case service }

        init(from decoder: any Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            let identifier = try values.decode(String.self, forKey: .service)
            usage = UsageService(rawValue: identifier) == nil ? nil : try ServiceUsage(from: decoder)
        }
    }

    public func usage(for service: UsageService) -> ServiceUsage {
        services.first { $0.service == service } ?? ServiceUsage(service: service, state: .disabled)
    }

    public func validityBoundaries(after date: Date) -> [Date] {
        let dates = services.flatMap { usage in
            [usage.updatedAt?.addingTimeInterval(Self.maximumAge)] + usage.windows.map(\.resetsAt)
        }.compactMap { $0 }.filter { $0 > date && $0 <= date.addingTimeInterval(Self.maximumAge) }
        return Set(dates).sorted()
    }
}
