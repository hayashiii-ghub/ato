// Mirrored by hand in ato? and cc: (Sources/*/Shared). Keep both copies identical.
import AppKit
import SwiftUI

enum SettingsStyle {
    static let body = Font.system(size: 13)
    static let heading = Font.system(size: 12, weight: .semibold)
    static let caption = Font.system(size: 11)
    static let statusSymbol = Font.system(size: 12, weight: .medium)
    /// The panel itself. It matches the app icon's own background in each appearance,
    /// so the icon macOS overlays on the window in Stage Manager does not stand apart from it.
    static let surface = adaptive(light: 0xF2F2F2, dark: 0x171717)
    /// Slabs of rows, one step off the surface.
    static let card = adaptive(light: 0xFFFFFF, dark: 0x232324)

    private static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let hex = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255,
                           blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
        })
    }
}

struct SettingsIcon: View {
    let name: String
    var isDisclosure = false

    var body: some View {
        Image(systemName: name)
            .font(.system(size: isDisclosure ? 12 : 14, weight: isDisclosure ? .semibold : .medium))
            .frame(width: isDisclosure ? 32 : 28, height: isDisclosure ? 32 : 28)
            .contentShape(Rectangle())
    }
}

extension View {
    func glassControlLabel(width: CGFloat = 94, tint: Color? = nil) -> some View {
        self
            .font(.system(size: 13, weight: .medium))
            .lineLimit(1)
            .minimumScaleFactor(0.85)
            .frame(width: width, height: 32)
            .contentShape(Capsule())
            .glassEffect(.regular.tint(tint).interactive(), in: Capsule())
    }
}

struct GlassIconButton: View {
    let title: LocalizedStringKey
    let image: Image
    let glyphSize: CGFloat
    let action: () -> Void

    init(_ title: LocalizedStringKey, systemImage: String, glyphSize: CGFloat = 18, action: @escaping () -> Void) {
        self.init(title, image: Image(systemName: systemImage), glyphSize: glyphSize, action: action)
    }

    init(_ title: LocalizedStringKey, image: Image, glyphSize: CGFloat = 18, action: @escaping () -> Void) {
        self.title = title
        self.image = image
        self.glyphSize = glyphSize
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            image
                .resizable()
                .scaledToFit()
                .frame(width: glyphSize, height: glyphSize)
                .glassControlLabel(width: 32)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(title))
        .help(Text(title))
    }
}

private struct ReportPanelHeightKey: EnvironmentKey {
    static let defaultValue: @MainActor (CGFloat) -> Void = { _ in }
}

extension EnvironmentValues {
    /// How the chrome tells its window the height its content needs.
    fileprivate var reportPanelHeight: @MainActor (CGFloat) -> Void {
        get { self[ReportPanelHeightKey.self] }
        set { self[ReportPanelHeightKey.self] = newValue }
    }
}

/// The panel's frame: a title bar to drag, the host's slabs, and an optional footer.
/// Passing `onBack` marks a second-level screen. The window follows the height this needs.
struct PanelChrome<Actions: View, Content: View, Footer: View>: View {
    private static var headerHeight: CGFloat { 48 }

    private let title: String
    private let onBack: (() -> Void)?
    private let onClose: () -> Void
    private let actions: Actions
    private let content: Content
    private let footer: Footer

    init(
        title: String,
        onBack: (() -> Void)? = nil,
        onClose: @escaping () -> Void,
        @ViewBuilder actions: () -> Actions = { EmptyView() },
        @ViewBuilder content: () -> Content,
        @ViewBuilder footer: () -> Footer
    ) {
        self.title = title
        self.onBack = onBack
        self.onClose = onClose
        self.actions = actions()
        self.content = content()
        self.footer = footer()
    }

    @Environment(\.reportPanelHeight) private var reportHeight
    @State private var contentHeight: CGFloat = 0
    @State private var footerHeight: CGFloat = 0

    private var version: String? {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                if let onBack {
                    GlassIconButton("Back", systemImage: "chevron.left", glyphSize: 12, action: onBack)
                }
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(title)
                    if onBack == nil, let version {
                        Text(version)
                            .font(.system(size: 11, weight: .medium).monospacedDigit())
                            .foregroundStyle(.tertiary)
                            .accessibilityLabel("Version \(version)")
                    }
                }
                .allowsHitTesting(false)
                Spacer(minLength: 4)
                actions
                GlassIconButton("Close", systemImage: "xmark", glyphSize: 12, action: onClose)
            }
            .font(.system(size: 20, weight: .bold, design: .rounded))
            .padding(.leading, onBack == nil ? 16 : 10)
            .padding(.trailing, 10)
            .frame(height: Self.headerHeight)
            .background(WindowDragArea())

            // Scrolling only matters when the content is taller than the screen allows the window to be.
            ScrollView {
                content
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding([.horizontal, .bottom], 10)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
            }

            footer
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { footerHeight = $0 }
        }
        .onChange(of: contentHeight + footerHeight, initial: true) { _, measured in
            if contentHeight > 0 { reportHeight(Self.headerHeight + measured) }
        }
        .font(SettingsStyle.body)
        .controlSize(.regular)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(SettingsStyle.surface)
        .overlay {
            shape.strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5)
                .allowsHitTesting(false)
        }
        .clipShape(shape)
    }
}

