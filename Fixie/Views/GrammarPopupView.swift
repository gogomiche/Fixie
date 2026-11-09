import SwiftUI
import AppKit

enum PopupMetrics {
    /// Corner radius of the glass panel; inner elements stay concentric to it.
    static let cornerRadius: CGFloat = 26
    static let contentInset: CGFloat = 10
}

/// Liquid Glass correction popup: a header (source app, mode, status), a
/// content well showing the changes or the clean result, and the actions.
struct GrammarPopupView: View {
    let originalText: String
    let correctedText: String
    let isLoading: Bool
    let streamingText: String
    let providerName: String
    let sourceAppIcon: NSImage?
    let sourceAppName: String?
    let mode: GrammarMode
    let onAccept: () -> Void
    let onReject: () -> Void

    /// false = word-level diff, true = clean result (Tab toggles).
    @State private var showResult = false

    private var hasChanges: Bool {
        DiffCalculator.hasChanges(original: originalText, corrected: correctedText)
    }

    private var isMarkdown: Bool {
        MarkdownRenderer.containsMarkdown(correctedText)
    }

    private var canToggleResult: Bool {
        !isLoading && hasChanges
    }

    var body: some View {
        let diff = isLoading ? nil : computeDiff()

        VStack(spacing: 0) {
            header(changeCount: diff?.changeCount ?? 0)
            contentWell(diffText: diff?.text)
            footer
        }
        .frame(minWidth: 500, minHeight: 260)
        .overlay {
            if isLoading {
                GenerationGlow(cornerRadius: PopupMetrics.cornerRadius)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.35), value: isLoading)
        .onReceive(NotificationCenter.default.publisher(for: .togglePopupResult)) { _ in
            guard canToggleResult else { return }
            withAnimation(.easeInOut(duration: 0.2)) { showResult.toggle() }
        }
    }

    // MARK: - Header

    private func header(changeCount: Int) -> some View {
        HStack(spacing: 12) {
            SourceBadge(icon: sourceAppIcon, mode: mode)

            VStack(alignment: .leading, spacing: 2) {
                Text(mode.popupTitle)
                    .font(.system(size: 14, weight: .semibold))
                Text(subtitle)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 12)

            statusChip(changeCount: changeCount)
        }
        .padding(.leading, 18)
        .padding(.trailing, 16)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }

