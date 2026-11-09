import Cocoa
import SwiftUI

/// NSPanel subclass that intercepts key events directly,
/// allowing the popup to work without activating the app (critical for full-screen).
final class FixiePanel: NSPanel {
    var onKeyHandler: ((UInt16) -> Bool)?

    override var canBecomeKey: Bool { true }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown,
           let handler = onKeyHandler,
           handler(event.keyCode) {
            return
        }
        super.sendEvent(event)
    }
}

/// Manages the grammar correction popup window
class PopupWindowManager {
    static let shared = PopupWindowManager()

    private var window: NSWindow?
    private var clickEventMonitor: Any?
    private var previousApp: NSRunningApplication?

    var onAccept: (() -> Void)?
    var onReject: (() -> Void)?

    private init() {}

    /// Show the grammar popup window
    func showPopup(
        originalText: String,
        streamingState: StreamingState,
        providerName: String,
        mode: GrammarMode,
        onAccept: @escaping () -> Void,
        onReject: @escaping () -> Void
    ) {
        // Close any existing window
        closeWindow()

        // Save the currently active application to restore focus later
        previousApp = NSWorkspace.shared.frontmostApplication

        self.onAccept = onAccept
        self.onReject = onReject

        let popupView = StreamingGrammarPopupView(
            originalText: originalText,
            streamingState: streamingState,
            providerName: providerName,
            sourceAppIcon: previousApp?.icon,
            sourceAppName: previousApp?.localizedName,
            mode: mode,
            onAccept: { [weak self] in
                self?.onAccept?()
            },
            onReject: { [weak self] in
                self?.onReject?()
            }
        )

        let panel = Self.makePanel(rootView: popupView, size: Self.panelSize(for: originalText))

        // Key handling via panel subclass (no local event monitor needed)
        panel.onKeyHandler = { [weak self] keyCode in
            guard let self = self else { return false }
            switch keyCode {
            case 36: // Enter
                if streamingState.isComplete {
                    self.onAccept?()
                }
                return true
            case 53: // Escape
                self.onReject?()
                return true
            case 48: // Tab
                NotificationCenter.default.post(name: .togglePopupResult, object: nil)
                return true
            default:
                return false
            }
        }

        panel.center()
        panel.makeKeyAndOrderFront(nil)

        // Handle click outside to close
        clickEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self = self, let window = self.window else { return }

            let screenLocation = NSEvent.mouseLocation
            if !window.frame.contains(screenLocation) {
                self.onReject?()
            }
        }

        window = panel
        // Activate AFTER the panel is on the current space (moveToActiveSpace)
        // so macOS doesn't switch to a different space.
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Popup size, growing with the text to correct.
    static func panelSize(for originalText: String) -> NSSize {
        NSSize(width: 600, height: min(500, max(270, CGFloat(originalText.count / 2) + 170)))
    }

    /// Borderless floating panel with a Liquid Glass background
    /// (`FixiePanel` handles keys without activating the app).
    static func makePanel<Content: View>(rootView: Content, size: NSSize) -> FixiePanel {
        let panel = FixiePanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        let hostingView = NSHostingView(rootView: rootView)
        // The panel keeps the size computed above instead of following the SwiftUI layout
        hostingView.sizingOptions = []
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = .clear

        panel.contentView = GlassPanelBackground.wrap(hostingView, cornerRadius: PopupMetrics.cornerRadius)
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        // popUpMenu level (101) ensures the panel appears above full-screen windows
        panel.level = .popUpMenu
        // moveToActiveSpace: panel moves to the current space (including full-screen)
        // so NSApp.activate won't cause a space switch
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = true
        return panel
    }

    /// Close the popup window
    func closeWindow() {
        if let monitor = clickEventMonitor {
            NSEvent.removeMonitor(monitor)
            clickEventMonitor = nil
        }
        window?.close()
        window = nil
        onAccept = nil
        onReject = nil

        // Restore focus to the previous application
        if let app = previousApp {
            app.activate(options: [])
            previousApp = nil
        }
    }

    /// Hide the window without closing (for deferred close)
    func hideWindow() {
        window?.orderOut(nil)
    }

    /// Close window after a delay
    func closeWindowDeferred(delay: TimeInterval = 0.1) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.closeWindow()
        }
    }

    /// Check if window is currently shown
    var isWindowShown: Bool {
        window != nil
    }
}
