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

class SettingsManager: ObservableObject {
    @Published var selectedProvider: LLMProvider {
        didSet { save() }
    }
    @Published var claudeAPIKey: String {
        didSet { save() }
    }
    @Published var openAIAPIKey: String {
        didSet { save() }
    }
    @Published var ollamaEndpoint: String {
        didSet { save() }
    }
    @Published var ollamaModel: String {
        didSet { save() }
    }
    @Published var hotkey: HotkeyConfig {
        didSet { save() }
    }
    @Published var launchAtLogin: Bool {
        didSet { save() }
    }

    private let defaults = UserDefaults.standard
    private let providerKey = "selectedProvider"
    private let claudeAPIKeyKey = "claudeAPIKey"
    private let openAIAPIKeyKey = "openAIAPIKey"
    private let ollamaEndpointKey = "ollamaEndpoint"
    private let ollamaModelKey = "ollamaModel"
    private let hotkeyKey = "hotkey"
    private let launchAtLoginKey = "launchAtLogin"

    init() {
        // Load from UserDefaults
        if let providerString = defaults.string(forKey: providerKey),
           let provider = LLMProvider(rawValue: providerString) {
            self.selectedProvider = provider
        } else {
            self.selectedProvider = .claude
        }

        self.claudeAPIKey = defaults.string(forKey: claudeAPIKeyKey) ?? ""
        self.openAIAPIKey = defaults.string(forKey: openAIAPIKeyKey) ?? ""
        self.ollamaEndpoint = defaults.string(forKey: ollamaEndpointKey) ?? "http://localhost:11434"
        self.ollamaModel = defaults.string(forKey: ollamaModelKey) ?? "llama3.2"
        self.launchAtLogin = defaults.bool(forKey: launchAtLoginKey)

        if let hotkeyData = defaults.data(forKey: hotkeyKey),
           let hotkey = try? JSONDecoder().decode(HotkeyConfig.self, from: hotkeyData) {
            self.hotkey = hotkey
        } else {
            self.hotkey = HotkeyConfig.defaultHotkey
        }
    }

    private func save() {
        defaults.set(selectedProvider.rawValue, forKey: providerKey)
        defaults.set(claudeAPIKey, forKey: claudeAPIKeyKey)
        defaults.set(openAIAPIKey, forKey: openAIAPIKeyKey)
        defaults.set(ollamaEndpoint, forKey: ollamaEndpointKey)
        defaults.set(ollamaModel, forKey: ollamaModelKey)
        defaults.set(launchAtLogin, forKey: launchAtLoginKey)

        if let hotkeyData = try? JSONEncoder().encode(hotkey) {
            defaults.set(hotkeyData, forKey: hotkeyKey)
        }
    }

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
}
