import Foundation

protocol LLMService {
    func correctGrammar(text: String) async throws -> String
    func correctGrammarStreaming(text: String) -> AsyncThrowingStream<String, Error>
}

enum LLMError: LocalizedError {
    case invalidAPIKey
    case networkError(Error)
    case invalidResponse
    case rateLimited
    case serverError(String)

    var errorDescription: String? {
        switch self {
        case .invalidAPIKey:
            return "Invalid API key. Please check your settings."
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .invalidResponse:
            return "Invalid response from API"
        case .rateLimited:
            return "Rate limited. Please try again later."
        case .serverError(let message):
            return "Server error: \(message)"
        }
    }
}

class LLMServiceFactory {
    static func create(provider: LLMProvider, settings: SettingsManager) -> LLMService {
        switch provider {
        case .claude:
            return ClaudeService(apiKey: settings.claudeAPIKey)
        case .openai:
            return OpenAIService(apiKey: settings.openAIAPIKey)
        case .ollama:
            return OllamaService(endpoint: settings.ollamaEndpoint, model: settings.ollamaModel)
        }
    }
}

let grammarPrompt = """
You are a grammar and spelling correction assistant. Your task is to fix any grammar, spelling, punctuation, and style issues in the provided text.

Rules:
1. Only fix errors - do not change the meaning or tone
2. Preserve the original formatting (line breaks, paragraphs)
3. Keep technical terms, proper nouns, and intentional stylistic choices
4. Return ONLY the corrected text, nothing else - no explanations, no quotes, no prefixes

Text to correct:
"""
