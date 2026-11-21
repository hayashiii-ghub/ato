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
            ServiceUsage(service: .codex, state: .ready, windows: [
                UsageWindow(id: "primary", title: "5 hours", usedPercent: 28, resetsAt: nil, period: .fiveHours),
                UsageWindow(id: "secondary", title: "Week", usedPercent: 60, resetsAt: nil, period: .week)
            ], updatedAt: now),
            ServiceUsage(service: .claude, state: .ready, windows: [
                UsageWindow(id: "five_hour", title: "5 hours", usedPercent: 70, resetsAt: nil),
                UsageWindow(id: "seven_day", title: "Week", usedPercent: 34, resetsAt: nil)
            ], updatedAt: now),
            ServiceUsage(service: .grokBot, state: .ready, windows: [
                UsageWindow(id: "subscription", title: "Week", usedPercent: 13, resetsAt: nil, period: .week)
            ], updatedAt: now),
            ServiceUsage(service: .gemini, state: .ready, windows: [
                UsageWindow(id: "gemini-5h", title: "5 hours", usedPercent: 59, resetsAt: nil, period: .fiveHours),
                UsageWindow(id: "gemini-weekly", title: "Week", usedPercent: 37, resetsAt: nil, period: .week)
            ], updatedAt: now)
        ]
        return UsageEntry(date: now, snapshot: UsageSnapshot(services: services))
    }
}
