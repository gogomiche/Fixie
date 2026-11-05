import Foundation

/// Decides how Fixie should read and write text in a given app, from its
/// bundle alone (no hardcoded app list).
enum AppClassifier {

    enum Kind: String, Equatable {
        /// AppKit app: Accessibility API reads and writes work.
        case native
        /// Chromium/Electron shell (Slack, Notion, Discord, VS Code…).
        case electron
        /// Web browser (Safari, Chrome, Arc, Dia…).
        case browser
        /// UIKit app running on the Mac (Mac Catalyst or "Designed for iPad"),
        /// e.g. the current WhatsApp. Their text views often report AX writes
        /// as successful without applying them.
        case catalyst

        /// Apps where Accessibility writes can't be trusted → use clipboard + ⌘V.
        var requiresClipboardFallback: Bool {
            self != .native
        }
    }

    static func classify(bundleURL: URL) -> Kind {
        let info = Bundle(url: bundleURL)?.infoDictionary ?? [:]
        return classify(bundleURL: bundleURL, infoDictionary: info)
    }

    static func classify(bundleURL: URL, infoDictionary info: [String: Any]) -> Kind {
        if isElectron(bundleURL: bundleURL) { return .electron }
        if isBrowser(infoDictionary: info) { return .browser }
        if isCatalyst(bundleURL: bundleURL, infoDictionary: info) { return .catalyst }
        return .native
    }

    /// Electron apps embed "Electron Framework.framework".
    static func isElectron(bundleURL: URL) -> Bool {
        let frameworkPath = bundleURL
            .appendingPathComponent("Contents/Frameworks/Electron Framework.framework")
            .path
        return FileManager.default.fileExists(atPath: frameworkPath)
    }

    /// Any real browser declares itself as an http/https URL handler so it can
    /// be set as the system default.
    static func isBrowser(infoDictionary info: [String: Any]) -> Bool {
        guard let urlTypes = info["CFBundleURLTypes"] as? [[String: Any]] else { return false }
        return urlTypes.contains { entry in
            guard let schemes = entry["CFBundleURLSchemes"] as? [String] else { return false }
            let lowered = schemes.map { $0.lowercased() }
            return lowered.contains("http") || lowered.contains("https")
        }
    }

    /// Mac Catalyst apps keep UIKit's `UIDeviceFamily` key (6 = Mac);
    /// iPhone/iPad apps installed on Apple silicon declare
    /// `LSRequiresIPhoneOS` and live inside a `Wrapper/` directory.
    static func isCatalyst(bundleURL: URL, infoDictionary info: [String: Any]) -> Bool {
        if info["UIDeviceFamily"] != nil { return true }
        if (info["LSRequiresIPhoneOS"] as? Bool) == true { return true }
        return bundleURL.pathComponents.contains("Wrapper")
    }
}
