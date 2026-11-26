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
    // Owned here rather than by the view so quitting can wait for an install in progress.
    private let agentTools = AgentToolsController()
    private lazy var window = PanelController(
        title: "ato?",
        size: NSSize(width: 400, height: 395),
        onClose: { [unowned self] in updateController.clearResult() }
    ) { [unowned self] close in
        UsageDetailsView(store: store, updateController: updateController, notifications: notifications,
                         agentTools: agentTools, onClose: close)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        updateController.onNeedsAttention = { [weak self] in self?.window.show() }
        updateController.start()
        store.startIfEnabled()
        if !LaunchAtLogin.wasLaunchedAtLogin { window.show() }
        Task { await widgetRecovery.recoverIfNeeded() }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard urls.contains(where: { $0.scheme == "usagerings" && $0.host == "usage" }) else { return }
        window.show()
        Task { await store.refresh() }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        agentTools.isWorking ? .terminateCancel : .terminateNow
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        window.show()
        return true
    }
}
