import CryptoKit
import Foundation

public struct ClaudeStatuslineInput: Sendable {
    public let usage: ServiceUsage
    public let responseMarker: String
    public let sessionMarker: String
    public let apiDurationMilliseconds: Double
}

public enum ClaudeStatusline {
    public static func parse(_ data: Data, now: Date = Date()) throws -> ClaudeStatuslineInput? {
        let input = try JSONDecoder().decode(Input.self, from: data)
        guard let limits = input.rate_limits, let session = input.session_id, !session.isEmpty,
              let duration = input.cost?.total_api_duration_ms, duration.isFinite, duration > 0 else { return nil }
        var windows: [UsageWindow] = []
        for (id, period, window) in [("five_hour", UsagePeriod.fiveHours, limits.five_hour),
                                     ("seven_day", UsagePeriod.week, limits.seven_day)] {
            guard let window else { continue }
            guard window.used_percentage.isFinite, (0...100).contains(window.used_percentage),
                  window.resets_at.isFinite, window.resets_at > 0 else { throw UsageReadError.invalidResponse }
            let reset = Date(timeIntervalSince1970: window.resets_at)
            guard reset > now else { continue }
            windows.append(UsageWindow(id: id, title: period.title, usedPercent: window.used_percentage,
                                       resetsAt: reset, period: period))
        }
        guard !windows.isEmpty else { return nil }
        // Status lines also run for UI events. Only new API activity renews freshness.
        // Hash the session marker so no session ID or workspace metadata is stored.
        return ClaudeStatuslineInput(
            usage: ServiceUsage(service: .claude, state: .ready, windows: windows, updatedAt: now),
            responseMarker: marker("\(session):\(duration)"),
            sessionMarker: marker(session),
            apiDurationMilliseconds: duration
        )
    }

    private static func marker(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private struct Input: Decodable {
        let session_id: String?
        let cost: Cost?
        let rate_limits: Limits?
    }
    private struct Cost: Decodable { let total_api_duration_ms: Double? }
    private struct Limits: Decodable { let five_hour: Window?; let seven_day: Window? }
    private struct Window: Decodable { let used_percentage: Double; let resets_at: Double }
}
