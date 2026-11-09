import AppKit
import SwiftUI

// Renders Fixie's popup and Settings with sample data, in dark and light
// appearance, over a wallpaper backdrop, and saves one PNG per scene.
// Usage: ui-preview <app-icon.png> <output-dir>

// MARK: - Capture

typealias WindowListCreateImage = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?

/// `CGWindowListCreateImage` is unavailable in the Swift overlay since macOS 15,
/// but still captures the caller's own windows without Screen Recording permission.
let windowListCreateImage: WindowListCreateImage = {
    let handle = dlopen("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", RTLD_NOW)
    return unsafeBitCast(dlsym(handle, "CGWindowListCreateImage")!, to: WindowListCreateImage.self)
}()

/// Captures `rect` (AppKit screen coordinates) with `window` and our windows below it.
func capture(_ rect: NSRect, from window: NSWindow) -> CGImage? {
    let primaryHeight = NSScreen.screens[0].frame.height
    let cgRect = CGRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    let onScreenBelowWindow: UInt32 = 1 << 2
    let includingWindow: UInt32 = 1 << 3
    let bestResolution: UInt32 = 1 << 3
    return windowListCreateImage(cgRect, onScreenBelowWindow | includingWindow, UInt32(window.windowNumber), bestResolution)?
        .takeRetainedValue()
}

// MARK: - Backdrop

struct Wallpaper: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.08, green: 0.14, blue: 0.40),
                    Color(red: 0.40, green: 0.18, blue: 0.55),
                    Color(red: 0.95, green: 0.48, blue: 0.32),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Circle().fill(Color(red: 0.2, green: 0.6, blue: 1.0)).frame(width: 440).blur(radius: 90).offset(x: -280, y: -170)
            Circle().fill(Color(red: 1.0, green: 0.76, blue: 0.3)).frame(width: 400).blur(radius: 100).offset(x: 300, y: 210)
            Circle().fill(Color(red: 0.92, green: 0.3, blue: 0.6)).frame(width: 320).blur(radius: 80).offset(x: 220, y: -190)
        }
    }
}

/// A document window behind the popup, with the text "selected".
struct DocumentMock: View {
    let appName: String
    let title: String
    let selectedText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 7) {
                ForEach([Color.red, .yellow, .green], id: \.self) { color in
                    Circle().fill(color.opacity(0.85)).frame(width: 11, height: 11)
                }
                Spacer()
                Text(appName).font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                Spacer()
                Color.clear.frame(width: 47, height: 1)
            }
            .padding(12)

            VStack(alignment: .leading, spacing: 12) {
                Text(title).font(.system(size: 22, weight: .bold))
                Text(selectedText)
                    .font(.system(size: 14))
                    .lineSpacing(4)
                    .background(Color.accentColor.opacity(0.28))
                ForEach([0.92, 0.85, 0.95, 0.6], id: \.self) { width in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.primary.opacity(0.12))
                        .frame(height: 9)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .scaleEffect(x: width, anchor: .leading)
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, 4)

            Spacer()
        }
        .frame(width: 560, height: 430)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(nsColor: .windowBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.3), radius: 24, y: 10)
    }
}

// MARK: - Scenes

struct Sample {
    let original: String
    let corrected: String
}

let frenchNote = Sample(
    original: "Salut l'équipe, je vous envois le compte-rendu de la réunion d'hier. Les point important sont dans le doc partagé, n'hésitez pas a ajouter vos remarque avant vendredi.",
    corrected: "Salut l'équipe, je vous envoie le compte-rendu de la réunion d'hier. Les points importants sont dans le doc partagé, n'hésitez pas à ajouter vos remarques avant vendredi."
)

let slackMessage = Sample(
    original: "So basically the new onboarding flow is done and we think it should be shipped next week if nobody have objections about it.",
    corrected: "The new onboarding flow is done, and we plan to ship it next week unless anyone has objections."
)

enum PopupState {
    case changes, result, streaming, noChanges
}

struct Shot {
    let name: String
    let backdropSize: NSSize
    let backdrop: AnyView
    /// Builds the window to capture, given the backdrop's screen frame.
    let makeWindow: (NSRect) -> NSWindow
    var afterShow: () -> Void = {}
}

let notesPath = "/System/Applications/Notes.app"
let slackPath = FileManager.default.fileExists(atPath: "/Applications/Slack.app")
    ? "/Applications/Slack.app" : "/System/Applications/Mail.app"
let slackName = slackPath.contains("Slack") ? "Slack" : "Mail"

