import Cocoa
import SwiftUI

/// NSPanel subclass that intercepts key events directly,
/// allowing the popup to work without activating the app (critical for full-screen).
private class FixiePanel: NSPanel {
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
        onAccept: @escaping () -> Void,
        onReject: @escaping () -> Void
    ) {
        // Close any existing window
        closeWindow()

        // Save the currently active application to restore focus later
        previousApp = NSWorkspace.shared.frontmostApplication

        self.onAccept = onAccept
        self.onReject = onReject

        // Get the source app icon
        let sourceAppIcon = previousApp?.icon

        let popupView = StreamingGrammarPopupView(
            originalText: originalText,
            streamingState: streamingState,
            providerName: providerName,
            sourceAppIcon: sourceAppIcon,
            onAccept: { [weak self] in
                self?.onAccept?()
            },
            onReject: { [weak self] in
                self?.onReject?()
            }
        )

        let hostingView = NSHostingView(rootView: popupView)

        // Calculate window size based on content
        let width: CGFloat = 600
        let height: CGFloat = min(500, max(250, CGFloat(originalText.count / 2) + 150))

        // Create borderless floating panel (FixiePanel handles keys without app activation)
        let panel = FixiePanel(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        // Make hosting view transparent
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = .clear

        panel.contentView = hostingView
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        // popUpMenu level (101) ensures the panel appears above full-screen windows
        panel.level = .popUpMenu
        // moveToActiveSpace: panel moves to the current space (including full-screen)
        // so NSApp.activate won't cause a space switch
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = true

        // Ensure window has no visible border
        if let contentView = panel.contentView {
            contentView.wantsLayer = true
            contentView.layer?.cornerRadius = 20
            contentView.layer?.masksToBounds = true
        }

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
                NotificationCenter.default.post(name: .toggleMarkdownPreview, object: nil)
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
