import CryptoKit
import Darwin
import Foundation

public struct AntigravityStatuslineCache: Codable, Equatable, Sendable {
    public let usage: ServiceUsage
    public let quotaMarkers: [String]
    public let quotaHistoryExpiresAt: Date
    public let version: Int
}

public enum AntigravityStatuslineFile {
    public static func url() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Caches/Usage Rings/gemini-statusline-v1.json")
    }

    public static func read(from location: URL = url()) -> AntigravityStatuslineCache? {
        guard let size = try? location.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              size <= 65_536, let data = try? Data(contentsOf: location),
              let cache = try? JSONDecoder().decode(AntigravityStatuslineCache.self, from: data),
              cache.version == 1, valid(cache.usage),
              cache.quotaHistoryExpiresAt.timeIntervalSinceReferenceDate.isFinite,
              cache.usage.windows.allSatisfy({ $0.resetsAt.map { $0 <= cache.quotaHistoryExpiresAt } == true }),
              !cache.quotaMarkers.isEmpty, cache.quotaMarkers.count <= 256,
              Set(cache.quotaMarkers).count == cache.quotaMarkers.count,
              cache.quotaMarkers.allSatisfy({ marker in
                  marker.utf8.count == 64 && marker.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
              }) else { return nil }
        return cache
    }

    @discardableResult
    public static func write(_ usage: ServiceUsage, to location: URL = url()) throws -> AntigravityStatuslineCache {
        guard valid(usage), let observedAt = usage.updatedAt,
              let quotaReset = usage.windows.compactMap(\.resetsAt).max() else { throw UsageReadError.invalidResponse }
        let folder = location.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        let descriptor = open(location.path + ".lock", O_CREAT | O_RDWR | O_NOFOLLOW, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw UsageReadError.requestFailed }
        defer { close(descriptor) }
        guard flock(descriptor, LOCK_EX) == 0 else { throw UsageReadError.requestFailed }
        defer { flock(descriptor, LOCK_UN) }
        let previous = read(from: location)
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let normalized = usage.windows.sorted { $0.id < $1.id }
        let marker = SHA256.hash(data: try encoder.encode(normalized)).map { String(format: "%02x", $0) }.joined()
        // Delayed writers can evict the current marker, so compare the current quota independently.
        if let previous, previous.usage.windows.sorted(by: { $0.id < $1.id }) == normalized
            || previous.quotaMarkers.contains(marker) {
            return previous
        }
        // The payload has no source timestamp; replay detection is limited to recent quotas.
        let markers = Array(((previous?.quotaMarkers ?? []) + [marker]).suffix(256))
        // Retain the v1 reset horizon for installed readers, without gating new observations.
        let historyExpiresAt = max(previous?.quotaHistoryExpiresAt ?? quotaReset, quotaReset)
        var current = usage
        if let previous, let previousTime = previous.usage.updatedAt, observedAt < previousTime {
            current = previous.usage
        }
        let cache = AntigravityStatuslineCache(usage: current, quotaMarkers: markers,
                                             quotaHistoryExpiresAt: historyExpiresAt, version: 1)
        if cache == previous { return cache }
        let data = try encoder.encode(cache)
        guard data.count <= 65_536 else { throw UsageReadError.requestFailed }
        try data.write(to: location, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: location.path)
        return cache
    }

    private static func valid(_ usage: ServiceUsage) -> Bool {
        guard usage.service == .gemini, usage.state == .ready, usage.preferredPeriod == nil,
              usage.updatedAt?.timeIntervalSinceReferenceDate.isFinite == true,
              !usage.windows.isEmpty, usage.windows.count <= 2,
              Set(usage.windows.map(\.id)).count == usage.windows.count else { return false }
        return usage.windows.allSatisfy { window in
            let period: UsagePeriod
            switch window.id {
            case "gemini-5h": period = .fiveHours
            case "gemini-weekly": period = .week
            default: return false
            }
            return window.title == period.title && window.period == period
                && window.usedPercent.isFinite && (0...100).contains(window.usedPercent)
                && window.resetsAt?.timeIntervalSinceReferenceDate.isFinite == true
        }
    }
}
