import Foundation

/// In-memory stand-in for `KeychainManager`, so the preview never reads or
/// writes the real Keychain (which would prompt for Fixie's saved API keys).
final class KeychainManager {
    static let shared = KeychainManager()

    private var store: [String: String] = [:]

    private init() {}

    @discardableResult
    func save(_ value: String, forKey key: String) -> Bool {
        store[key] = value
        return true
    }

    func get(key: String) -> String? {
        store[key]
    }

    @discardableResult
    func delete(key: String) -> Bool {
        store[key] = nil
        return true
    }

    func exists(key: String) -> Bool {
        store[key] != nil
    }

    enum Keys {
        static let claudeAPIKey = "claude_api_key"
        static let openAIAPIKey = "openai_api_key"
    }
}
