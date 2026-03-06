import Foundation

/// Converts clipboard HTML to markdown, preserving formatting that plain text loses.
/// Used when capturing text from Electron/web apps (Slite, Slack, Notion, etc.).
enum HTMLToMarkdown {

    static func convert(_ html: String) -> String? {
        guard html.count < 100_000 else { return nil }

        var text = html

        // Strip everything outside <body> if present
        if let range = text.range(of: "<body[^>]*>", options: .regularExpression) {
            text = String(text[range.upperBound...])
        }
        if let range = text.range(of: "</body>") {
            text = String(text[..<range.lowerBound])
        }

        // Slack-specific: data-stringify-type attributes (process before standard tags)
        text = re(text, "<div[^>]*data-stringify-type=\"unordered-list-item\"[^>]*>([\\s\\S]*?)</div>", "\n- $1")
        text = processSlackOrderedItems(text)
        text = re(text, "<div[^>]*data-stringify-type=\"blockquote\"[^>]*>([\\s\\S]*?)</div>", "\n> $1\n")
        text = re(text, "<div[^>]*data-stringify-type=\"pre\"[^>]*>([\\s\\S]*?)</div>", "\n```\n$1\n```\n")
        text = re(text, "<div[^>]*data-stringify-type=\"paragraph-break\"[^>]*>[\\s\\S]*?</div>", "\n\n")

        // Code blocks (pre > code) — process first to protect content
        text = re(text, "<pre[^>]*>\\s*<code[^>]*>([\\s\\S]*?)</code>\\s*</pre>", "\n```\n$1\n```\n")
        text = re(text, "<pre[^>]*>([\\s\\S]*?)</pre>", "\n```\n$1\n```\n")

        // Inline code
        text = re(text, "<code[^>]*>(.*?)</code>", "`$1`")

        // Headers
        for i in 1...6 {
            let hashes = String(repeating: "#", count: i)
            text = re(text, "<h\(i)[^>]*>([\\s\\S]*?)</h\(i)>", "\n\(hashes) $1\n")
        }

        // Bold
        text = re(text, "<(?:strong|b)[^>]*>([\\s\\S]*?)</(?:strong|b)>", "**$1**")

        // Italic
        text = re(text, "<(?:em|i)[^>]*>([\\s\\S]*?)</(?:em|i)>", "*$1*")

        // Strikethrough
        text = re(text, "<(?:del|s|strike)[^>]*>([\\s\\S]*?)</(?:del|s|strike)>", "~~$1~~")

        // Links
        text = re(text, "<a[^>]*href=\"([^\"]*?)\"[^>]*>([\\s\\S]*?)</a>", "[$2]($1)")

        // Images
        text = re(text, "<img[^>]*alt=\"([^\"]*?)\"[^>]*src=\"([^\"]*?)\"[^>]*/?>", "![$1]($2)")
        text = re(text, "<img[^>]*src=\"([^\"]*?)\"[^>]*/?>", "![]($1)")

        // Ordered lists — number the items before generic <li> processing
        text = processOrderedLists(text)

        // Remaining <li> tags are inside <ul> → bullet points
        text = re(text, "<li[^>]*>([\\s\\S]*?)</li>", "- $1\n")

        // Remove list wrapper tags
        text = re(text, "</?[uo]l[^>]*>", "\n")

        // Blockquotes
        text = re(text, "<blockquote[^>]*>([\\s\\S]*?)</blockquote>", "\n> $1\n")

        // Horizontal rules
        text = re(text, "<hr[^>]*/?>", "\n---\n")

        // Line breaks
        text = re(text, "<br\\s*/?>", "\n")

        // Paragraphs and divs
        text = text.replacingOccurrences(of: "</p>", with: "\n\n")
        text = re(text, "<p[^>]*>", "")
        text = text.replacingOccurrences(of: "</div>", with: "\n")
        text = re(text, "<div[^>]*>", "")

        // Strip remaining tags
        text = re(text, "<[^>]+>", "")

        // Decode HTML entities
        text = decodeEntities(text)

        // Convert bullet characters (•, ◦, ▪, ▸) to markdown bullets
        // Covers apps that don't use semantic HTML for lists
        text = re(text, "(?m)^\\s*[•◦▪▸►●○]\\s*(.*)", "- $1")

        // Clean up whitespace
        text = re(text, "\\n{3,}", "\n\n")
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)