    private var subtitle: String {
        [sourceAppName, providerName]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

    @ViewBuilder
    private func statusChip(changeCount: Int) -> some View {
        if isLoading {
            StatusChip(tint: .secondary) {
                ActivityGlyph()
                Text(streamingText.isEmpty ? mode.loadingLabel : "Writing…")
            }
        } else if hasChanges {
            StatusChip(tint: mode.tint) {
                Image(systemName: "pencil.line")
                Text(changeCount == 1 ? "1 change" : "\(changeCount) changes")
            }
        } else {
            StatusChip(tint: .green) {
                Image(systemName: "checkmark")
                Text("Looks good")
            }
        }
    }

    // MARK: - Content

    private func contentWell(diffText: AttributedString?) -> some View {
        let shape = RoundedRectangle(
            cornerRadius: PopupMetrics.cornerRadius - PopupMetrics.contentInset,
            style: .continuous
        )

        return Group {
            if !isLoading && !hasChanges {
                noChangesBody
            } else {
                ScrollView(.vertical) {
                    textBody(diffText: diffText)
                        .font(.system(size: 15))
                        .lineSpacing(5)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(shape.fill(Color.primary.opacity(0.05)))
        .overlay(shape.strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.5))
        .clipShape(shape)
        .padding(.horizontal, PopupMetrics.contentInset)
    }

    @ViewBuilder
    private func textBody(diffText: AttributedString?) -> some View {
        if isLoading {
            if streamingText.isEmpty {
                // Original text, dimmed, while waiting for the first token
                Text(originalText)
                    .foregroundStyle(.tertiary)
                    .modifier(Shimmer())
            } else {
                Text(streamingText)
                    .foregroundStyle(.secondary)
            }
        } else if showResult {
            Text(isMarkdown ? MarkdownRenderer.render(correctedText) : AttributedString(correctedText))
                .foregroundStyle(.primary)
                .textSelection(.enabled)
        } else {
            Text(diffText ?? AttributedString(""))
                .textSelection(.enabled)
        }
    }

    private var noChangesBody: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 34))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.green)
                .padding(.bottom, 2)
            Text("No corrections needed")
                .font(.system(size: 15, weight: .semibold))
            Text("Your text already reads well.")
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
        }
        .padding(24)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 8) {
            if canToggleResult {
                ResultToggle(showResult: $showResult)
                KeyCap(label: "⇥")
            }

            Spacer()

            if isLoading || hasChanges {
                Button(action: onReject) {
                    HStack(spacing: 7) {
                        Text("Cancel")
                        KeyCap(label: "esc")
                    }
                }
                .fixieButtonStyle()
            }

            Button(action: onAccept) {
                HStack(spacing: 7) {
                    Text(isLoading || hasChanges ? "Accept" : "Done")
                    KeyCap(label: "↩", onProminent: true)
                }
            }
            .fixieButtonStyle(prominent: true)
            .disabled(isLoading)
        }
        .controlSize(.large)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    // MARK: - Diff

    private func computeDiff() -> (text: AttributedString, changeCount: Int) {
        guard !correctedText.isEmpty else {
            return (AttributedString(""), 0)
        }

        let segments = DiffCalculator.calculateDiff(original: originalText, corrected: correctedText)

        var attributed = AttributedString("")
        var changes = 0

        for (index, segment) in segments.enumerated() {
            // Make newline tokens visible in added/removed segments
            let displayText: String
            if segment.type != .unchanged && segment.text.contains("\n") {
                displayText = segment.text.replacingOccurrences(of: "\n", with: "\u{21B5}\n")
            } else {
                displayText = segment.text
            }
            var part = AttributedString(displayText)
            let isBlank = segment.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

            switch segment.type {
            case .unchanged:
                part.foregroundColor = .primary
            case .added:
                part.foregroundColor = .green
                part.backgroundColor = Color.green.opacity(0.16)
                if !isBlank { changes += 1 }
            case .removed:
                part.foregroundColor = Color.red.opacity(0.85)
                part.backgroundColor = Color.red.opacity(0.1)
                part.strikethroughStyle = .single
                // A replacement (removed + added) counts once, on the added side
                let replaced = index + 1 < segments.count && segments[index + 1].type == .added
                if !isBlank && !replaced { changes += 1 }
                attributed.append(part)
                // Keep the old and new words apart ("envois envoie", not "envoisenvoie")
                if replaced { part = AttributedString("\u{2009}") }
                else { continue }
            }

            attributed.append(part)
        }

        return (attributed, changes)
    }
}

// MARK: - Popup components

/// Source app icon with the mode's badge in the corner.
private struct SourceBadge: View {
    let icon: NSImage?
    let mode: GrammarMode

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Group {
                if let icon {
                    Image(nsImage: icon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else {
                    Image(systemName: "text.cursor")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 34, height: 34)

            Image(systemName: mode.symbolName)
                .font(.system(size: 8.5, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 17, height: 17)
                .background(Circle().fill(mode.tint.gradient))
                .overlay(Circle().strokeBorder(Color.white.opacity(0.4), lineWidth: 0.75))
                .offset(x: 4, y: 3)
        }
    }
}

private struct StatusChip<Content: View>: View {
    let tint: Color
    @ViewBuilder let content: Content

    var body: some View {
        HStack(spacing: 5) { content }
            .font(.system(size: 11.5, weight: .semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(tint.opacity(0.14)))
            .overlay(Capsule().strokeBorder(tint.opacity(0.18), lineWidth: 0.5))
    }
}

/// Two-option capsule switch: "Changes" (diff) / "Result" (clean text).
private struct ResultToggle: View {
    @Binding var showResult: Bool
    @Namespace private var selection

    var body: some View {
        HStack(spacing: 2) {
            option("Changes", isResult: false)
            option("Result", isResult: true)
        }
        .padding(3)
        .background(Capsule().fill(Color.primary.opacity(0.06)))
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.5))
    }

    private func option(_ title: String, isResult: Bool) -> some View {
        let isSelected = showResult == isResult
        return Text(title)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(isSelected ? Color.primary : Color.secondary)
            .padding(.horizontal, 11)
            .padding(.vertical, 5)
            .background {
                if isSelected {
                    Capsule()
                        .fill(Color.primary.opacity(0.12))
                        .matchedGeometryEffect(id: "selection", in: selection)
                }
            }
            .contentShape(Capsule())
            .onTapGesture {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { showResult = isResult }
            }
    }
}

private struct ActivityGlyph: View {
    var body: some View {
        if #available(macOS 14.0, *) {
            Image(systemName: "sparkles")
                .symbolEffect(.pulse)
        } else {
            Image(systemName: "sparkles")
        }
    }
}

