import AppKit
import SwiftUI

@MainActor
final class UsageWindowController {
    private let store: UsageStore
    private let updateController: AppUpdateController
    private let notifications: UsageNotificationController
    private var window: NSWindow?

    init(store: UsageStore, updateController: AppUpdateController, notifications: UsageNotificationController) {
        self.store = store
        self.updateController = updateController
        self.notifications = notifications
    }

    func show() {
        if window == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 440, height: 500),
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            window.title = "ato?"
            window.isReleasedWhenClosed = false
            window.contentMinSize = NSSize(width: 440, height: 400)
            window.contentMaxSize = NSSize(width: 560, height: 720)
            let content = NSHostingView(rootView:
                UsageDetailsView(store: store, updateController: updateController, notifications: notifications)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            )
            // Keep the window size stable when its content changes.
            content.sizingOptions = []
            window.contentView = content
            window.center()
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
