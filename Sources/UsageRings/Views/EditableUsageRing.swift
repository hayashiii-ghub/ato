import SwiftUI
import UsageCore

struct EditableUsageRing: View {
    @ObservedObject var store: UsageStore
    let service: UsageService
    let index: Int
    let date: Date
    @Binding var isExpanded: Bool
    private static let dragPrefix = "usage-rings:"

    private var usage: ServiceUsage { store.snapshot.usage(for: service) }
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
        let remainingPercent = usage.remainingPercent(at: date).map { Int($0.rounded()) }

        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                UsageRingView(usage: usage, date: date, size: 32, compact: true)
                    .help("Drag to reorder")
                    .draggable(Self.dragPrefix + service.rawValue) {
                        UsageRingView(usage: usage, date: date, size: 32, compact: true)
                    }
                    .contextMenu {
                        Button("Move up") { store.moveRing(from: index, to: index - 1) }
                            .disabled(index == 0)
                        Button("Move down") { store.moveRing(from: index, to: index + 1) }
                            .disabled(index == store.ringOrder.count - 1)
                    }
                Picker("Service for ring \(index + 1)", selection: Binding(
                    get: { service },
                    set: { store.selectRing($0, at: index) }
                )) {
                    ForEach(UsageService.allCases) { candidate in
                        Text(candidate.name).tag(candidate)
                    }
                }
                .pickerStyle(.menu)
                .buttonSizing(.flexible)
                .controlSize(.large)
                .labelsHidden()
                .frame(width: 110, height: 28)
                Spacer(minLength: 4)
                periodPicker
                Text(remainingPercent.map { "\($0)%" } ?? "—")
                    .font(.system(size: 13, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(remainingPercent == nil ? .secondary : .primary)
                    .frame(width: 42, alignment: .trailing)
                    .accessibilityLabel("Remaining")
                    .accessibilityValue(remainingPercent.map { "\($0) percent" } ?? "Unavailable")
                Button {
                    isExpanded.toggle()
                } label: {
                    SettingsIcon(name: isExpanded ? "chevron.up" : "chevron.down", isDisclosure: true)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Usage and reset times for \(service.name)")
                .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
            .dropDestination(for: String.self) { items, _ in return acceptDrop(items) }
            if isExpanded {
                UsageServiceDetails(store: store, service: service, date: date)
                    .padding(.leading, 42)
                    .padding(.bottom, 12)
            }
        }
    }

    @ViewBuilder
    private var periodPicker: some View {
        if !periodOptions.isEmpty {
            Picker("Period for \(service.name)", selection: Binding<UsagePeriod?>(
                get: { store.preferredPeriods[service] },
                set: { store.setPreferredPeriod($0, for: service) }
            )) {
                Text("Auto").tag(Optional<UsagePeriod>.none)
                ForEach(periodOptions) { period in
                    Text(period.title).tag(Optional(period))
                }
            }
            .pickerStyle(.menu)
            .buttonSizing(.flexible)
            .controlSize(.large)
            .labelsHidden()
            .frame(width: 82, height: 28)
        } else {
            Text(usage.headline?.title ?? "—")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: 82, height: 28)
                .background(.quaternary, in: Capsule())
                .accessibilityLabel("Period for \(service.name)")
                .accessibilityValue(usage.headline?.title ?? "Unavailable")
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
