import Foundation

public struct UsageStatusReport: Encodable, Sendable {
    public let schemaVersion = 1
    public let generatedAt: Date
    public let pollIntervalSeconds = 300
    public let maxAgeSeconds = Int(UsageSnapshot.maximumAge)
    public let thresholdPercent: Double
    public let services: [ServiceStatus]
    public let alerts: [Alert]

    public init(snapshot: UsageSnapshot, provider: UsageService? = nil, now: Date = Date(), thresholdPercent: Double = 20) {
        generatedAt = now
        self.thresholdPercent = thresholdPercent
        let providers = provider.map { [$0] } ?? UsageService.allCases
        services = providers.map { ServiceStatus(usage: snapshot.usage(for: $0), now: now) }
        alerts = services.flatMap { service in
            service.windows.compactMap { window in
                guard window.isMain, window.state == "ready", let remaining = window.remainingPercent,
                      remaining < thresholdPercent else { return nil }
                return Alert(provider: service.provider, window: window, remainingPercent: remaining,
                             observedAt: service.observedAt, now: now)
            }
        }
    }

    public struct ServiceStatus: Encodable, Sendable {
        public let provider: String
        public let state: String
        public let observedAt: Date?
        public let ageSeconds: Double?
        public let limitingRemainingPercent: Double?
        public let windows: [WindowStatus]

        fileprivate init(usage: ServiceUsage, now: Date) {
            provider = usage.service == .grokBot ? "grok" : usage.service.rawValue
            let observed = UsageStatusReport.finiteDate(usage.updatedAt)
            observedAt = observed
            ageSeconds = observed.flatMap { observed in
                let age = now.timeIntervalSince(observed)
                return age.isFinite && age >= -60 ? max(0, age) : nil
            }
            let readingState: String
            if usage.state != .ready || ageSeconds == nil {
                readingState = "unavailable"
            } else if let ageSeconds, ageSeconds >= UsageSnapshot.maximumAge {
                readingState = "stale"
            } else {
                readingState = "ready"
            }
            windows = usage.windows.map {
                WindowStatus(window: $0, usage: usage, readingState: readingState, observedAt: observed, now: now)
            }
            let main = windows.filter(\.isMain)
            if !main.isEmpty, main.allSatisfy({ $0.state == "ready" }) {
                limitingRemainingPercent = main.compactMap(\.remainingPercent).min()
            } else {
                limitingRemainingPercent = nil
            }
            if usage.state != .ready {
                state = usage.state.rawValue
            } else if !main.isEmpty, windows.allSatisfy({ $0.state == "ready" }) {
                state = "ready"
            } else if windows.contains(where: { $0.state == "ready" }) {
                state = "partial"
            } else if !windows.isEmpty, windows.allSatisfy({ $0.state == "stale" }) {
                state = "stale"
            } else {
                state = "unavailable"
            }
        }

        private enum CodingKeys: String, CodingKey {
            case provider, state, observedAt, ageSeconds, limitingRemainingPercent, windows
        }

        public func encode(to encoder: Encoder) throws {
            var values = encoder.container(keyedBy: CodingKeys.self)
            try values.encode(provider, forKey: .provider)
            try values.encode(state, forKey: .state)
            try values.encode(observedAt, forKey: .observedAt)
            try values.encode(ageSeconds, forKey: .ageSeconds)
            try values.encode(limitingRemainingPercent, forKey: .limitingRemainingPercent)
            try values.encode(windows, forKey: .windows)
        }
    }

    public struct WindowStatus: Encodable, Sendable {
        public let id: String
        public let title: String
        public let period: UsagePeriod?
        public let isMain: Bool
        public let state: String
        public let remainingPercent: Double?
        public let resetsAt: Date?
        public let validUntil: Date?

        fileprivate init(window: UsageWindow, usage: ServiceUsage, readingState: String, observedAt: Date?, now: Date) {
            id = window.id
            title = window.title
            period = usage.period(for: window)
            switch usage.service {
            case .cursor: isMain = window.id == "total"
            case .claude: isMain = window.id == "five_hour" || window.id == "seven_day"
            default: isMain = true
            }
            resetsAt = UsageStatusReport.finiteDate(window.resetsAt)
            guard readingState != "unavailable", let observedAt,
                  window.usedPercent.isFinite, window.usedPercent >= 0,
                  window.resetsAt == nil || resetsAt != nil else {
                state = "unavailable"
                remainingPercent = nil
                validUntil = nil
                return
            }
            let expiresAt = observedAt.addingTimeInterval(UsageSnapshot.maximumAge)
            validUntil = resetsAt.map { min($0, expiresAt) } ?? expiresAt
            if readingState == "stale" || resetsAt.map({ $0 <= now }) == true {
                state = "stale"
                remainingPercent = nil
            } else {
                state = "ready"
                remainingPercent = window.remainingPercent
            }
        }

        private enum CodingKeys: String, CodingKey {
            case id, title, period, isMain, state, remainingPercent, resetsAt, validUntil
        }

        public func encode(to encoder: Encoder) throws {
            var values = encoder.container(keyedBy: CodingKeys.self)
            try values.encode(id, forKey: .id)
            try values.encode(title, forKey: .title)
            try values.encode(period, forKey: .period)
            try values.encode(isMain, forKey: .isMain)
            try values.encode(state, forKey: .state)
            try values.encode(remainingPercent, forKey: .remainingPercent)
            try values.encode(resetsAt, forKey: .resetsAt)
            try values.encode(validUntil, forKey: .validUntil)
        }
    }

    public struct Alert: Encodable, Sendable {
        public let provider: String
        public let windowId: String
        public let title: String
        public let remainingPercent: Double
        public let observedAt: Date?
        public let resetsAt: Date?
        public let secondsUntilReset: Double?

        fileprivate init(provider: String, window: WindowStatus, remainingPercent: Double, observedAt: Date?, now: Date) {
            self.provider = provider
            windowId = window.id
            title = window.title
            self.remainingPercent = remainingPercent
            self.observedAt = observedAt
            resetsAt = window.resetsAt
            secondsUntilReset = window.resetsAt.map { $0.timeIntervalSince(now) }
        }

        private enum CodingKeys: String, CodingKey {
            case provider, windowId, title, remainingPercent, observedAt, resetsAt, secondsUntilReset
        }

        public func encode(to encoder: Encoder) throws {
            var values = encoder.container(keyedBy: CodingKeys.self)
            try values.encode(provider, forKey: .provider)
            try values.encode(windowId, forKey: .windowId)
            try values.encode(title, forKey: .title)
            try values.encode(remainingPercent, forKey: .remainingPercent)
            try values.encode(observedAt, forKey: .observedAt)
            try values.encode(resetsAt, forKey: .resetsAt)
            try values.encode(secondsUntilReset, forKey: .secondsUntilReset)
        }
    }

    private static func finiteDate(_ date: Date?) -> Date? {
        guard let date, date.timeIntervalSinceReferenceDate.isFinite else { return nil }
        return date
    }
}