private struct WindowDragArea: NSViewRepresentable {
    final class DragView: NSView {
        override func mouseDown(with event: NSEvent) {
            window?.performDrag(with: event)
        }
    }

    func makeNSView(context: Context) -> NSView { DragView() }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

@MainActor
final class PanelController: NSObject, NSWindowDelegate {
    private let title: String
    private let size: NSSize
    private let onClose: () -> Void
    private let content: (_ close: @escaping () -> Void) -> AnyView
    private var window: NSWindow?
    private var hostingController: NSHostingController<AnyView>?

    init<Content: View>(
        title: String,
        size: NSSize,
        onClose: @escaping () -> Void = {},
        content: @escaping (_ close: @escaping () -> Void) -> Content
    ) {
        self.title = title
        // The width, and the height to open at before the content has been measured.
        self.size = size
        self.onClose = onClose
        self.content = { AnyView(content($0)) }
    }

    func show() {
        let window = window ?? makeWindow()
        let isOpening = !window.isVisible
        hostingController?.rootView = rootView
        fitToScreen(window)
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        // A scheduled update can ask for the panel while another app is active.
        window.orderFrontRegardless()
        if isOpening {
            window.makeFirstResponder(nil)
        }
    }

    func windowWillClose(_ notification: Notification) {
        onClose()
    }

    /// Follows the content: taller when a warning appears, shorter when it clears, as tall as each screen needs.
    /// The top edge stays put, and the screen caps the height so longer content scrolls instead.
    private func fit(height: CGFloat) {
        guard let window, let screen = window.screen ?? NSScreen.main else { return }
        let available = screen.visibleFrame.insetBy(dx: 12, dy: 12)
        var frame = window.frame
        let target = min(height.rounded(.up), available.height)
        guard abs(frame.height - target) >= 1 else { return }
        frame.origin.y = max(frame.maxY - target, available.minY)
        frame.size.height = target
        guard window.isVisible else { return window.setFrame(frame, display: false) }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            window.animator().setFrame(frame, display: true)
        }
    }

    func windowDidResize(_ notification: Notification) {
        // The shadow follows the rounded sheet, which AppKit does not track for a clear window.
        window?.invalidateShadow()
    }

    private var rootView: AnyView {
        AnyView(
            content { [weak self] in self?.window?.close() }
                .environment(\.reportPanelHeight) { [weak self] in self?.fit(height: $0) }
        )
    }

    private func makeWindow() -> NSWindow {
        let window = PanelWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        self.window = window
        window.title = title
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.isReleasedWhenClosed = false
        window.delegate = self

        let hostingController = NSHostingController(rootView: rootView)
        // Keep the panel size stable when its content changes.
        hostingController.sizingOptions = []
        window.contentViewController = hostingController
        window.setContentSize(size)
        window.center()
        self.hostingController = hostingController
        return window
    }

    private func fitToScreen(_ window: NSWindow) {
        guard let screen = window.screen ?? NSScreen.main else { return }
        let available = screen.visibleFrame.insetBy(dx: 12, dy: 12)
        var frame = window.frame
        frame.size.width = min(frame.width, available.width)
        frame.size.height = min(frame.height, available.height)
        frame.origin.x = min(max(frame.minX, available.minX), available.maxX - frame.width)
        frame.origin.y = min(max(frame.minY, available.minY), available.maxY - frame.height)
        window.setFrame(frame, display: true)
    }
}

private final class PanelWindow: NSWindow {
    // Borderless windows refuse key status by default, which would block text fields and shortcuts.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        guard modifiers == [.command] else { return super.performKeyEquivalent(with: event) }
        switch event.charactersIgnoringModifiers?.lowercased() {
        case "w":
            // performClose needs a close button, which a borderless window lacks.
            close()
            return true
        case "q":
            // Handled here so the shortcut works whichever control has focus.
            NSApp.terminate(nil)
            return true
        default:
            return super.performKeyEquivalent(with: event)
        }
    }
}
