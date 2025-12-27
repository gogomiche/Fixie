import Foundation

/// Base class for LLM services with common HTTP handling
class BaseLLMService: LLMService {

    let timeout: TimeInterval

    init(timeout: TimeInterval = ServiceConfiguration.defaultTimeout) {
        self.timeout = timeout
    }

    // MARK: - Abstract properties/methods (to be overridden by subclasses)

    var providerName: String { fatalError("Subclasses must override providerName") }
    var apiURL: String { fatalError("Subclasses must override apiURL") }
    var streamParser: StreamParser { fatalError("Subclasses must override streamParser") }

    func configureRequest(_ request: inout URLRequest, forText text: String) {
        fatalError("Subclasses must override configureRequest")
    }

    func buildRequestBody(text: String, stream: Bool) -> [String: Any] {
        fatalError("Subclasses must override buildRequestBody")
    }

    func parseResponse(data: Data) throws -> String {
        fatalError("Subclasses must override parseResponse")
    }

    func validateConfiguration() throws {
        // Override in subclasses if needed
    }

    // MARK: - Common implementation

    func correctGrammar(text: String) async throws -> String {
        try validateConfiguration()

        let sanitizedText = text.sanitizedForLLM()

        guard let url = URL(string: apiURL) else {
            throw LLMError.serverError("Invalid API URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        configureRequest(&request, forText: sanitizedText)
        request.httpBody = try JSONSerialization.data(withJSONObject: buildRequestBody(text: sanitizedText, stream: false))

        let (data, response) = try await URLSession.shared.data(for: request)

        try handleHTTPResponse(response, data: data)

        return try parseResponse(data: data)
    }

    func correctGrammarStreaming(text: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    try validateConfiguration()

                    let sanitizedText = text.sanitizedForLLM()

                    guard let url = URL(string: apiURL) else {
                        continuation.finish(throwing: LLMError.serverError("Invalid API URL"))
                        return
                    }

                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.timeoutInterval = timeout
                    request.addValue("application/json", forHTTPHeaderField: "Content-Type")

                    configureRequest(&request, forText: sanitizedText)
                    request.httpBody = try JSONSerialization.data(withJSONObject: buildRequestBody(text: sanitizedText, stream: true))

                    let (bytes, response) = try await URLSession.shared.bytes(for: request)

                    try handleHTTPResponseForStreaming(response)

                    let parser = self.streamParser

                    for try await line in bytes.lines {
                        if parser.isComplete(line: line) {
                            break
                        }
                        if let chunk = parser.parseChunk(from: line) {
                            continuation.yield(chunk)
                        }
                    }
                    continuation.finish()
                } catch let error as URLError where error.code == .timedOut {
                    continuation.finish(throwing: LLMError.timeout)
                } catch let error as URLError where error.code == .cancelled {
                    continuation.finish(throwing: LLMError.cancelled)
                } catch {
                    if error is LLMError {
                        continuation.finish(throwing: error)
                    } else {
                        continuation.finish(throwing: LLMError.networkError(error))
                    }
                }
            }
        }
    }

    // MARK: - Helper methods

    private func handleHTTPResponse(_ response: URLResponse, data: Data) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200...299:
            return
        case 401, 403:
            throw LLMError.invalidAPIKey
        case 429:
            throw LLMError.rateLimited
        case 408, 504:
            throw LLMError.timeout
        case 500...599:
            let errorMessage = extractErrorMessage(from: data) ?? "Server error (HTTP \(httpResponse.statusCode))"
            throw LLMError.serverError(errorMessage)
        default:
            let errorMessage = extractErrorMessage(from: data) ?? "HTTP \(httpResponse.statusCode)"
            throw LLMError.serverError(errorMessage)
        }
    }

    private func handleHTTPResponseForStreaming(_ response: URLResponse) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200...299:
            return
        case 401, 403:
            throw LLMError.invalidAPIKey
        case 429:
            throw LLMError.rateLimited
        case 408, 504:
            throw LLMError.timeout
        default:
            throw LLMError.serverError("HTTP \(httpResponse.statusCode)")
        }
    }

    private func extractErrorMessage(from data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return String(data: data, encoding: .utf8)
        }

        // Try common error message formats
        if let error = json["error"] as? [String: Any],
           let message = error["message"] as? String {
            return message
        }
        if let message = json["message"] as? String {
            return message
        }
        if let error = json["error"] as? String {
            return error
        }

        return nil
    }
}
