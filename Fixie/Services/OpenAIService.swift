import Foundation

class OpenAIService: LLMService {
    private let apiKey: String
    private let apiURL = "https://api.openai.com/v1/chat/completions"

    init(apiKey: String) {
        self.apiKey = apiKey
    }

    func correctGrammar(text: String) async throws -> String {
        guard !apiKey.isEmpty else {
            throw LLMError.invalidAPIKey
        }

        var request = URLRequest(url: URL(string: apiURL)!)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let body: [String: Any] = [
            "model": "gpt-4o-mini",
            "messages": [
                ["role": "user", "content": "\(grammarPrompt)\(text)"]
            ],
            "max_tokens": 4096,
            "temperature": 0.3
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMError.invalidResponse
        }

        if httpResponse.statusCode == 401 {
            throw LLMError.invalidAPIKey
        } else if httpResponse.statusCode == 429 {
            throw LLMError.rateLimited
        } else if httpResponse.statusCode != 200 {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw LLMError.serverError(errorMessage)
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let correctedText = message["content"] as? String else {
            throw LLMError.invalidResponse
        }

        return correctedText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func correctGrammarStreaming(text: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    guard !apiKey.isEmpty else {
                        continuation.finish(throwing: LLMError.invalidAPIKey)
                        return
                    }

                    var request = URLRequest(url: URL(string: apiURL)!)
                    request.httpMethod = "POST"
                    request.addValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

                    let body: [String: Any] = [
                        "model": "gpt-4o-mini",
                        "messages": [
                            ["role": "user", "content": "\(grammarPrompt)\(text)"]
                        ],
                        "max_tokens": 4096,
                        "temperature": 0.3,
                        "stream": true
                    ]

                    request.httpBody = try JSONSerialization.data(withJSONObject: body)

                    let (bytes, response) = try await URLSession.shared.bytes(for: request)

                    guard let httpResponse = response as? HTTPURLResponse else {
                        continuation.finish(throwing: LLMError.invalidResponse)
                        return
                    }

                    if httpResponse.statusCode == 401 {
                        continuation.finish(throwing: LLMError.invalidAPIKey)
                        return
                    } else if httpResponse.statusCode == 429 {
                        continuation.finish(throwing: LLMError.rateLimited)
                        return
                    } else if httpResponse.statusCode != 200 {
                        continuation.finish(throwing: LLMError.serverError("HTTP \(httpResponse.statusCode)"))
                        return
                    }

                    for try await line in bytes.lines {
                        if line.hasPrefix("data: ") {
                            let jsonString = String(line.dropFirst(6))
                            if jsonString == "[DONE]" { break }
                            if let data = jsonString.data(using: .utf8),
                               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                               let choices = json["choices"] as? [[String: Any]],
                               let firstChoice = choices.first,
                               let delta = firstChoice["delta"] as? [String: Any],
                               let content = delta["content"] as? String {
                                continuation.yield(content)
                            }
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: LLMError.networkError(error))
                }
            }
        }
    }
}
