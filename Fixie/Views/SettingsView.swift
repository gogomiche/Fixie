import SwiftUI
import ServiceManagement

enum SettingsTab: String, CaseIterable, Identifiable {
    case general
    case provider
    case shortcuts
    case prompts
    case about

    var id: Self { self }

    var title: String {
        switch self {
        case .general: return "General"
        case .provider: return "AI Provider"
        case .shortcuts: return "Shortcuts"
        case .prompts: return "Prompts"
        case .about: return "About"
        }
    }

    var icon: String {
        switch self {
        case .general: return "gearshape.fill"
        case .provider: return "cpu"
        case .shortcuts: return "command"
        case .prompts: return "text.bubble.fill"
        case .about: return "info.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .general: return .gray
        case .provider: return .purple
        case .shortcuts: return .blue
        case .prompts: return .orange
        case .about: return .teal
        }
    }
}

extension LLMProvider {
    /// Models line under the company name on the provider cards.
    var subtitle: String {
        switch self {
        case .claude: return "Claude · Cloud"
        case .openai: return "GPT · Cloud"
        case .ollama: return "Local · On your Mac"
        }
    }

    /// Logo tile colors, after each brand's own mark.
    fileprivate var logoTile: (mark: Color, background: Color) {
        switch self {
        case .claude: return (Color(red: 0.08, green: 0.08, blue: 0.07), Color(red: 0.94, green: 0.93, blue: 0.90))
        case .openai: return (.white, .black)
        case .ollama: return (.black, .white)
        }
    }
}

/// The provider's logo on its brand-colored tile.
private struct ProviderLogoTile: View {
    let provider: LLMProvider
    var size: CGFloat = 28

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
        ProviderLogo(provider: provider)
            .fill(provider.logoTile.mark)
            .padding(size * 0.2)
            .frame(width: size, height: size)
            .background(shape.fill(provider.logoTile.background))
            .overlay(shape.strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5))
    }
}

struct SettingsView: View {
    @EnvironmentObject var settings: SettingsManager
    @ObservedObject private var updateChecker = UpdateChecker.shared
    @State private var selection: SettingsTab?
    @State private var recordingMode: GrammarMode?
    @State private var ollamaModels: [String] = []
    @State private var ollamaModelsLoading = false
    @State private var ollamaModelsError: String?

    init(initialTab: SettingsTab = .general) {
        _selection = State(initialValue: initialTab)
    }

    private var currentTab: SettingsTab { selection ?? .general }

