import Foundation
import SwiftUI

enum LLMProvider: String, CaseIterable, Codable {
    case claude = "Claude"
    case openai = "OpenAI"
    case ollama = "Ollama"

    var displayName: String {
        return self.rawValue
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
    @Published var hotkey: HotkeyConfig {
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
        static let hotkey = "hotkey"
        static let launchAtLogin = "launchAtLogin"
        static let requestTimeout = "requestTimeout"
        static let maxRetries = "maxRetries"
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
        self.openAIModel = defaults.string(forKey: DefaultsKeys.openAIModel) ?? "gpt-4o-mini"
        self.claudeModel = defaults.string(forKey: DefaultsKeys.claudeModel) ?? "claude-sonnet-4-20250514"
        self.launchAtLogin = defaults.bool(forKey: DefaultsKeys.launchAtLogin)

        // Load hotkey before other properties that depend on self
        if let hotkeyData = defaults.data(forKey: DefaultsKeys.hotkey),
           let hotkey = try? JSONDecoder().decode(HotkeyConfig.self, from: hotkeyData) {
            self.hotkey = hotkey
        } else {
            self.hotkey = HotkeyConfig.defaultHotkey
        }

        // Load timeout and retries with defaults
        let savedTimeout = defaults.double(forKey: DefaultsKeys.requestTimeout)
        self.requestTimeout = savedTimeout > 0 ? savedTimeout : ServiceConfiguration.defaultTimeout

        let savedRetries = defaults.integer(forKey: DefaultsKeys.maxRetries)
        self.maxRetries = savedRetries > 0 ? savedRetries : ServiceConfiguration.defaultMaxRetries

        // Migrate API keys from UserDefaults to Keychain (one-time migration)
        migrateAPIKeysToKeychain()
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

        if let hotkeyData = try? JSONEncoder().encode(hotkey) {
            defaults.set(hotkeyData, forKey: DefaultsKeys.hotkey)
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
