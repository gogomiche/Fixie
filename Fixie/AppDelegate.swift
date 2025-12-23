import Cocoa
import SwiftUI
import Carbon.HIToolbox
import UserNotifications

class StreamingState: ObservableObject {
    @Published var text: String = ""
    @Published var isComplete: Bool = false
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var settingsManager = SettingsManager()
    var hotkeyManager: HotkeyManager!
    var diffWindow: NSWindow?
    var settingsWindow: NSWindow?
    var currentOriginalText: String = ""
    var currentCorrectedText: String = ""
    var streamingState = StreamingState()
    var eventMonitor: Any?
    var savedClipboardContent: String?
    var usedAccessibilityForRead: Bool = false
    var isProcessing: Bool = false  // Prevent race conditions from multiple triggers
    var currentTask: Task<Void, Never>?  // Track current streaming task for cancellation
    var savedFocusedElement: AXUIElement?  // Save the original focused element to write back to

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupHotkey()

        // Request accessibility permissions if needed
        requestAccessibilityPermissions()

        // Request notification permissions
        requestNotificationPermissions()
    }

    private func setupHotkey() {
        hotkeyManager = HotkeyManager(settingsManager: settingsManager)
        hotkeyManager.onHotkeyPressed = { [weak self] in
            self?.triggerGrammarCheck()
        }
        hotkeyManager.register()
    }

    private func requestAccessibilityPermissions() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        AXIsProcessTrustedWithOptions(options as CFDictionary)
    }
    
    private func requestNotificationPermissions() {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error = error {
                print("Notification permission error: \(error)")
            }
        }
    }

    @objc func triggerGrammarCheck() {
        print("[Fixie] triggerGrammarCheck called")

        // Prevent race conditions - ignore if already processing
        guard !isProcessing else {
            print("[Fixie] Already processing, ignoring trigger")
            return
        }

        // Check accessibility permissions first
        let trusted = AXIsProcessTrusted()
        print("[Fixie] Accessibility trusted: \(trusted)")

        if !trusted {
            // Show alert about permissions
            let alert = NSAlert()
            alert.messageText = "Accessibility Permission Required"
            alert.informativeText = "Fixie needs Accessibility permission to capture selected text.\n\nPlease enable it in System Settings → Privacy & Security → Accessibility"
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Open System Settings")
            alert.addButton(withTitle: "Cancel")

            NSApp.activate(ignoringOtherApps: true)
            let response = alert.runModal()

            if response == .alertFirstButtonReturn {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
            }
            return
        }

        // Try Accessibility API first (doesn't touch clipboard)
        if let selectedText = getSelectedTextViaAccessibility() {
            print("[Fixie] Got text via Accessibility API")
            usedAccessibilityForRead = true
            currentOriginalText = selectedText
            checkGrammar(text: selectedText)
            return
        }

        // Fall back to clipboard simulation
        print("[Fixie] Falling back to clipboard simulation")
        usedAccessibilityForRead = false

        // Save current clipboard content to restore later if user cancels
        let pasteboard = NSPasteboard.general
        savedClipboardContent = pasteboard.string(forType: .string)

        // Clear and copy selected text
        pasteboard.clearContents()
        simulateCopy()

        // Wait a bit for the copy to complete
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self = self else { return }

            let newContent = pasteboard.string(forType: .string)
            print("[Fixie] Clipboard content after copy: \(newContent ?? "nil")")

            if let selectedText = newContent, !selectedText.isEmpty, selectedText != self.savedClipboardContent {
                self.currentOriginalText = selectedText
                self.checkGrammar(text: selectedText)
            } else {
                // Restore original clipboard content
                self.restoreClipboard()
                // Show alert instead of notification for better visibility
                let alert = NSAlert()
                alert.messageText = "No Text Selected"
                alert.informativeText = "Please select some text first, then trigger Fixie."
                alert.alertStyle = .informational
                alert.addButton(withTitle: "OK")
                NSApp.activate(ignoringOtherApps: true)
                alert.runModal()
            }
        }
    }

    private func simulateCopy() {
        // Create a new event source for each operation
        let source = CGEventSource(stateID: .combinedSessionState)

        // Create both events upfront
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_C), keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_C), keyDown: false) else {
            print("[Fixie] ERROR: Could not create CGEvent for copy")
            return
        }

        // Set command modifier
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand

        // Post key down
        keyDown.post(tap: .cgSessionEventTap)

        // Small delay between key down and up
        Thread.sleep(forTimeInterval: 0.02)  // 20ms

        // Post key up
        keyUp.post(tap: .cgSessionEventTap)
    }

    private func checkGrammar(text: String) {
        print("[Fixie] checkGrammar called with: \(text)")
        print("[Fixie] Using provider: \(settingsManager.selectedProvider)")

        // Cancel any existing task
        currentTask?.cancel()

        // Mark as processing
        isProcessing = true

        let llmService = LLMServiceFactory.create(provider: settingsManager.selectedProvider, settings: settingsManager)

        // Reset streaming state and show window
        streamingState.text = ""
        streamingState.isComplete = false
        currentCorrectedText = ""  // Also reset this to prevent stale data
        showDiffWindow(original: text)

        currentTask = Task { @MainActor [weak self] in
            guard let self = self else { return }

            defer {
                // Always reset processing state when done
                self.isProcessing = false
                self.currentTask = nil
            }

            do {
                // Check for cancellation
                try Task.checkCancellation()

                print("[Fixie] Calling LLM API with streaming...")
                var fullText = ""

                for try await chunk in llmService.correctGrammarStreaming(text: text) {
                    // Check for cancellation between chunks
                    try Task.checkCancellation()
                    fullText += chunk
                    self.streamingState.text = fullText
                }

                // Final cancellation check before completing
                try Task.checkCancellation()

                let correctedText = fullText.trimmingCharacters(in: .whitespacesAndNewlines)
                print("[Fixie] Got response: \(correctedText)")
                self.currentCorrectedText = correctedText
                self.streamingState.text = correctedText
                self.streamingState.isComplete = true
            } catch is CancellationError {
                print("[Fixie] Task was cancelled")
                // Don't show error for cancellation
            } catch {
                print("[Fixie] API Error: \(error)")
                self.closeDiffWindow()
                let alert = NSAlert()
                alert.messageText = "Fixie Error"
                alert.informativeText = error.localizedDescription
                alert.alertStyle = .critical
                alert.addButton(withTitle: "OK")
                NSApp.activate(ignoringOtherApps: true)
                alert.runModal()
            }
        }
    }

    private func showDiffWindow(original: String) {
        // Close any existing window without clearing savedFocusedElement
        // (we need it for writing back later)
        currentTask?.cancel()
        currentTask = nil
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
        diffWindow?.close()
        diffWindow = nil

        let diffView = StreamingDiffPopupView(
            originalText: original,
            streamingState: streamingState,
            onAccept: { [weak self] in
                self?.acceptCorrection()
            },
            onReject: { [weak self] in
                self?.closeDiffWindow()
            }
        )

        let hostingView = NSHostingView(rootView: diffView)

        // Calculate window size based on content
        let width: CGFloat = 500
        let height: CGFloat = min(400, max(150, CGFloat(original.count / 2) + 100))

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )

        window.contentView = hostingView
        window.title = "Fixie - Grammar Check"
        window.level = .floating
        window.center()
        window.makeKeyAndOrderFront(nil)

        // Handle keyboard events
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return event }
            if event.keyCode == 36 && self.streamingState.isComplete { // Enter key
                self.acceptCorrection()
                return nil
            } else if event.keyCode == 53 { // Escape key
                self.closeDiffWindow()
                return nil
            }
            return event
        }

        diffWindow = window
        NSApp.activate(ignoringOtherApps: true)
    }

    private func acceptCorrection() {
        guard !currentCorrectedText.isEmpty else {
            print("[Fixie] acceptCorrection called but correctedText is empty, ignoring")
            return
        }

        // Capture the text we need to paste (avoid race conditions)
        let textToPaste = currentCorrectedText
        print("[Fixie] acceptCorrection called with: \(textToPaste.prefix(50))...")

        // Defer to avoid crash when called from event monitor callback
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            // Remove event monitor first
            if let monitor = self.eventMonitor {
                NSEvent.removeMonitor(monitor)
                self.eventMonitor = nil
            }
            print("[Fixie] Event monitor removed")

            // Just hide the window (orderOut), don't close it yet - closing triggers SwiftUI crash
            self.diffWindow?.orderOut(nil)
            print("[Fixie] Window hidden")

            // Deactivate our app to return focus to previous app
            NSApp.deactivate()
            print("[Fixie] App deactivated")

            // Small delay to let the system settle, then write text
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                guard let self = self else { return }

                // Try Accessibility API first using saved element (doesn't touch clipboard)
                if self.setSelectedTextViaAccessibility(textToPaste) {
                    print("[Fixie] Text replaced via Accessibility API")
                    self.restoreClipboard()
                } else {
                    // Fall back to clipboard + paste
                    print("[Fixie] Falling back to clipboard + paste")
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(textToPaste, forType: .string)

                    self.simulatePaste()
                    print("[Fixie] Paste simulated")

                    // Restore original clipboard after paste completes
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                        self?.restoreClipboard()
                        print("[Fixie] Clipboard restored")
                    }
                }

                // Close window and reset state
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                    self?.diffWindow?.close()
                    self?.diffWindow = nil
                    self?.isProcessing = false
                    self?.savedFocusedElement = nil
                    print("[Fixie] Window closed (deferred)")
                }
            }
        }
    }

    private func simulatePaste() {
        // Create a new event source for each operation
        let source = CGEventSource(stateID: .combinedSessionState)
        print("[Fixie] simulatePaste - source: \(source != nil ? "created" : "nil")")

        // Create both events upfront
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false) else {
            print("[Fixie] ERROR: Could not create CGEvent for paste")
            return
        }

        // Set command modifier
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand

        // Post key down
        keyDown.post(tap: .cgSessionEventTap)
        print("[Fixie] Cmd+V keyDown posted")

        // Use RunLoop-friendly delay instead of blocking usleep
        Thread.sleep(forTimeInterval: 0.02)  // 20ms

        // Post key up
        keyUp.post(tap: .cgSessionEventTap)
        print("[Fixie] Cmd+V keyUp posted")
    }

    private func closeDiffWindow() {
        // Cancel any ongoing task
        currentTask?.cancel()
        currentTask = nil

        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
        diffWindow?.close()
        diffWindow = nil

        // Reset processing state
        isProcessing = false

        // Clear saved accessibility element
        savedFocusedElement = nil

        // Restore original clipboard content when user cancels
        restoreClipboard()
    }

    private func restoreClipboard() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        if let saved = savedClipboardContent {
            pasteboard.setString(saved, forType: .string)
        }
        savedClipboardContent = nil
    }

    // MARK: - Accessibility API Methods

    private func getSelectedTextViaAccessibility() -> String? {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedElement: CFTypeRef?

        let focusResult = AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &focusedElement
        )

        guard focusResult == .success, let element = focusedElement else {
            print("[Fixie] Accessibility: Could not get focused element")
            return nil
        }

        // Safe cast - CFTypeRef to AXUIElement
        let axElement = element as! AXUIElement  // This is safe because AXUIElementCopyAttributeValue for kAXFocusedUIElementAttribute always returns AXUIElement

        var selectedText: CFTypeRef?
        let textResult = AXUIElementCopyAttributeValue(
            axElement,
            kAXSelectedTextAttribute as CFString,
            &selectedText
        )

        guard textResult == .success, let text = selectedText as? String, !text.isEmpty else {
            print("[Fixie] Accessibility: Could not get selected text")
            return nil
        }

        // Save the focused element for later use when writing back
        savedFocusedElement = axElement
        print("[Fixie] Accessibility: Saved focused element for later")

        print("[Fixie] Accessibility: Got selected text: \(text.prefix(50))...")
        return text
    }

    private func setSelectedTextViaAccessibility(_ text: String) -> Bool {
        // First, try to use the saved focused element (most reliable)
        if let savedElement = savedFocusedElement {
            let setResult = AXUIElementSetAttributeValue(
                savedElement,
                kAXSelectedTextAttribute as CFString,
                text as CFTypeRef
            )

            if setResult == .success {
                print("[Fixie] Accessibility: Successfully set selected text via saved element")
                savedFocusedElement = nil  // Clear after use
                return true
            } else {
                print("[Fixie] Accessibility: Failed to set via saved element (error: \(setResult.rawValue)), trying current focus")
            }
        }

        // Fall back to getting current focused element
        let systemWide = AXUIElementCreateSystemWide()
        var focusedElement: CFTypeRef?

        let focusResult = AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &focusedElement
        )

        guard focusResult == .success, let element = focusedElement else {
            print("[Fixie] Accessibility: Could not get focused element for writing")
            return false
        }

        // Safe cast - CFTypeRef to AXUIElement
        let axElement = element as! AXUIElement

        let setResult = AXUIElementSetAttributeValue(
            axElement,
            kAXSelectedTextAttribute as CFString,
            text as CFTypeRef
        )

        if setResult == .success {
            print("[Fixie] Accessibility: Successfully set selected text via current focus")
            return true
        } else {
            print("[Fixie] Accessibility: Failed to set selected text (error: \(setResult.rawValue))")
            return false
        }
    }

    private func showNotification(title: String, message: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = message
        content.sound = .default
        
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil // nil trigger means deliver immediately
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Error showing notification: \(error)")
            }
        }
    }

    @objc func openSettings() {
        if settingsWindow == nil {
            let settingsView = SettingsView()
                .environmentObject(settingsManager)

            let hostingController = NSHostingController(rootView: settingsView)

            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 450, height: 350),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.contentViewController = hostingController
            window.title = "Fixie Settings"
            window.center()
            window.isReleasedWhenClosed = false

            settingsWindow = window
        }

        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

}
