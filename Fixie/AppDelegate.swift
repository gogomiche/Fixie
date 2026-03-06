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
    var settingsWindow: NSWindow?

    // Grammar check state
    var currentOriginalText: String = ""
    var currentCorrectedText: String = ""
    var streamingState = StreamingState()
    var usedAccessibilityForRead: Bool = false
    var isProcessing: Bool = false
    var currentTask: Task<Void, Never>?
    var previousApp: NSRunningApplication?  // Saved BEFORE showing popup

    // Managers
    private let accessibilityManager = AccessibilityManager.shared
    private let clipboardManager = ClipboardManager.shared
    private let keyboardSimulator = KeyboardSimulator.shared
    private let popupManager = PopupWindowManager.shared

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupHotkey()
        accessibilityManager.requestAccessibilityPermissions()
        requestNotificationPermissions()
    }

    private func setupHotkey() {
        hotkeyManager = HotkeyManager(settingsManager: settingsManager)
        hotkeyManager.onHotkeyPressed = { [weak self] in
            self?.triggerGrammarCheck()
        }
        hotkeyManager.register()
    }

    private func requestNotificationPermissions() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, error in
            if let error = error {
                print("Notification permission error: \(error)")
            }
        }
    }

    // MARK: - Grammar Check Flow

    @objc func triggerGrammarCheck() {
        guard !isProcessing else { return }

        if !accessibilityManager.isAccessibilityTrusted {
            showAccessibilityPermissionAlert()
            return
        }

        // Save the frontmost app BEFORE showing popup - this is critical for pasting back
        previousApp = NSWorkspace.shared.frontmostApplication
        print("[Fixie] Saved previous app: \(previousApp?.localizedName ?? "nil")")

        // For Electron/web apps, skip Accessibility API (can return garbled/lowercase text)
        let useClipboardOnly = accessibilityManager.frontmostAppRequiresFallback
        print("[Fixie] Frontmost app requires clipboard fallback: \(useClipboardOnly)")

        // Try Accessibility API first (only for native apps)
        if !useClipboardOnly {
            print("[Fixie] Trying Accessibility API...")
            if let selectedText = accessibilityManager.getSelectedText() {
                print("[Fixie] Accessibility API succeeded: \(selectedText.prefix(50))...")
                usedAccessibilityForRead = true
                currentOriginalText = selectedText
                checkGrammar(text: selectedText)
                return
            }
            print("[Fixie] Accessibility API failed, falling back to clipboard simulation")
        }

        // Fall back to clipboard simulation (Cmd+C)
        usedAccessibilityForRead = false
        clipboardManager.saveCurrentContent()
        clipboardManager.clear()
        print("[Fixie] Simulating Cmd+C...")
        keyboardSimulator.simulateCopy()

        // Wait for clipboard to be populated
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self = self else { return }

            // Prefer HTML→markdown from clipboard (preserves formatting from web/Electron apps)
            let clipboardContent = self.clipboardManager.getContentPreferringMarkdown()
            print("[Fixie] Clipboard content after copy: \(clipboardContent?.prefix(50) ?? "nil")")

            if let selectedText = clipboardContent, !selectedText.isEmpty {
                self.currentOriginalText = selectedText
                self.checkGrammar(text: selectedText)
            } else {
                print("[Fixie] No text in clipboard, showing alert")
                self.clipboardManager.restoreSavedContent()
                self.showNoTextSelectedAlert()
            }
        }
    }

    private func checkGrammar(text: String) {
        currentTask?.cancel()
        isProcessing = true

        let llmService = LLMServiceFactory.create(provider: settingsManager.selectedProvider, settings: settingsManager)

        // Reset streaming state
        streamingState.text = ""
        streamingState.isComplete = false
        currentCorrectedText = ""

        // Show popup
        popupManager.showPopup(
            originalText: text,
            streamingState: streamingState,
            providerName: getProviderDisplayName(),
            onAccept: { [weak self] in self?.acceptCorrection() },
            onReject: { [weak self] in self?.rejectCorrection() }
        )

        currentTask = Task { @MainActor [weak self] in
            guard let self = self else { return }

            defer {
                self.isProcessing = false
                self.currentTask = nil
            }

            do {
                try Task.checkCancellation()
                var fullText = ""

                for try await chunk in llmService.correctGrammarStreaming(text: text) {
                    try Task.checkCancellation()
                    fullText += chunk
                    self.streamingState.text = fullText
                }

                try Task.checkCancellation()
                let correctedText = PromptBuilder.sanitizeResponse(fullText)
                self.currentCorrectedText = correctedText
                self.streamingState.text = correctedText
                self.streamingState.isComplete = true
            } catch is CancellationError {
                // Task was cancelled - ignore
            } catch {
                self.popupManager.closeWindow()
                self.showErrorAlert(error.localizedDescription)
            }
        }
    }

    private func acceptCorrection() {
        guard !currentCorrectedText.isEmpty else {
            print("[Fixie] acceptCorrection: No corrected text to paste")
            return
        }

        let textToPaste = currentCorrectedText
        let savedElement = accessibilityManager.getSavedElement()
        let requiresTypingFallback = accessibilityManager.savedAppRequiresTypingFallback

        // Use the app saved at the start of triggerGrammarCheck(), not the current frontmost app
        let targetApp = self.previousApp

        print("[Fixie] acceptCorrection: Text to insert: \(textToPaste.prefix(50))...")
        print("[Fixie] acceptCorrection: Has saved element: \(savedElement != nil)")
        print("[Fixie] acceptCorrection: Requires typing fallback: \(requiresTypingFallback)")
        print("[Fixie] acceptCorrection: Target app: \(targetApp?.localizedName ?? "nil")")

        // Reset state immediately
        isProcessing = false
        currentCorrectedText = ""
        accessibilityManager.clearSavedElement()

        // For Electron/web apps, use clipboard + paste
        if requiresTypingFallback {
            print("[Fixie] Using clipboard + paste for Electron/web app")

            // Set clipboard content FIRST
            clipboardManager.setContent(textToPaste)

            // Close popup window (this deactivates Fixie)
            popupManager.closeWindow()

            // Activate the target app to give it keyboard focus
            if let app = targetApp {
                print("[Fixie] Activating target app: \(app.localizedName ?? "unknown")")
                app.activate(options: [.activateIgnoringOtherApps])
            }

            // Wait for focus to settle, then paste
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                print("[Fixie] Simulating Cmd+V paste")
                self?.keyboardSimulator.simulatePaste()

                // Restore clipboard after paste completes
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                    self?.clipboardManager.restoreSavedContent()
                }
            }
            return
        }

        // For native apps, try Accessibility API first
        popupManager.hideWindow()

        DispatchQueue.main.async { [weak self] in
            NSApp.deactivate()

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                guard let self = self else { return }

                if let element = savedElement {
                    print("[Fixie] Trying to set text via Accessibility API...")
                    let result = AXUIElementSetAttributeValue(
                        element,
                        kAXSelectedTextAttribute as CFString,
                        textToPaste as CFTypeRef
                    )
                    print("[Fixie] Accessibility API set result: \(result.rawValue)")
                    if result == .success {
                        print("[Fixie] Accessibility API succeeded!")
                        self.clipboardManager.restoreSavedContent()
                        self.popupManager.closeWindowDeferred()
                        return
                    }
                    print("[Fixie] Accessibility API failed, falling back to clipboard paste")
                }

                // Fallback: clipboard + paste
                print("[Fixie] Using clipboard + paste fallback")
                self.clipboardManager.setContent(textToPaste)

                if let app = targetApp {
                    app.activate(options: [.activateIgnoringOtherApps])
                }

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                    self?.keyboardSimulator.simulatePaste()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                        self?.clipboardManager.restoreSavedContent()
                    }
                    self?.popupManager.closeWindowDeferred()
                }
            }
        }
    }

    private func rejectCorrection() {
        currentTask?.cancel()
        currentTask = nil
        isProcessing = false
        accessibilityManager.clearSavedElement()
        clipboardManager.restoreSavedContent()
        popupManager.closeWindow()
    }

    // MARK: - Helpers

    private func getProviderDisplayName() -> String {
        let modelId: String
        switch settingsManager.selectedProvider {
        case .claude: modelId = settingsManager.claudeModel
        case .openai: modelId = settingsManager.openAIModel
        case .ollama: return settingsManager.ollamaModel
        }
        let displayNames: [String: String] = [
            "gpt-5.2": "GPT-5.2",
            "gpt-5.2-mini": "GPT-5.2 Mini",
            "gpt-4o": "GPT-4o",
            "gpt-4o-mini": "GPT-4o Mini",
            "claude-sonnet-4-20250514": "Claude Sonnet 4",
            "claude-haiku-4-5-20251001": "Claude Haiku",
        ]
        return displayNames[modelId] ?? modelId
    }

    // MARK: - Alerts

    private func showAccessibilityPermissionAlert() {
        let alert = NSAlert()
        alert.messageText = "Accessibility Permission Required"
        alert.informativeText = "Fixie needs Accessibility permission to capture selected text.\n\nPlease enable it in System Settings → Privacy & Security → Accessibility"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Cancel")

        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
        }
    }

    private func showNoTextSelectedAlert() {
        let alert = NSAlert()
        alert.messageText = "No Text Selected"
        alert.informativeText = "Please select some text first, then trigger Fixie."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    private func showErrorAlert(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "Fixie Error"
        alert.informativeText = message
        alert.alertStyle = .critical
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    // MARK: - Settings

    @objc func openSettings() {
        if settingsWindow == nil {
            let settingsView = SettingsView().environmentObject(settingsManager)
            let hostingController = NSHostingController(rootView: settingsView)

            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 550, height: 400),
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
