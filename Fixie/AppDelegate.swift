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

        // Try Accessibility API first
        if let selectedText = accessibilityManager.getSelectedText() {
            usedAccessibilityForRead = true
            currentOriginalText = selectedText
            checkGrammar(text: selectedText)
            return
        }

        // Fall back to clipboard simulation
        usedAccessibilityForRead = false
        clipboardManager.saveCurrentContent()
        clipboardManager.clear()
        keyboardSimulator.simulateCopy()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self = self else { return }

            if let selectedText = self.clipboardManager.getContent(), !selectedText.isEmpty {
                self.currentOriginalText = selectedText
                self.checkGrammar(text: selectedText)
            } else {
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
                let correctedText = fullText.trimmingCharacters(in: .whitespacesAndNewlines)
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
        guard !currentCorrectedText.isEmpty else { return }

        let textToPaste = currentCorrectedText
        let savedElement = accessibilityManager.getSavedElement()

        // Reset state immediately
        isProcessing = false
        currentCorrectedText = ""
        accessibilityManager.clearSavedElement()

        popupManager.hideWindow()

        DispatchQueue.main.async { [weak self] in
            NSApp.deactivate()

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                guard let self = self else { return }

                // Try Accessibility API first
                if let element = savedElement {
                    let result = AXUIElementSetAttributeValue(
                        element,
                        kAXSelectedTextAttribute as CFString,
                        textToPaste as CFTypeRef
                    )
                    if result == .success {
                        self.clipboardManager.restoreSavedContent()
                        self.popupManager.closeWindowDeferred()
                        return
                    }
                }

                // Fall back to clipboard + paste
                self.clipboardManager.setContent(textToPaste)
                self.keyboardSimulator.simulatePaste()

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                    self?.clipboardManager.restoreSavedContent()
                }

                self.popupManager.closeWindowDeferred()
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
        switch settingsManager.selectedProvider {
        case .claude: return "Claude Sonnet"
        case .openai: return "GPT-4o mini"
        case .ollama: return settingsManager.ollamaModel
        }
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
