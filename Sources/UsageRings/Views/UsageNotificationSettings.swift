import AppKit
import SwiftUI

struct UsageNotificationSettings: View {
    @ObservedObject var controller: UsageNotificationController
    let monitoringEnabled: Bool

    var body: some View {
        SettingsSection {
            SettingsToggle("Alert at 20% and 10% left", isOn: Binding(
                get: { controller.isEnabled },
                set: { enabled in Task { await controller.setEnabled(enabled) } }
            ))
            .disabled(controller.isRequestingAuthorization)
            SettingsToggle("Alert sound", isOn: Binding(
                get: { controller.soundEnabled },
                set: { controller.setSoundEnabled($0) }
            ))
            .disabled(!controller.isEnabled)
            if controller.isRequestingAuthorization {
                SettingsRow("Allow notifications when macOS asks.") {
                    ProgressView().controlSize(.small)
                }
            }
            if controller.authorizationStatus == .denied {
                SettingsRow("Notifications are off for ato?") {
                    Button("Open Settings…") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                }
            }
            if controller.isEnabled && !monitoringEnabled {
                SettingsNote("Enable usage monitoring to receive alerts.")
            }
            if let error = controller.errorMessage {
                SettingsNote(error, isWarning: true)
            }
        }
        .task { await controller.refreshAuthorization() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await controller.refreshAuthorization() }
        }
    }
}
