import Foundation

// MARK: - LLM Service Protocol

protocol LLMService {
    var providerName: String { get }
    func correctGrammar(text: String) async throws -> String
    func correctGrammarStreaming(text: String) -> AsyncThrowingStream<String, Error>
}

// MARK: - Stream Parsing Strategy

protocol StreamParser {
    func parseChunk(from line: String) -> String?
    func isComplete(line: String) -> Bool
}

/// SSE (Server-Sent Events) parser for Claude and OpenAI
struct SSEStreamParser: StreamParser {
    private let chunkExtractor: ([String: Any]) -> String?

    init(chunkExtractor: @escaping ([String: Any]) -> String?) {
        self.chunkExtractor = chunkExtractor
    }

    func parseChunk(from line: String) -> String? {
        guard line.hasPrefix("data: ") else { return nil }

        let jsonString = String(line.dropFirst(6))
        if jsonString == "[DONE]" { return nil }

        guard let data = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        return chunkExtractor(json)
    }

    func isComplete(line: String) -> Bool {
        line.hasPrefix("data: [DONE]")
    }
}

/// JSONL (JSON Lines) parser for Ollama
struct JSONLStreamParser: StreamParser {
    private let chunkExtractor: ([String: Any]) -> String?
    private let completionChecker: ([String: Any]) -> Bool

    init(
        chunkExtractor: @escaping ([String: Any]) -> String?,
        completionChecker: @escaping ([String: Any]) -> Bool
    ) {
        self.chunkExtractor = chunkExtractor
        self.completionChecker = completionChecker
    }

    func parseChunk(from line: String) -> String? {
        guard let data = line.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        if completionChecker(json) { return nil }
        return chunkExtractor(json)
    }

    func isComplete(line: String) -> Bool {
        guard let data = line.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return false
        }
        return completionChecker(json)
    }
}

// MARK: - LLM Errors

enum LLMError: LocalizedError {
    case invalidAPIKey
    case networkError(Error)
    case invalidResponse
    case rateLimited
    case serverError(String)
    case timeout
    case cancelled
    case configurationError(String)

    var errorDescription: String? {
        switch self {
        case .invalidAPIKey:
            return "Invalid API key. Please check your settings."
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .invalidResponse:
            return "Invalid response from API"
        case .rateLimited:
            return "Rate limited. Please try again in a few moments."
        case .serverError(let message):
            return "Server error: \(message)"
        case .timeout:
            return "Request timed out. Please try again."
        case .cancelled:
            return "Request was cancelled."
        case .configurationError(let message):
            return message
        }
    }

    var isRetryable: Bool {
        switch self {
        case .rateLimited, .timeout, .networkError:
            return true
        default:
            return false
        }
    }
}

// MARK: - Service Factory

class LLMServiceFactory {
    static func create(provider: LLMProvider, settings: SettingsManager) -> LLMService {
        let config = settings.getServiceConfiguration()

        switch provider {
        case .claude:
            return ClaudeService(
                apiKey: config.apiKey ?? "",
                timeout: config.timeout
            )
        case .openai:
            return OpenAIService(
                apiKey: config.apiKey ?? "",
                timeout: config.timeout
            )
        case .ollama:
            return OllamaService(
                endpoint: config.endpoint ?? "http://localhost:11434",
                model: config.model ?? "llama3.2",
                timeout: config.timeout
            )
        }
    }

    static func create(from configuration: ServiceConfiguration) throws -> LLMService {
        try configuration.validate()

        switch configuration.provider {
        case .claude:
            return ClaudeService(
                apiKey: configuration.apiKey ?? "",
                timeout: configuration.timeout
            )
        case .openai:
            return OpenAIService(
                apiKey: configuration.apiKey ?? "",
                timeout: configuration.timeout
            )
        case .ollama:
            return OllamaService(
                endpoint: configuration.endpoint ?? "http://localhost:11434",
                model: configuration.model ?? "llama3.2",
                timeout: configuration.timeout
            )
        }
    }
}

// MARK: - Grammar Prompt

let grammarPrompt = """
You are a grammar and spelling correction assistant. Your task is to fix any grammar, spelling, punctuation, and style issues in the provided text.

Rules:
1. Only fix errors - do not change the meaning or tone
2. Preserve the original formatting (line breaks, paragraphs)
3. Keep technical terms, proper nouns, and intentional stylistic choices
4. Return ONLY the corrected text, nothing else - no explanations, no quotes, no prefixes

Text to correct:
"""

// MARK: - Input Sanitization

extension String {
    /// Sanitize input text for LLM processing
    func sanitizedForLLM() -> String {
        // Remove null bytes and other control characters that could cause issues
        let filtered = self.unicodeScalars.filter { scalar in
            // Allow printable characters, newlines, tabs
            scalar.value == 0x09 || // Tab
            scalar.value == 0x0A || // Newline
            scalar.value == 0x0D || // Carriage return
            (scalar.value >= 0x20 && scalar.value != 0x7F) // Printable ASCII and Unicode
        }
        return String(String.UnicodeScalarView(filtered))
    }

    /// Check if the string contains potentially problematic content
    var containsProblematicContent: Bool {
        // Check for extremely long lines that might cause issues
        let lines = self.components(separatedBy: .newlines)
        return lines.contains { $0.count > 10000 }
    }
}
