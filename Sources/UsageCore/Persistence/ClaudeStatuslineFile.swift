import Darwin
import Foundation

public struct ClaudeStatuslineCache: Codable, Equatable, Sendable {
    public var usage: ServiceUsage
    public var responseMarkers: [String]
    public let version: Int
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
              cache.version == 1, cache.usage.service == .claude, cache.usage.state == .ready,
              cache.usage.updatedAt != nil, !cache.usage.windows.isEmpty, cache.usage.windows.count <= 2,
              Set(cache.usage.windows.map(\.id)).count == cache.usage.windows.count,
              cache.usage.windows.allSatisfy({
                  ["five_hour", "seven_day"].contains($0.id) && $0.usedPercent.isFinite &&
                  (0...100).contains($0.usedPercent) && $0.resetsAt != nil
              }), cache.responseMarkers.count <= 256 else { return nil }
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
        if let previous, previous.responseMarkers.contains(input.responseMarker) { return previous }
        let markers = Array(((previous?.responseMarkers ?? []) + [input.responseMarker]).suffix(256))
        var usage = input.usage
        // Concurrent status-line processes can acquire the lock out of reading order.
        if let previous, let updatedAt = usage.updatedAt, let previousUpdatedAt = previous.usage.updatedAt,
           updatedAt < previousUpdatedAt {
            usage = previous.usage
        }
        let cache = ClaudeStatuslineCache(usage: usage, responseMarkers: markers, version: 1)
        try JSONEncoder().encode(cache).write(to: location, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: location.path)
        return cache
    }
}
