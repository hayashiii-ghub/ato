import AppKit
import SwiftUI

struct UsageNotificationSettings: View {
    @ObservedObject var controller: UsageNotificationController
    let monitoringEnabled: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Notifications")
                .font(SettingsStyle.heading)
                .foregroundStyle(.secondary)
            Toggle("Low usage alerts", isOn: Binding(
                get: { controller.isEnabled },
                set: { enabled in Task { await controller.setEnabled(enabled) } }
            ))
            .disabled(controller.isRequestingAuthorization)
            if controller.isRequestingAuthorization {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Allow notifications in the macOS permission dialog.")
                }
                .font(SettingsStyle.caption)
                .foregroundStyle(.secondary)
            }
            Text("Notify once at 20% and again at 10% for each allowance in your rings.")
                .font(SettingsStyle.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Toggle("Play a sound", isOn: Binding(
                    get: { controller.soundEnabled },
                    set: { controller.setSoundEnabled($0) }
                ))
                .disabled(!controller.isEnabled)
                Spacer()
                Button("Test Notification") { Task { await controller.sendTest() } }
                    .disabled(!controller.isEnabled || !controller.isAuthorized || controller.isRequestingAuthorization)
            }
            if controller.authorizationStatus == .denied {
                Text("Allow notifications for ato? in System Settings → Notifications.")
                    .font(SettingsStyle.caption)
                    .foregroundStyle(.secondary)
            }
            if controller.authorizationStatus == .denied {
                Button("Open Notification Settings…") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .font(SettingsStyle.caption)
            }
            if controller.isEnabled && !monitoringEnabled {
                Text("Enable usage monitoring to receive alerts.")
                    .font(SettingsStyle.caption)
                    .foregroundStyle(.secondary)
            }
            if let error = controller.errorMessage {
                Text(error).font(SettingsStyle.caption).foregroundStyle(.orange)
            }
        }
        .task { await controller.refreshAuthorization() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await controller.refreshAuthorization() }
        }
    }
}
