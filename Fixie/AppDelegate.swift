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

        // Get selected text by simulating Cmd+C
        let pasteboard = NSPasteboard.general
        let oldContent = pasteboard.string(forType: .string)

        // Clear and copy
        pasteboard.clearContents()
        simulateCopy()

        // Wait a bit for the copy to complete
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self = self else { return }

            let newContent = pasteboard.string(forType: .string)
            print("[Fixie] Clipboard content after copy: \(newContent ?? "nil")")

            if let selectedText = newContent, !selectedText.isEmpty, selectedText != oldContent {
                self.currentOriginalText = selectedText
                self.checkGrammar(text: selectedText)
            } else {
                // Restore old clipboard content
                if let old = oldContent {
                    pasteboard.clearContents()
                    pasteboard.setString(old, forType: .string)
                }
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
        // Source can be nil - CGEvent still works without it
        let source = CGEventSource(stateID: .hidSystemState)

        // Key down
        if let keyDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_C), keyDown: true) {
            keyDown.flags = .maskCommand
            keyDown.post(tap: .cghidEventTap)
        }

        // Key up
        if let keyUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_C), keyDown: false) {
            keyUp.flags = .maskCommand
            keyUp.post(tap: .cghidEventTap)
        }
    }

    private func checkGrammar(text: String) {
        print("[Fixie] checkGrammar called with: \(text)")
        print("[Fixie] Using provider: \(settingsManager.selectedProvider)")

        let llmService = LLMServiceFactory.create(provider: settingsManager.selectedProvider, settings: settingsManager)

        // Reset streaming state and show window
        streamingState.text = ""
        streamingState.isComplete = false
        showDiffWindow(original: text)

        Task {
            do {
                print("[Fixie] Calling LLM API with streaming...")
                var fullText = ""

                for try await chunk in llmService.correctGrammarStreaming(text: text) {
                    fullText += chunk
                    await MainActor.run {
                        self.streamingState.text = fullText
                    }
                }

                let correctedText = fullText.trimmingCharacters(in: .whitespacesAndNewlines)
                print("[Fixie] Got response: \(correctedText)")
                await MainActor.run {
                    self.currentCorrectedText = correctedText
                    self.streamingState.text = correctedText
                    self.streamingState.isComplete = true
                }
            } catch {
                print("[Fixie] API Error: \(error)")
                await MainActor.run {
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
    }

    private func showDiffWindow(original: String) {
        closeDiffWindow()

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
        guard !currentCorrectedText.isEmpty else { return }

        // Copy corrected text to clipboard
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(currentCorrectedText, forType: .string)

        // Defer window close to avoid crash when called from event monitor callback
        DispatchQueue.main.async { [weak self] in
            self?.closeDiffWindow()

            // Hide our app to return focus to the previous app
            NSApp.hide(nil)

            // Simulate paste after focus returns
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                self?.simulatePaste()
            }
        }
    }

    private func simulatePaste() {
        // Source can be nil - CGEvent still works without it
        let source = CGEventSource(stateID: .hidSystemState)

        // Key down
        if let keyDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true) {
            keyDown.flags = .maskCommand
            keyDown.post(tap: .cghidEventTap)
        }

        // Key up
        if let keyUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false) {
            keyUp.flags = .maskCommand
            keyUp.post(tap: .cghidEventTap)
        }
    }

    private func closeDiffWindow() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
        diffWindow?.close()
        diffWindow = nil
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
