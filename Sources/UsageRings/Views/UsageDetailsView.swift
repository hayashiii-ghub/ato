import AppKit
import UsageCore
import SwiftUI

struct UsageDetailsView: View {
    @ObservedObject var store: UsageStore
    @ObservedObject var updateController: AppUpdateController
    @State private var showingHelp = false
    @State private var selectedService: UsageService?

    private var currentService: UsageService? {
        if let selectedService, store.ringOrder.contains(selectedService) { return selectedService }
        return store.ringOrder.first
    }

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
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 12, weight: .medium))
                            .frame(width: 14, height: 14)
                            .accessibilityHidden(true)
                        Text("Refresh")
                    }
                }
                .disabled(!store.isEnabled || store.isRefreshing)
            }

            if let message = updateController.configurationMessage {
                Text(message)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if store.needsConsent {
                connectionExplanation
            }

            TimelineView(.periodic(from: .now, by: 30)) { timeline in
                VStack(spacing: 16) {
                    RingLayoutSettings(store: store, date: timeline.date, selectedService: currentService) {
                        selectedService = $0
                    }
                    if let service = currentService {
                        UsageServiceDetails(store: store, service: service, date: timeline.date) { candidate in
                            guard let index = store.ringOrder.firstIndex(of: service) else { return }
                            store.selectRing(candidate, at: index)
                            selectedService = candidate
                        }
                    }
                }
            }

            Divider()
            HStack {
                Button {
                    showingHelp = true
                } label: {
                    Label("Help", systemImage: "questionmark.circle")
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showingHelp, arrowEdge: .bottom) {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Text("Help").font(.headline)
                            Spacer()
                            Button("Done") { showingHelp = false }
                                .keyboardShortcut(.cancelAction)
                        }
                        usageInstructions
                    }
                    .padding(20)
                    .frame(width: 380)
                }
                Spacer()
                Button("Quit Usage Rings") {
                    NSApp.terminate(nil)
                }
                .keyboardShortcut("q", modifiers: .command)
                .help("Quit Usage Rings and stop refreshing usage.")
            }
            if store.sharingError {
                Text("The widget connection is unavailable. Restart Usage Rings to try again.")
                    .foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            }
        }
        .font(.body)
        .controlSize(.regular)
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            if selectedService == nil { selectedService = store.ringOrder.first }
        }
    }

    private var usageInstructions: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Select a ring to see its usage and display options below. Use Change service to replace it. Drag rings to reorder.")
            Text("Refreshes every 5 minutes while Usage Rings is running. Claude usage comes from Claude Code activity.")
            Text("Quit Usage Rings to stop refreshing. Opening the app again resumes it; closing the window keeps it running.")
            Text("Codex requires an installed Codex CLI signed in with ChatGPT. Cursor and Grok use the local Cursor session.")
            Text("Gemini reads the Gemini model quotas from Antigravity CLI 1.1.11 or later. Choose Gemini in Change service to connect; the CLI manages its existing Google sign-in and cache.")
            Text("To add the widget, right-click your desktop, choose Edit Widgets, then search for Usage Rings.")
        }
        .font(.body)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var connectionExplanation: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Connect your usage accounts").font(.headline)
            Text("Usage Rings waits for you to enable monitoring. This also applies after updating from a version that connected automatically.")
            Text("Only services shown in your rings are read. Codex uses the official local Codex CLI App Server. The CLI contacts OpenAI and may update its existing sign-in and local cache. Cursor and Grok read the Cursor session on this Mac and contact their services. Claude usage is read from its optional local status-line cache. Selecting Gemini lets Antigravity CLI read its Gemini usage quotas using your existing Google sign-in; the CLI manages its own authentication and cache.")
            Text("Only usage and reset times are shared with the widget. Other apps on this Mac can read those display values. No usage data is sent to the Usage Rings developer.")
            Text("Quit Usage Rings to stop future reads. Opening the app again resumes them. The separate Claude Code status-line helper is disconnected separately.")
            HStack {
                Link("Security and data FAQ", destination: URL(string: "https://github.com/hayashiii-ghub/usage-rings#security-and-data-faq")!)
                Spacer()
                Button("Enable AI usage") { store.enableAfterConsent() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .font(.body)
        .fixedSize(horizontal: false, vertical: true)
        .padding(16)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 16))
    }
}
