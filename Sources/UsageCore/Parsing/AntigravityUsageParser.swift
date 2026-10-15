import Foundation

public enum AntigravityUsageParser {
    public static func parse(_ data: Data, now: Date = Date()) throws -> ServiceUsage {
        let response = try JSONDecoder().decode(Response.self, from: data)
        guard response.status == "SUCCESS", response.num_turns == 0,
              response.usage.isEmpty, ["usage", "/usage"].contains(response.command.name) else {
            throw UsageReadError.invalidResponse
        }
        let groups = response.command.data.groups.filter { $0.name == "Gemini Models" }
        guard groups.count == 1 else { throw UsageReadError.invalidResponse }
        var windows: [UsageWindow] = []
        for bucket in groups[0].buckets {
            let period: UsagePeriod
            switch (bucket.id, bucket.window) {
            case ("gemini-5h", "5h"): period = .fiveHours
            case ("gemini-weekly", "weekly"): period = .week
            default: continue
            }
            // Disabled quota buckets omit their fraction; they are never a full allowance.
            guard let fraction = bucket.remaining_fraction else { continue }
            guard fraction.isFinite, (0...1).contains(fraction),
                  let timestamp = bucket.reset_time, let reset = parseDate(timestamp),
                  !windows.contains(where: { $0.id == bucket.id }) else { throw UsageReadError.invalidResponse }
            windows.append(UsageWindow(id: bucket.id, title: period.title, usedPercent: (1 - fraction) * 100,
                                       resetsAt: reset, period: period))
        }
        guard !windows.isEmpty else { throw UsageReadError.invalidResponse }
        windows.sort { $0.id < $1.id }
        return ServiceUsage(service: .gemini, state: .ready, windows: windows, updatedAt: now)
    }

    private static func parseDate(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }
}

private struct Response: Decodable {
    let status: String
    let num_turns: Int
    let usage: TokenUsage
    let command: Command
    struct TokenUsage: Decodable {
        let input_tokens, output_tokens, thinking_tokens, cache_read_tokens, total_tokens: Int
        var isEmpty: Bool {
            [input_tokens, output_tokens, thinking_tokens, cache_read_tokens, total_tokens].allSatisfy { $0 == 0 }
        }
    }
    struct Command: Decodable {
        let name: String
        let data: Quota
    }
    struct Quota: Decodable { let groups: [Group] }
    struct Group: Decodable {
        let name: String
        let buckets: [Bucket]
    }
    struct Bucket: Decodable {
        let id: String
        let window: String
        let remaining_fraction: Double?
        let reset_time: String?
    }
}
