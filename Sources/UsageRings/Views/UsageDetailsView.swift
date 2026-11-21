import AppKit
import UsageCore
import SwiftUI

struct UsageDetailsView: View {
    @ObservedObject var store: UsageStore
    @ObservedObject var updateController: AppUpdateController
    @ObservedObject var notifications: UsageNotificationController
    @StateObject private var agentTools = AgentToolsController()

    var body: some View {
        VStack(spacing: 8) {
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
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
                            .disabled(!store.isEnabled || store.isRefreshing || store.isAuthorizingAntigravity)
                            .accessibilityLabel("Refresh usage")
                            .help("Refresh usage")
                        }
                        .frame(minHeight: 28)
                        TimelineView(.periodic(from: .now, by: 30)) { timeline in
                            RingLayoutSettings(store: store, date: timeline.date)
                        }
                        if store.needsAntigravityAuthorization {
                            antigravityAccessExplanation
                        }
                    }
                    Divider()
                    UsageNotificationSettings(controller: notifications, monitoringEnabled: store.isEnabled)
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
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .font(SettingsStyle.body)
        .controlSize(.regular)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
            Color.clear
                .glassEffect(.regular, in: Rectangle())
                .ignoresSafeArea()
                .allowsHitTesting(false)
        }
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
                .focusEffectDisabled()
                .disabled(agentTools.isWorking)
        }
        .frame(minHeight: 28)
    }

    private var connectionExplanation: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Usage monitoring").fontWeight(.medium)
            Text("Codex uses its CLI. Claude uses its local status line. Grok Build and Antigravity use their existing sign-ins to request usage from xAI and Google. Antigravity may need separate Keychain permission.")
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

    private var antigravityAccessExplanation: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Allow ato? to read Antigravity's saved sign-in through macOS Keychain. Choose Always Allow to keep access after reopening. Automatic refresh never opens a permission dialog.")
                .foregroundStyle(.secondary)
            Button(store.isAuthorizingAntigravity ? "Waiting for permission…" : "Allow Antigravity Access…") {
                Task { await store.authorizeAntigravityAccess() }
            }
            .disabled(store.isRefreshing || store.isAuthorizingAntigravity)
        }
        .font(SettingsStyle.caption)
        .padding(.vertical, 8)
        .fixedSize(horizontal: false, vertical: true)
    }
}
