import Cocoa

/// Manages reading and writing text via macOS Accessibility API
final class AccessibilityManager {
    static let shared = AccessibilityManager()

    private var savedFocusedElement: AXUIElement?
    private var savedAppBundleID: String?
    private var enabledAccessibilityPIDs: Set<pid_t> = []

    /// Apps where Accessibility API write doesn't work (Electron/web-based apps)
    /// These apps report success for kAXSelectedTextAttribute writes but don't actually update
    private static let appsRequiringTypingFallback: Set<String> = [
        // Electron apps
        "net.whatsapp.WhatsApp",
        "com.tinyspeck.slackmacgap",  // Slack
        "com.microsoft.teams",
        "com.microsoft.teams2",
        "com.hnc.Discord",
        "com.spotify.client",
        "com.figma.Desktop",
        "com.notion.id",
        "com.slite.desktop",
        "com.slite.Slite",
        "com.linear",
        "com.vscodium",
        "com.microsoft.VSCode",
        "com.microsoft.VSCodeInsiders",
        "com.todesktop.230313mzl4w4u92",  // Linear
        // Browsers (web content)
        "com.google.Chrome",
        "com.google.Chrome.canary",
        "org.chromium.Chromium",
        "com.brave.Browser",
        "com.microsoft.edgemac",
        "com.operasoftware.Opera",
        "com.vivaldi.Vivaldi",
        "org.mozilla.firefox",
        "org.mozilla.firefoxdeveloperedition",
        "company.thebrowser.Browser",  // Arc
        "com.apple.Safari",  // Safari web content
    ]

    private init() {}

    // MARK: - Permission Management

    /// Check if accessibility is enabled
    var isAccessibilityTrusted: Bool {
        AXIsProcessTrusted()
    }

    /// Request accessibility permissions
    func requestAccessibilityPermissions() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        AXIsProcessTrustedWithOptions(options as CFDictionary)
    }

    // MARK: - Electron App Support

    /// Enable accessibility on the frontmost application (required for Electron apps)
    /// See: https://www.electronjs.org/docs/latest/tutorial/accessibility#macos
    private func enableAccessibilityOnFrontmostApp() {
        guard let frontApp = NSWorkspace.shared.frontmostApplication else {
            print("[Accessibility] No frontmost application")
            return
        }
        let pid = frontApp.processIdentifier
        let appName = frontApp.localizedName ?? "Unknown"

        print("[Accessibility] Frontmost app: \(appName) (PID: \(pid))")

        // Only enable once per app to avoid repeated calls
        if enabledAccessibilityPIDs.contains(pid) {
            print("[Accessibility] Already enabled for this app")
            return
        }

        let appElement = AXUIElementCreateApplication(pid)

        // Set AXManualAccessibility to true to enable accessibility in Electron apps
        let result = AXUIElementSetAttributeValue(
            appElement,
            "AXManualAccessibility" as CFString,
            true as CFTypeRef
        )

        print("[Accessibility] AXManualAccessibility result: \(result.rawValue)")

        if result == .success || result == .attributeUnsupported {
            // attributeUnsupported means it's not an Electron app, which is fine
            enabledAccessibilityPIDs.insert(pid)
        }
    }

    // MARK: - Element Management

    /// Clear the saved focused element
    func clearSavedElement() {
        savedFocusedElement = nil
        savedAppBundleID = nil
    }

    /// Check if there's a saved element
    var hasSavedElement: Bool {
        savedFocusedElement != nil
    }

    /// Get the saved AXUIElement for direct use
    func getSavedElement() -> AXUIElement? {
        return savedFocusedElement
    }

    /// Check if the saved app requires typing fallback (Electron/web apps)
    var savedAppRequiresTypingFallback: Bool {
        guard let bundleID = savedAppBundleID else { return false }
        return Self.appsRequiringTypingFallback.contains(bundleID)
    }

    /// Check if the current frontmost app needs clipboard fallback
    /// (Electron/web apps where Accessibility API returns garbled text)
    var frontmostAppRequiresFallback: Bool {
        guard let bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier else {
            return false
        }
        return Self.appsRequiringTypingFallback.contains(bundleID)
    }

    // MARK: - Text Operations

    /// Get selected text from the focused element and save the element for later use
    /// - Returns: The selected text, or nil if not available
    func getSelectedText() -> String? {
        // Enable accessibility on Electron apps (WhatsApp, Slack, etc.)
        enableAccessibilityOnFrontmostApp()

        let systemWide = AXUIElementCreateSystemWide()
        var focusedElement: CFTypeRef?

        let focusResult = AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &focusedElement
        )

        guard focusResult == .success, let element = focusedElement else {
            print("[Accessibility] Failed to get focused element: \(focusResult.rawValue)")
            return nil
        }

        // Safe cast using CFGetTypeID
        guard CFGetTypeID(element) == AXUIElementGetTypeID() else {
            print("[Accessibility] Focused element is not an AXUIElement")
            return nil
        }

        // Now we know it's an AXUIElement, safe to use unsafeBitCast
        let axElement = unsafeBitCast(element, to: AXUIElement.self)

        var selectedText: CFTypeRef?
        let textResult = AXUIElementCopyAttributeValue(
            axElement,
            kAXSelectedTextAttribute as CFString,
            &selectedText
        )

        guard textResult == .success,
              let textRef = selectedText,
              CFGetTypeID(textRef) == CFStringGetTypeID() else {
            print("[Accessibility] Failed to get selected text: \(textResult.rawValue)")
            return nil
        }

        let text = textRef as! String
        guard !text.isEmpty else {
            print("[Accessibility] Selected text is empty")
            return nil
        }

        print("[Accessibility] Got selected text: \(text.prefix(50))...")

        // Save the focused element and app bundle ID for later use when writing back
        savedFocusedElement = axElement
        savedAppBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        print("[Accessibility] Saved app bundle ID: \(savedAppBundleID ?? "nil")")

        return text
    }

    /// Set selected text using the saved focused element
    /// - Parameter text: The text to set
    /// - Returns: True if successful
    @discardableResult
    func setSelectedText(_ text: String) -> Bool {
        // First, try to use the saved focused element (most reliable)
        if let savedElement = savedFocusedElement {
            let setResult = AXUIElementSetAttributeValue(
                savedElement,
                kAXSelectedTextAttribute as CFString,
                text as CFTypeRef
            )

            if setResult == .success {
                savedFocusedElement = nil
                return true
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
            return false
        }

        // Safe cast using CFGetTypeID
        guard CFGetTypeID(element) == AXUIElementGetTypeID() else {
            return false
        }

        let axElement = unsafeBitCast(element, to: AXUIElement.self)

        let setResult = AXUIElementSetAttributeValue(
            axElement,
            kAXSelectedTextAttribute as CFString,
            text as CFTypeRef
        )

        return setResult == .success
    }
}

// MARK: - Text Capture Protocol

protocol TextCaptureService {
    var isAvailable: Bool { get }
    func captureSelectedText() -> String?
    func replaceSelectedText(_ text: String) -> Bool
    func reset()
}

extension AccessibilityManager: TextCaptureService {
    var isAvailable: Bool {
        isAccessibilityTrusted
    }

    func captureSelectedText() -> String? {
        getSelectedText()
    }

    func replaceSelectedText(_ text: String) -> Bool {
        setSelectedText(text)
    }

    func reset() {
        clearSavedElement()
    }
}
