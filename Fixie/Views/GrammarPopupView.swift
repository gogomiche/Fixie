import SwiftUI

/// Raycast-style grammar correction popup
struct GrammarPopupView: View {
    let originalText: String
    let correctedText: String
    let isLoading: Bool
    let streamingText: String
    let providerName: String
    let onAccept: () -> Void
    let onReject: () -> Void

    @State private var isHoveringAccept = false

    private var characterCount: Int {
        correctedText.count
    }

    private var wordCount: Int {
        correctedText.split(separator: " ").count
    }

    // Compute diff text directly instead of using @State
    private var diffResult: (text: AttributedString, changeCount: Int) {
        computeDiff()
    }

    private var diffText: AttributedString {
        diffResult.text
    }

    private var changeCount: Int {
        diffResult.changeCount
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: "text.badge.checkmark")
                    .font(.system(size: 16))
                    .foregroundColor(.yellow)
                Text("Fix Spelling and Grammar")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white.opacity(0.9))
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 12)

            // Main content area - scrollable
            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 0) {
                    if isLoading {
                        HStack(spacing: 10) {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text(streamingText.isEmpty ? "Checking grammar..." : streamingText)
                                .font(.system(size: 15))
                                .foregroundColor(streamingText.isEmpty ? .white.opacity(0.5) : .white.opacity(0.9))
                                .lineSpacing(6)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    } else if !hasChanges {
                        // No changes needed
                        HStack(spacing: 12) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 32))
                                .foregroundColor(.green)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("No corrections needed!")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(.white.opacity(0.9))
                                Text("Your text looks good.")
                                    .font(.system(size: 13))
                                    .foregroundColor(.white.opacity(0.5))
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 20)
                    } else {
                        Text(diffText)
                            .font(.system(size: 15))
                            .lineSpacing(6)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
            .frame(maxHeight: .infinity)
            .background(Color.white.opacity(0.03))

            // Stats bar
            if !isLoading {
                HStack {
                    // Provider
                    HStack(spacing: 5) {
                        providerIcon
                        Text(providerName)
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.5))
                    }

                    Spacer()

                    // Stats
                    if hasChanges {
                        Text("\(characterCount) chars • \(wordCount) words • \(changeCount) changes")
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.5))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(Color.white.opacity(0.02))
            }

            Divider()
                .background(Color.white.opacity(0.15))

            // Action bar
            HStack {
                Button(action: onReject) {
                    HStack(spacing: 6) {
                        Text("Cancel")
                            .font(.system(size: 13))
                        Text("esc")
                            .font(.system(size: 11, weight: .medium))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color.white.opacity(0.1))
                            .cornerRadius(4)
                    }
                    .foregroundColor(.white.opacity(0.6))
                }
                .buttonStyle(.plain)

                Spacer()

                Button(action: onAccept) {
                    HStack(spacing: 6) {
                        Text(hasChanges ? "Accept Changes" : "Close")
                            .font(.system(size: 13, weight: .medium))
                        Image(systemName: "return")
                            .font(.system(size: 11, weight: .bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color.white.opacity(0.15))
                            .cornerRadius(4)
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(isHoveringAccept ? Color.green.opacity(0.4) : Color.green.opacity(0.25))
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
                .onHover { isHoveringAccept = $0 }
                .disabled(isLoading)
                .opacity(isLoading ? 0.5 : 1)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        .frame(minWidth: 500, minHeight: 300)
        .background(Color(red: 0.11, green: 0.11, blue: 0.13))
        .cornerRadius(14)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.6), radius: 30, x: 0, y: 15)
    }

    private var hasChanges: Bool {
        originalText.trimmingCharacters(in: .whitespacesAndNewlines) !=
        correctedText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @ViewBuilder
    private var providerIcon: some View {
        switch providerName.lowercased() {
        case let name where name.contains("claude"):
            Image(systemName: "brain")
                .font(.system(size: 12))
                .foregroundColor(.orange)
        case let name where name.contains("gpt") || name.contains("openai"):
            Image(systemName: "sparkles")
                .font(.system(size: 12))
                .foregroundColor(.green)
        case let name where name.contains("ollama"):
            Image(systemName: "desktopcomputer")
                .font(.system(size: 12))
                .foregroundColor(.blue)
        default:
            Image(systemName: "cpu")
                .font(.system(size: 12))
                .foregroundColor(.gray)
        }
    }

    private func computeDiff() -> (text: AttributedString, changeCount: Int) {
        guard !correctedText.isEmpty else {
            return (AttributedString(""), 0)
        }

        let segments = DiffCalculator.calculateDiff(original: originalText, corrected: correctedText)

        var attributed = AttributedString("")
        var changes = 0

        for segment in segments {
            var part = AttributedString(segment.text)

            switch segment.type {
            case .unchanged:
                part.foregroundColor = .white.opacity(0.9)
            case .added:
                part.foregroundColor = Color(red: 0.4, green: 0.95, blue: 0.5)
                part.backgroundColor = Color.green.opacity(0.2)
                // Only count non-whitespace segments as changes
                if !segment.text.trimmingCharacters(in: .whitespaces).isEmpty {
                    changes += 1
                }
            case .removed:
                part.foregroundColor = Color(red: 1.0, green: 0.4, blue: 0.4)
                part.backgroundColor = Color.red.opacity(0.2)
                part.strikethroughStyle = .single
            }

            attributed.append(part)
        }

        return (attributed, changes)
    }
}

/// Wrapper for streaming state
struct StreamingGrammarPopupView: View {
    let originalText: String
    @ObservedObject var streamingState: StreamingState
    let providerName: String
    let onAccept: () -> Void
    let onReject: () -> Void

    var body: some View {
        GrammarPopupView(
            originalText: originalText,
            correctedText: streamingState.isComplete ? streamingState.text : "",
            isLoading: !streamingState.isComplete,
            streamingText: streamingState.text,
            providerName: providerName,
            onAccept: streamingState.isComplete ? onAccept : {},
            onReject: onReject
        )
    }
}

#Preview {
    StreamingGrammarPopupView(
        originalText: "Ceci et un teste avec plains de fotes d'ortpgraphe pour tester les compétence de Fixie.",
        streamingState: {
            let state = StreamingState()
            state.text = "Ceci est un test avec plein de fautes d'orthographe pour tester les compétences de Fixie."
            state.isComplete = true
            return state
        }(),
        providerName: "GPT-4o mini",
        onAccept: {},
        onReject: {}
    )
    .frame(width: 600, height: 400)
    .padding(20)
    .background(Color.black)
}
