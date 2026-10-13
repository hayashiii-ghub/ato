import AppKit
import SwiftUI
import Sparkle

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
    private let store = UsageStore()
    private let updateController = AppUpdateController()
    private lazy var window = UsageWindowController(store: store, updateController: updateController)
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        updateController.start()
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "chart.donut", accessibilityDescription: "Usage Rings")
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Open Usage Rings", action: #selector(show), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Refresh", action: #selector(refresh), keyEquivalent: ""))
        let checkForUpdatesItem = NSMenuItem(
            title: "Check for Updates…",
            action: #selector(SPUStandardUpdaterController.checkForUpdates(_:)),
            keyEquivalent: ""
        )
        menu.addItem(checkForUpdatesItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Usage Rings", action: #selector(quit), keyEquivalent: "q"))
        for entry in menu.items { entry.target = self }
        checkForUpdatesItem.target = updateController.controller
        item.menu = menu
        statusItem = item
        store.startIfEnabled()
        window.show()
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

    @objc private func show() { window.show() }
    @objc private func refresh() { Task { await store.refresh() } }
    @objc private func quit() { NSApp.terminate(nil) }
}
