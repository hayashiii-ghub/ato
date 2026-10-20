import Foundation

public enum AntigravityUsageParser {
    public static func parse(_ data: Data, now: Date = Date()) throws -> ServiceUsage {
        let input = try JSONDecoder().decode(Input.self, from: data)
        guard input.product == "antigravity" else { throw UsageReadError.invalidResponse }
        var windows: [UsageWindow] = []
        for (id, period, bucket) in [("gemini-5h", UsagePeriod.fiveHours, input.quota.fiveHours),
                                     ("gemini-weekly", UsagePeriod.week, input.quota.week)] {
            guard let bucket, let fraction = bucket.remaining_fraction else { continue }
            guard fraction.isFinite, (0...1).contains(fraction),
                  let timestamp = bucket.reset_time, let reset = parseDate(timestamp) else {
                throw UsageReadError.invalidResponse
            }
            windows.append(UsageWindow(id: id, title: period.title, usedPercent: (1 - fraction) * 100,
                                       resetsAt: reset, period: period))
        }
        guard !windows.isEmpty else { throw UsageReadError.invalidResponse }
        return ServiceUsage(service: .gemini, state: .ready, windows: windows, updatedAt: now)
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
        let remaining_fraction: Double?
        let reset_time: String?
    }
}
