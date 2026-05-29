import Cocoa
import Carbon.HIToolbox

/// Simulates keyboard input via CGEvent
class KeyboardSimulator {
    static let shared = KeyboardSimulator()

    private init() {}

    /// Simulate Cmd+C (copy). Waits for the user to release any held
    /// modifier keys first — otherwise the hotkey modifiers (e.g. ⌥⌘ from
    /// the global hotkey that triggered Fixie) leak into the synthesized
    /// Cmd+C and the app interprets it as ⌥⌘C, which is a different
    /// shortcut → nothing gets copied.
    func simulateCopy() {
        waitForModifiersToClear()
        simulateKeyPress(keyCode: CGKeyCode(kVK_ANSI_C), withCommand: true)
    }

    /// Simulate Cmd+V (paste). Same modifier-release wait as Cmd+C.
    func simulatePaste() {
        waitForModifiersToClear()
        simulateKeyPress(keyCode: CGKeyCode(kVK_ANSI_V), withCommand: true)
    }

    /// Block (synchronously) until none of Cmd/Option/Shift/Control are
    /// physically held, or `timeoutMs` elapses. Polls every 10 ms.
    /// After detecting release, sleeps an additional `settleMs` to let the
    /// system event queue fully drain modifier-up events — otherwise a
    /// subsequent synthesized key event can still be merged with a residual
    /// modifier state by the receiving app.
    private func waitForModifiersToClear(timeoutMs: Int = 1000, settleMs: Int = 60) {
        let modifierMask: CGEventFlags = [.maskCommand, .maskAlternate, .maskShift, .maskControl]
        let start = Date()
        let timeout = Double(timeoutMs) / 1000.0

        while Date().timeIntervalSince(start) < timeout {
            let flags = CGEventSource.flagsState(.combinedSessionState)
            if flags.intersection(modifierMask).isEmpty {
                let elapsed = Int(Date().timeIntervalSince(start) * 1000)
                Thread.sleep(forTimeInterval: Double(settleMs) / 1000.0)
                print("[KeyboardSimulator] Modifiers cleared after \(elapsed)ms (+\(settleMs)ms settle)")
                return
            }
            Thread.sleep(forTimeInterval: 0.01)
        }
        let flags = CGEventSource.flagsState(.combinedSessionState)
        print("[KeyboardSimulator] Timed out (\(timeoutMs)ms) waiting for modifiers. Current flags: \(flags)")
    }

    /// Simulate Backspace key press
    func simulateBackspace() {
        print("[KeyboardSimulator] Simulating backspace")
        simulateKeyPress(keyCode: CGKeyCode(kVK_Delete))
    }

    /// Type text by simulating keyboard input using CGEventKeyboardSetUnicodeString
    /// This works with Electron apps (WhatsApp, Slack, browsers) where paste doesn't work
    func typeText(_ text: String) {
        guard !text.isEmpty else { return }

        let maxCharsPerEvent = 20 // macOS limit for CGEventKeyboardSetUnicodeString
        var index = text.startIndex

        while index < text.endIndex {
            // Get next chunk of up to 20 characters
            let endIndex = text.index(index, offsetBy: maxCharsPerEvent, limitedBy: text.endIndex) ?? text.endIndex
            let chunk = String(text[index..<endIndex])

            typeChunk(chunk)

            index = endIndex

            // Small delay between chunks for reliability
            if index < text.endIndex {
                Thread.sleep(forTimeInterval: 0.005) // 5ms
            }
        }
    }

    /// Type a chunk of text (up to 20 characters)
    private func typeChunk(_ chunk: String) {
        let unicodeChars = Array(chunk.utf16)
        guard !unicodeChars.isEmpty else { return }

        print("[KeyboardSimulator] Typing chunk: \(chunk) (\(unicodeChars.count) chars)")

        // Create a keyboard event
        guard let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false) else {
            print("[KeyboardSimulator] Failed to create CGEvent")
            return
        }

        // Set the Unicode string on the event
        unicodeChars.withUnsafeBufferPointer { buffer in
            keyDown.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: buffer.baseAddress)
            keyUp.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: buffer.baseAddress)
        }

        // Post key down and key up events
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)

        print("[KeyboardSimulator] Posted events for chunk")
    }

    /// Simulate a key press with optional modifiers
    /// Uses hidSystemState and cgAnnotatedSessionEventTap for better compatibility
    private func simulateKeyPress(keyCode: CGKeyCode, withCommand: Bool = false) {
        let source = CGEventSource(stateID: .hidSystemState)

        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) else {
            print("[KeyboardSimulator] Failed to create key event")
            return
        }

        if withCommand {
            keyDown.flags = .maskCommand
            keyUp.flags = .maskCommand
        }

        print("[KeyboardSimulator] Posting key event: keyCode=\(keyCode), command=\(withCommand)")

        // Use cgAnnotatedSessionEventTap for better app compatibility
        keyDown.post(tap: .cgAnnotatedSessionEventTap)
        Thread.sleep(forTimeInterval: 0.02) // 20ms between key down and up
        keyUp.post(tap: .cgAnnotatedSessionEventTap)
    }
}
