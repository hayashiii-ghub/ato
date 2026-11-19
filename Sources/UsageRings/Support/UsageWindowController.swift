import AppKit
import SwiftUI

@MainActor
final class UsageWindowController: NSObject {
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
            let available = NSScreen.main?.visibleFrame.insetBy(dx: 12, dy: 12)
            let size = NSSize(width: min(380, available?.width ?? 380),
                              height: min(482, available?.height ?? 482))
            let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
            self.window = window
            window.title = "ato?"
            window.isOpaque = false
            window.backgroundColor = .clear
            window.titlebarAppearsTransparent = true
            window.isReleasedWhenClosed = false
            window.contentMinSize = NSSize(width: 380, height: 400)
            window.contentMaxSize = NSSize(width: 800, height: CGFloat.greatestFiniteMagnitude)
            let content = NSHostingView(rootView:
                UsageDetailsView(store: store, updateController: updateController, notifications: notifications)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            )
            // Keep the window size stable when its content changes.
            content.sizingOptions = []
            window.contentView = content
            window.center()
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
