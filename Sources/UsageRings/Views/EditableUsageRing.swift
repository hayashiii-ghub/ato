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

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
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
                UsageRingReadout(values: usage.ringValues(at: date))
                    .frame(maxWidth: 120, alignment: .trailing)
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

    private func acceptDrop(_ items: [String]) -> Bool {
        guard items.count == 1, let item = items.first, item.hasPrefix(Self.dragPrefix),
              let source = UsageService(rawValue: String(item.dropFirst(Self.dragPrefix.count))),
              let sourceIndex = store.ringOrder.firstIndex(of: source), sourceIndex != index else { return false }
        store.moveRing(from: sourceIndex, to: index)
        return true
    }
}
