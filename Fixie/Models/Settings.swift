import Foundation
import SwiftUI

enum LLMProvider: String, CaseIterable, Codable {
    // Raw values are persisted in UserDefaults: never rename them
    case claude = "Claude"
    case openai = "OpenAI"
    case ollama = "Ollama"

    /// Company name shown in Settings and error messages.
    var displayName: String {
        switch self {
        case .claude: return "Anthropic"
        case .openai: return "OpenAI"
        case .ollama: return "Ollama"
        }
    }

    var requiresAPIKey: Bool {
        switch self {
        case .claude, .openai:
            return true
        case .ollama:
            return false
        }
    }
}

/// Models offered in Settings. One source of truth for the pickers, the
/// popup's provider label and the upgrade of outdated saved choices.
enum ModelCatalog {
    struct Model: Identifiable, Equatable {
        let id: String
        let name: String
    }

    static let claude: [Model] = [
        Model(id: "claude-sonnet-5-5", name: "Claude Sonnet 5.5"),
        Model(id: "claude-haiku-5-5", name: "Claude Haiku 5.5 (fastest)"),
        Model(id: "claude-opus-5-5", name: "Claude Opus 5.5 (most capable)"),
        Model(id: "claude-fable-5-1", name: "Claude Fable 5.1"),
    ]

    static let openAI: [Model] = [
        Model(id: "gpt-6-luna", name: "GPT-6 Luna (fastest)"),
        Model(id: "gpt-6.1-terra", name: "GPT-6.1 Terra"),
        Model(id: "gpt-6.1-sol", name: "GPT-6.1 Sol"),
        Model(id: "gpt-6-astra", name: "GPT-6 Astra (most capable)"),
    ]

    static let defaultClaude = "claude-sonnet-5-5"
    static let defaultOpenAI = "gpt-6-luna"

    /// Models previously offered in the pickers → their current equivalent.
    /// Custom model IDs typed by the user are never touched.
    static let upgrades: [String: String] = [
        "claude-sonnet-4-20250514": "claude-sonnet-5-5",
        "claude-haiku-4-5-20251001": "claude-haiku-5-5",
        "gpt-4o-mini": "gpt-6-luna",
        "gpt-5.2-mini": "gpt-6-luna",
        "gpt-4o": "gpt-6.1-terra",
        "gpt-5.2": "gpt-6.1-sol",
    ]

    static func upgraded(_ modelID: String) -> String {
        upgrades[modelID] ?? modelID
    }

    /// Rewrite outdated saved model choices in place.
    static func migrateSavedModels(in defaults: UserDefaults, keys: [String]) {
        for key in keys {
            guard let saved = defaults.string(forKey: key) else { continue }
            let current = upgraded(saved)
            if current != saved {
                defaults.set(current, forKey: key)
            }
        }
    }

    static func displayName(for modelID: String) -> String {
        guard let model = (claude + openAI).first(where: { $0.id == modelID }) else { return modelID }
        // Drop the "(fastest)"-style hints in compact labels
        return model.name.components(separatedBy: " (").first ?? model.name
    }
}

struct HotkeyConfig: Codable, Equatable {
    var keyCode: UInt32
    var modifiers: UInt32

    static let defaultHotkey = HotkeyConfig(
        keyCode: 5, // G key
        modifiers: 0x100 | 0x800 // Cmd + Option
    )

    var displayString: String {
        var parts: [String] = []
        if modifiers & 0x100 != 0 { parts.append("⌘") }
        if modifiers & 0x800 != 0 { parts.append("⌥") }
        if modifiers & 0x200 != 0 { parts.append("⇧") }
        if modifiers & 0x1000 != 0 { parts.append("⌃") }

        let keyName = keyCodeToString(keyCode)
        parts.append(keyName)

        return parts.joined()
    }

    /// One label per key, in the standard macOS order (⌃⌥⇧⌘ then the key),
    /// for rendering the shortcut as key caps.
    var keyCaps: [String] {
        var caps: [String] = []
        if modifiers & 0x1000 != 0 { caps.append("⌃") }
        if modifiers & 0x800 != 0 { caps.append("⌥") }
        if modifiers & 0x200 != 0 { caps.append("⇧") }
        if modifiers & 0x100 != 0 { caps.append("⌘") }
        caps.append(keyCodeToString(keyCode))
        return caps
    }

    private func keyCodeToString(_ keyCode: UInt32) -> String {
        let keyMap: [UInt32: String] = [
            0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X",
            8: "C", 9: "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R",
            16: "Y", 17: "T", 31: "O", 32: "U", 34: "I", 35: "P", 37: "L",
            38: "J", 40: "K", 45: "N", 46: "M"
        ]
        return keyMap[keyCode] ?? "?"
    }
}

// MARK: - Service Configuration

