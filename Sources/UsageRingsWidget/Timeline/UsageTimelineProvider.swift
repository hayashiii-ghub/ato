import UsageCore
import WidgetKit

struct UsageEntry: TimelineEntry {
    let date: Date
    let snapshot: UsageSnapshot
}

struct UsageTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> UsageEntry { sample() }

    func getSnapshot(in context: Context, completion: @escaping (UsageEntry) -> Void) {
        if context.isPreview { completion(sample()); return }
        Task {
            let snapshot = await WidgetSnapshotReader.load()
            completion(UsageEntry(date: Date(), snapshot: snapshot))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<UsageEntry>) -> Void) {
        Task { completion(timeline(snapshot: await WidgetSnapshotReader.load())) }
    }

    private func timeline(snapshot: UsageSnapshot) -> Timeline<UsageEntry> {
        let now = Date()
        let refresh = now.addingTimeInterval(15 * 60)
        // Include expiry even beyond the requested reload, which macOS may defer.
        let dates = Set([now, refresh] + snapshot.validityBoundaries(after: now)).sorted()
        return Timeline(entries: dates.map { UsageEntry(date: $0, snapshot: snapshot) }, policy: .after(refresh))
    }

    private func sample() -> UsageEntry {
        let now = Date()
        let services = [
            ServiceUsage(service: .codex, state: .ready,
                         windows: [UsageWindow(id: "week", title: "Week", usedPercent: 24, resetsAt: nil)], updatedAt: now),
            ServiceUsage(service: .claude, state: .ready,
                         windows: [UsageWindow(id: "five_hour", title: "5 hours", usedPercent: 18, resetsAt: nil)], updatedAt: now),
            ServiceUsage(service: .cursor, state: .ready,
                         windows: [UsageWindow(id: "total", title: "This month", usedPercent: 59, resetsAt: nil)], updatedAt: now),
            ServiceUsage(service: .grokBot, state: .ready,
                         windows: [UsageWindow(id: "week", title: "Week", usedPercent: 13, resetsAt: nil)], updatedAt: now)
        ]
        return UsageEntry(date: now, snapshot: UsageSnapshot(services: services))
    }
}
