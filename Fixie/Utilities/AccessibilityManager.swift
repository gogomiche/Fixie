import Cocoa

/// Manages reading and writing text via macOS Accessibility API
final class AccessibilityManager {
    static let shared = AccessibilityManager()

    private var savedFocusedElement: AXUIElement?

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

    // MARK: - Element Management

    /// Clear the saved focused element
    func clearSavedElement() {
        savedFocusedElement = nil
    }

    /// Check if there's a saved element
    var hasSavedElement: Bool {
        savedFocusedElement != nil
    }

    /// Get the saved AXUIElement for direct use
    func getSavedElement() -> AXUIElement? {
        return savedFocusedElement
    }

    // MARK: - Text Operations

    /// Get selected text from the focused element and save the element for later use
    /// - Returns: The selected text, or nil if not available
    func getSelectedText() -> String? {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedElement: CFTypeRef?

        let focusResult = AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &focusedElement
        )

        guard focusResult == .success, let element = focusedElement else {
            return nil
        }

        // Safe cast using CFGetTypeID
        guard CFGetTypeID(element) == AXUIElementGetTypeID() else {
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
            return nil
        }

        let text = textRef as! String
        guard !text.isEmpty else {
            return nil
        }

        // Save the focused element for later use when writing back
        savedFocusedElement = axElement

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
