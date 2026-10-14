import AppKit
import UsageCore
import SwiftUI

struct UsageDetailsView: View {
    @ObservedObject var store: UsageStore
    @ObservedObject var updateController: AppUpdateController

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("Usage Rings").font(.title2.weight(.semibold))
                Spacer()
                Button("Check for Updates…") {
                    updateController.controller.checkForUpdates(nil)
                }
                .disabled(!updateController.canCheckForUpdates)
                .help(updateController.configurationMessage ?? "Check for a new version of Usage Rings.")
                Button {
                    Task { await store.refresh() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(!store.isEnabled || store.isRefreshing)
            }

            if let message = updateController.configurationMessage {
                Text(message)
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if store.needsConsent {
                connectionExplanation
            }

            TimelineView(.periodic(from: .now, by: 30)) { timeline in
                UsageRingsView(snapshot: store.snapshot, date: timeline.date)
                    .padding(24)
                    .frame(height: 190)
                    .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 28))
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(UsageService.allCases) { service in
                        details(store.snapshot.usage(for: service), date: timeline.date)
                    }
                }
            }

            Divider()
            if !store.needsConsent {
                Toggle("Show AI usage", isOn: Binding(get: { store.isEnabled }, set: store.setEnabled))
            }
            Text("Refreshes every 5 minutes while Usage Rings is running. Claude usage comes from Claude Code activity.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Text("Codex requires an installed Codex CLI signed in with ChatGPT. Cursor and Grok Bot use the local Cursor session.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Text("To add the widget, right-click your desktop, choose Edit Widgets, then search for Usage Rings.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if store.sharingError {
                Text("The widget connection is unavailable. Restart Usage Rings to try again.")
                    .font(.callout).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            }
            Button("Quit Usage Rings") {
                NSApp.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: .command)
            .help("Quit Usage Rings and stop refreshing usage.")
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var connectionExplanation: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Connect your usage accounts").font(.headline)
            Text("Usage Rings waits for you to enable monitoring. This also applies after updating from a version that connected automatically.")
            Text("Codex uses the official local Codex CLI App Server. The CLI contacts OpenAI and may update its existing sign-in and local cache. Cursor and Grok Bot read the Cursor session on this Mac and contact their services. Claude usage is read from its optional local status-line cache.")
            Text("Only usage and reset times are shared with the widget. Other apps on this Mac can read those display values. No usage data is sent to the Usage Rings developer.")
            Text("You can stop future reads with Show AI usage. The separate Claude Code status-line helper is disconnected separately.")
            HStack {
                Link("Security and data FAQ", destination: URL(string: "https://github.com/hayashiii-ghub/usage-rings#security-and-data-faq")!)
                Spacer()
                Button("Enable AI usage") { store.enableAfterConsent() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .font(.callout)
        .fixedSize(horizontal: false, vertical: true)
        .padding(16)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 16))
    }

    private func details(_ usage: ServiceUsage, date: Date) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(usage.service.name).font(.headline)
                Spacer()
                if let updated = usage.updatedAt {
                    Text("Updated \(updated, format: .dateTime.hour().minute())").font(.caption).foregroundStyle(.secondary)
                }
            }
            if usage.isCurrent(at: date) {
                ForEach(usage.windows) { window in
                    HStack {
                        Text(window.title)
                        Spacer()
                        Text("\(Int(window.remainingPercent.rounded()))% left").monospacedDigit()
                        if let reset = window.resetsAt {
                            Text("· \(reset, format: .dateTime.month(.abbreviated).day().hour().minute())")
                                .foregroundStyle(.secondary)
                                .help("Resets at \(reset.formatted())")
                        }
                    }
                    .font(.callout)
                }
            } else {
                Text(statusText(usage)).font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    private func statusText(_ usage: ServiceUsage) -> String {
        switch usage.state {
        case .disabled: return "Enable AI usage to connect."
        case .setupRequired: return "Install or update the Codex CLI, then refresh."
        case .signInRequired:
            switch usage.service {
            case .codex: return "Sign in to the Codex CLI with ChatGPT, then refresh."
            case .cursor: return "Open Cursor and sign in, then refresh."
            case .claude: return "Use Claude Code, then refresh to receive usage."
            case .grokBot: return "Sign in to Cursor with your Grok Bot account, then refresh."
            }
        case .unavailable: return "Could not update. Try refreshing in a moment."
        case .ready: return usage.service == .claude ? "Use Claude Code to update your usage." : "Waiting for a fresh reading."
        }
    }
}
