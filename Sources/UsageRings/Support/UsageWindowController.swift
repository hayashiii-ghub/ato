import AppKit
import SwiftUI

@MainActor
final class UsageWindowController {
    private let store: UsageStore
    private let updateController: AppUpdateController
    private var window: NSWindow?

    init(store: UsageStore, updateController: AppUpdateController) {
        self.store = store
        self.updateController = updateController
    }

    func show() {
        if window == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 508, height: 680),
                                  styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
            window.title = "ato?"
            window.isReleasedWhenClosed = false
            let content = NSHostingView(rootView:
                UsageDetailsView(store: store, updateController: updateController)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            )
            // This window owns its size; changing pages must not resize it to their ideal heights.
            content.sizingOptions = []
            window.contentView = content
            window.center()
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
