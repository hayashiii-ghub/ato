import SwiftUI
import UsageCore

struct EditableUsageRing: View {
    @ObservedObject var store: UsageStore
    let service: UsageService
    let index: Int
    let date: Date
    let size: CGFloat
    @State private var choosingService = false
    @State private var hovered = false
    @State private var dropTargeted = false
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
    private var periodOptions: [UsagePeriod] {
        switch service {
        case .claude, .gemini: return UsagePeriod.allCases
        case .codex:
            return UsagePeriod.allCases.filter { period in
                usage.windows.contains { usage.period(for: $0) == period } || usage.preferredPeriod == period
            }
        case .cursor, .grokBot: return []
        }
    }

    var body: some View {
        Button { choosingService = true } label: {
            VStack(spacing: 8) {
                UsageRingView(usage: usage, date: date, size: size)
                VStack(spacing: 2) {
                    HStack(spacing: 6) {
                        Text(service.name)
                        Image(systemName: "chevron.down").font(.system(size: 10, weight: .medium))
                    }
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(hovered ? .primary : .secondary)
                    Text(displayedWindowTitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .frame(height: 42)
            }
            .frame(width: size)
            .padding(.vertical, 6)
            .contentShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .background(.primary.opacity(hovered ? 0.05 : 0), in: RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(dropTargeted ? Color.accentColor : .clear, lineWidth: 2)
                .allowsHitTesting(false)
        }
        .onHover { hovered = $0 }
        .help("Click to change \(service.name). Drag to reorder.")
        .accessibilityLabel("\(service.name), ring \(index + 1)")
        .accessibilityValue(accessibilityValue)
        .accessibilityHint("Choose a service. Move left and right are available in the picker.")
        .popover(isPresented: $choosingService, arrowEdge: .bottom) { servicePicker }
        .draggable(Self.dragPrefix + service.rawValue) {
            UsageRingView(usage: usage, date: date, size: size)
                .padding(12)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
        }
        .dropDestination(for: String.self) { items, _ in
            acceptDrop(items)
        } isTargeted: { dropTargeted = $0 }
    }

    private func acceptDrop(_ items: [String]) -> Bool {
        guard items.count == 1, let item = items.first, item.hasPrefix(Self.dragPrefix),
              let source = UsageService(rawValue: String(item.dropFirst(Self.dragPrefix.count))),
              let sourceIndex = store.ringOrder.firstIndex(of: source), sourceIndex != index else { return false }
        store.moveRing(from: sourceIndex, to: index)
        return true
    }

    private var servicePicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Choose service").font(.headline).padding(.horizontal, 8)
            ForEach(UsageService.allCases) { candidate in
                Button {
                    choosingService = false
                    store.selectRing(candidate, at: index)
                } label: {
                    HStack(spacing: 10) {
                        ServiceMark(service: candidate).frame(width: 22, height: 22)
                        Text(candidate.name)
                        Spacer()
                        if candidate == service {
                            Image(systemName: "checkmark").foregroundStyle(.tint)
                        } else if let slot = store.ringOrder.firstIndex(of: candidate) {
                            Text("Ring \(slot + 1)").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .padding(8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityValue(candidate == service ? "Selected" : "")
            }
            if !periodOptions.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    Text("Ring shows").font(.caption).foregroundStyle(.secondary)
                    Picker("Usage window", selection: Binding<UsagePeriod?>(
                        get: { store.preferredPeriods[service] },
                        set: { store.setPreferredPeriod($0, for: service) }
                    )) {
                        Text("Auto").tag(Optional<UsagePeriod>.none)
                        ForEach(periodOptions) { period in
                            Text(period.title).tag(Optional(period))
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    if usage.preferredPeriod == nil {
                        Text("Auto shows the lowest remaining main window.")
                            .font(.caption).foregroundStyle(.secondary)
                    } else if usage.headline == nil {
                        Text("No reading for this window yet.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Divider()
            HStack {
                Button("Move left", systemImage: "arrow.left") { move(to: index - 1) }
                    .disabled(index == 0)
                Spacer()
                Button("Move right", systemImage: "arrow.right") { move(to: index + 1) }
                    .disabled(index == 3)
            }
            .controlSize(.small)
        }
        .padding(12)
        .frame(width: 248)
    }

    private func move(to destination: Int) {
        choosingService = false
        store.moveRing(from: index, to: destination)
    }
}
