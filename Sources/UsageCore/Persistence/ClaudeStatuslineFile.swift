import Darwin
import Foundation

public struct ClaudeStatuslineCache: Codable, Equatable, Sendable {
    public var usage: ServiceUsage?
    public var responseMarkers: [String]
    public var sessionProgress: [String: SessionProgress]?
    public let version: Int

    public struct SessionProgress: Codable, Equatable, Sendable {
        public let apiDurationMilliseconds: Double
        public let expiresAt: Date
    }
}

public enum ClaudeStatuslineFile {
    public static func url() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Caches/Usage Rings/claude-statusline-v1.json")
    }

    public static func read(from location: URL = url()) -> ClaudeStatuslineCache? {
        guard let size = try? location.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              size <= 65_536, let data = try? Data(contentsOf: location),
              let cache = try? JSONDecoder().decode(ClaudeStatuslineCache.self, from: data),
              cache.version == 1, cache.responseMarkers.count <= 256,
              (cache.sessionProgress?.count ?? 0) <= 256,
              cache.sessionProgress?.allSatisfy({ entry in
                  entry.key.utf8.count == 64 && entry.key.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
                      && entry.value.apiDurationMilliseconds.isFinite && entry.value.apiDurationMilliseconds >= 0
                      && entry.value.expiresAt.timeIntervalSinceReferenceDate.isFinite
              }) ?? true else { return nil }
        if let usage = cache.usage {
            guard usage.service == .claude, usage.state == .ready,
                  usage.updatedAt?.timeIntervalSinceReferenceDate.isFinite == true,
                  !usage.windows.isEmpty, usage.windows.count <= 2,
                  Set(usage.windows.map(\.id)).count == usage.windows.count,
                  usage.windows.allSatisfy({
                      ["five_hour", "seven_day"].contains($0.id) && $0.usedPercent.isFinite &&
                      (0...100).contains($0.usedPercent) && $0.resetsAt?.timeIntervalSinceReferenceDate.isFinite == true
                  }) else { return nil }
        } else if cache.sessionProgress?.isEmpty != false {
            return nil
        }
        return cache
    }

    @discardableResult
    public static func write(_ input: ClaudeStatuslineInput, to location: URL = url()) throws -> ClaudeStatuslineCache {
        let folder = location.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        let descriptor = open(location.path + ".lock", O_CREAT | O_RDWR | O_NOFOLLOW, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw UsageReadError.requestFailed }
        defer { close(descriptor) }
        guard flock(descriptor, LOCK_EX) == 0 else { throw UsageReadError.requestFailed }
        defer { flock(descriptor, LOCK_UN) }
        let previous = read(from: location)
        let observedAt = input.observedAt
        guard observedAt.timeIntervalSinceReferenceDate.isFinite else { throw UsageReadError.invalidResponse }
        let reset = input.usage?.windows.compactMap(\.resetsAt).max() ?? observedAt.addingTimeInterval(24 * 60 * 60)
        var progress = (previous?.sessionProgress ?? [:]).filter { $0.value.expiresAt > observedAt }
        let previousProgress = progress[input.sessionMarker]
        if previousProgress == nil, progress.count == 256, let previous { return previous }
        progress[input.sessionMarker] = ClaudeStatuslineCache.SessionProgress(
            apiDurationMilliseconds: max(previousProgress?.apiDurationMilliseconds ?? 0, input.apiDurationMilliseconds),
            expiresAt: max(previousProgress?.expiresAt ?? reset, reset)
        )
        var markers = previous?.responseMarkers ?? []
        let wasSeen = markers.contains(input.responseMarker)
        if input.usage != nil, !wasSeen { markers = Array((markers + [input.responseMarker]).suffix(256)) }
        var usage = input.usage ?? previous?.usage
        let advanced = previousProgress.map { input.apiDurationMilliseconds > $0.apiDurationMilliseconds } ?? false
        // An unseen session may be an idle v1 session; establish progress before renewing freshness.
        if let previousUsage = previous?.usage, wasSeen || !advanced { usage = previousUsage }
        // Concurrent status-line processes can acquire the lock out of reading order.
        if let previous, let updatedAt = usage?.updatedAt, let previousUpdatedAt = previous.usage?.updatedAt,
           updatedAt < previousUpdatedAt {
            usage = previous.usage
        }
        let cache = ClaudeStatuslineCache(usage: usage, responseMarkers: markers, sessionProgress: progress, version: 1)
        if cache == previous { return cache }
        let data = try JSONEncoder().encode(cache)
        guard data.count <= 65_536 else { throw UsageReadError.requestFailed }
        try data.write(to: location, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: location.path)
        return cache
    }
}
