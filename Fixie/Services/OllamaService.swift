import Foundation

class OllamaService: LLMService {
    private let endpoint: String
    private let model: String

    init(endpoint: String, model: String) {
        self.endpoint = endpoint
        self.model = model
    }

    func correctGrammar(text: String) async throws -> String {
        let apiURL = "\(endpoint)/api/generate"

        guard let url = URL(string: apiURL) else {
            throw LLMError.serverError("Invalid Ollama endpoint URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 60 // Longer timeout for local models

        let body: [String: Any] = [
            "model": model,
            "prompt": "\(grammarPrompt)\(text)",
            "stream": false,
            "options": [
                "temperature": 0.3
            ]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMError.invalidResponse
        }

        if httpResponse.statusCode != 200 {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw LLMError.serverError("Ollama error: \(errorMessage)")
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let correctedText = json["response"] as? String else {
            throw LLMError.invalidResponse
        }

        return correctedText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func correctGrammarStreaming(text: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let apiURL = "\(endpoint)/api/generate"

                    guard let url = URL(string: apiURL) else {
                        continuation.finish(throwing: LLMError.serverError("Invalid Ollama endpoint URL"))
                        return
                    }

                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.addValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.timeoutInterval = 120

                    let body: [String: Any] = [
                        "model": model,
                        "prompt": "\(grammarPrompt)\(text)",
                        "stream": true,
                        "options": ["temperature": 0.3]
                    ]

                    request.httpBody = try JSONSerialization.data(withJSONObject: body)

                    let (bytes, response) = try await URLSession.shared.bytes(for: request)

                    guard let httpResponse = response as? HTTPURLResponse else {
                        continuation.finish(throwing: LLMError.invalidResponse)
                        return
                    }

                    if httpResponse.statusCode != 200 {
                        continuation.finish(throwing: LLMError.serverError("Ollama HTTP \(httpResponse.statusCode)"))
                        return
                    }

                    for try await line in bytes.lines {
                        if let data = line.data(using: .utf8),
                           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                            if let responseText = json["response"] as? String {
                                continuation.yield(responseText)
                            }
                            if let done = json["done"] as? Bool, done { break }
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
