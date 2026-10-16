import SwiftUI
import UsageCore

struct UsageServiceDetails: View {
    @ObservedObject var store: UsageStore
    let service: UsageService
    let date: Date
    let onSelectService: (UsageService) -> Void

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
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(service.name).font(.headline)
                    Spacer()
                    serviceMenu
                }
                if let updated = usage.updatedAt {
                    Text("Updated \(updated, format: .dateTime.month(.abbreviated).day().hour().minute())")
                        .foregroundStyle(.secondary)
                }
            }

            if !usage.windows.isEmpty {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 24), GridItem(.flexible())], alignment: .leading, spacing: 16) {
                    ForEach(usage.windows) { window in
                        windowDetails(window)
                    }
                }
            }

            if let status = UsageDisplayText.status(usage, at: date) {
                Text(status)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !periodOptions.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    Text("Ring shows").foregroundStyle(.secondary)
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
                    .fixedSize(horizontal: true, vertical: false)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    // A changed segment count needs a fresh native control to recalculate its width.
                    .id(periodOptions)
                    if usage.preferredPeriod == nil {
                        Text("Auto shows the lowest remaining main window.")
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .font(.body)
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 24))
    }

    private func windowDetails(_ window: UsageWindow) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(window.title)
                Spacer()
                Text(usage.remainingPercent(for: window, at: date).map { "\(Int($0.rounded()))% left" } ?? "—")
                    .monospacedDigit()
            }
            Group {
                if let reset = window.resetsAt {
                    if reset <= date {
                        Text("Reset passed · Awaiting update")
                    } else if let countdown = UsageDisplayText.countdown(until: reset, from: date) {
                        Text("Resets in \(countdown)")
                            .help(Text("Resets \(reset, format: .dateTime.month(.abbreviated).day().hour().minute())"))
                    } else {
                        Text("Reset time unavailable")
                    }
                } else {
                    Text("Reset time unavailable")
                }
            }
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var serviceMenu: some View {
        Menu {
            ForEach(UsageService.allCases) { candidate in
                Button {
                    onSelectService(candidate)
                } label: {
                    if candidate == service {
                        Label(candidate.name, systemImage: "checkmark")
                    } else if let slot = store.ringOrder.firstIndex(of: candidate) {
                        Text("\(candidate.name) · Ring \(slot + 1)")
                    } else {
                        Text(candidate.name)
                    }
                }
                .accessibilityValue(candidate == service ? "Selected" : "")
            }
        } label: {
            HStack(spacing: 6) {
                Text("Change service")
                Image(systemName: "chevron.down")
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 14, height: 14)
                    .accessibilityHidden(true)
            }
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
    }
}
