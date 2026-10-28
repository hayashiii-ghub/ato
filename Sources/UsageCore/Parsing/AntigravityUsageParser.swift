import Foundation

public enum AntigravityUsageParser {
    public struct Observation: Sendable {
        public let usage: ServiceUsage
        public let disabledWindowIDs: Set<String>
    }

    public static func parse(_ data: Data, now: Date = Date()) throws -> ServiceUsage {
        try parseObservation(data, now: now).usage
    }

    public static func parseObservation(_ data: Data, now: Date = Date()) throws -> Observation {
        let input = try JSONDecoder().decode(Input.self, from: data)
        guard input.product == "antigravity" else { throw UsageReadError.invalidResponse }
        var windows: [UsageWindow] = []
        var disabledWindowIDs: Set<String> = []
        for (id, period, bucket) in [("gemini-5h", UsagePeriod.fiveHours, input.quota.fiveHours),
                                     ("gemini-weekly", UsagePeriod.week, input.quota.week)] {
            guard let bucket else { continue }
            if bucket.disabled == true {
                disabledWindowIDs.insert(id)
                continue
            }
            guard let fraction = bucket.remaining_fraction else { continue }
            guard fraction.isFinite, (0...1).contains(fraction),
                  let timestamp = bucket.reset_time, let reset = parseDate(timestamp) else {
                throw UsageReadError.invalidResponse
            }
            windows.append(UsageWindow(id: id, title: period.title, usedPercent: (1 - fraction) * 100,
                                       resetsAt: reset, period: period))
        }
        guard !windows.isEmpty || !disabledWindowIDs.isEmpty else { throw UsageReadError.invalidResponse }
        let usage = ServiceUsage(service: .gemini, state: windows.isEmpty ? .unavailable : .ready,
                                 windows: windows, updatedAt: now)
        return Observation(usage: usage, disabledWindowIDs: disabledWindowIDs)
    }

    private static func parseDate(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }

    private struct Input: Decodable {
        let product: String
        let quota: Quota
    }

    private struct Quota: Decodable {
        let fiveHours: Bucket?
        let week: Bucket?

        enum CodingKeys: String, CodingKey {
            case fiveHours = "gemini-5h"
            case week = "gemini-weekly"
        }
    }

    private struct Bucket: Decodable {
        let disabled: Bool?
        let remaining_fraction: Double?
        let reset_time: String?

        enum CodingKeys: String, CodingKey { case disabled, remaining_fraction, reset_time }

        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            disabled = try values.decodeIfPresent(Bool.self, forKey: .disabled)
            // Disabled buckets may still carry obsolete or malformed allowance fields.
            if disabled == true {
                remaining_fraction = nil
                reset_time = nil
            } else {
                remaining_fraction = try values.decodeIfPresent(Double.self, forKey: .remaining_fraction)
                reset_time = try values.decodeIfPresent(String.self, forKey: .reset_time)
            }
        }
    }
}
