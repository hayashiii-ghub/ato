// Mirrored by hand in ato? and cc: (Sources/*/Shared). Keep both copies identical.
import AppKit
import ServiceManagement
import SwiftUI

/// A slab of rows with hairlines between them. Its title, if it needs one, sits inside it.
struct SettingsSection<Accessory: View, Content: View>: View {
    private let title: String?
    private let accessory: Accessory
    private let content: Content

    init(_ title: String? = nil, accessory: Accessory = EmptyView(), @ViewBuilder content: () -> Content) {
        self.title = title
        self.accessory = accessory
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let title {
                HStack(spacing: 8) {
                    Text(title)
                        .font(SettingsStyle.heading)
                        .foregroundStyle(.secondary)
                        .accessibilityAddTraits(.isHeader)
                    Spacer(minLength: 0)
                    accessory
                }
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 2)
            }
            Group(subviews: content) { rows in
                ForEach(rows) { row in
                    row
                    if row.id != rows.last?.id {
                        Divider().padding(.leading, 12)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SettingsStyle.card, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

extension View {
    /// The inset every row of a `SettingsSection` shares.
    func settingsCell() -> some View {
        padding(.horizontal, 12)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
            // A minimum-height frame may be squeezed below its content; rows must keep their text.
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// One setting per row: its name on the left, its control on the right edge.
/// The second line is for a state or a problem, not for explaining the setting.
struct SettingsRow<Control: View>: View {
    private let title: String
    private let detail: String?
    private let isWarning: Bool
    private let control: Control

    init(
        _ title: String,
        detail: String? = nil,
        isWarning: Bool = false,
        @ViewBuilder control: () -> Control = { EmptyView() }
    ) {
        self.title = title
        self.detail = detail
        self.isWarning = isWarning
        self.control = control()
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                if let detail {
                    Text(detail)
                        .font(SettingsStyle.caption)
                        .foregroundStyle(isWarning ? Color.orange : Color.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
            control
        }
        .settingsCell()
    }
}

struct SettingsToggle: View {
    private let title: String
    @Binding private var isOn: Bool

    init(_ title: String, isOn: Binding<Bool>) {
        self.title = title
        _isOn = isOn
    }

    var body: some View {
        SettingsRow(title) {
            Toggle(title, isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }
    }
}

/// A line of guidance or a result inside a section, for text that is not itself a setting.
struct SettingsNote: View {
    private let text: String
    private let isWarning: Bool

    init(_ text: String, isWarning: Bool = false) {
        self.text = text
        self.isWarning = isWarning
    }

    var body: some View {
        Text(text)
            .font(SettingsStyle.caption)
            .foregroundStyle(isWarning ? Color.orange : Color.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .settingsCell()
    }
}

enum LaunchAtLogin {
    /// True when macOS started the app as a login item, so it should stay out of the way.
    static var wasLaunchedAtLogin: Bool {
        let event = NSAppleEventManager.shared().currentAppleEvent
        return event?.eventID == kAEOpenApplication
            && event?.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
    }

    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}

/// The settings every background utility needs: starting with the Mac and staying current.
struct SystemSettingsSection: View {
    @ObservedObject var updates: AppUpdateController
    @State private var opensAtLogin = LaunchAtLogin.isEnabled
    @State private var loginError: String?

    var body: some View {
        SettingsSection {
            SettingsToggle("Open at login", isOn: Binding(
                get: { opensAtLogin },
                set: { enabled in
                    do {
                        try LaunchAtLogin.setEnabled(enabled)
                        loginError = nil
                    } catch {
                        loginError = error.localizedDescription
                    }
                    opensAtLogin = LaunchAtLogin.isEnabled
                }
            ))
            if let loginError {
                SettingsNote(loginError, isWarning: true)
            }
            if updates.isConfigured {
                SettingsToggle("Check for updates automatically", isOn: $updates.checksAutomatically)
                SettingsToggle("Install updates automatically", isOn: $updates.installsAutomatically)
                    .disabled(!updates.checksAutomatically)
                    .help("Downloads in the background and installs when you quit.")
            }
        }
        // Login items can also be switched off in System Settings while the panel is open.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            opensAtLogin = LaunchAtLogin.isEnabled
        }
    }
}
