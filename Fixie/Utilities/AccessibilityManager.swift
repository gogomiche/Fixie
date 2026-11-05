import Cocoa

/// Manages reading and writing text via macOS Accessibility API
final class AccessibilityManager {
    static let shared = AccessibilityManager()

    private var savedFocusedElement: AXUIElement?
    private var savedAppBundleID: String?
    private var savedAppRequiresFallback: Bool = false
    private var savedSelectedRange: CFRange?
    private var enabledAccessibilityPIDs: Set<pid_t> = []
    private var classificationCache: [String: AppClassifier.Kind] = [:]

    private init() {}

    // MARK: - App Classification

    /// Classify an app (cached per bundle ID). See `AppClassifier`.
    func classify(_ app: NSRunningApplication) -> AppClassifier.Kind {
        guard let bundleID = app.bundleIdentifier, let bundleURL = app.bundleURL else { return .native }
        if let cached = classificationCache[bundleID] {
            return cached
        }
        let kind = AppClassifier.classify(bundleURL: bundleURL)
        classificationCache[bundleID] = kind
        print("[Accessibility] \(app.localizedName ?? bundleID) classified as \(kind.rawValue)")
        return kind
    }

    /// Electron apps, browsers and Mac Catalyst apps (WhatsApp…) need the
    /// clipboard + paste path: AX reads return garbled text or AX writes
    /// silently do nothing.
    private func appRequiresFallback(_ app: NSRunningApplication) -> Bool {
        classify(app).requiresClipboardFallback
    }

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
        savedAppRequiresFallback = false
        savedSelectedRange = nil
    }

    /// The selection range captured at read time (location + length in chars).
    /// Used to restore the selection before writing back, since the selection
    /// can be collapsed by focus changes between read and write.
    var savedSelectionRange: CFRange? {
        savedSelectedRange
    }

    /// Check if there's a saved element
    var hasSavedElement: Bool {
        savedFocusedElement != nil
    }

    /// Get the saved AXUIElement for direct use
    func getSavedElement() -> AXUIElement? {
        return savedFocusedElement
    }

    /// Check if the saved app requires typing fallback (Electron/web apps).
    /// Captured at read time so the decision is stable across the request.
    var savedAppRequiresTypingFallback: Bool {
        savedAppRequiresFallback
    }

    /// Check if the current frontmost app needs clipboard fallback
    /// (Electron/web apps where Accessibility API returns garbled text)
    var frontmostAppRequiresFallback: Bool {
        guard let app = NSWorkspace.shared.frontmostApplication else { return false }
        return appRequiresFallback(app)
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
        if let app = NSWorkspace.shared.frontmostApplication {
            savedAppBundleID = app.bundleIdentifier
            savedAppRequiresFallback = appRequiresFallback(app)
        } else {
            savedAppBundleID = nil
            savedAppRequiresFallback = false
        }
        print("[Accessibility] Saved app bundle ID: \(savedAppBundleID ?? "nil") (requires fallback: \(savedAppRequiresFallback))")

        // Capture the selection range so we can restore it before writing back.
        // If the user clicks in the popup or focus shifts, the selection may
        // collapse — AX would then insert at the cursor instead of replacing.
        var rangeRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(axElement, kAXSelectedTextRangeAttribute as CFString, &rangeRef) == .success,
           let value = rangeRef,
           CFGetTypeID(value) == AXValueGetTypeID() {
            var range = CFRange()
            if AXValueGetValue(value as! AXValue, .cfRange, &range) {
                savedSelectedRange = range
                print("[Accessibility] Saved selection range: location=\(range.location), length=\(range.length)")
            }
        } else {
            savedSelectedRange = nil
        }

        return text
    }

    /// Write replacement text via AX, restoring the originally-captured
    /// selection range first. This prevents the "insert at cursor instead of
    /// replace" failure when the selection has been collapsed between read
    /// and write (e.g. user clicked in the popup).
    ///
    /// Returns true only if the write is confirmed: some apps (Mac Catalyst
    /// text views, for instance) answer `.success` without changing anything,
    /// so the element's value is compared before and after. When nothing
    /// changed, the caller falls back to clipboard + paste — which is safe
    /// because the original selection is still in place.
    func writeReplacingSelection(_ text: String, element: AXUIElement, range: CFRange?) -> Bool {
        if var mutableRange = range {
            if let rangeValue = AXValueCreate(.cfRange, &mutableRange) {
                let restoreResult = AXUIElementSetAttributeValue(
                    element,
                    kAXSelectedTextRangeAttribute as CFString,
                    rangeValue
                )
                print("[Accessibility] Restored selection (loc=\(mutableRange.location), len=\(mutableRange.length)): \(restoreResult.rawValue)")
            }
        }

        let valueBefore = stringValue(of: element)

        let result = AXUIElementSetAttributeValue(
            element,
            kAXSelectedTextAttribute as CFString,
            text as CFTypeRef
        )
        guard result == .success else {
            print("[Accessibility] AX write failed: \(result.rawValue)")
            return false
        }

        // Can't verify (no readable value, or a huge document): trust AX.
        guard let before = valueBefore, (before as NSString).length < 2_000_000 else { return true }

        // Replacing the selection with identical text legitimately changes nothing.
        if let range = range {
            let ns = before as NSString
            let r = NSRange(location: range.location, length: range.length)
            if r.location >= 0, NSMaxRange(r) <= ns.length, ns.substring(with: r) == text {
                return true
            }
        }

        if stringValue(of: element) != before { return true }
        // Give apps that update their AX value asynchronously a moment.
        Thread.sleep(forTimeInterval: 0.1)
        if stringValue(of: element) != before { return true }

        print("[Accessibility] AX write reported success but the value is unchanged — not trusting it")
        return false
    }

    private func stringValue(of element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &value) == .success,
              let v = value, CFGetTypeID(v) == CFStringGetTypeID() else { return nil }
        return (v as! String)
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