struct ServiceConfiguration {
    let provider: LLMProvider
    let apiKey: String?
    let endpoint: String?
    let model: String?
    let timeout: TimeInterval
    let maxRetries: Int

    static let defaultTimeout: TimeInterval = 60
    static let defaultOllamaTimeout: TimeInterval = 120
    static let defaultMaxRetries: Int = 2
    static let maxInputLength: Int = 50000

    func validate() throws {
        switch provider {
        case .claude:
            guard let key = apiKey, !key.isEmpty else {
                throw ConfigurationError.missingAPIKey(provider: .claude)
            }
            guard key.hasPrefix("sk-ant-") else {
                throw ConfigurationError.invalidAPIKeyFormat(provider: .claude)
            }
        case .openai:
            guard let key = apiKey, !key.isEmpty else {
                throw ConfigurationError.missingAPIKey(provider: .openai)
            }
            guard key.hasPrefix("sk-") else {
                throw ConfigurationError.invalidAPIKeyFormat(provider: .openai)
            }
        case .ollama:
            guard let endpoint = endpoint, URL(string: endpoint) != nil else {
                throw ConfigurationError.invalidEndpoint
            }
        }
    }
}

enum ConfigurationError: LocalizedError {
    case missingAPIKey(provider: LLMProvider)
    case invalidAPIKeyFormat(provider: LLMProvider)
    case invalidEndpoint
    case textTooLong(maxLength: Int)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey(let provider):
            return "\(provider.displayName) API key is required. Please add it in Settings."
        case .invalidAPIKeyFormat(let provider):
            return "\(provider.displayName) API key format appears invalid. Please check your key."
        case .invalidEndpoint:
            return "Invalid Ollama endpoint URL. Please check your settings."
        case .textTooLong(let maxLength):
            return "Text exceeds maximum length of \(maxLength) characters."
        }
    }
}

// MARK: - Settings Manager

class SettingsManager: ObservableObject {
    @Published var selectedProvider: LLMProvider {
        didSet { saveNonSecure() }
    }
    @Published var ollamaEndpoint: String {
        didSet { saveNonSecure() }
    }
    @Published var ollamaModel: String {
        didSet { saveNonSecure() }
    }
    @Published var hotkeyGrammar: HotkeyConfig {
        didSet { saveNonSecure() }
    }
    @Published var hotkeyImprove: HotkeyConfig {
        didSet { saveNonSecure() }
    }
    @Published var customPromptGrammar: String {
        didSet { saveNonSecure() }
    }
    @Published var customPromptImprove: String {
        didSet { saveNonSecure() }
    }
    @Published var openAIModel: String {
        didSet { saveNonSecure() }
    }
    @Published var claudeModel: String {
        didSet { saveNonSecure() }
    }
    @Published var launchAtLogin: Bool {
        didSet { saveNonSecure() }
    }
    @Published var requestTimeout: TimeInterval {
        didSet { saveNonSecure() }
    }
    @Published var maxRetries: Int {
        didSet { saveNonSecure() }
    }
    @Published var checkForUpdatesOnLaunch: Bool {
        didSet { saveNonSecure() }
    }

    // API keys are stored in Keychain, not UserDefaults
    var claudeAPIKey: String {
        get { keychain.get(key: KeychainManager.Keys.claudeAPIKey) ?? "" }
        set {
            keychain.save(newValue, forKey: KeychainManager.Keys.claudeAPIKey)
            objectWillChange.send()
        }
    }

    var openAIAPIKey: String {
        get { keychain.get(key: KeychainManager.Keys.openAIAPIKey) ?? "" }
        set {
            keychain.save(newValue, forKey: KeychainManager.Keys.openAIAPIKey)
            objectWillChange.send()
        }
    }

    private let defaults = UserDefaults.standard
    private let keychain = KeychainManager.shared

    // UserDefaults keys (non-sensitive data only)
    private enum DefaultsKeys {
        static let provider = "selectedProvider"
        static let ollamaEndpoint = "ollamaEndpoint"
        static let ollamaModel = "ollamaModel"
        static let openAIModel = "openAIModel"
        static let claudeModel = "claudeModel"
        static let hotkey = "hotkey"  // legacy, migrated to hotkeyGrammar
        static let hotkeyGrammar = "hotkeyGrammar"
        static let hotkeyImprove = "hotkeyImprove"
        static let customPromptGrammar = "customPromptGrammar"
        static let customPromptImprove = "customPromptImprove"
        static let launchAtLogin = "launchAtLogin"
        static let requestTimeout = "requestTimeout"
        static let maxRetries = "maxRetries"
        static let checkForUpdatesOnLaunch = "checkForUpdatesOnLaunch"
    }

