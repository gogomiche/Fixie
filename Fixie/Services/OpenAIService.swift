import Foundation

final class OpenAIService: BaseLLMService {
    private let apiKey: String

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

    init(apiKey: String, timeout: TimeInterval = ServiceConfiguration.defaultTimeout) {
        self.apiKey = apiKey
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

    override func buildRequestBody(text: String, stream: Bool) -> [String: Any] {
        var body: [String: Any] = [
            "model": "gpt-4o-mini",
            "messages": [
                ["role": "user", "content": "\(grammarPrompt)\(text)"]
            ],
            "max_tokens": 4096,
            "temperature": 0.3
        ]
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
        return correctedText.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
