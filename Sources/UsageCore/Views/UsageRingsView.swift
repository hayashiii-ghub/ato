import SwiftUI

public struct UsageRingsView: View {
    public let snapshot: UsageSnapshot
    public let date: Date
    public let compact: Bool

    public init(snapshot: UsageSnapshot, date: Date, compact: Bool = false) {
        self.snapshot = snapshot
        self.date = date
        self.compact = compact
    }

    public var body: some View {
        UsageRingsLayout(ringOrder: snapshot.ringOrder, compact: compact) { service, size in
            UsageRingView(usage: snapshot.usage(for: service), date: date, size: size, compact: compact)
        }
    }
}

public struct UsageRingsLayout<Ring: View>: View {
    public let ringOrder: [UsageService]
    public let compact: Bool
    private let ring: (UsageService, CGFloat) -> Ring

    public init(ringOrder: [UsageService], compact: Bool = false,
                @ViewBuilder ring: @escaping (UsageService, CGFloat) -> Ring) {
        self.ringOrder = ringOrder
        self.compact = compact
        self.ring = ring
    }

    public var body: some View {
        GeometryReader { geometry in
            // The small widget has no percentage rows: use the full square for its 2 × 2 grid.
            let size = max(1, min(compact ? (geometry.size.width - 14) / 2 : (geometry.size.width - 48) / 4,
                           compact ? (geometry.size.height - 14) / 2 : geometry.size.height * 0.62))
            if compact {
                VStack(spacing: 14) {
                    HStack(spacing: 14) {
                        ForEach(ringOrder.prefix(2)) { ring($0, size) }
                    }
                    HStack(spacing: 14) {
                        ForEach(ringOrder.suffix(2)) { ring($0, size) }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HStack(alignment: .top, spacing: 16) {
                    ForEach(ringOrder) { ring($0, size) }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}
