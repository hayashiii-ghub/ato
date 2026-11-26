// Mirrored by hand in ato? and cc: (Sources/*/Shared). Keep both copies identical.
import AppKit
import SwiftUI

/// One bar at the foot of every screen. Update progress happens inside it: a result sits beside the
/// button for a moment, and a step that needs an answer borrows the whole bar until it has one.
struct SettingsFooter: View {
    @ObservedObject var updates: AppUpdateController
    let helpURL: URL
    var isBusy = false

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 8) {
                switch updates.status {
                case .idle:
                    resting(result: nil, isError: false)
                case let .message(text, isError):
                    resting(result: text, isError: isError)
                case .checking:
                    progress("Checking…", value: nil, spins: true)
                    Spacer(minLength: 4)
                    action("Cancel", perform: updates.cancel)
                case .askingPermission:
                    Text("Check for updates automatically?")
                    Spacer(minLength: 4)
                    action("No") { updates.allowAutomaticChecks(false) }
                    action("Yes", isPrimary: true) { updates.allowAutomaticChecks(true) }
                case let .available(version, info, informationOnly):
                    VStack(alignment: .leading, spacing: 1) {
                        Text("\(version) is available")
                        if let info, !informationOnly {
                            Link("What’s new", destination: info)
                                .font(SettingsStyle.caption)
                        }
                    }
                    Spacer(minLength: 4)
                    action("Later", perform: updates.later)
                    action(informationOnly ? "Learn More" : "Install", isPrimary: true, perform: updates.install)
                case let .downloading(fraction):
                    progress("Downloading…", value: fraction, spins: false)
                    action("Cancel", perform: updates.cancel)
                case let .preparing(fraction):
                    progress("Preparing…", value: fraction, spins: false)
                case .readyToInstall:
                    Text("Ready to install")
                    Spacer(minLength: 4)
                    action("Later", perform: updates.later)
                    action("Relaunch", isPrimary: true, perform: updates.install)
                case .installing:
                    progress("Installing…", value: nil, spins: true)
                    Spacer(minLength: 4)
                }
            }
            .padding(.leading, updates.status.borrowsBar ? 16 : 10)
            .padding(.trailing, 10)
            .frame(height: 48)
        }
    }

    @ViewBuilder private func resting(result: String?, isError: Bool) -> some View {
        Button(action: updates.checkForUpdates) {
            Text("Updates…").glassControlLabel()
        }
        .buttonStyle(.plain)
        .disabled(!updates.canCheckForUpdates || isBusy)
        if let result {
            Text(result)
                .font(SettingsStyle.caption)
                .foregroundStyle(isError ? Color.orange : Color.secondary)
                .lineLimit(2)
                .help(result)
        }
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

    @ViewBuilder private func progress(_ title: String, value: Double?, spins: Bool) -> some View {
        if spins {
            ProgressView().controlSize(.small)
            Text(title)
        } else {
            Text(title)
            ProgressView(value: value)
        }
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

private extension AppUpdateController.Status {
    /// Steps that replace the bar's usual buttons start with text, which wants the content inset.
    var borrowsBar: Bool {
        switch self {
        case .idle, .message: false
        default: true
        }
    }
}
