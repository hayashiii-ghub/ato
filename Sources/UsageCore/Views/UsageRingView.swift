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
        let values = usage.ringValues(at: date)
        VStack(spacing: 13) {
            ZStack {
                arcs(for: values)
                    .padding(size * 0.055)
                ServiceMark(service: usage.service)
                    .foregroundStyle(values.hasReading ? .primary : .secondary)
                    .frame(width: size * 0.60, height: size * 0.60)
            }
            .frame(width: size, height: size)
            if !compact {
                WidgetUsageReadout(values: values)
                    .frame(width: size)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(usage.service.name)
        .accessibilityValue(accessibleValue(values))
        .accessibilityHint(usage.isFiveHourArcBlocked(at: date) ? "Weekly usage limit reached." : "")
    }

    @ViewBuilder
    private func arcs(for values: UsageRingValues) -> some View {
        switch values {
        case let .split(top, bottom):
            UsageArc(remaining: top.remaining, fraction: 156.0 / 360, rotation: 192, width: size * 0.095)
            UsageArc(remaining: bottom.remaining, fraction: 156.0 / 360, rotation: 12, width: size * 0.095)
                .scaleEffect(x: -1, y: 1)
        case let .single(reading):
            UsageArc(remaining: reading.remaining, fraction: 1, rotation: -90, width: size * 0.095)
        case .unknown:
            UsageArc(remaining: nil, fraction: 1, rotation: -90, width: size * 0.095)
        }
    }

    private func accessibleValue(_ values: UsageRingValues) -> String {
        func value(_ reading: UsageRingValues.Reading) -> String {
            let remaining = reading.remaining.map { "\(Int($0.rounded())) percent remaining" } ?? "unavailable"
            return "\(reading.title): \(remaining)."
        }
        switch values {
        case let .split(top, bottom):
            return "\(value(top)) \(value(bottom))"
        case let .single(reading):
            return value(reading)
        case .unknown:
            return "Unavailable"
        }
    }
}

private struct UsageArc: View {
    let remaining: Double?
    let fraction: CGFloat
    let rotation: Double
    let width: CGFloat

    var body: some View {
        let stroke = StrokeStyle(lineWidth: width, lineCap: .round)
        ZStack {
            Circle().trim(from: 0, to: fraction)
                .stroke(.primary.opacity(remaining == nil ? 0.075 : 0.16), style: stroke)
            if let remaining, remaining > 0 {
                Circle().trim(from: 0, to: fraction * CGFloat(remaining / 100))
                    .stroke(remaining <= 10 ? Color.red : remaining <= 20 ? .yellow : .green, style: stroke)
            }
        }
        .rotationEffect(.degrees(rotation))
    }
}

private struct WidgetUsageReadout: View {
    let values: UsageRingValues

    var body: some View {
        Group {
            switch values {
            case let .split(top, bottom):
                grid([top, bottom])
            case let .single(reading):
                grid([reading])
            case .unknown:
                EmptyView()
            }
        }
        .frame(height: 42, alignment: .top)
        .lineLimit(1)
    }

    // A Grid keeps the label and number columns aligned while the block stays centered under the ring.
    private func grid(_ readings: [UsageRingValues.Reading]) -> some View {
        Grid(horizontalSpacing: 4, verticalSpacing: 1) {
            ForEach(Array(readings.enumerated()), id: \.offset) { _, reading in
                if let remaining = reading.remaining {
                    GridRow(alignment: .firstTextBaseline) {
                        Text(marker(reading.title) + ":")
                            .foregroundStyle(.secondary)
                            .gridColumnAlignment(.leading)
                        Text("\(Int(remaining.rounded()))%")
                            .monospacedDigit()
                            .gridColumnAlignment(.trailing)
                    }
                }
            }
        }
        .font(.system(size: 13, weight: .medium))
        .fixedSize()
    }

    private func marker(_ title: String) -> String {
        switch title {
        case UsagePeriod.week.title: "W"
        default: title
        }
    }
}

public struct UsageRingReadout: View {
    private let values: UsageRingValues

    public init(values: UsageRingValues) { self.values = values }

    public var body: some View {
        if values.hasReading {
            VStack(alignment: .trailing, spacing: 2) {
                switch values {
                case let .split(top, bottom):
                    row(top)
                    row(bottom)
                case let .single(reading):
                    if let remaining = reading.remaining {
                        ViewThatFits(in: .horizontal) {
                            row(reading).fixedSize(horizontal: true, vertical: false)
                            VStack(spacing: 0) {
                                percentage(remaining)
                                label(reading.title)
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                case .unknown:
                    EmptyView()
                }
            }
            .font(.system(size: 11, weight: .medium))
            .lineLimit(1)
        }
    }

    @ViewBuilder
    private func row(_ reading: UsageRingValues.Reading) -> some View {
        if let remaining = reading.remaining {
            HStack(spacing: 4) {
                label(reading.title)
                percentage(remaining)
                    .layoutPriority(1)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(reading.title)
            .accessibilityValue("\(Int(remaining.rounded())) percent remaining")
        } else {
            Color.clear
                .frame(width: 0, height: 13.2)
                .accessibilityHidden(true)
        }
    }

    private func label(_ title: String) -> some View {
        Text(title)
            .foregroundStyle(.secondary)
            .minimumScaleFactor(0.8)
    }

    private func percentage(_ remaining: Double) -> some View {
        Text("\(Int(remaining.rounded()))%")
            .monospacedDigit()
            .minimumScaleFactor(0.8)
    }
}
