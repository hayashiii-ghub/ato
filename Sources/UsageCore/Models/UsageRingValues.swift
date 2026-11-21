import Foundation

public enum UsageRingValues: Equatable {
    public struct Reading: Equatable {
        public let title: String
        public let remaining: Double?

        public init(title: String, remaining: Double?) {
            self.title = title
            self.remaining = remaining
        }
    }

    case split(top: Reading, bottom: Reading)
    case single(Reading)
    case unknown

    public var hasReading: Bool {
        switch self {
        case let .split(top, bottom): return top.remaining != nil || bottom.remaining != nil
        case let .single(reading): return reading.remaining != nil
        case .unknown: return false
        }
    }
}

extension ServiceUsage {
    public func ringValues(at date: Date) -> UsageRingValues {
        let main = windows.filter(isMainWindow)
        let fiveHours = main.filter { period(for: $0) == .fiveHours }
            .min { $0.remainingPercent < $1.remainingPercent }
        let week = main.filter { period(for: $0) == .week }
            .min { $0.remainingPercent < $1.remainingPercent }
        // Expiring readings should clear the numbers without changing the last known layout.
        let displayed = [fiveHours, week].compactMap { $0 } + main.filter { period(for: $0) == nil }
        let readings = displayed.prefix(2).map { window in
            let isFiveHours = period(for: window) == .fiveHours
            let effectiveWindow = isFiveHours ? exhaustedWeeklyWindow ?? window : window
            return UsageRingValues.Reading(
                title: isFiveHours ? "5h" : window.title,
                remaining: remainingPercent(for: effectiveWindow, at: date)
            )
        }
        guard let first = readings.first else { return .unknown }
        if readings.count == 1 { return .single(first) }
        return .split(top: first, bottom: readings[1])
    }

    public func isFiveHourArcBlocked(at date: Date) -> Bool {
        guard let blocker = exhaustedWeeklyWindow, remainingPercent(for: blocker, at: date) == 0 else { return false }
        return windows.contains { isMainWindow($0) && period(for: $0) == .fiveHours }
    }
}
