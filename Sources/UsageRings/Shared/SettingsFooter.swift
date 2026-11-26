// Mirrored by hand in ato? and cc: (Sources/*/Shared). Keep both copies identical.
import AppKit
import SwiftUI

/// Update progress, shown only while there is something to report.
private struct UpdateStatusBar: View {
    @ObservedObject var updates: AppUpdateController

    var body: some View {
        if updates.status != .idle {
            VStack(spacing: 0) {
                Divider()
                UpdateStatusRow(updates: updates)
                    .padding(.leading, 16)
                    .padding(.trailing, 10)
                    .frame(minHeight: 48)
            }
        }
    }
}

struct SettingsFooter: View {
    @ObservedObject var updates: AppUpdateController
    let helpURL: URL
    var isBusy = false

    var body: some View {
        VStack(spacing: 0) {
            UpdateStatusBar(updates: updates)
            Divider()
            HStack(spacing: 8) {
                Button(action: updates.checkForUpdates) {
                    Text("Updates…").glassControlLabel()
                }
                .buttonStyle(.plain)
                .disabled(!updates.canCheckForUpdates || isBusy)
                Spacer(minLength: 4)
                GlassIconButton("Help", systemImage: "questionmark", glyphSize: 14) {
                    NSWorkspace.shared.open(helpURL)
                }
                Button { NSApp.terminate(nil) } label: {
                    Text("Quit").glassControlLabel(width: 68)
                }
                .buttonStyle(.plain)
                .focusEffectDisabled()
                .disabled(isBusy)
            }
            .padding(.horizontal, 10)
            .frame(height: 48)
        }
    }
}

private struct UpdateStatusRow: View {
    @ObservedObject var updates: AppUpdateController

    var body: some View {
        HStack(spacing: 8) {
            switch updates.status {
            case .idle:
                EmptyView()
            case let .message(text, isError):
                Text(text)
                    .foregroundStyle(isError ? Color.orange : Color.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            case .askingPermission:
                Text("Check for updates automatically?")
                Spacer(minLength: 4)
                action("Don’t Check") { updates.allowAutomaticChecks(false) }
                action("Check", isPrimary: true) { updates.allowAutomaticChecks(true) }
            case .checking:
                ProgressView().controlSize(.small)
                Text("Checking for updates…")
                Spacer(minLength: 4)
                action("Cancel", perform: updates.cancel)
            case let .available(version, info, informationOnly):
                VStack(alignment: .leading, spacing: 2) {
                    Text("Version \(version) is available.")
                    if let info, !informationOnly {
                        Link("What’s new", destination: info)
                            .font(SettingsStyle.caption)
                    }
                }
                Spacer(minLength: 4)
                action("Later", perform: updates.later)
                action(informationOnly ? "Learn More" : "Install", isPrimary: true, perform: updates.install)
            case let .downloading(fraction):
                Text("Downloading…")
                ProgressView(value: fraction)
                action("Cancel", perform: updates.cancel)
            case let .preparing(fraction):
                Text("Preparing…")
                ProgressView(value: fraction)
            case .readyToInstall:
                Text("Ready to install.")
                Spacer(minLength: 4)
                action("Later", perform: updates.later)
                action("Relaunch", isPrimary: true, perform: updates.install)
            case .installing:
                ProgressView().controlSize(.small)
                Text("Installing…")
                Spacer(minLength: 0)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Update status")
    }

    private func action(_ title: String, isPrimary: Bool = false, perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            Text(title)
                .foregroundStyle(isPrimary ? Color.white : Color.primary)
                .glassControlLabel(width: 84, tint: isPrimary ? .accentColor : nil)
        }
        .buttonStyle(.plain)
    }
}
