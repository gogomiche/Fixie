import Foundation

final class ClaudeService: BaseLLMService {
    private let apiKey: String
    private let model: String

    override var providerName: String { "Claude" }
    override var apiURL: String { "https://api.anthropic.com/v1/messages" }

    override var streamParser: StreamParser {
        SSEStreamParser { json in
            guard let type = json["type"] as? String,
                  type == "content_block_delta",
                  let delta = json["delta"] as? [String: Any],
                  let text = delta["text"] as? String else {
                return nil
            }
            return text
        }
    }

    init(apiKey: String, model: String = "claude-sonnet-4-20250514", timeout: TimeInterval = ServiceConfiguration.defaultTimeout) {
        self.apiKey = apiKey
        self.model = model
        super.init(timeout: timeout)
    }

    override func validateConfiguration() throws {
        guard !apiKey.isEmpty else {
            throw LLMError.invalidAPIKey
        }
    }

    override func configureRequest(_ request: inout URLRequest, forText text: String) {
        request.addValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.addValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
    }

    override func buildRequestBody(text: String, stream: Bool) -> [String: Any] {
        var body: [String: Any] = [
            "model": model,
            "system": PromptBuilder.systemPrompt,
            "max_tokens": 4096,
            "messages": [
                ["role": "user", "content": PromptBuilder.userMessage(for: text)]
            ]
        ]
        if stream {
            body["stream"] = true
        }
        return body
    }

    override func parseResponse(data: Data) throws -> String {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]],
              let firstContent = content.first,
              let correctedText = firstContent["text"] as? String else {
            throw LLMError.invalidResponse
        }
        return PromptBuilder.sanitizeResponse(correctedText)
    }
}
