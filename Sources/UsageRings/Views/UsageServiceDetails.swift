import SwiftUI
import UsageCore

struct UsageServiceDetails: View {
    @ObservedObject var store: UsageStore
    let service: UsageService
    let date: Date

    private var usage: ServiceUsage { store.snapshot.usage(for: service) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                ForEach(usage.windows) { window in
                    GridRow(alignment: .firstTextBaseline) {
                        Text(window.title).foregroundStyle(.secondary)
                        Text(usage.remainingPercent(for: window, at: date).map { "\(Int($0.rounded()))%" } ?? "—")
                            .monospacedDigit()
                            .gridColumnAlignment(.trailing)
                        Text(resetText(window))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .help(window.resetsAt.map { "Resets \($0.formatted(.dateTime.month(.abbreviated).day().hour().minute()))" } ?? "Reset unavailable")
                    }
                }
            }
            if let status = UsageDisplayText.status(usage, at: date) {
                Text(status).foregroundStyle(.secondary)
            }
            if let updated = usage.updatedAt {
                Text("Updated \(updated, format: .dateTime.month(.abbreviated).day().hour().minute())")
                    .foregroundStyle(.tertiary)
            }
        }
        .font(SettingsStyle.caption)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func resetText(_ window: UsageWindow) -> String {
        guard let reset = window.resetsAt else { return "Reset unavailable" }
        guard reset > date else { return "Awaiting update" }
        guard let countdown = UsageDisplayText.countdown(until: reset, from: date) else {
            return "Reset unavailable"
        }
        return "Resets in \(countdown)"
    }
}