    init() {
        // Load from UserDefaults (non-sensitive settings)
        if let providerString = defaults.string(forKey: DefaultsKeys.provider),
           let provider = LLMProvider(rawValue: providerString) {
            self.selectedProvider = provider
        } else {
            self.selectedProvider = .claude
        }

        self.ollamaEndpoint = defaults.string(forKey: DefaultsKeys.ollamaEndpoint) ?? "http://localhost:11434"
        self.ollamaModel = defaults.string(forKey: DefaultsKeys.ollamaModel) ?? "llama3.2:3b"
        ModelCatalog.migrateSavedModels(in: defaults, keys: [DefaultsKeys.openAIModel, DefaultsKeys.claudeModel])
        self.openAIModel = defaults.string(forKey: DefaultsKeys.openAIModel) ?? ModelCatalog.defaultOpenAI
        self.claudeModel = defaults.string(forKey: DefaultsKeys.claudeModel) ?? ModelCatalog.defaultClaude
        self.launchAtLogin = defaults.bool(forKey: DefaultsKeys.launchAtLogin)

        // Load per-mode hotkeys, with migration from the legacy single `hotkey` field.
        self.hotkeyGrammar = Self.loadHotkey(
            from: defaults,
            key: DefaultsKeys.hotkeyGrammar,
            legacyKey: DefaultsKeys.hotkey,
            legacyDefault: HotkeyConfig(keyCode: 5, modifiers: 0x100 | 0x800),  // old ⌥⌘G
            newDefault: GrammarMode.grammar.defaultHotkey                       // new ⌥⌘F
        )
        self.hotkeyImprove = Self.loadHotkey(
            from: defaults,
            key: DefaultsKeys.hotkeyImprove,
            legacyKey: nil,
            legacyDefault: nil,
            newDefault: GrammarMode.improve.defaultHotkey                       // ⌥⌘G
        )

        // Custom per-mode prompts (default empty)
        self.customPromptGrammar = defaults.string(forKey: DefaultsKeys.customPromptGrammar) ?? ""
        self.customPromptImprove = defaults.string(forKey: DefaultsKeys.customPromptImprove) ?? ""

        // Load timeout and retries with defaults
        let savedTimeout = defaults.double(forKey: DefaultsKeys.requestTimeout)
        self.requestTimeout = savedTimeout > 0 ? savedTimeout : ServiceConfiguration.defaultTimeout

        let savedRetries = defaults.integer(forKey: DefaultsKeys.maxRetries)
        self.maxRetries = savedRetries > 0 ? savedRetries : ServiceConfiguration.defaultMaxRetries

        // Default to checking for updates on launch (opt-out, not opt-in)
        if defaults.object(forKey: DefaultsKeys.checkForUpdatesOnLaunch) == nil {
            self.checkForUpdatesOnLaunch = true
        } else {
            self.checkForUpdatesOnLaunch = defaults.bool(forKey: DefaultsKeys.checkForUpdatesOnLaunch)
        }

        // Migrate API keys from UserDefaults to Keychain (one-time migration)
        migrateAPIKeysToKeychain()

        // Safety: if grammar and improve hotkeys collide (e.g. from a
        // migration edge case), reset improve to its default.
        if self.hotkeyGrammar == self.hotkeyImprove {
            self.hotkeyImprove = GrammarMode.improve.defaultHotkey
        }

        // Clear the legacy `hotkey` field now that migration is complete.
        if defaults.object(forKey: DefaultsKeys.hotkey) != nil {
            defaults.removeObject(forKey: DefaultsKeys.hotkey)
        }
    }

    /// Load a hotkey from UserDefaults, falling back to:
    /// 1. The legacy single-hotkey field if `legacyKey` is provided. If the
    ///    legacy value matches `legacyDefault`, it was the old default ⌥⌘G —
    ///    so we ignore it and use `newDefault` (which is ⌥⌘F now). If the
    ///    legacy value is something else, the user had customized it, so we
    ///    preserve their customization by binding it to the grammar mode.
    /// 2. `newDefault` if nothing was stored.
    private static func loadHotkey(
        from defaults: UserDefaults,
        key: String,
        legacyKey: String?,
        legacyDefault: HotkeyConfig?,
        newDefault: HotkeyConfig
    ) -> HotkeyConfig {
        if let data = defaults.data(forKey: key),
           let hotkey = try? JSONDecoder().decode(HotkeyConfig.self, from: data) {
            return hotkey
        }
        if let legacyKey = legacyKey,
           let data = defaults.data(forKey: legacyKey),
           let legacy = try? JSONDecoder().decode(HotkeyConfig.self, from: data) {
            if let legacyDefault = legacyDefault, legacy == legacyDefault {
                return newDefault
            }
            return legacy
        }
        return newDefault
    }

    // MARK: - Per-mode accessors

    func hotkey(for mode: GrammarMode) -> HotkeyConfig {
        switch mode {
        case .grammar: return hotkeyGrammar
        case .improve: return hotkeyImprove
        }
    }

