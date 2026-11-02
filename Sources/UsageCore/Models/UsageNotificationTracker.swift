import CryptoKit
import Foundation

public struct UsageNotificationTracker: Codable, Sendable {
    public struct Notice: Equatable, Sendable {
        public let service: UsageService
        public let windowID: String
        public let title: String
        public let remainingPercent: Double
        public let thresholdPercent: Int
        public let observedAt: Date
        public let resetsAt: Date?
    }

    private struct Boundary: Codable, Sendable {
        let resetsAt: Date?
        let thresholdPercent: Int
    }

    private struct WindowState: Codable, Sendable {
        let observedAt: Date
        let remainingPercent: Double
        let resetsAt: Date?
        let boundaries: [Boundary]
    }

    private static let maximumWindows = 64
    private static let maximumBoundaries = 8
    private var windows: [String: WindowState] = [:]

    public init() {}

    private enum CodingKeys: String, CodingKey { case windows }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let decoded = try values.decode([String: WindowState].self, forKey: .windows)
        for (key, state) in decoded.sorted(by: { $0.value.observedAt > $1.value.observedAt }) {
            guard windows.count < Self.maximumWindows, key.count == 64,
                  key.allSatisfy({ $0.isHexDigit }), Self.isFinite(state.observedAt),
                  state.remainingPercent.isFinite, (0...100).contains(state.remainingPercent),
                  state.resetsAt.map(Self.isFinite) ?? true else { continue }
            let boundaries = state.boundaries.filter {
                [10, 20].contains($0.thresholdPercent) && ($0.resetsAt.map(Self.isFinite) ?? true)
            }
            windows[key] = WindowState(observedAt: state.observedAt,
                                       remainingPercent: state.remainingPercent, resetsAt: state.resetsAt,
                                       boundaries: Array(boundaries.suffix(Self.maximumBoundaries)))
        }
    }

    public mutating func notices(for report: UsageStatusReport) -> [Notice] {
        guard Self.isFinite(report.generatedAt) else { return [] }
        var notices: [Notice] = []
        for service in report.services {
            guard let provider = service.provider == "grok" ? UsageService.grokBot : UsageService(rawValue: service.provider),
                  let observedAt = service.observedAt, Self.isFinite(observedAt) else { continue }
            for window in service.windows where window.isMain && window.state == "ready" {
                guard let remaining = window.remainingPercent, remaining.isFinite,
                      (0...100).contains(remaining),
                      window.resetsAt.map(Self.isFinite) ?? true else { continue }
                let key = Self.key(service: provider, windowID: window.id)
                let previous = windows[key]
                if let previous {
                    guard observedAt >= previous.observedAt else { continue }
                    guard observedAt > previous.observedAt
                        || (remaining == previous.remainingPercent && window.resetsAt == previous.resetsAt) else { continue }
                }
                let boundaries = previous?.boundaries ?? []
                if let threshold = Self.threshold(for: remaining) {
                    let existing = boundaries.first { $0.resetsAt == window.resetsAt }?.thresholdPercent
                    if existing == nil || threshold < existing! {
                        notices.append(Notice(service: provider, windowID: window.id, title: window.title,
                                              remainingPercent: remaining, thresholdPercent: threshold,
                                              observedAt: observedAt, resetsAt: window.resetsAt))
                    }
                }
                // Recovery and missing readings must not re-arm a stage already shown for this period.
                if previous == nil && windows.count >= Self.maximumWindows,
                   let oldest = windows.min(by: { lhs, rhs in
                       lhs.value.observedAt == rhs.value.observedAt
                           ? lhs.key < rhs.key : lhs.value.observedAt < rhs.value.observedAt
                   })?.key { windows.removeValue(forKey: oldest) }
                windows[key] = WindowState(observedAt: observedAt,
                                           remainingPercent: remaining, resetsAt: window.resetsAt,
                                           boundaries: Array(boundaries.suffix(Self.maximumBoundaries)))
            }
        }
        return notices
    }

    public mutating func markDelivered(_ notice: Notice) {
        let key = Self.key(service: notice.service, windowID: notice.windowID)
        guard let previous = windows[key], Self.isFinite(notice.observedAt),
              notice.observedAt <= previous.observedAt,
              notice.remainingPercent.isFinite, (0...100).contains(notice.remainingPercent),
              Self.threshold(for: notice.remainingPercent) == notice.thresholdPercent,
              notice.resetsAt.map(Self.isFinite) ?? true else { return }
        var boundaries = previous.boundaries
        let existing = boundaries.first { $0.resetsAt == notice.resetsAt }?.thresholdPercent
        boundaries.removeAll { $0.resetsAt == notice.resetsAt }
        boundaries.append(Boundary(resetsAt: notice.resetsAt,
                                   thresholdPercent: min(existing ?? notice.thresholdPercent, notice.thresholdPercent)))
        windows[key] = WindowState(observedAt: previous.observedAt,
                                   remainingPercent: previous.remainingPercent, resetsAt: previous.resetsAt,
                                   boundaries: Array(boundaries.suffix(Self.maximumBoundaries)))
    }

    private static func threshold(for remaining: Double) -> Int? {
        remaining <= 10 ? 10 : remaining <= 20 ? 20 : nil
    }

    private static func isFinite(_ date: Date) -> Bool {
        date.timeIntervalSinceReferenceDate.isFinite
    }

    private static func key(service: UsageService, windowID: String) -> String {
        SHA256.hash(data: Data("\(service.rawValue):\(windowID)".utf8))
            .map { String(format: "%02x", $0) }.joined()
    }
}
