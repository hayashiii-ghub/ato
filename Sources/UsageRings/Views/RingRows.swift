import SwiftUI
import UsageCore

/// The rings as the widget shows them, top to bottom: pick what each one tracks and read what is left.
struct RingRows: View {
    @ObservedObject var store: UsageStore
    let date: Date

    var body: some View {
        SettingsSection {
            ForEach(Array(store.ringOrder.enumerated()), id: \.offset) { index, service in
                RingRow(store: store, service: service, index: index, date: date)
            }
        }
    }
}

private struct RingRow: View {
    @ObservedObject var store: UsageStore
    let service: UsageService
    let index: Int
    let date: Date

    private var usage: ServiceUsage { store.snapshot.usage(for: service) }

    /// A service can report allowances for more than its own models: Antigravity also meters a pool shared by
    /// Claude and GPT. The service's own windows sit beside its name; every other family gets a line of its own.
    private struct Family: Identifiable {
        let name: String?
        var windows: [UsageWindow]
        var id: String { name ?? "" }
    }

    private var families: [Family] {
        var result: [Family] = []
        for window in usage.windows {
            let parts = window.title.components(separatedBy: " · ")
            let name = parts.count > 1 && parts[0] != service.name ? parts[0] : nil
            if let position = result.firstIndex(where: { $0.name == name }) {
                result[position].windows.append(window)
            } else {
                result.append(Family(name: name, windows: [window]))
            }
        }
        for position in result.indices {
            // The short window first, as the other rings report theirs.
            result[position].windows.sort { usage.period(for: $0) == .fiveHours && usage.period(for: $1) != .fiveHours }
        }
        return result.sorted { $0.name == nil && $1.name != nil }
    }

    var body: some View {
        let families = families
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                UsageRingView(usage: usage, date: date, size: 34, compact: true)
                // Choosing a service that another ring shows swaps the two, so this also reorders.
                Picker("Service for ring \(index + 1)", selection: Binding(
                    get: { service },
                    set: { store.selectRing($0, at: index) }
                )) {
                    ForEach(UsageService.allCases) { candidate in
                        Text(candidate.name).tag(candidate)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .fixedSize()
                Spacer(minLength: 8)
                if service == .gemini && store.needsAntigravityAuthorization {
                    Button(store.isAuthorizingAntigravity ? "Waiting…" : "Allow Access…") {
                        Task { await store.authorizeAntigravityAccess() }
                    }
                    .disabled(store.isRefreshing || store.isAuthorizingAntigravity)
                    .help("Choose Always Allow when macOS asks.")
                } else if let own = families.first(where: { $0.name == nil }) {
                    UsageReadings(usage: usage, windows: own.windows, date: date)
                }
            }
            ForEach(families.filter { $0.name != nil }) { family in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(family.name ?? "")
                        .font(SettingsStyle.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    UsageReadings(usage: usage, windows: family.windows, date: date)
                }
                .padding(.leading, 44)
            }
            if let status = UsageDisplayText.status(usage, at: date) {
                Text(status)
                    .font(SettingsStyle.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 44)
            }
        }
        .settingsCell()
        .help(usage.updatedAt.map { "Updated \($0.formatted(.dateTime.month(.abbreviated).day().hour().minute()))" } ?? "")
    }
}
