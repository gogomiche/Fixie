import Foundation

/// The two operating modes Fixie supports. Each mode has its own hotkey,
/// system prompt, and custom-prompt slot in Settings.
enum GrammarMode: String, CaseIterable, Codable {
    case grammar
    case improve

    /// User-facing name shown in Settings and menus.
    var displayName: String {
        switch self {
        case .grammar: return "Grammar Correction"
        case .improve: return "Improve Phrasing"
        }
    }

    /// Title shown at the top of the popup window during processing.
    var popupTitle: String {
        switch self {
        case .grammar: return "Fix Spelling and Grammar"
        case .improve: return "Improve Phrasing"
        }
    }

    /// Loading text shown while the LLM is streaming.
    var loadingLabel: String {
        switch self {
        case .grammar: return "Checking grammar…"
        case .improve: return "Improving phrasing…"
        }
    }

    /// The default global hotkey for this mode.
    /// ⌥⌘F for grammar, ⌥⌘G for improve.
    var defaultHotkey: HotkeyConfig {
        switch self {
        case .grammar:
            return HotkeyConfig(keyCode: 3, modifiers: 0x100 | 0x800)   // F + Cmd + Option
        case .improve:
            return HotkeyConfig(keyCode: 5, modifiers: 0x100 | 0x800)   // G + Cmd + Option
        }
    }

    /// The strict system prompt sent to the LLM for this mode. Custom user
    /// instructions are appended on top (see `PromptBuilder.systemPrompt`).
    var baseSystemPrompt: String {
        switch self {
        case .grammar:
            return Self.grammarBasePrompt
        case .improve:
            return Self.improveBasePrompt
        }
    }

    // MARK: - Base prompts

    private static let formattingRules = """
    - Detect the language of the input automatically and respond in the same language. The user may write in any language (English, French, Spanish, etc.) — do not translate.
    - Preserve all formatting: line breaks, paragraphs, indentation, lists, and whitespace structure.
    - If the text contains ANY markdown or rich-text syntax, you MUST preserve every syntax character exactly. This includes:
      • Headers: # ## ### etc.
      • Bold: **text** or __text__
      • Italic: *text* or _text_
      • Strikethrough: ~text~ or ~~text~~
      • Links: [text](url)
      • Images: ![alt](url)
      • Lists: - item, * item, 1. item
      • Code: `inline` and ```code blocks```
      • Blockquotes: > text
      • Tables, horizontal rules (---), and any other markup
      Do NOT add markdown syntax that was not in the original. Do NOT remove or alter existing markdown syntax.
    - Return ONLY the resulting text. No explanations, no quotes, no prefixes, no labels.
    - NEVER wrap your response in code fences, backticks, or any other markup that wasn't in the original text.
    """

    private static let grammarBasePrompt = """
    You are a grammar, spelling, and style correction assistant. Follow these rules strictly:

    1. Fix grammar, spelling, punctuation, and light style issues (awkward phrasing, redundancy).
    2. Do NOT change the meaning, tone, or intent of the text.
    3. If the text has no errors, return it unchanged.
    4. \(formattingRules)
    """

    private static let improveBasePrompt = """
    You are a writing assistant. Your job is to lightly improve clarity and fluidity of the user's text. Follow these rules strictly:

    1. Improve clarity, flow, and readability with light edits only.
    2. Do NOT change the meaning, intent, or tone of the text. Keep the same voice.
    3. Do NOT restructure paragraphs or rewrite extensively. Prefer small, targeted edits.
    4. Fix any grammar or spelling errors you encounter as part of the improvement.
    5. If the text is already clear and well-phrased, return it unchanged.
    6. \(formattingRules)
    """
}
