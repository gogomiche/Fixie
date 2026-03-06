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

    /// Get clipboard content, converting HTML to markdown when available.
    /// Electron/web apps (Slite, Slack, Notion…) put HTML on the clipboard
    /// that contains formatting lost in the plain-text representation.
    func getContentPreferringMarkdown() -> String? {
        let pasteboard = NSPasteboard.general

        // Try Slack's Quill Delta from Chromium web-custom-data (Slack doesn't put HTML on clipboard)
        let chromiumType = NSPasteboard.PasteboardType("org.chromium.web-custom-data")
        if let data = pasteboard.data(forType: chromiumType),
           let slackJSON = QuillDeltaParser.extractSlackJSON(from: data),
           let markdown = QuillDeltaParser.toMarkdown(slackJSON) {
            return markdown
        }

        // Try HTML → markdown (Slite, Notion, other Electron apps)
        if let html = pasteboard.string(forType: .html),
           let markdown = HTMLToMarkdown.convert(html) {
            return markdown
        }

        // Fall back to plain text, converting bullet characters to markdown
        guard var text = pasteboard.string(forType: .string) else { return nil }
        if let re = try? NSRegularExpression(pattern: "(?m)^\\s*[•◦▪▸►●○]\\s*(.*)") {
            text = re.stringByReplacingMatches(
                in: text,
                range: NSRange(text.startIndex..., in: text),
                withTemplate: "- $1"
            )
        }
        return text
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
