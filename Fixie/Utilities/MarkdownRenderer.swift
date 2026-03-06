import Foundation
import SwiftUI

enum MarkdownRenderer {
    private static let markdownPatterns = [
        #"^#{1,6}\s"#,            // Headers
        #"\*\*.+?\*\*"#,           // Bold
        #"\[.+?\]\(.+?\)"#,        // Links
        #"^[-*+]\s"#,              // Unordered lists
        #"^\d+\.\s"#,              // Ordered lists
        #"^```"#,                  // Code blocks
        #"^>"#,                    // Blockquotes
        #"`[^`]+`"#,              // Inline code
    ]

    static func containsMarkdown(_ text: String) -> Bool {
        for pattern in markdownPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .anchorsMatchLines),
               regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil {
                return true
            }
        }
        return false
    }

    static func render(_ text: String) -> AttributedString {
        if let attributed = try? AttributedString(markdown: text, options: .init(
            interpretedSyntax: .inlineOnlyPreservingWhitespace
        )) {
            return attributed
        }
        return AttributedString(text)
    }
}
