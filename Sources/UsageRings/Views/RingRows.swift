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

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
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
                } else {
                    UsageReadings(usage: usage, date: date)
                }
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