/// Light sweep across the text while waiting for the first token.
private struct Shimmer: ViewModifier {
    func body(content: Content) -> some View {
        content.overlay(
            TimelineView(.animation) { context in
                let period = 1.8
                let phase = context.date.timeIntervalSinceReferenceDate
                    .truncatingRemainder(dividingBy: period) / period
                LinearGradient(
                    colors: [.clear, Color.primary.opacity(0.55), .clear],
                    startPoint: UnitPoint(x: phase * 3 - 1.5, y: 0.5),
                    endPoint: UnitPoint(x: phase * 3 - 0.5, y: 0.5)
                )
            }
            .mask(content)
            .allowsHitTesting(false)
        )
    }
}

/// Animated multicolor rim shown while the model is writing.
private struct GenerationGlow: View {
    let cornerRadius: CGFloat

    private static let colors: [Color] = [
        Color(red: 1.0, green: 0.78, blue: 0.2),
        Color(red: 1.0, green: 0.45, blue: 0.35),
        Color(red: 0.93, green: 0.35, blue: 0.75),
        Color(red: 0.55, green: 0.45, blue: 1.0),
        Color(red: 0.3, green: 0.7, blue: 1.0),
        Color(red: 1.0, green: 0.78, blue: 0.2),
    ]

    var body: some View {
        TimelineView(.animation) { context in
            let period = 4.0
            let turn = context.date.timeIntervalSinceReferenceDate
                .truncatingRemainder(dividingBy: period) / period
            let gradient = AngularGradient(colors: Self.colors, center: .center, angle: .degrees(turn * 360))
            let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

            ZStack {
                shape.strokeBorder(gradient, lineWidth: 8).blur(radius: 10).opacity(0.75)
                shape.strokeBorder(gradient, lineWidth: 1.5)
            }
            .clipShape(shape)
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Streaming wrapper

/// Wrapper for streaming state
struct StreamingGrammarPopupView: View {
    let originalText: String
    @ObservedObject var streamingState: StreamingState
    let providerName: String
    let sourceAppIcon: NSImage?
    let sourceAppName: String?
    let mode: GrammarMode
    let onAccept: () -> Void
    let onReject: () -> Void

    var body: some View {
        GrammarPopupView(
            originalText: originalText,
            correctedText: streamingState.isComplete ? streamingState.text : "",
            isLoading: !streamingState.isComplete,
            streamingText: streamingState.text,
            providerName: providerName,
            sourceAppIcon: sourceAppIcon,
            sourceAppName: sourceAppName,
            mode: mode,
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
        providerName: "Claude Sonnet 5.5",
        sourceAppIcon: NSImage(systemSymbolName: "doc.text", accessibilityDescription: nil),
        sourceAppName: "Notes",
        mode: .grammar,
        onAccept: {},
        onReject: {}
    )
    .frame(width: 600, height: 400)
    .padding(20)
    .background(Color.black)
}
