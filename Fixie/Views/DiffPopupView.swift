import SwiftUI

struct DiffPopupView: View {
    let originalText: String
    let correctedText: String
    let isLoading: Bool
    let streamingText: String
    let onAccept: () -> Void
    let onReject: () -> Void

    @State private var diffSegments: [DiffSegment] = []
    @State private var hasChanges: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                Image(systemName: "textformat.abc")
                    .foregroundColor(.accentColor)
                Text("Grammar Check")
                    .font(.headline)
                Spacer()
                if isLoading {
                    ProgressView()
                        .scaleEffect(0.7)
                }
            }

            Divider()

            if isLoading {
                // Streaming state - show text as it comes in
                ScrollView {
                    Text(streamingText.isEmpty ? "Checking grammar..." : streamingText)
                        .foregroundColor(streamingText.isEmpty ? .secondary : .primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(Color(NSColor.textBackgroundColor))
                        .cornerRadius(8)
                }
            } else if !hasChanges {
                // No changes needed
                VStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 40))
                        .foregroundColor(.green)
                    Text("No corrections needed!")
                        .font(.headline)
                    Text("Your text looks good.")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else {
                // Diff view
                ScrollView {
                    diffTextView
                        .padding(12)
                        .background(Color(NSColor.textBackgroundColor))
                        .cornerRadius(8)
                }

                // Legend
                HStack(spacing: 16) {
                    HStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.red.opacity(0.3))
                            .frame(width: 16, height: 16)
                        Text("Removed")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    HStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.green.opacity(0.3))
                            .frame(width: 16, height: 16)
                        Text("Added")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }

            Divider()

            // Action buttons
            HStack {
                Button("Cancel (Esc)") {
                    onReject()
                }
                .keyboardShortcut(.escape, modifiers: [])

                Spacer()

                if hasChanges {
                    Button("Accept (Enter)") {
                        onAccept()
                    }
                    .keyboardShortcut(.return, modifiers: [])
                    .buttonStyle(.borderedProminent)
                } else {
                    Button("Close (Enter)") {
                        onReject()
                    }
                    .keyboardShortcut(.return, modifiers: [])
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding()
        .frame(minWidth: 400, minHeight: 200)
        .onAppear {
            if !isLoading && !correctedText.isEmpty {
                calculateDiff(with: correctedText)
            }
        }
        .onChange(of: correctedText) { newCorrectedText in
            // When correctedText becomes non-empty, streaming is complete - calculate diff
            // Must use newCorrectedText, not self.correctedText (which is stale)
            if !newCorrectedText.isEmpty {
                calculateDiff(with: newCorrectedText)
            }
        }
    }

    private var diffTextView: some View {
        let segments = diffSegments

        return Text(segments.reduce(AttributedString()) { result, segment in
            var attributed = AttributedString(segment.text)

            switch segment.type {
            case .unchanged:
                attributed.foregroundColor = .primary
            case .added:
                attributed.foregroundColor = .green
                attributed.backgroundColor = Color.green.opacity(0.2)
            case .removed:
                attributed.foregroundColor = .red
                attributed.backgroundColor = Color.red.opacity(0.2)
                attributed.strikethroughStyle = .single
            }

            return result + attributed
        })
        .font(.body)
        .textSelection(.enabled)
    }

    private func calculateDiff(with corrected: String) {
        print("[Fixie] DiffPopupView.calculateDiff called")
        print("[Fixie] originalText: '\(originalText.prefix(50))...'")
        print("[Fixie] corrected: '\(corrected.prefix(50))...'")

        hasChanges = DiffCalculator.hasChanges(original: originalText, corrected: corrected)
        print("[Fixie] hasChanges: \(hasChanges)")

        if hasChanges {
            diffSegments = DiffCalculator.calculateDiff(original: originalText, corrected: corrected)
        }
    }
}

struct StreamingDiffPopupView: View {
    let originalText: String
    @ObservedObject var streamingState: StreamingState
    let onAccept: () -> Void
    let onReject: () -> Void

    var body: some View {
        DiffPopupView(
            originalText: originalText,
            correctedText: streamingState.isComplete ? streamingState.text : "",
            isLoading: !streamingState.isComplete,
            streamingText: streamingState.text,
            onAccept: onAccept,
            onReject: onReject
        )
    }
}

#Preview {
    DiffPopupView(
        originalText: "This is a sentense with some erors in it.",
        correctedText: "This is a sentence with some errors in it.",
        isLoading: false,
        streamingText: "",
        onAccept: {},
        onReject: {}
    )
}
