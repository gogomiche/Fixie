import XCTest
@testable import Fixie

final class SettingsTests: XCTestCase {

    // MARK: - HotkeyConfig Tests

    func testHotkeyConfig_defaultHotkey() {
        let hotkey = HotkeyConfig.defaultHotkey

        XCTAssertEqual(hotkey.keyCode, 5) // G key
        XCTAssertEqual(hotkey.modifiers, 0x100 | 0x800) // Cmd + Option
    }

    func testHotkeyConfig_displayString() {
        let hotkey = HotkeyConfig(keyCode: 5, modifiers: 0x100 | 0x800)
        XCTAssertEqual(hotkey.displayString, "⌘⌥G")

        let hotkeyWithShift = HotkeyConfig(keyCode: 5, modifiers: 0x100 | 0x800 | 0x200)
        XCTAssertEqual(hotkeyWithShift.displayString, "⌘⌥⇧G")
    }

    // MARK: - ServiceConfiguration Tests

    func testServiceConfiguration_validateClaude_missingKey() {
        let config = ServiceConfiguration(
            provider: .claude,
            apiKey: nil,
            endpoint: nil,
            model: nil,
            timeout: 60,
            maxRetries: 2
        )

        XCTAssertThrowsError(try config.validate()) { error in
            guard let configError = error as? ConfigurationError else {
                XCTFail("Expected ConfigurationError")
                return
            }
            if case .missingAPIKey(let provider) = configError {
                XCTAssertEqual(provider, .claude)
            } else {
                XCTFail("Expected missingAPIKey error")
            }
        }
    }

    func testServiceConfiguration_validateClaude_invalidFormat() {
        let config = ServiceConfiguration(
            provider: .claude,
            apiKey: "invalid-key",
            endpoint: nil,
            model: nil,
            timeout: 60,
            maxRetries: 2
        )

        XCTAssertThrowsError(try config.validate()) { error in
            guard let configError = error as? ConfigurationError else {
                XCTFail("Expected ConfigurationError")
                return
            }
            if case .invalidAPIKeyFormat(let provider) = configError {
                XCTAssertEqual(provider, .claude)
            } else {
                XCTFail("Expected invalidAPIKeyFormat error")
            }
        }
    }

    func testServiceConfiguration_validateClaude_validKey() {
        let config = ServiceConfiguration(
            provider: .claude,
            apiKey: "sk-ant-test-key",
            endpoint: nil,
            model: nil,
            timeout: 60,
            maxRetries: 2
        )

        XCTAssertNoThrow(try config.validate())
    }

    func testServiceConfiguration_validateOpenAI_validKey() {
        let config = ServiceConfiguration(
            provider: .openai,
            apiKey: "sk-test-key",
            endpoint: nil,
            model: nil,
            timeout: 60,
            maxRetries: 2
        )

        XCTAssertNoThrow(try config.validate())
    }

    func testServiceConfiguration_validateOllama_validEndpoint() {
        let config = ServiceConfiguration(
            provider: .ollama,
            apiKey: nil,
            endpoint: "http://localhost:11434",
            model: "llama3.2",
            timeout: 120,
            maxRetries: 2
        )

        XCTAssertNoThrow(try config.validate())
    }

    func testServiceConfiguration_validateOllama_invalidEndpoint() {
        let config = ServiceConfiguration(
            provider: .ollama,
            apiKey: nil,
            endpoint: nil,
            model: "llama3.2",
            timeout: 120,
            maxRetries: 2
        )

        XCTAssertThrowsError(try config.validate()) { error in
            guard let configError = error as? ConfigurationError else {
                XCTFail("Expected ConfigurationError")
                return
            }
            if case .invalidEndpoint = configError {
                // Expected
            } else {
                XCTFail("Expected invalidEndpoint error")
            }
        }
    }

    // MARK: - GrammarMode Tests

    func testGrammarMode_defaultHotkey_grammar() {
        let hotkey = GrammarMode.grammar.defaultHotkey
        XCTAssertEqual(hotkey.keyCode, 3) // F
        XCTAssertEqual(hotkey.modifiers, 0x100 | 0x800) // Cmd + Option
        XCTAssertEqual(hotkey.displayString, "⌘⌥F")
    }

    func testGrammarMode_defaultHotkey_improve() {
        let hotkey = GrammarMode.improve.defaultHotkey
        XCTAssertEqual(hotkey.keyCode, 5) // G
        XCTAssertEqual(hotkey.modifiers, 0x100 | 0x800) // Cmd + Option
        XCTAssertEqual(hotkey.displayString, "⌘⌥G")
    }

    func testGrammarMode_displayName() {
        XCTAssertEqual(GrammarMode.grammar.displayName, "Grammar Correction")
        XCTAssertEqual(GrammarMode.improve.displayName, "Improve Phrasing")
    }

    func testGrammarMode_baseSystemPrompt_differsByMode() {
        XCTAssertNotEqual(GrammarMode.grammar.baseSystemPrompt, GrammarMode.improve.baseSystemPrompt)
        XCTAssertFalse(GrammarMode.grammar.baseSystemPrompt.isEmpty)
        XCTAssertFalse(GrammarMode.improve.baseSystemPrompt.isEmpty)
    }

    // MARK: - PromptBuilder Tests

    func testPromptBuilder_noAppendix_returnsBaseOnly() {
        let prompt = PromptBuilder.systemPrompt(for: .grammar, customAppendix: nil)
        XCTAssertEqual(prompt, GrammarMode.grammar.baseSystemPrompt)
    }

    func testPromptBuilder_emptyAppendix_returnsBaseOnly() {
        let prompt = PromptBuilder.systemPrompt(for: .grammar, customAppendix: "   \n   ")
        XCTAssertEqual(prompt, GrammarMode.grammar.baseSystemPrompt)
    }

    func testPromptBuilder_withAppendix_appendsInstructions() {
        let appendix = "Use a formal tone."
        let prompt = PromptBuilder.systemPrompt(for: .improve, customAppendix: appendix)

        XCTAssertTrue(prompt.contains(GrammarMode.improve.baseSystemPrompt))
        XCTAssertTrue(prompt.contains("Additional instructions from the user:"))
        XCTAssertTrue(prompt.contains(appendix))
    }

    // MARK: - LLMProvider Tests

    func testLLMProvider_requiresAPIKey() {
        XCTAssertTrue(LLMProvider.claude.requiresAPIKey)
        XCTAssertTrue(LLMProvider.openai.requiresAPIKey)
        XCTAssertFalse(LLMProvider.ollama.requiresAPIKey)
    }

    func testLLMProvider_displayName() {
        XCTAssertEqual(LLMProvider.claude.displayName, "Claude")
        XCTAssertEqual(LLMProvider.openai.displayName, "OpenAI")
        XCTAssertEqual(LLMProvider.ollama.displayName, "Ollama")
    }
}
