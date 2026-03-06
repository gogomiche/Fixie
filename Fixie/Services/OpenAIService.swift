import Foundation

final class OpenAIService: BaseLLMService {
    private let apiKey: String
    private let model: String

    override var providerName: String { "OpenAI" }
    override var apiURL: String { "https://api.openai.com/v1/chat/completions" }

    override var streamParser: StreamParser {
        SSEStreamParser { json in
            guard let choices = json["choices"] as? [[String: Any]],
                  let firstChoice = choices.first,
                  let delta = firstChoice["delta"] as? [String: Any],
                  let content = delta["content"] as? String else {
                return nil
            }
            return content
        }
    }

    init(apiKey: String, model: String = "gpt-4o-mini", timeout: TimeInterval = ServiceConfiguration.defaultTimeout) {
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
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
    }

    /// Reasoning models (o-series, gpt-5+) use different parameters than classic models
    private var isReasoningModel: Bool {
        model.hasPrefix("o1") || model.hasPrefix("o3") || model.hasPrefix("o4") ||
        model.hasPrefix("gpt-5")
    }

    override func buildRequestBody(text: String, stream: Bool) -> [String: Any] {
        var body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": PromptBuilder.systemPrompt],
                ["role": "user", "content": PromptBuilder.userMessage(for: text)]
            ]
        ]

        if isReasoningModel {
            body["max_completion_tokens"] = 4096
            body["reasoning_effort"] = "low"
        } else {
            body["max_tokens"] = 4096
            body["temperature"] = 0.3
        }

        if stream {
            body["stream"] = true
        }
        return body
    }

    override func parseResponse(data: Data) throws -> String {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let correctedText = message["content"] as? String else {
            throw LLMError.invalidResponse
        }
        return PromptBuilder.sanitizeResponse(correctedText)
    }
}