    func customPrompt(for mode: GrammarMode) -> String {
        switch mode {
        case .grammar: return customPromptGrammar
        case .improve: return customPromptImprove
        }
    }

    func setHotkey(_ hotkey: HotkeyConfig, for mode: GrammarMode) {
        switch mode {
        case .grammar: hotkeyGrammar = hotkey
        case .improve: hotkeyImprove = hotkey
        }
    }

    func setCustomPrompt(_ value: String, for mode: GrammarMode) {
        switch mode {
        case .grammar: customPromptGrammar = value
        case .improve: customPromptImprove = value
        }
    }

    private func saveNonSecure() {
        defaults.set(selectedProvider.rawValue, forKey: DefaultsKeys.provider)
        defaults.set(ollamaEndpoint, forKey: DefaultsKeys.ollamaEndpoint)
        defaults.set(ollamaModel, forKey: DefaultsKeys.ollamaModel)
        defaults.set(openAIModel, forKey: DefaultsKeys.openAIModel)
        defaults.set(claudeModel, forKey: DefaultsKeys.claudeModel)
        defaults.set(launchAtLogin, forKey: DefaultsKeys.launchAtLogin)
        defaults.set(requestTimeout, forKey: DefaultsKeys.requestTimeout)
        defaults.set(maxRetries, forKey: DefaultsKeys.maxRetries)
        defaults.set(checkForUpdatesOnLaunch, forKey: DefaultsKeys.checkForUpdatesOnLaunch)
        defaults.set(customPromptGrammar, forKey: DefaultsKeys.customPromptGrammar)
        defaults.set(customPromptImprove, forKey: DefaultsKeys.customPromptImprove)

        if let data = try? JSONEncoder().encode(hotkeyGrammar) {
            defaults.set(data, forKey: DefaultsKeys.hotkeyGrammar)
        }
        if let data = try? JSONEncoder().encode(hotkeyImprove) {
            defaults.set(data, forKey: DefaultsKeys.hotkeyImprove)
        }
    }

    /// One-time migration of API keys from UserDefaults to Keychain
    private func migrateAPIKeysToKeychain() {
        let oldClaudeKey = "claudeAPIKey"
        let oldOpenAIKey = "openAIAPIKey"

        // Migrate Claude API key if exists in UserDefaults
        if let claudeKey = defaults.string(forKey: oldClaudeKey), !claudeKey.isEmpty {
            if keychain.save(claudeKey, forKey: KeychainManager.Keys.claudeAPIKey) {
                defaults.removeObject(forKey: oldClaudeKey)
            }
        }

        // Migrate OpenAI API key if exists in UserDefaults
        if let openAIKey = defaults.string(forKey: oldOpenAIKey), !openAIKey.isEmpty {
            if keychain.save(openAIKey, forKey: KeychainManager.Keys.openAIAPIKey) {
                defaults.removeObject(forKey: oldOpenAIKey)
            }
        }
    }

    // MARK: - Configuration

    var isConfigured: Bool {
        switch selectedProvider {
        case .claude:
            return !claudeAPIKey.isEmpty
        case .openai:
            return !openAIAPIKey.isEmpty
        case .ollama:
            return true
        }
    }

    /// Compact name of the model in use (popup subtitle, Settings status).
    var activeModelDisplayName: String {
        switch selectedProvider {
        case .claude: return ModelCatalog.displayName(for: claudeModel)
        case .openai: return ModelCatalog.displayName(for: openAIModel)
        case .ollama: return ollamaModel
        }
    }

    /// Get the current service configuration
    func getServiceConfiguration() -> ServiceConfiguration {
        let timeout: TimeInterval
        switch selectedProvider {
        case .ollama:
            timeout = max(requestTimeout, ServiceConfiguration.defaultOllamaTimeout)
        default:
            timeout = requestTimeout
        }

        let model: String?
        switch selectedProvider {
        case .openai: model = openAIModel
        case .claude: model = claudeModel
        case .ollama: model = ollamaModel
        }

        return ServiceConfiguration(
            provider: selectedProvider,
            apiKey: selectedProvider == .claude ? claudeAPIKey : (selectedProvider == .openai ? openAIAPIKey : nil),
            endpoint: selectedProvider == .ollama ? ollamaEndpoint : nil,
            model: model,
            timeout: timeout,
            maxRetries: maxRetries
        )
    }

    /// Validate input text before sending to LLM
    func validateInput(_ text: String) throws {
        guard !text.isEmpty else {
            throw ConfigurationError.textTooLong(maxLength: 0)
        }
        guard text.count <= ServiceConfiguration.maxInputLength else {
            throw ConfigurationError.textTooLong(maxLength: ServiceConfiguration.maxInputLength)
        }
    }
}
