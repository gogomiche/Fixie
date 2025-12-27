import Cocoa
import SwiftUI

/// Manages the grammar correction popup window
class PopupWindowManager {
    static let shared = PopupWindowManager()

    private var window: NSWindow?
    private var keyEventMonitor: Any?
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

        // Create borderless floating panel
        let panel = NSPanel(
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
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = true

        // Ensure window has no visible border
        if let contentView = panel.contentView {
            contentView.wantsLayer = true
            contentView.layer?.cornerRadius = 20
            contentView.layer?.masksToBounds = true
        }

        panel.center()
        panel.makeKeyAndOrderFront(nil)

        // Handle keyboard events
        keyEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return event }
            if event.keyCode == 36 { // Enter key
                if streamingState.isComplete {
                    self.onAccept?()
                }
                return nil
            } else if event.keyCode == 53 { // Escape key
                self.onReject?()
                return nil
            }
            return event
        }

        // Handle click outside to close
        clickEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self = self, let window = self.window else { return }
            let clickLocation = event.locationInWindow
            let windowFrame = window.frame

            // Convert screen coordinates
            let screenLocation = NSEvent.mouseLocation

            if !windowFrame.contains(screenLocation) {
                self.onReject?()
            }
        }

        window = panel
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Close the popup window
    func closeWindow() {
        if let monitor = keyEventMonitor {
            NSEvent.removeMonitor(monitor)
            keyEventMonitor = nil
        }
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
