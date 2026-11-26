import SwiftUI
import UsageCore

/// What is left in each of a service's allowances and how long until it comes back.
struct UsageReadings: View {
    let usage: ServiceUsage
    let date: Date

    var body: some View {
        // Fixed columns line the readings up from one ring to the next.
        Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 2) {
            ForEach(usage.windows) { window in
                GridRow(alignment: .firstTextBaseline) {
                    Text(window.title)
                        .foregroundStyle(.secondary)
                        .frame(width: 46, alignment: .leading)
                    Text(usage.remainingPercent(for: window, at: date).map { "\(Int($0.rounded()))%" } ?? "–")
                        .font(.system(size: 12, weight: .semibold))
                        .monospacedDigit()
                        .frame(width: 36, alignment: .trailing)
                    Text(resetText(window))
                        .foregroundStyle(.tertiary)
                        .frame(width: 62, alignment: .leading)
                        .help(window.resetsAt.map { "Resets \($0.formatted(.dateTime.month(.abbreviated).day().hour().minute()))" } ?? "Reset unavailable")
                }
                .accessibilityElement(children: .combine)
            }
        }
        .font(SettingsStyle.caption)
        .lineLimit(1)
    }

    private func resetText(_ window: UsageWindow) -> String {
        guard let reset = window.resetsAt, reset > date,
              let countdown = UsageDisplayText.countdown(until: reset, from: date) else { return "" }
        return "in \(countdown)"
    }
}
