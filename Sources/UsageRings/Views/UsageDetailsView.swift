import AppKit
import UsageCore
import SwiftUI

/// Two screens in one panel: what is left, and behind the gear everything that is set once.
struct UsageDetailsView: View {
    @ObservedObject var store: UsageStore
    @ObservedObject var updateController: AppUpdateController
    @ObservedObject var notifications: UsageNotificationController
    @ObservedObject var agentTools: AgentToolsController
    let onClose: () -> Void
    @State private var showsSettings = false

    var body: some View {
        if showsSettings {
            settings
        } else {
            usage
        }
    }

    private var usage: some View {
        PanelChrome(title: "ato?", onClose: onClose) {
            GlassIconButton("Refresh usage", systemImage: "arrow.clockwise", glyphSize: 15) {
                Task { await store.refresh() }
            }
            .disabled(!store.isEnabled || store.isRefreshing || store.isAuthorizingAntigravity)
            GlassIconButton("Settings", systemImage: "gearshape", glyphSize: 16) {
                showsSettings = true
            }
        } content: {
            VStack(alignment: .leading, spacing: 10) {
                if store.needsConsent {
                    connectionExplanation
                }
                if store.sharingError {
                    SettingsSection {
                        SettingsNote("Restart ato? to reconnect the widget.", isWarning: true)
                    }
                }
                TimelineView(.periodic(from: .now, by: 30)) { timeline in
                    RingRows(store: store, date: timeline.date)
                }
                UsageNotificationSettings(controller: notifications, monitoringEnabled: store.isEnabled)
            }
        } footer: {
            footer
        }
    }

    private var settings: some View {
        PanelChrome(title: "Settings", onBack: { showsSettings = false }, onClose: onClose) {
            // The same place and shape as the first screen's refresh: re-check what this screen shows.
            GlassIconButton("Check AI tools", systemImage: "arrow.clockwise", glyphSize: 15) {
                Task { await agentTools.refresh() }
            }
            .disabled(agentTools.isWorking)
        } content: {
            VStack(alignment: .leading, spacing: 10) {
                AgentToolsView(controller: agentTools)
                SystemSettingsSection(updates: updateController)
            }
        } footer: {
            footer
        }
    }

    /// The same on both screens, so updating, help, and quitting never move.
    private var footer: some View {
        SettingsFooter(
            updates: updateController,
            helpURL: URL(string: "https://github.com/hayashiii-ghub/ato#readme")!,
            isBusy: agentTools.isWorking
        )
    }

    private var connectionExplanation: some View {
        SettingsSection("Usage monitoring") {
            VStack(alignment: .leading, spacing: 10) {
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
            .settingsCell()
        }
    }
}
