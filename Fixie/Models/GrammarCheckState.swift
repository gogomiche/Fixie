import Foundation

/// State machine for grammar check workflow
enum GrammarCheckState: Equatable {
    case idle
    case capturing
    case processing(progress: StreamProgress)
    case complete(result: GrammarResult)
    case error(GrammarError)

    var isActive: Bool {
        switch self {
        case .idle, .complete, .error:
            return false
        case .capturing, .processing:
            return true
        }
    }

    var canAccept: Bool {
        if case .complete = self {
            return true
        }
        return false
    }
}

/// Progress information for streaming
struct StreamProgress: Equatable {
    let originalText: String
    var streamedText: String
    var characterCount: Int

    var isEmpty: Bool {
        streamedText.isEmpty
    }

    init(originalText: String) {
        self.originalText = originalText
        self.streamedText = ""
        self.characterCount = 0
    }

    mutating func append(_ chunk: String) {
        streamedText += chunk
        characterCount = streamedText.count
    }
}

/// Result of a successful grammar check
struct GrammarResult: Equatable {
    let originalText: String
    let correctedText: String
    let provider: String

    var hasChanges: Bool {
        originalText != correctedText
    }

    var characterDelta: Int {
        correctedText.count - originalText.count
    }
}

/// Errors that can occur during grammar check
enum GrammarError: LocalizedError, Equatable {
    case noTextSelected
    case textTooLong(maxLength: Int)
    case accessibilityNotAvailable
    case configurationInvalid(String)
    case networkError(String)
    case apiError(String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .noTextSelected:
            return "No text selected. Please select some text and try again."
        case .textTooLong(let maxLength):
            return "Selected text is too long. Maximum \(maxLength) characters allowed."
        case .accessibilityNotAvailable:
            return "Accessibility permission is required. Please enable it in System Settings."
        case .configurationInvalid(let message):
            return message
        case .networkError(let message):
            return "Network error: \(message)"
        case .apiError(let message):
            return "API error: \(message)"
        case .cancelled:
            return "Operation was cancelled."
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .noTextSelected:
            return "Select text in any application, then press the hotkey."
        case .textTooLong:
            return "Try selecting a smaller portion of text."
        case .accessibilityNotAvailable:
            return "Go to System Settings → Privacy & Security → Accessibility and enable Fixie."
        case .configurationInvalid:
            return "Open Fixie settings to configure your API key."
        case .networkError:
            return "Check your internet connection and try again."
        case .apiError:
            return "Check your API key and try again."
        case .cancelled:
            return nil
        }
    }
}

// MARK: - State Manager

@MainActor
class GrammarCheckStateManager: ObservableObject {
    @Published private(set) var state: GrammarCheckState = .idle
    @Published var streamingText: String = ""
    @Published var isComplete: Bool = false

    private var currentTask: Task<Void, Never>?

    var originalText: String {
        switch state {
        case .processing(let progress):
            return progress.originalText
        case .complete(let result):
            return result.originalText
        default:
            return ""
        }
    }

    var correctedText: String {
        switch state {
        case .processing(let progress):
            return progress.streamedText
        case .complete(let result):
            return result.correctedText
        default:
            return ""
        }
    }

    func startCapturing() {
        state = .capturing
        streamingText = ""
        isComplete = false
    }

    func startProcessing(originalText: String) {
        state = .processing(progress: StreamProgress(originalText: originalText))
        streamingText = ""
        isComplete = false
    }

    func appendChunk(_ chunk: String) {
        guard case .processing(var progress) = state else { return }
        progress.append(chunk)
        state = .processing(progress: progress)
        streamingText = progress.streamedText
    }

    func complete(correctedText: String, provider: String) {
        guard case .processing(let progress) = state else { return }
        let result = GrammarResult(
            originalText: progress.originalText,
            correctedText: correctedText,
            provider: provider
        )
        state = .complete(result: result)
        streamingText = correctedText
        isComplete = true
    }

    func fail(with error: GrammarError) {
        state = .error(error)
        isComplete = true
    }

    func reset() {
        currentTask?.cancel()
        currentTask = nil
        state = .idle
        streamingText = ""
        isComplete = false
    }

    func setTask(_ task: Task<Void, Never>) {
        currentTask = task
    }

    func cancelCurrentTask() {
        currentTask?.cancel()
        currentTask = nil
    }
}
