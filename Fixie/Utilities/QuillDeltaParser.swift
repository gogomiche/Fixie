import Foundation

/// Converts Slack's Quill Delta JSON format to markdown.
/// Slack stores formatted text in `org.chromium.web-custom-data` as Quill Delta ops.
enum QuillDeltaParser {

    static func toMarkdown(_ json: String) -> String? {
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let ops = obj["ops"] as? [[String: Any]] else { return nil }

        // 1. Split the delta into lines: inline content + the line-level
        //    attributes carried by the "\n" that terminates each line.
        var lines: [Line] = []
        var current = ""

        for op in ops {
            let attrs = op["attributes"] as? [String: Any]
            if let text = op["insert"] as? String {
                let parts = text.components(separatedBy: "\n")
                // Quill puts block attributes (list, quote, code…) on the
                // newline that ends the line; inline attributes on the text.
                let blockAttrs = attrs?.filter { blockKeys.contains($0.key) }
                for (i, part) in parts.enumerated() {
                    if i > 0 {
                        lines.append(Line(text: current, attrs: blockAttrs))
                        current = ""
                    }
                    if !part.isEmpty {
                        current += formatInline(part, attrs: attrs)
                    }
                }
            } else if let embed = op["insert"] as? [String: Any] {
                current += embedText(embed)
            }
        }
        if !current.isEmpty {
            lines.append(Line(text: current, attrs: nil))
        }

        // 2. Render lines, grouping consecutive code-block lines into one fence
        //    and numbering ordered lists per indentation level.
        var output: [String] = []
        var orderedCounters: [Int: Int] = [:]
        var inCodeBlock = false

        for line in lines {
            let attrs = line.attrs ?? [:]
            // Quill 1: `"code-block": true` — Quill 2: `"code-block": "plain"`/language
            let codeAttr = attrs["code-block"]
            let isCode = codeAttr is String || (codeAttr as? Bool) == true

            if isCode {
                if !inCodeBlock { output.append("```"); inCodeBlock = true }
                output.append(stripInlineCode(line.text))
                continue
            } else if inCodeBlock {
                output.append("```")
                inCodeBlock = false
            }

            let indentLevel = (attrs["indent"] as? Int) ?? 0
            let listType = attrs["list"] as? String

            if listType != "ordered" {
                orderedCounters = orderedCounters.filter { $0.key < indentLevel }
            }

            switch listType {
            case "bullet":
                output.append(listIndent(indentLevel) + "- " + line.text)
            case "ordered":
                orderedCounters = orderedCounters.filter { $0.key <= indentLevel }
                let n = (orderedCounters[indentLevel] ?? 0) + 1
                orderedCounters[indentLevel] = n
                output.append(listIndent(indentLevel) + "\(n). " + line.text)
            case "checked":
                output.append(listIndent(indentLevel) + "- [x] " + line.text)
            case "unchecked":
                output.append(listIndent(indentLevel) + "- [ ] " + line.text)
            default:
                orderedCounters = [:]
                if attrs["blockquote"] as? Bool == true {
                    output.append("> " + line.text)
                } else if let level = attrs["header"] as? Int, (1...6).contains(level) {
                    output.append(String(repeating: "#", count: level) + " " + line.text)
                } else {
                    output.append(line.text)
                }
            }
        }
        if inCodeBlock { output.append("```") }

        let result = output.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return result.isEmpty ? nil : result
    }

    // MARK: - Chromium clipboard

    /// Extract the Slack Quill Delta JSON from Chromium's web-custom-data.
    /// Searches for `{"ops":[` in UTF-16LE encoded data and extracts the complete JSON object.
    static func extractSlackJSON(from data: Data) -> String? {
        // Decode entire blob as UTF-16LE
        guard let decoded = String(data: data, encoding: .utf16LittleEndian) else { return nil }

        // Find the Quill Delta JSON — starts with {"ops":[
        guard let jsonStart = decoded.range(of: "{\"ops\":[") else { return nil }

        // Extract from { to the matching closing }, ignoring braces inside strings
        let substring = decoded[jsonStart.lowerBound...]
        var depth = 0
        var inString = false
        var escaped = false
        var endIndex = substring.startIndex
        for ch in substring {
            endIndex = substring.index(after: endIndex)
            if inString {
                if escaped { escaped = false }
                else if ch == "\\" { escaped = true }
                else if ch == "\"" { inString = false }
                continue
            }
            if ch == "\"" { inString = true }
            else if ch == "{" { depth += 1 }
            else if ch == "}" {
                depth -= 1
                if depth == 0 { break }
            }
        }

        guard depth == 0 else { return nil }
        return String(substring[..<endIndex])
    }

    // MARK: - Private

    private static let blockKeys: Set<String> = ["list", "indent", "blockquote", "code-block", "header", "align"]

    private struct Line {
        let text: String
        let attrs: [String: Any]?
    }

    private static func listIndent(_ level: Int) -> String {
        String(repeating: "  ", count: max(0, level))
    }

    private static func formatInline(_ text: String, attrs: [String: Any]?) -> String {
        guard let attrs = attrs else { return text }
        let leading = text.prefix { $0 == " " }
        let trailing = String(text.reversed().prefix { $0 == " " })
        var core = text.trimmingCharacters(in: .whitespaces)
        guard !core.isEmpty else { return text }

        if attrs["code"] as? Bool == true { core = "`\(core)`" }
        if attrs["bold"] as? Bool == true { core = "**\(core)**" }
        if attrs["italic"] as? Bool == true { core = "*\(core)*" }
        if attrs["strike"] as? Bool == true { core = "~~\(core)~~" }
        if let link = attrs["link"] as? String, !link.isEmpty, link != core { core = "[\(core)](\(link))" }
        return leading + core + trailing
    }

    private static func stripInlineCode(_ text: String) -> String {
        guard text.hasPrefix("`"), text.hasSuffix("`"), text.count >= 2 else { return text }
        return String(text.dropFirst().dropLast())
    }

    /// Slack embeds (emoji, @mentions, #channels, @here…). Emoji become their
    /// `:shortcode:`; anything else keeps its visible label rather than
    /// silently disappearing.
    private static func embedText(_ embed: [String: Any]) -> String {
        if let emoji = embed["slackemoji"] as? [String: Any] {
            if let text = emoji["text"] as? String { return text }
            if let name = emoji["name"] as? String { return ":\(name):" }
        }
        for (key, value) in embed {
            if let dict = value as? [String: Any] {
                let prefix: String
                switch key.lowercased() {
                case let k where k.contains("channel"): prefix = "#"
                case let k where k.contains("user") || k.contains("mention") || k.contains("broadcast")
                    || k.contains("usergroup") || k.contains("subteam"): prefix = "@"
                default: prefix = ""
                }
                for field in ["text", "label", "display_name", "name", "range", "handle"] {
                    if let s = dict[field] as? String, !s.isEmpty {
                        return s.hasPrefix(prefix) ? s : prefix + s
                    }
                }
            } else if let s = value as? String, !s.isEmpty, key != "image" {
                return s
            }
        }
        return ""
    }
}
