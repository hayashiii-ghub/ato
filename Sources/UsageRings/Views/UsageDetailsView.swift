import AppKit
import UsageCore
import SwiftUI

struct UsageDetailsView: View {
    @ObservedObject var store: UsageStore
    @ObservedObject var updateController: AppUpdateController
    @StateObject private var agentTools = AgentToolsController()

    var body: some View {
        VStack(spacing: 12) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let message = updateController.configurationMessage {
                        Text(message).foregroundStyle(.secondary)
                    }
                    if store.needsConsent {
                        connectionExplanation
                        Divider()
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Usage")
                                .font(SettingsStyle.heading)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button {
                                Task { await store.refresh() }
                            } label: {
                                SettingsIcon(name: "arrow.clockwise")
                            }
                            .buttonStyle(.borderless)
                            .disabled(!store.isEnabled || store.isRefreshing)
                            .accessibilityLabel("Refresh usage")
                            .help("Refresh usage")
                        }
                        .frame(minHeight: 28)
                        TimelineView(.periodic(from: .now, by: 30)) { timeline in
                            RingLayoutSettings(store: store, date: timeline.date)
                        }
                    }
                    Divider()
                    AgentToolsView(controller: agentTools)
                    if store.sharingError {
                        Text("Restart ato? to reconnect the widget.")
                            .foregroundStyle(.orange)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            footer
        }
        .padding(20)
        .font(SettingsStyle.body)
        .controlSize(.regular)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Button("Updates…") { updateController.controller.checkForUpdates(nil) }
                .disabled(!updateController.canCheckForUpdates || agentTools.isWorking)
            Spacer()
            Link(destination: URL(string: "https://github.com/hayashiii-ghub/ato#readme")!) {
                SettingsIcon(name: "questionmark.circle")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .accessibilityLabel("Help")
            .help("Help")
            Button("Quit") { NSApp.terminate(nil) }
                .keyboardShortcut("q", modifiers: .command)
                .disabled(agentTools.isWorking)
        }
        .frame(minHeight: 28)
    }

    private var connectionExplanation: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Usage monitoring").fontWeight(.medium)
            Text("Only accounts in your rings are read. Codex, Cursor and Grok contact their services. Codex may update its existing sign-in and cache. Claude and Gemini use local status-line caches; ato? never starts Antigravity.")
            Text("Usage and reset times are shared with the widget and can be read by other apps on this Mac. Nothing is sent to the ato? developer. Quit stops monitoring; status-line helpers are disconnected separately.")
            HStack {
                Link("Privacy", destination: URL(string: "https://github.com/hayashiii-ghub/ato#security-and-data-faq")!)
                Spacer()
                Button("Enable") { store.enableAfterConsent() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}
