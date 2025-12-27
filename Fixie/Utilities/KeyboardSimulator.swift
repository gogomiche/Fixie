import Cocoa
import Carbon.HIToolbox

/// Simulates keyboard input via CGEvents
class KeyboardSimulator {
    static let shared = KeyboardSimulator()

    private init() {}

    /// Simulate Cmd+C (copy)
    func simulateCopy() {
        simulateKeyPress(keyCode: CGKeyCode(kVK_ANSI_C), withCommand: true)
    }

    /// Simulate Cmd+V (paste)
    func simulatePaste() {
        simulateKeyPress(keyCode: CGKeyCode(kVK_ANSI_V), withCommand: true)
    }

    /// Simulate a key press with optional modifiers
    private func simulateKeyPress(keyCode: CGKeyCode, withCommand: Bool = false) {
        let source = CGEventSource(stateID: .combinedSessionState)

        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) else {
            return
        }

        if withCommand {
            keyDown.flags = .maskCommand
            keyUp.flags = .maskCommand
        }

        keyDown.post(tap: .cgSessionEventTap)
        Thread.sleep(forTimeInterval: 0.02) // 20ms between key down and up
        keyUp.post(tap: .cgSessionEventTap)
    }
}
