import SwiftUI

public struct UsageRingView: View {
    public let usage: ServiceUsage
    public let date: Date
    public let size: CGFloat
    public let compact: Bool

    public init(usage: ServiceUsage, date: Date, size: CGFloat, compact: Bool = false) {
        self.usage = usage
        self.date = date
        self.size = size
        self.compact = compact
    }

    public var body: some View {
        let remaining = usage.remainingPercent(at: date)
        VStack(spacing: 16) {
            ZStack {
                Circle().stroke(.primary.opacity(0.13), lineWidth: size * 0.095)
                    .padding(size * 0.048)
                if let remaining, remaining > 0 {
                    Circle()
                        .trim(from: 0, to: remaining / 100)
                        .stroke(color(remaining), style: StrokeStyle(lineWidth: size * 0.095, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .padding(size * 0.048)
                }
                ServiceMark(service: usage.service)
                    .foregroundStyle(remaining == nil ? .secondary : .primary)
                    .frame(width: size * 0.60, height: size * 0.60)
            }
            .frame(width: size, height: size)
            .overlay(alignment: .bottom) {
                // Unknown usage needs a badge when there is no percentage row.
                if compact && remaining == nil {
                    Text("—")
                        .font(.system(size: size * 0.22, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 3)
                        .background(.background, in: Capsule())
                        .offset(y: 2)
                }
            }
            if !compact {
                Text(remaining.map { "\(Int($0.rounded()))%" } ?? "—")
                    .font(.system(size: size * 0.27, weight: .regular))
                    .monospacedDigit()
                    .foregroundStyle(remaining == nil ? .secondary : .primary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(usage.service.name)
        .accessibilityValue((remaining.map { "\(Int($0.rounded())) percent remaining" } ?? "Usage unavailable. Open ato? to refresh.")
                            + (usage.preferredPeriod.map { ", \($0.title)" } ?? ""))
    }

    private func color(_ remaining: Double) -> Color {
        remaining <= 10 ? .red : remaining <= 20 ? .yellow : .green
    }
}
