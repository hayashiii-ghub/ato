import UsageCore
import Foundation

enum WidgetSnapshotReader {
    static func load() async -> UsageSnapshot {
        do {
            let snapshot = try await UsageSnapshotBridge.load(requestTimeout: 3, resourceTimeout: 4)
            try? UsageSnapshotFile.write(snapshot)
            return snapshot
        } catch { return UsageSnapshotFile.read() }
    }
}
