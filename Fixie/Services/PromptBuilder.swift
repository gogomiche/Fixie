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
