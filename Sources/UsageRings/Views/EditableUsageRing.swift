import SwiftUI
import UsageCore

struct EditableUsageRing: View {
    @ObservedObject var store: UsageStore
    let service: UsageService
    let index: Int
    let date: Date
    let size: CGFloat
    let isSelected: Bool
    let onSelect: () -> Void
    private static let dragPrefix = "usage-rings:"

    private var usage: ServiceUsage { store.snapshot.usage(for: service) }
    private var displayedWindowTitle: String { usage.preferredPeriod?.title ?? usage.headline?.title ?? "—" }
    private var accessibilityValue: String {
        let remaining: String
        if let percent = usage.remainingPercent(at: date) {
            remaining = "\(Int(percent.rounded())) percent remaining"
        } else {
            remaining = "Usage unavailable"
        }
        return "\(remaining), \(displayedWindowTitle)"
    }

    var body: some View {
        Button(action: onSelect) {
            UsageRingView(usage: usage, date: date, size: size)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .background {
            RoundedRectangle(cornerRadius: 16)
                .fill(.primary.opacity(isSelected ? 0.04 : 0))
                .padding(-6)
                .allowsHitTesting(false)
        }
        .help("View \(service.name) usage and options. Drag to reorder.")
        .accessibilityLabel("\(service.name), ring \(index + 1)")
        .accessibilityValue(accessibilityValue)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityHint("Show usage details below. Drag to reorder.")
        .draggable(Self.dragPrefix + service.rawValue) {
            UsageRingView(usage: usage, date: date, size: size)
        }
        .dropDestination(for: String.self) { items, _ in
            return acceptDrop(items)
        }
    }

    private func acceptDrop(_ items: [String]) -> Bool {
        guard items.count == 1, let item = items.first, item.hasPrefix(Self.dragPrefix),
              let source = UsageService(rawValue: String(item.dropFirst(Self.dragPrefix.count))),
              let sourceIndex = store.ringOrder.firstIndex(of: source), sourceIndex != index else { return false }
        store.moveRing(from: sourceIndex, to: index)
        return true
    }
}
