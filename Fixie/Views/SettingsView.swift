import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @EnvironmentObject var settings: SettingsManager
    @State private var isRecordingHotkey = false

    var body: some View {
        TabView {
            generalTab
                .tabItem {
                    Label("General", systemImage: "gear")
                }

            llmTab
                .tabItem {
                    Label("LLM Provider", systemImage: "brain")
                }

            hotkeyTab
                .tabItem {
                    Label("Hotkey", systemImage: "keyboard")
                }

            aboutTab
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
        }
        .padding(20)
        .frame(width: 450, height: 350)
    }

    private var generalTab: some View {
        Form {
            Section {
                Toggle("Launch at login", isOn: $settings.launchAtLogin)
                    .onChange(of: settings.launchAtLogin) { newValue in
                        setLaunchAtLogin(enabled: newValue)
                    }
            }

            Section {
                HStack {
                    Text("Status:")
                    Spacer()
                    if settings.isConfigured {
                        Label("Ready", systemImage: "checkmark.circle.fill")
                            .foregroundColor(.green)
                    } else {
                        Label("API key needed", systemImage: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private var llmTab: some View {
        Form {
            Section("Provider") {
                Picker("LLM Provider", selection: $settings.selectedProvider) {
                    ForEach(LLMProvider.allCases, id: \.self) { provider in
                        Text(provider.displayName).tag(provider)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section("Configuration") {
                switch settings.selectedProvider {
                case .claude:
                    SecureField("Claude API Key", text: $settings.claudeAPIKey)
                        .textFieldStyle(.roundedBorder)
                    Link("Get API Key", destination: URL(string: "https://console.anthropic.com/")!)
                        .font(.caption)

                case .openai:
                    SecureField("OpenAI API Key", text: $settings.openAIAPIKey)
                        .textFieldStyle(.roundedBorder)
                    Link("Get API Key", destination: URL(string: "https://platform.openai.com/api-keys")!)
                        .font(.caption)

                case .ollama:
                    TextField("Ollama Endpoint", text: $settings.ollamaEndpoint)
                        .textFieldStyle(.roundedBorder)
                    TextField("Model Name", text: $settings.ollamaModel)
                        .textFieldStyle(.roundedBorder)
                    Text("Make sure Ollama is running locally")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }

    private var hotkeyTab: some View {
        Form {
            Section("Global Hotkey") {
                HStack {
                    Text("Current hotkey:")
                    Spacer()
                    Text(settings.hotkey.displayString)
                        .font(.system(.body, design: .monospaced))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(6)
                }

                Button(isRecordingHotkey ? "Press new hotkey..." : "Change Hotkey") {
                    isRecordingHotkey.toggle()
                }
                .disabled(isRecordingHotkey)

                if isRecordingHotkey {
                    HotkeyRecorderView { keyCode, modifiers in
                        settings.hotkey = HotkeyConfig(keyCode: keyCode, modifiers: modifiers)
                        isRecordingHotkey = false
                        // Re-register the hotkey
                        NotificationCenter.default.post(name: .hotkeyChanged, object: nil)
                    }
                    .frame(height: 40)
                }

                Button("Reset to Default (⌥⌘G)") {
                    settings.hotkey = HotkeyConfig.defaultHotkey
                    NotificationCenter.default.post(name: .hotkeyChanged, object: nil)
                }
                .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var aboutTab: some View {
        VStack(spacing: 16) {
            Image(systemName: "textformat.abc")
                .font(.system(size: 60))
                .foregroundColor(.accentColor)

            Text("Fixie")
                .font(.title)
                .fontWeight(.bold)

            Text("Version 1.0.0")
                .foregroundColor(.secondary)

            Text("A lightweight grammar correction tool")
                .foregroundColor(.secondary)

            Divider()

            Link("View on GitHub", destination: URL(string: "https://github.com/gogomiche/Fixie")!)

            Spacer()
        }
        .padding()
    }

    private func setLaunchAtLogin(enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            print("Failed to set launch at login: \(error)")
        }
    }
}

struct HotkeyRecorderView: NSViewRepresentable {
    var onHotkeyRecorded: (UInt32, UInt32) -> Void

    func makeNSView(context: Context) -> HotkeyRecorderNSView {
        let view = HotkeyRecorderNSView()
        view.onHotkeyRecorded = onHotkeyRecorded
        return view
    }

    func updateNSView(_ nsView: HotkeyRecorderNSView, context: Context) {}
}

class HotkeyRecorderNSView: NSView {
    var onHotkeyRecorded: ((UInt32, UInt32) -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
    }

    override func keyDown(with event: NSEvent) {
        let keyCode = UInt32(event.keyCode)
        var modifiers: UInt32 = 0

        if event.modifierFlags.contains(.command) { modifiers |= 0x100 }
        if event.modifierFlags.contains(.option) { modifiers |= 0x800 }
        if event.modifierFlags.contains(.shift) { modifiers |= 0x200 }
        if event.modifierFlags.contains(.control) { modifiers |= 0x1000 }

        // Require at least one modifier
        if modifiers != 0 {
            onHotkeyRecorded?(keyCode, modifiers)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.controlBackgroundColor.setFill()
        dirtyRect.fill()

        let text = "Press a key combination..."
        let attributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: NSColor.secondaryLabelColor,
            .font: NSFont.systemFont(ofSize: 13)
        ]
        let size = text.size(withAttributes: attributes)
        let point = NSPoint(
            x: (bounds.width - size.width) / 2,
            y: (bounds.height - size.height) / 2
        )
        text.draw(at: point, withAttributes: attributes)
    }
}

extension Notification.Name {
    static let hotkeyChanged = Notification.Name("hotkeyChanged")
}

#Preview {
    SettingsView()
        .environmentObject(SettingsManager())
}
