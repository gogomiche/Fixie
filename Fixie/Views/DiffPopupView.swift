import SwiftUI

struct DiffPopupView: View {
    let originalText: String
    let correctedText: String
    let isLoading: Bool
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
                // Loading state
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Checking grammar...")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
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
            if !isLoading {
                calculateDiff()
            }
        }
        .onChange(of: correctedText) { _ in
            calculateDiff()
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

    private func calculateDiff() {
        hasChanges = DiffCalculator.hasChanges(original: originalText, corrected: correctedText)
        if hasChanges {
            diffSegments = DiffCalculator.calculateDiff(original: originalText, corrected: correctedText)
        }
    }
}

#Preview {
    DiffPopupView(
        originalText: "This is a sentense with some erors in it.",
        correctedText: "This is a sentence with some errors in it.",
        isLoading: false,
        onAccept: {},
        onReject: {}
    )
}
