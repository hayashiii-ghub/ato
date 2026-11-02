import AppKit
import SwiftUI

@main
struct UsageRingsMain {
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = UsageRingsApplication()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { app.run() }
    }
}

@MainActor
final class UsageRingsApplication: NSObject, NSApplicationDelegate {
    private lazy var notifications: UsageNotificationController = UsageNotificationController(onOpen: { [weak self] in self?.window.show() })
    private lazy var store: UsageStore = UsageStore(onSnapshot: { [weak self] snapshot in
        self?.notifications.update(snapshot)
    })
    private let updateController = AppUpdateController()
    private let widgetRecovery = UsageWidgetRecovery()
    private lazy var window: UsageWindowController = UsageWindowController(store: store, updateController: updateController, notifications: notifications)

    func applicationDidFinishLaunching(_ notification: Notification) {
        updateController.start()
        store.startIfEnabled()
        window.show()
        Task { await widgetRecovery.recoverIfNeeded() }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard urls.contains(where: { $0.scheme == "usagerings" && $0.host == "usage" }) else { return }
        window.show()
        Task { await store.refresh() }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        window.show()
        return true
    }
}
