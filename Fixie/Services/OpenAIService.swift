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

    init(apiKey: String, model: String = ModelCatalog.defaultOpenAI, timeout: TimeInterval = ServiceConfiguration.defaultTimeout) {
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

    /// Reasoning models (o-series, gpt-5+, gpt-6) use different parameters than classic models:
    /// `max_completion_tokens` instead of `max_tokens`, no `temperature`.
    var isReasoningModel: Bool {
        model.hasPrefix("o1") || model.hasPrefix("o3") || model.hasPrefix("o4") ||
        model.hasPrefix("gpt-5") || model.hasPrefix("gpt-6")
    }

    /// Lowest reasoning effort the model accepts — proofreading doesn't need
    /// deliberation, and every reasoning token adds latency.
    /// GPT-6 Terra/Luna accept `none`; GPT-6 Astra/Sol start at `low`.
    var reasoningEffort: String {
        if model.hasPrefix("gpt-6"), model.contains("terra") || model.contains("luna") {
            return "none"
        }
        return "low"
    }

    override func buildRequestBody(text: String, stream: Bool, systemPrompt: String) -> [String: Any] {
        var body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": PromptBuilder.userMessage(for: text)]
            ]
        ]

        if isReasoningModel {
            // Reasoning tokens count against this limit: leave room so long
            // texts aren't cut off.
            body["max_completion_tokens"] = 16384
            body["reasoning_effort"] = reasoningEffort
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
