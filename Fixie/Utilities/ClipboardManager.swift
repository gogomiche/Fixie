import Cocoa

/// Manages clipboard operations with save/restore functionality
class ClipboardManager {
    static let shared = ClipboardManager()

    private var savedContent: String?

    private init() {}

    /// Save the current clipboard content for later restoration
    func saveCurrentContent() {
        savedContent = NSPasteboard.general.string(forType: .string)
    }

    /// Restore previously saved clipboard content
    func restoreSavedContent() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        if let saved = savedContent {
            pasteboard.setString(saved, forType: .string)
        }
        savedContent = nil
    }

    /// Get the current clipboard content
    func getContent() -> String? {
        NSPasteboard.general.string(forType: .string)
    }

    /// Set clipboard content
    func setContent(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    /// Clear the clipboard
    func clear() {
        NSPasteboard.general.clearContents()
    }

    /// Check if clipboard content changed (useful after simulating copy)
    func contentChanged(from original: String?) -> Bool {
        let current = getContent()
        return current != nil && !current!.isEmpty && current != original
    }
}
