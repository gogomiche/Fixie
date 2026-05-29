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

    override func buildRequestBody(text: String, stream: Bool, systemPrompt: String) -> [String: Any] {
        return [
            "model": model,
            "system": systemPrompt,
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

    /// Fetch the list of locally-installed Ollama models from `/api/tags`.
    /// Returns model names (e.g. "llama3.2:3b"). Throws on network/parse failure
    /// so callers can distinguish "Ollama is not running" from "no models".
    static func fetchAvailableModels(endpoint: String) async throws -> [String] {
        guard let url = URL(string: "\(endpoint)/api/tags") else {
            throw LLMError.serverError("Invalid Ollama endpoint URL")
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 5

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw LLMError.serverError("Ollama not reachable at \(endpoint)")
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let models = json["models"] as? [[String: Any]] else {
            throw LLMError.invalidResponse
        }

        return models.compactMap { $0["name"] as? String }
    }
}