        return text.isEmpty ? nil : text
    }

    // MARK: - Private

    /// Convert Slack's `data-stringify-type="ordered-list-item"` divs to numbered list.
    private static func processSlackOrderedItems(_ text: String) -> String {
        guard let regex = try? NSRegularExpression(
            pattern: "<div[^>]*data-stringify-type=\"ordered-list-item\"[^>]*>([\\s\\S]*?)</div>",
            options: .caseInsensitive
        ) else { return text }

        var result = text
        let matches = regex.matches(in: result, range: NSRange(result.startIndex..., in: result))

        for (i, match) in matches.reversed().enumerated() {
            guard let fullRange = Range(match.range, in: result),
                  let contentRange = Range(match.range(at: 1), in: result) else { continue }
            let number = matches.count - i
            let content = result[contentRange].trimmingCharacters(in: .whitespacesAndNewlines)
            result.replaceSubrange(fullRange, with: "\n\(number). \(content)")
        }
        return result
    }

    /// Convert <ol> blocks: number each <li> as 1. 2. 3. then remove the <ol> wrapper.
    private static func processOrderedLists(_ text: String) -> String {
        guard let olRegex = try? NSRegularExpression(
            pattern: "<ol[^>]*>([\\s\\S]*?)</ol>",
            options: .caseInsensitive
        ) else { return text }

        var result = text
        let matches = olRegex.matches(in: result, range: NSRange(result.startIndex..., in: result))

        for match in matches.reversed() {
            guard let fullRange = Range(match.range, in: result),
                  let contentRange = Range(match.range(at: 1), in: result) else { continue }

            let listHTML = String(result[contentRange])

            guard let liRegex = try? NSRegularExpression(
                pattern: "<li[^>]*>([\\s\\S]*?)</li>",
                options: .caseInsensitive
            ) else { continue }

            let items = liRegex.matches(in: listHTML, range: NSRange(listHTML.startIndex..., in: listHTML))
            var numbered = "\n"
            for (i, item) in items.enumerated() {
                if let itemRange = Range(item.range(at: 1), in: listHTML) {
                    let content = listHTML[itemRange].trimmingCharacters(in: .whitespacesAndNewlines)
                    numbered += "\(i + 1). \(content)\n"
                }
            }

            result.replaceSubrange(fullRange, with: numbered)
        }
        return result
    }

    private static func re(_ text: String, _ pattern: String, _ template: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            return text
        }
        return regex.stringByReplacingMatches(
            in: text,
            range: NSRange(text.startIndex..., in: text),
            withTemplate: template
        )
    }

    private static func decodeEntities(_ text: String) -> String {
        var t = text
        let entities: [(String, String)] = [
            ("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"),
            ("&quot;", "\""), ("&#39;", "'"), ("&apos;", "'"),
            ("&nbsp;", " "), ("&#160;", " "),
        ]
        for (entity, char) in entities {
            t = t.replacingOccurrences(of: entity, with: char)
        }
        // Numeric entities like &#8217;
        if let regex = try? NSRegularExpression(pattern: "&#(\\d+);") {
            let ns = t as NSString
            for match in regex.matches(in: t, range: NSRange(location: 0, length: ns.length)).reversed() {
                if let num = Int(ns.substring(with: match.range(at: 1))),
                   let scalar = Unicode.Scalar(num) {
                    t = ns.replacingCharacters(in: match.range, with: String(scalar)) as String
                }
            }
        }
        return t
    }
}
