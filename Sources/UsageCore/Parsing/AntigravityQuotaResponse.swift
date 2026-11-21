import Foundation

public enum AntigravityQuotaResponse {
    public static func summary(_ data: Data, now: Date) throws -> [UsageWindow] {
        let result = try JSONDecoder().decode(Summary.self, from: data)
        let groups = result.groups?.contains { !($0.buckets ?? []).isEmpty } == true
            ? result.groups ?? [] : [Group(displayName: nil, buckets: result.buckets)]
        var windows: [UsageWindow] = []
        var seen = Set<String>()
        for group in groups {
            for bucket in group.buckets ?? [] {
                guard bucket.disabled != true, !bucket.bucketId.isEmpty else { continue }
                let period: UsagePeriod? = bucket.window == "5h" ? .fiveHours : bucket.window == "weekly" ? .week : nil
                let title = "\(family(for: bucket.bucketId, group: group.displayName)) · \(period?.title ?? bucket.displayName ?? "Quota")"
                let reset = bucket.resetTime.flatMap(UsageResponseParser.parseDate)
                let duration: TimeInterval? = period.map { $0 == .fiveHours ? 18_000 : 604_800 }
                // At full allowance an untouched bucket can report a reset that moves with each request.
                let movingReset = bucket.remainingFraction == 1 && bucket.description == nil
                    && reset.map { date in duration.map { abs(date.timeIntervalSince(now) - $0) <= 60 } ?? false } == true
                if let window = window(id: bucket.bucketId, title: title, fraction: bucket.remainingFraction,
                                       reset: movingReset ? nil : reset, period: period),
                   seen.insert(window.id).inserted {
                    windows.append(window)
                }
            }
        }
        return windows
    }

    public static func models(_ data: Data) throws -> [UsageWindow] {
        let response = try JSONDecoder().decode(Models.self, from: data)
        var windows: [String: UsageWindow] = [:]
        for (modelID, model) in response.models {
            let family: String
            if model.modelProvider == "MODEL_PROVIDER_GOOGLE" || modelID.hasPrefix("gemini-") {
                family = "Gemini"
            } else if model.modelProvider == "MODEL_PROVIDER_ANTHROPIC" || modelID.hasPrefix("claude-") {
                family = "Claude"
            } else if model.modelProvider == "MODEL_PROVIDER_OPENAI" || modelID.hasPrefix("gpt-") {
                family = "GPT"
            } else {
                continue
            }
            for (suffix, quota) in [("quota", model.quotaInfo), ("weekly", model.weeklyQuotaInfo)] {
                guard let quota else { continue }
                let id = "\(family.lowercased())-\(suffix)"
                let period: UsagePeriod? = suffix == "weekly" ? .week : nil
                if let window = window(id: id, title: "\(family) · \(period?.title ?? "Reported quota")",
                                       fraction: quota.remainingFraction, reset: quota.resetTime.flatMap(UsageResponseParser.parseDate),
                                       period: period) {
                    if let previous = windows[id] {
                        let earlierReset = (window.resetsAt ?? .distantFuture) < (previous.resetsAt ?? .distantFuture)
                        guard window.usedPercent > previous.usedPercent
                            || (window.usedPercent == previous.usedPercent && earlierReset) else { continue }
                    }
                    windows[id] = window
                }
            }
        }
        return windows.values.sorted { $0.id < $1.id }
    }

    private static func family(for id: String, group: String?) -> String {
        if id.hasPrefix("gemini-argon-") { return group ?? "Gemini Argon" }
        if id.hasPrefix("gemini-carbon-") { return group ?? "Gemini Carbon" }
        if id.hasPrefix("gemini-") { return "Gemini" }
        if id.hasPrefix("3p-") { return "Claude & GPT (shared)" }
        return group ?? id
    }

    private static func window(id: String, title: String, fraction: Double?, reset: Date?,
                               period: UsagePeriod?) -> UsageWindow? {
        guard let fraction, fraction.isFinite, (0...1).contains(fraction) else { return nil }
        return UsageWindow(id: id, title: title, usedPercent: (1 - fraction) * 100, resetsAt: reset, period: period)
    }

    private struct Summary: Decodable {
        let groups: [Group]?
        let buckets: [Bucket]?
    }

    private struct Group: Decodable {
        let displayName: String?
        let buckets: [Bucket]?
    }

    private struct Bucket: Decodable {
        let bucketId: String
        let window: String?
        let displayName: String?
        let description: String?
        let disabled: Bool?
        let remainingFraction: Double?
        let resetTime: String?
    }

    private struct Models: Decodable {
        let models: [String: Model]
    }

    private struct Model: Decodable {
        let modelProvider: String?
        let quotaInfo: Quota?
        let weeklyQuotaInfo: Quota?
    }

    private struct Quota: Decodable {
        let remainingFraction: Double?
        let resetTime: String?
    }
}
