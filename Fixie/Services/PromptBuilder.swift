import Foundation

enum PromptBuilder {
    /// Build the system prompt for a given mode, optionally appending the
    /// user's custom instructions from Settings.
    static func systemPrompt(for mode: GrammarMode, customAppendix: String? = nil) -> String {
        var prompt = mode.baseSystemPrompt

        if let appendix = customAppendix?.trimmingCharacters(in: .whitespacesAndNewlines),
           !appendix.isEmpty {
            prompt += """


            Additional instructions from the user:
            \(appendix)
            """
        }

        return prompt
    }

    static func userMessage(for text: String) -> String {
        text
    }

    /// Strip outer code fence wrapping if LLM ignored instructions
    static func sanitizeResponse(_ text: String) -> String {
        var result = text.trimmingCharacters(in: .whitespacesAndNewlines)

        let codeFencePattern = #"^```[a-zA-Z]*\n?([\s\S]*?)\n?```$"#
        if let regex = try? NSRegularExpression(pattern: codeFencePattern),
           let match = regex.firstMatch(in: result, range: NSRange(result.startIndex..., in: result)),
           let captureRange = Range(match.range(at: 1), in: result) {
            result = String(result[captureRange])
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return result
    }
}

/// What the model can't be trusted to keep: the line break characters (Notes
/// and other AppKit apps put U+2028 between lines of a paragraph; models drop
/// it and glue the lines together) and the whitespace around the selection
/// (responses are trimmed, so a selected trailing newline would be lost).
/// The model and the diff get `body`, with plain "\n" breaks and nothing around
/// it; `restore` puts the original breaks and whitespace back before writing.
struct TextEnvelope {
    /// Text sent to the model and shown in the diff.
    let body: String
    private let leading: String
    private let trailing: String
    /// The body's original line breaks, in order ("\r\n" counts as one).
    private let lineBreaks: [String]

    init(_ original: String) {
        let start = original.firstIndex { !$0.isWhitespace } ?? original.endIndex
        let end = original.lastIndex { !$0.isWhitespace }.map { original.index(after: $0) } ?? start
        let core = String(original[start..<end])
        leading = String(original[..<start])
        trailing = String(original[end...])
        lineBreaks = core.filter(\.isNewline).map(String.init)
        body = Self.normalizingLineBreaks(core)
    }

    /// Every kind of line break (U+2028, U+2029, "\r\n", "\r"…) as "\n".
    static func normalizingLineBreaks(_ text: String) -> String {
        String(text.map { $0.isNewline ? "\n" : $0 })
    }

    /// The model's answer with the original line breaks and surrounding whitespace.
    func restore(_ corrected: String) -> String {
        let lines = Self.normalizingLineBreaks(corrected)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: "\n")
        let breakCount = lines.count - 1

        let separators: [String]
        if breakCount == lineBreaks.count {
            // Same shape: each break goes back where it was
            separators = lineBreaks
        } else if let only = lineBreaks.first, lineBreaks.allSatisfy({ $0 == only }) {
            // Lines added or merged, but the text used a single kind of break
            separators = Array(repeating: only, count: breakCount)
        } else {
            separators = Array(repeating: "\n", count: breakCount)
        }

        var result = leading
        for (index, line) in lines.enumerated() {
            if index > 0 { result += separators[index - 1] }
            result += line
        }
        return result + trailing
    }
}
