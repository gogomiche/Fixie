import Foundation

final class OllamaService: BaseLLMService {
    private let endpoint: String
    private let model: String

    override var providerName: String { "Ollama" }
    override var apiURL: String { "\(endpoint)/api/generate" }

    override var streamParser: StreamParser {
        JSONLStreamParser(
            chunkExtractor: { json in
                json["response"] as? String
            },
            completionChecker: { json in
                json["done"] as? Bool ?? false
            }
        )
    }

    init(endpoint: String, model: String, timeout: TimeInterval = ServiceConfiguration.defaultOllamaTimeout) {
        self.endpoint = endpoint
        self.model = model
        super.init(timeout: timeout)
    }

    override func validateConfiguration() throws {
        guard URL(string: apiURL) != nil else {
            throw LLMError.serverError("Invalid Ollama endpoint URL")
        }
    }

    override func configureRequest(_ request: inout URLRequest, forText text: String) {
        // No additional headers needed for Ollama
    }

    override func buildRequestBody(text: String, stream: Bool) -> [String: Any] {
        return [
            "model": model,
            "system": PromptBuilder.systemPrompt,
            "prompt": PromptBuilder.userMessage(for: text),
            "stream": stream,
            "options": ["temperature": 0.3]
        ]
    }

    override func parseResponse(data: Data) throws -> String {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let correctedText = json["response"] as? String else {
            throw LLMError.invalidResponse
        }
        return PromptBuilder.sanitizeResponse(correctedText)
    }
}