    var body: some View {
        HStack(spacing: 0) {
            sidebar

            VStack(alignment: .leading, spacing: 0) {
                // Pane title, on the traffic lights' row
                Text(currentTab.title)
                    .font(.system(size: 15, weight: .semibold))
                    .padding(.leading, 20)
                    .frame(height: SettingsMetrics.titlebarHeight)
                detail
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        // Fills the whole window, title bar included (its size is set in makeWindow)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
        .onChange(of: selection) { _ in recordingMode = nil }
    }

    /// Floating glass sidebar; the window's traffic lights sit in its top corner.
    private var sidebar: some View {
        List(SettingsTab.allCases, selection: $selection) { tab in
            Label {
                Text(tab.title)
            } icon: {
                IconTile(symbol: tab.icon, color: tab.color)
            }
            .padding(.vertical, 2)
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .padding(.top, SettingsMetrics.titlebarHeight - SettingsMetrics.sidebarInset)
        .frame(width: 196)
        .fixieGlassBackground(in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .padding(SettingsMetrics.sidebarInset)
    }

    @ViewBuilder
    private var detail: some View {
        switch currentTab {
        case .general: generalPane
        case .provider: providerPane
        case .shortcuts: shortcutsPane
        case .prompts: promptsPane
        case .about: aboutPane
        }
    }

    // MARK: - General

    private var generalPane: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    AppIconView(size: 52)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Fixie")
                            .font(.system(size: 19, weight: .semibold))
                        HStack(spacing: 6) {
                            Circle()
                                .fill(settings.isConfigured ? Color.green : Color.orange)
                                .frame(width: 7, height: 7)
                            Text(settings.isConfigured
                                 ? "Ready · \(settings.activeModelDisplayName)"
                                 : "Add an API key to get started")
                                .foregroundStyle(.secondary)
                        }
                        .font(.system(size: 12.5))
                    }

                    Spacer()

                    if !settings.isConfigured {
                        Button("Set Up…") { selection = .provider }
                            .fixieButtonStyle(prominent: true)
                    }
                }
                .padding(.vertical, 4)
            }

            Section {
                Toggle("Launch at login", isOn: $settings.launchAtLogin)
                    .onChange(of: settings.launchAtLogin) { newValue in
                        setLaunchAtLogin(enabled: newValue)
                    }
            }

            Section("Updates") {
                Toggle("Check for updates on launch", isOn: $settings.checkForUpdatesOnLaunch)
                LabeledContent("Current version", value: updateChecker.currentVersion)
                LabeledContent("Last checked", value: formattedLastCheck)

                HStack {
                    updateStatusRow
                    Spacer()
                    if case .available = updateChecker.status {
                        Button("Download…") {
                            updateChecker.openLatestReleaseURL()
                        }
                    }
                    Button("Check Now") {
                        Task { await updateChecker.check(silent: false) }
                    }
                    .disabled(updateChecker.status == .checking)
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
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

    // MARK: - AI Provider

    private var providerPane: some View {
        Form {
            Section("Provider") {
                HStack(spacing: 10) {
                    ForEach(LLMProvider.allCases, id: \.self) { provider in
                        ProviderCard(provider: provider, isSelected: settings.selectedProvider == provider) {
                            settings.selectedProvider = provider
                        }
                    }
                }
                .padding(.vertical, 4)
            }

            Section {
                providerConfiguration
            } header: {
                Text("\(settings.selectedProvider.displayName) settings")
            } footer: {
                providerFooter
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }

    @ViewBuilder
    private var providerConfiguration: some View {
        switch settings.selectedProvider {
        case .claude:
            SecureField("API key", text: $settings.claudeAPIKey, prompt: Text("sk-ant-…"))
            modelPicker(selection: $settings.claudeModel, models: ModelCatalog.claude)
            TextField("Custom model ID", text: $settings.claudeModel)

        case .openai:
            SecureField("API key", text: $settings.openAIAPIKey, prompt: Text("sk-…"))
            modelPicker(selection: $settings.openAIModel, models: ModelCatalog.openAI)
            TextField("Custom model ID", text: $settings.openAIModel)

        case .ollama:
            TextField("Endpoint", text: $settings.ollamaEndpoint)

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
                TextField("Model", text: $settings.ollamaModel)
            }

            HStack {
                if let error = ollamaModelsError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                        .lineLimit(1)
                } else if ollamaModels.isEmpty {
                    Text("Make sure Ollama is running locally")
                        .foregroundColor(.secondary)
                } else {
                    Text("\(ollamaModels.count) model\(ollamaModels.count == 1 ? "" : "s") installed")
                        .foregroundColor(.secondary)
                }

                Spacer()

                Button(ollamaModelsLoading ? "Loading…" : "Refresh Models") {
                    Task { await loadOllamaModels() }
                }
                .disabled(ollamaModelsLoading)
            }
            .font(.callout)
        }
    }

    private func modelPicker(selection: Binding<String>, models: [ModelCatalog.Model]) -> some View {
        Picker("Model", selection: selection) {
            ForEach(models) { model in
                Text(model.name).tag(model.id)
            }
            // Keep a custom model ID visible instead of an empty picker
            if !models.contains(where: { $0.id == selection.wrappedValue }) {
                Divider()
                Text("Custom").tag(selection.wrappedValue)
            }
        }
    }

    @ViewBuilder
    private var providerFooter: some View {
        switch settings.selectedProvider {
        case .claude:
            keychainFooter(linkTitle: "Get an Anthropic API key", url: "https://console.anthropic.com/")
        case .openai:
            keychainFooter(linkTitle: "Get an OpenAI API key", url: "https://platform.openai.com/api-keys")
        case .ollama:
            Label("Runs on your Mac: your text never leaves it.", systemImage: "lock.fill")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func keychainFooter(linkTitle: String, url: String) -> some View {
        HStack {
            Label("Stored in your macOS Keychain", systemImage: "lock.fill")
                .foregroundStyle(.secondary)
            Spacer()
            Link(linkTitle, destination: URL(string: url)!)
        }
        .font(.caption)
    }

    // MARK: - Shortcuts

    private var shortcutsPane: some View {
        Form {
            Section {
                ForEach(GrammarMode.allCases, id: \.self) { mode in
                    shortcutRow(for: mode)
                }
            } header: {
                Text("Global shortcuts")
            } footer: {
                Text("Select text in any app, then press a shortcut. Click a shortcut to change it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("In the popup") {
                LabeledContent("Accept the correction") { KeyCap(label: "↩", size: 12) }
                LabeledContent("Cancel") { KeyCap(label: "esc", size: 12) }
                LabeledContent("Switch between changes and result") { KeyCap(label: "⇥", size: 12) }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }

    @ViewBuilder
    private func shortcutRow(for mode: GrammarMode) -> some View {
        let current = settings.hotkey(for: mode)
        let isRecording = recordingMode == mode

        HStack(spacing: 12) {
            IconTile(symbol: mode.symbolName, color: mode.tint, size: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(mode.displayName)
                Text(mode.tagline)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if current != mode.defaultHotkey && !isRecording {
                Button {
                    settings.setHotkey(mode.defaultHotkey, for: mode)
                    NotificationCenter.default.post(name: .hotkeyChanged, object: nil)
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                }
                .buttonStyle(.borderless)
                .help("Reset to \(mode.defaultHotkey.keyCaps.joined())")
            }

            ShortcutField(
                keys: current.keyCaps,
                isRecording: isRecording,
                onToggle: { recordingMode = isRecording ? nil : mode },
                onRecord: { keyCode, modifiers in
                    settings.setHotkey(HotkeyConfig(keyCode: keyCode, modifiers: modifiers), for: mode)
                    recordingMode = nil
                    NotificationCenter.default.post(name: .hotkeyChanged, object: nil)
                },
                onCancel: { recordingMode = nil }
            )
            .disabled(recordingMode != nil && !isRecording)
        }
        .padding(.vertical, 4)
    }

    // MARK: - Prompts

    private var promptsPane: some View {
        Form {
            Section {
                Label {
                    Text("Add your own instructions to each mode. They're appended to the built-in prompt, never replace it.")
                        .foregroundStyle(.secondary)
                } icon: {
                    Image(systemName: "info.circle")
                        .foregroundStyle(.secondary)
                }
            }

            ForEach(GrammarMode.allCases, id: \.self) { mode in
                Section {
                    PromptEditor(
                        text: Binding(
                            get: { settings.customPrompt(for: mode) },
                            set: { settings.setCustomPrompt($0, for: mode) }
                        ),
                        placeholder: promptPlaceholder(for: mode)
                    )
                } header: {
                    HStack {
                        Label(mode.displayName, systemImage: mode.symbolName)
                        Spacer()
                        Button("Reset") {
                            settings.setCustomPrompt("", for: mode)
                        }
                        .buttonStyle(.borderless)
                        .disabled(settings.customPrompt(for: mode).isEmpty)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }

    private func promptPlaceholder(for mode: GrammarMode) -> String {
        switch mode {
        case .grammar:
            return "e.g. \"Prefer British spellings\" or \"Match the surrounding tone\""
        case .improve:
            return "e.g. \"Use a formal register\" or \"Keep sentences short\""
        }
    }

    // MARK: - About

    private var aboutPane: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 16)

            AppIconView(size: 88)

            Text("Fixie")
                .font(.system(size: 26, weight: .semibold))
                .padding(.top, 14)
            Text("Version \(updateChecker.currentVersion)")
                .foregroundStyle(.secondary)
                .padding(.top, 2)
            Text("A lightweight grammar correction tool")
                .foregroundStyle(.secondary)
                .padding(.top, 10)

            HStack(spacing: 10) {
                Button {
                    NSWorkspace.shared.open(URL(string: "https://github.com/gogomiche/Fixie")!)
                } label: {
                    Label("View on GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
                }
                .fixieButtonStyle()

                Button {
                    NSWorkspace.shared.open(URL(string: "https://github.com/gogomiche/Fixie/blob/main/PRIVACY.md")!)
                } label: {
                    Label("Privacy Policy", systemImage: "hand.raised.fill")
                }
                .fixieButtonStyle()
            }
            .controlSize(.large)
            .padding(.top, 18)

            Spacer(minLength: 16)

            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 22))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.green)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Privacy Summary")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Your text is sent only to your chosen AI provider for correction. API keys are stored securely in macOS Keychain. No analytics or usage data is collected.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.primary.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
            )
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Actions

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

// MARK: - Window

extension SettingsView {
    /// The Settings window: full-size content, transparent title bar, and a
    /// floating Liquid Glass sidebar holding the traffic lights.
    static func makeWindow(settings: SettingsManager, initialTab: SettingsTab = .general) -> NSWindow {
        let controller = NSHostingController(
            rootView: SettingsView(initialTab: initialTab).environmentObject(settings)
        )
        // The window keeps the size below instead of following the SwiftUI layout
        controller.sizingOptions = []
        let window = NSWindow(contentViewController: controller)
        window.styleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
        // An empty unified toolbar gives the taller title bar, which moves the
        // traffic lights inside the floating sidebar
        window.toolbar = NSToolbar(identifier: "FixieSettings")
        window.toolbarStyle = .unified
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.title = "Fixie Settings"
        window.setContentSize(SettingsMetrics.size)
        window.center()
        window.isReleasedWhenClosed = false
        return window
    }
}

private enum SettingsMetrics {
    static let size = NSSize(width: 720, height: 500)
    /// Unified title bar (traffic lights row)
    static let titlebarHeight: CGFloat = 52
    static let sidebarInset: CGFloat = 8
}

// MARK: - Components

struct AppIconView: View {
    let size: CGFloat

    var body: some View {
        Image(nsImage: NSApp.applicationIconImage)
            .resizable()
            .interpolation(.none)  // the icon is pixel art
            .aspectRatio(contentMode: .fit)
            .frame(width: size, height: size)
    }
}

private struct ProviderCard: View {
    let provider: LLMProvider
    let isSelected: Bool
    let action: () -> Void

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
    }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    ProviderLogoTile(provider: provider)
                    Spacer()
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 15))
                        .foregroundStyle(isSelected ? Color.accentColor : Color.secondary.opacity(0.5))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(provider.displayName)
                        .font(.system(size: 13, weight: .semibold))
                    Text(provider.subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(shape.fill(isSelected ? Color.accentColor.opacity(0.1) : Color.primary.opacity(0.03)))
            .overlay(
                shape.strokeBorder(
                    isSelected ? Color.accentColor.opacity(0.9) : Color.primary.opacity(0.1),
                    lineWidth: isSelected ? 1.5 : 0.5
                )
            )
            .contentShape(shape)
        }
        .buttonStyle(.plain)
    }
}

/// Shortcut shown as key caps; click to record a new one.
private struct ShortcutField: View {
    let keys: [String]
    let isRecording: Bool
    let onToggle: () -> Void
    let onRecord: (UInt32, UInt32) -> Void
    let onCancel: () -> Void

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
    }

    var body: some View {
        Button(action: onToggle) {
            Group {
                if isRecording {
                    Text("Type shortcut…")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.accentColor)
                } else {
                    HStack(spacing: 3) {
                        ForEach(Array(keys.enumerated()), id: \.offset) { _, key in
                            KeyCap(label: key, size: 12)
                        }
                    }
                }
            }
            .frame(minWidth: 96, minHeight: 24)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(shape.fill(isRecording ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.04)))
            .overlay(
                shape.strokeBorder(
                    isRecording ? Color.accentColor : Color.primary.opacity(0.1),
                    lineWidth: isRecording ? 1.5 : 0.5
                )
            )
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .background {
            if isRecording {
                HotkeyRecorderView(onHotkeyRecorded: onRecord, onCancel: onCancel)
            }
        }
    }
}

private struct PromptEditor: View {
    @Binding var text: String
    let placeholder: String

    var body: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: $text)
                .font(.system(size: 13))
                .scrollContentBackground(.hidden)
                .frame(minHeight: 72)
            if text.isEmpty {
                Text(placeholder)
                    .font(.system(size: 13))
                    .foregroundStyle(.tertiary)
                    .padding(.leading, 5)
                    .allowsHitTesting(false)
            }
        }
    }
}

// MARK: - Hotkey recording

struct HotkeyRecorderView: NSViewRepresentable {
    var onHotkeyRecorded: (UInt32, UInt32) -> Void
    var onCancel: () -> Void

    func makeNSView(context: Context) -> HotkeyRecorderNSView {
        let view = HotkeyRecorderNSView()
        view.onHotkeyRecorded = onHotkeyRecorded
        view.onCancel = onCancel
        return view
    }

    func updateNSView(_ nsView: HotkeyRecorderNSView, context: Context) {
        nsView.onHotkeyRecorded = onHotkeyRecorded
        nsView.onCancel = onCancel
    }
}

/// Invisible key catcher: takes first responder while recording.
class HotkeyRecorderNSView: NSView {
    var onHotkeyRecorded: ((UInt32, UInt32) -> Void)?
    var onCancel: (() -> Void)?

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

        if modifiers != 0 {
            // Require at least one modifier
            onHotkeyRecorded?(keyCode, modifiers)
        } else if keyCode == 53 {
            // Escape cancels
            onCancel?()
        }
    }
}

extension Notification.Name {
    static let hotkeyChanged = Notification.Name("hotkeyChanged")
    /// Tab in the popup: switch between the changes and the clean result.
    static let togglePopupResult = Notification.Name("togglePopupResult")
}

#Preview {
    SettingsView()
        .environmentObject(SettingsManager())
}
