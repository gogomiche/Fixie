import SwiftUI
import ServiceManagement

enum SettingsTab: String, CaseIterable {
    case general = "General"
    case llm = "LLM Provider"
    case hotkey = "Hotkeys"
    case prompts = "Prompts"
    case about = "About"

    var icon: String {
        switch self {
        case .general: return "gear"
        case .llm: return "brain"
        case .hotkey: return "keyboard"
        case .prompts: return "text.bubble"
        case .about: return "info.circle"
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject var settings: SettingsManager
    @ObservedObject private var updateChecker = UpdateChecker.shared
    @State private var recordingMode: GrammarMode?
    @State private var selectedTab: SettingsTab = .general
    @State private var ollamaModels: [String] = []
    @State private var ollamaModelsLoading = false
    @State private var ollamaModelsError: String?

    var body: some View {
        HStack(spacing: 0) {
            // Sidebar
            VStack(spacing: 4) {
                ForEach(SettingsTab.allCases, id: \.self) { tab in
                    SidebarButton(
                        title: tab.rawValue,
                        icon: tab.icon,
                        isSelected: selectedTab == tab
                    ) {
                        selectedTab = tab
                    }
                }
                Spacer()
            }
            .padding(12)
            .frame(width: 160)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            // Content
            ScrollView {
                VStack(alignment: .leading) {
                    switch selectedTab {
                    case .general:
                        generalTab
                    case .llm:
                        llmTab
                    case .hotkey:
                        hotkeyTab
                    case .prompts:
                        promptsTab
                    case .about:
                        aboutTab
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 550, height: 400)
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

            Section("Updates") {
                Toggle("Check for updates on launch", isOn: $settings.checkForUpdatesOnLaunch)

                HStack {
                    Text("Current version:")
                    Spacer()
                    Text(updateChecker.currentVersion)
                        .foregroundColor(.secondary)
                }

                HStack {
                    Text("Last checked:")
                    Spacer()
                    Text(formattedLastCheck)
                        .foregroundColor(.secondary)
                }

                updateStatusRow

                HStack {
                    Button("Check Now") {
                        Task { await updateChecker.check(silent: false) }
                    }
                    .disabled(updateChecker.status == .checking)

                    if case .available = updateChecker.status {
                        Button("Download…") {
                            updateChecker.openLatestReleaseURL()
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private var formattedLastCheck: String {
        guard let date = updateChecker.lastCheckDate else { return "Never" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    @ViewBuilder
    private var updateStatusRow: some View {
        switch updateChecker.status {
        case .idle:
            EmptyView()
        case .checking:
            HStack {
                ProgressView().controlSize(.small)
                Text("Checking…").foregroundColor(.secondary)
            }
        case .upToDate(let version):
            Label("Up to date (\(version))", systemImage: "checkmark.circle.fill")
                .foregroundColor(.green)
        case .available(let version, _):
            Label("Version \(version) is available", systemImage: "arrow.down.circle.fill")
                .foregroundColor(.accentColor)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
                .lineLimit(2)
        }
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
                    Picker("Model", selection: $settings.claudeModel) {
                        Text("Claude Sonnet 4").tag("claude-sonnet-4-20250514")
                        Text("Claude Haiku").tag("claude-haiku-4-5-20251001")
                    }
                    TextField("Custom model ID", text: $settings.claudeModel)
                        .textFieldStyle(.roundedBorder)
                        .font(.caption)
                    Link("Get API Key", destination: URL(string: "https://console.anthropic.com/")!)
                        .font(.caption)

                case .openai:
                    SecureField("OpenAI API Key", text: $settings.openAIAPIKey)
                        .textFieldStyle(.roundedBorder)
                    Picker("Model", selection: $settings.openAIModel) {
                        Text("GPT-5.2").tag("gpt-5.2")
                        Text("GPT-5.2 Mini").tag("gpt-5.2-mini")
                        Text("GPT-4o").tag("gpt-4o")
                        Text("GPT-4o Mini").tag("gpt-4o-mini")
                    }
                    TextField("Custom model ID", text: $settings.openAIModel)
                        .textFieldStyle(.roundedBorder)
                        .font(.caption)
                    Link("Get API Key", destination: URL(string: "https://platform.openai.com/api-keys")!)
                        .font(.caption)

                case .ollama:
                    TextField("Ollama Endpoint", text: $settings.ollamaEndpoint)
                        .textFieldStyle(.roundedBorder)

                    if !ollamaModels.isEmpty {
                        Picker("Model", selection: $settings.ollamaModel) {
                            ForEach(ollamaModels, id: \.self) { model in
                                Text(model).tag(model)
                            }
                            if !ollamaModels.contains(settings.ollamaModel) && !settings.ollamaModel.isEmpty {
                                Text("\(settings.ollamaModel) (not installed)").tag(settings.ollamaModel)
                            }
                        }
                    } else {
                        TextField("Model Name", text: $settings.ollamaModel)
                            .textFieldStyle(.roundedBorder)
                    }

                    HStack {
                        Button(ollamaModelsLoading ? "Loading…" : "Refresh models") {
                            Task { await loadOllamaModels() }
                        }
                        .disabled(ollamaModelsLoading)

                        if let error = ollamaModelsError {
                            Text(error)
                                .font(.caption)
                                .foregroundColor(.orange)
                                .lineLimit(1)
                        } else if ollamaModels.isEmpty {
                            Text("Make sure Ollama is running locally")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else {
                            Text("\(ollamaModels.count) model\(ollamaModels.count == 1 ? "" : "s") installed")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private var hotkeyTab: some View {
        Form {
            ForEach(GrammarMode.allCases, id: \.self) { mode in
                Section(mode.displayName) {
                    hotkeyRow(for: mode)
                }
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private func hotkeyRow(for mode: GrammarMode) -> some View {
        let current = settings.hotkey(for: mode)
        let isRecording = recordingMode == mode

        HStack {
            Text("Current hotkey:")
            Spacer()
            Text(current.displayString)
                .font(.system(.body, design: .monospaced))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(6)
        }

        Button(isRecording ? "Press new hotkey…" : "Change Hotkey") {
            recordingMode = isRecording ? nil : mode
        }
        .disabled(recordingMode != nil && !isRecording)

        if isRecording {
            HotkeyRecorderView { keyCode, modifiers in
                settings.setHotkey(HotkeyConfig(keyCode: keyCode, modifiers: modifiers), for: mode)
                recordingMode = nil
                NotificationCenter.default.post(name: .hotkeyChanged, object: nil)
            }
            .frame(height: 40)
        }

        Button("Reset to Default (\(mode.defaultHotkey.displayString))") {
            settings.setHotkey(mode.defaultHotkey, for: mode)
            NotificationCenter.default.post(name: .hotkeyChanged, object: nil)
        }
        .foregroundColor(.secondary)
    }

    private var promptsTab: some View {
        Form {
            Section {
                Text("Add your own instructions to the built-in prompt for each mode. Your text is appended to the system prompt — it doesn't replace it.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            ForEach(GrammarMode.allCases, id: \.self) { mode in
                Section(mode.displayName) {
                    promptEditor(for: mode)
                }
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private func promptEditor(for mode: GrammarMode) -> some View {
        let binding = Binding<String>(
            get: { settings.customPrompt(for: mode) },
            set: { settings.setCustomPrompt($0, for: mode) }
        )

        TextEditor(text: binding)
            .font(.system(size: 13))
            .frame(minHeight: 80)
            .padding(6)
            .background(Color(NSColor.textBackgroundColor))
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
            )

        HStack {
            Text(promptPlaceholder(for: mode))
                .font(.caption)
                .foregroundColor(.secondary)

            Spacer()

            Button("Reset") {
                settings.setCustomPrompt("", for: mode)
            }
            .disabled(settings.customPrompt(for: mode).isEmpty)
        }
    }

    private func promptPlaceholder(for mode: GrammarMode) -> String {
        switch mode {
        case .grammar:
            return "e.g. \"Prefer British spellings\" or \"Match the surrounding tone\""
        case .improve:
            return "e.g. \"Use a formal register\" or \"Keep sentences short\""
        }
    }

    private var aboutTab: some View {
        VStack(spacing: 16) {
            Image(systemName: "textformat.abc")
                .font(.system(size: 60))
                .foregroundColor(.accentColor)

            Text("Fixie")
                .font(.title)
                .fontWeight(.bold)

            Text("Version \(updateChecker.currentVersion)")
                .foregroundColor(.secondary)

            Text("A lightweight grammar correction tool")
                .foregroundColor(.secondary)

            Divider()

            VStack(spacing: 8) {
                Link("View on GitHub", destination: URL(string: "https://github.com/gogomiche/Fixie")!)
                Link("Privacy Policy", destination: URL(string: "https://github.com/gogomiche/Fixie/blob/main/PRIVACY.md")!)
                    .font(.caption)
            }

            Spacer()

            // Privacy summary
            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Privacy Summary", systemImage: "lock.shield")
                        .font(.headline)

                    Text("Your text is sent only to your chosen AI provider for correction. API keys are stored securely in macOS Keychain. No analytics or usage data is collected.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding()
    }

    private func loadOllamaModels() async {
        ollamaModelsLoading = true
        ollamaModelsError = nil
        defer { ollamaModelsLoading = false }
        do {
            ollamaModels = try await OllamaService.fetchAvailableModels(endpoint: settings.ollamaEndpoint)
        } catch {
            ollamaModels = []
            ollamaModelsError = error.localizedDescription
        }
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
    static let toggleMarkdownPreview = Notification.Name("toggleMarkdownPreview")
}

struct SidebarButton: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .frame(width: 20)
                    .foregroundColor(isSelected ? .accentColor : .secondary)
                Text(title)
                    .font(.system(size: 13, weight: isSelected ? .medium : .regular))
                    .foregroundColor(isSelected ? .primary : .secondary)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? Color.accentColor.opacity(0.15) : (isHovering ? Color.primary.opacity(0.05) : Color.clear))
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}

#Preview {
    SettingsView()
        .environmentObject(SettingsManager())
}
