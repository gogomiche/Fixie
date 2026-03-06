import Foundation

/// Converts Slack's Quill Delta JSON format to markdown.
/// Slack stores formatted text in `org.chromium.web-custom-data` as Quill Delta ops.
enum QuillDeltaParser {

    static func toMarkdown(_ json: String) -> String? {
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let ops = obj["ops"] as? [[String: Any]] else { return nil }

        var result = ""
        var currentLine = ""
        var orderedCounter = 0

        for op in ops {
            if let text = op["insert"] as? String {
                let attrs = op["attributes"] as? [String: Any]

                if text == "\n" {
                    // Standalone newline — may carry line-level attributes (list, blockquote…)
                    finalizeLine(&result, &currentLine, attrs, &orderedCounter)
                } else {
                    // Text that may contain embedded newlines
                    let parts = text.components(separatedBy: "\n")
                    for (i, part) in parts.enumerated() {
                        if i > 0 {
                            // Embedded \n — no special line-level attributes
                            finalizeLine(&result, &currentLine, nil, &orderedCounter)
                        }
                        if !part.isEmpty {
                            var formatted = part
                            if let attrs = attrs {
                                if attrs["bold"] as? Bool == true { formatted = "**\(formatted)**" }
                                if attrs["italic"] as? Bool == true { formatted = "*\(formatted)*" }
                                if attrs["strike"] as? Bool == true { formatted = "~~\(formatted)~~" }
                                if attrs["code"] as? Bool == true { formatted = "`\(formatted)`" }
                                if let link = attrs["link"] as? String { formatted = "[\(formatted)](\(link))" }
                            }
                            currentLine += formatted
                        }
                    }
                }
            } else if let embed = op["insert"] as? [String: Any] {
                if let emoji = embed["slackemoji"] as? [String: Any],
                   let emojiText = emoji["text"] as? String {
                    currentLine += emojiText
                }
            }
        }

        // Remaining text (no trailing \n)
        if !currentLine.isEmpty {
            result += currentLine
        }

        let trimmed = result.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    // MARK: - Chromium clipboard

    /// Extract the Slack Quill Delta JSON from Chromium's web-custom-data.
    /// Searches for `{"ops":[` in UTF-16LE encoded data and extracts the complete JSON object.
    static func extractSlackJSON(from data: Data) -> String? {
        // Decode entire blob as UTF-16LE
        guard let decoded = String(data: data, encoding: .utf16LittleEndian) else { return nil }

        // Find the Quill Delta JSON — starts with {"ops":[
        guard let jsonStart = decoded.range(of: "{\"ops\":[") else { return nil }

        // Extract from { to the matching closing }
        let substring = decoded[jsonStart.lowerBound...]
        var depth = 0
        var endIndex = substring.startIndex
        for ch in substring {
            if ch == "{" { depth += 1 }
            else if ch == "}" { depth -= 1 }
            endIndex = substring.index(after: endIndex)
            if depth == 0 { break }
        }

        guard depth == 0 else { return nil }
        return String(substring[..<endIndex])
    }

    // MARK: - Private

    private static func finalizeLine(
        _ result: inout String,
        _ currentLine: inout String,
        _ attrs: [String: Any]?,
        _ orderedCounter: inout Int
    ) {
        if let listType = attrs?["list"] as? String {
            if listType == "bullet" {
                result += "- " + currentLine + "\n"
                orderedCounter = 0
            } else if listType == "ordered" {
                orderedCounter += 1
                result += "\(orderedCounter). " + currentLine + "\n"
            }
        } else if attrs?["blockquote"] as? Bool == true {
            result += "> " + currentLine + "\n"
            orderedCounter = 0
        } else if attrs?["code-block"] as? Bool == true {
            result += "```\n" + currentLine + "\n```\n"
            orderedCounter = 0
        } else {
            result += currentLine + "\n"
            orderedCounter = 0
        }
        currentLine = ""
    }
}
