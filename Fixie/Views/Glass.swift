import SwiftUI
import AppKit

// Liquid Glass building blocks shared by the popup and Settings.
// Glass APIs need the macOS 26 SDK (Swift 6.2 / Xcode 26) at build time and
// macOS 26 at run time; older systems get the closest material equivalent.

// MARK: - Window background

enum GlassPanelBackground {
    /// Wraps `content` in the panel's background: Liquid Glass on macOS 26+,
    /// a rounded behind-window material before that.
    static func wrap(_ content: NSView, cornerRadius: CGFloat) -> NSView {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView()
            glass.cornerRadius = cornerRadius
            glass.contentView = content
            // Glass controls inside add a full-size backdrop: clip everything to
            // the panel's shape, or the window shadow follows a square outline
            glass.wantsLayer = true
            glass.layer?.cornerRadius = cornerRadius
            glass.layer?.cornerCurve = .continuous
            glass.layer?.masksToBounds = true
            return glass
        }
        #endif
        let effect = NSVisualEffectView()
        effect.material = .popover
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.maskImage = roundedMask(cornerRadius: cornerRadius)
        content.translatesAutoresizingMaskIntoConstraints = false
        effect.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: effect.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: effect.trailingAnchor),
            content.topAnchor.constraint(equalTo: effect.topAnchor),
            content.bottomAnchor.constraint(equalTo: effect.bottomAnchor),
        ])
        return effect
    }

    /// Stretchable rounded-rect mask (only the corners are fixed).
    private static func roundedMask(cornerRadius: CGFloat) -> NSImage {
        let edge = cornerRadius * 2 + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: cornerRadius, left: cornerRadius, bottom: cornerRadius, right: cornerRadius)
        image.resizingMode = .stretch
        return image
    }
}

// MARK: - Surfaces

extension View {
    /// Liquid Glass behind the view on macOS 26+, a material before that.
    @ViewBuilder
    func fixieGlassBackground<S: Shape>(in shape: S) -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            self.glassEffect(.regular, in: shape)
        } else {
            self.background(.regularMaterial, in: shape)
        }
        #else
        self.background(.regularMaterial, in: shape)
        #endif
    }
}

// MARK: - Buttons

extension View {
    /// Glass button (`prominent` = tinted with the accent color, for the
    /// primary action). Falls back to a capsule button before macOS 26.
    func fixieButtonStyle(prominent: Bool = false) -> some View {
        modifier(FixieButtonStyleModifier(prominent: prominent))
    }
}

private struct FixieButtonStyleModifier: ViewModifier {
    let prominent: Bool

    func body(content: Content) -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            if prominent {
                content.buttonStyle(.glassProminent)
            } else {
                content.buttonStyle(.glass)
            }
        } else {
            content.buttonStyle(CapsuleButtonStyle(prominent: prominent))
        }
        #else
        content.buttonStyle(CapsuleButtonStyle(prominent: prominent))
        #endif
    }
}

/// Pre-macOS 26 stand-in for the glass button styles.
private struct CapsuleButtonStyle: ButtonStyle {
    let prominent: Bool
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(prominent ? Color.white : Color.primary)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(
                Capsule().fill(prominent ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.regularMaterial))
            )
            .overlay(Capsule().strokeBorder(Color.primary.opacity(prominent ? 0 : 0.1), lineWidth: 0.5))
            .opacity(configuration.isPressed ? 0.75 : (isEnabled ? 1 : 0.45))
    }
}

// MARK: - Small components

/// A keyboard key, e.g. "↩", "esc" or "⌘".
struct KeyCap: View {
    let label: String
    /// Set when drawn on an accent-filled button.
    var onProminent = false
    var size: CGFloat = 11

    var body: some View {
        Text(label)
            .font(.system(size: size, weight: .semibold, design: .rounded))
            .foregroundStyle(onProminent ? Color.white.opacity(0.9) : Color.secondary)
            .frame(minWidth: size + 7)
            .padding(.horizontal, size * 0.4)
            .padding(.vertical, size * 0.18)
            .background(
                RoundedRectangle(cornerRadius: size * 0.45, style: .continuous)
                    .fill(onProminent ? Color.white.opacity(0.2) : Color.primary.opacity(0.07))
            )
            .overlay(
                RoundedRectangle(cornerRadius: size * 0.45, style: .continuous)
                    .strokeBorder(onProminent ? Color.white.opacity(0.15) : Color.primary.opacity(0.1), lineWidth: 0.5)
            )
    }
}

/// System Settings-style colored icon tile.
struct IconTile: View {
    let symbol: String
    let color: Color
    var size: CGFloat = 22

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.52, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(
                RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                    .fill(color.gradient)
            )
            .overlay(
                RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.5)
            )
    }
}

extension GrammarMode {
    var tint: Color {
        switch self {
        case .grammar: return .green
        case .improve: return .purple
        }
    }
}