func popupScene(_ name: String, sample: Sample, mode: GrammarMode, state: PopupState,
                appPath: String, appName: String, docTitle: String) -> Shot {
    let backdropSize = NSSize(width: 960, height: 600)
    return Shot(
        name: name,
        backdropSize: backdropSize,
        backdrop: AnyView(
            ZStack(alignment: .topLeading) {
                Wallpaper()
                DocumentMock(appName: appName, title: docTitle, selectedText: sample.original)
                    .padding(.leading, 48)
                    .padding(.top, 40)
            }
        ),
        makeWindow: { backdrop in
            let streamingState = StreamingState()
            switch state {
            case .changes, .result:
                streamingState.text = sample.corrected
                streamingState.isComplete = true
            case .streaming:
                streamingState.text = String(sample.corrected.prefix(sample.corrected.count / 2))
                streamingState.isComplete = false
            case .noChanges:
                streamingState.text = sample.original
                streamingState.isComplete = true
            }
            let view = StreamingGrammarPopupView(
                originalText: sample.original,
                streamingState: streamingState,
                providerName: "Claude Sonnet 5.5",
                sourceAppIcon: NSWorkspace.shared.icon(forFile: appPath),
                sourceAppName: appName,
                mode: mode,
                onAccept: {},
                onReject: {}
            )
            let size = PopupWindowManager.panelSize(for: sample.original)
            let panel = PopupWindowManager.makePanel(rootView: view, size: size)
            panel.setFrameOrigin(NSPoint(x: backdrop.maxX - size.width - 70, y: backdrop.minY + 60))
            return panel
        },
        afterShow: {
            if state == .result {
                NotificationCenter.default.post(name: .togglePopupResult, object: nil)
            }
        }
    )
}

func settingsScene(_ tab: SettingsTab, settings: SettingsManager) -> Shot {
    let backdropSize = NSSize(width: 860, height: 640)
    return Shot(
        name: "settings-\(tab.rawValue)",
        backdropSize: backdropSize,
        backdrop: AnyView(Wallpaper()),
        makeWindow: { backdrop in
            let window = SettingsView.makeWindow(settings: settings, initialTab: tab)
            let frame = window.frame
            window.setFrameOrigin(NSPoint(x: backdrop.midX - frame.width / 2, y: backdrop.midY - frame.height / 2))
            return window
        }
    )
}

// MARK: - Run

let arguments = CommandLine.arguments
guard arguments.count == 3 else {
    print("Usage: ui-preview <app-icon.png> <output-dir>")
    exit(2)
}
let outputDir = URL(fileURLWithPath: arguments[2], isDirectory: true)
try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
if let icon = NSImage(contentsOfFile: arguments[1]) {
    app.applicationIconImage = icon
}

let settings = SettingsManager()
settings.selectedProvider = .claude
settings.claudeAPIKey = "sk-ant-preview"

let scenes: [Shot] = [
    popupScene("popup-changes", sample: frenchNote, mode: .grammar, state: .changes,
               appPath: notesPath, appName: "Notes", docTitle: "Compte-rendu"),
    popupScene("popup-result", sample: slackMessage, mode: .improve, state: .result,
               appPath: slackPath, appName: slackName, docTitle: "#product"),
    popupScene("popup-streaming", sample: slackMessage, mode: .improve, state: .streaming,
               appPath: slackPath, appName: slackName, docTitle: "#product"),
    popupScene("popup-no-changes",
               sample: Sample(original: "Merci pour ton retour, je regarde ça demain matin.",
                              corrected: "Merci pour ton retour, je regarde ça demain matin."),
               mode: .grammar, state: .noChanges,
               appPath: notesPath, appName: "Notes", docTitle: "Brouillon"),
] + SettingsTab.allCases.map { settingsScene($0, settings: settings) }

let appearances: [(suffix: String, name: NSAppearance.Name)] = [("dark", .darkAqua), ("light", .aqua)]
// ONLY=<prefix> renders the matching scenes only (e.g. ONLY=settings).
let only = ProcessInfo.processInfo.environment["ONLY"] ?? ""
let jobs = appearances.flatMap { appearance in
    scenes.filter { $0.name.hasPrefix(only) }.map { (scene: $0, appearance: appearance) }
}

func runJob(_ index: Int) {
    guard index < jobs.count else {
        if let domain = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: domain)
        }
        exit(0)
    }
    let (scene, appearance) = jobs[index]
    app.appearance = NSAppearance(named: appearance.name)

    let visible = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
    let backdropFrame = NSRect(
        x: (visible.midX - scene.backdropSize.width / 2).rounded(),
        y: (visible.midY - scene.backdropSize.height / 2).rounded(),
        width: scene.backdropSize.width,
        height: scene.backdropSize.height
    )

    let backdrop = NSWindow(contentRect: backdropFrame, styleMask: [.borderless], backing: .buffered, defer: false)
    backdrop.contentView = NSHostingView(rootView: scene.backdrop.frame(width: backdropFrame.width, height: backdropFrame.height))
    // Above other apps' windows, so none of them can end up in a capture
    backdrop.level = .floating
    backdrop.orderFrontRegardless()

    let window = scene.makeWindow(backdropFrame)
    window.level = max(window.level, NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1))
    window.makeKeyAndOrderFront(nil)
    app.activate(ignoringOtherApps: true)

    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
        scene.afterShow()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            let file = outputDir.appendingPathComponent("\(scene.name)-\(appearance.suffix).png")
            // A capture right after a window appears occasionally comes back empty: retry once
            if let image = capture(backdropFrame, from: window) ?? capture(backdropFrame, from: window),
               let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) {
                try? png.write(to: file)
                print("✓ \(file.lastPathComponent)")
            } else {
                print("✗ \(scene.name)-\(appearance.suffix): capture failed")
            }
            window.orderOut(nil)
            backdrop.orderOut(nil)
            runJob(index + 1)
        }
    }
}

// Start once the app is active, so windows render in their key/active state
app.activate(ignoringOtherApps: true)
DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { runJob(0) }
app.run()
