import Foundation
import UserNotifications
import AppKit

/// Checks GitHub Releases for a newer version of Fixie and notifies the user.
///
/// This is a lightweight alternative to Sparkle: no in-app install — the user
/// is sent to the Releases page to download the new DMG themselves.
@MainActor
final class UpdateChecker: ObservableObject {
    static let shared = UpdateChecker()

    enum Status: Equatable {
        case idle
        case checking
        case upToDate(version: String)
        case available(version: String, url: URL)
        case failed(String)
    }

    @Published private(set) var status: Status = .idle

    /// Hard-coded because the repo identity is part of the app's release channel.
    private let releasesAPIURL = URL(string: "https://api.github.com/repos/gogomiche/Fixie/releases/latest")!

    /// Notification action that opens the Releases page when tapped.
    static let notificationCategoryID = "fixie.update.available"
    private static let urlUserInfoKey = "releaseURL"

    /// Minimum interval between automatic background checks (6h).
    private let backgroundCheckInterval: TimeInterval = 6 * 60 * 60

    private let lastCheckKey = "lastUpdateCheckDate"
    private let skippedVersionKey = "skippedUpdateVersion"

    private init() {}

    // MARK: - Public API

    /// The current installed version string (e.g. "1.0.0").
    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    /// Date of the last successful check, if any.
    var lastCheckDate: Date? {
        UserDefaults.standard.object(forKey: lastCheckKey) as? Date
    }

    /// Register the notification category so taps on the "update available"
    /// notification route through `handle(response:)`.
    nonisolated func registerNotificationCategory() {
        let category = UNNotificationCategory(
            identifier: Self.notificationCategoryID,
            actions: [],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }

    /// Run a background check if enough time has passed since the last one.
    /// Silent: only posts a notification if an update is available.
    func checkInBackgroundIfDue() async {
        if let last = lastCheckDate, Date().timeIntervalSince(last) < backgroundCheckInterval {
            return
        }
        await check(silent: true)
    }

    /// Perform a check. When `silent` is false, the SettingsView reflects the
    /// status via `@Published` so the user gets feedback even if up-to-date.
    func check(silent: Bool) async {
        status = .checking

        do {
            let release = try await fetchLatestRelease()
            UserDefaults.standard.set(Date(), forKey: lastCheckKey)

            let comparison = compareVersions(currentVersion, release.version)
            if comparison == .orderedAscending {
                status = .available(version: release.version, url: release.htmlURL)
                if silent {
                    await postUpdateNotification(version: release.version, url: release.htmlURL)
                }
            } else {
                status = .upToDate(version: currentVersion)
            }
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    /// Open the saved release URL (called from menu or notification tap).
    func openLatestReleaseURL() {
        if case let .available(_, url) = status {
            NSWorkspace.shared.open(url)
        } else {
            NSWorkspace.shared.open(URL(string: "https://github.com/gogomiche/Fixie/releases/latest")!)
        }
    }

    /// Handle a notification response. Returns true if the response targeted
    /// the update notification.
    @discardableResult
    nonisolated func handle(response: UNNotificationResponse) -> Bool {
        guard response.notification.request.content.categoryIdentifier == Self.notificationCategoryID else {
            return false
        }
        let userInfo = response.notification.request.content.userInfo
        if let urlString = userInfo[Self.urlUserInfoKey] as? String, let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
        return true
    }

    // MARK: - Internals

    private struct Release {
        let version: String
        let htmlURL: URL
    }

    private func fetchLatestRelease() async throws -> Release {
        var request = URLRequest(url: releasesAPIURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Fixie/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw UpdateCheckError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw UpdateCheckError.httpStatus(http.statusCode)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = json["tag_name"] as? String,
              let htmlURLString = json["html_url"] as? String,
              let htmlURL = URL(string: htmlURLString) else {
            throw UpdateCheckError.malformedPayload
        }

        return Release(version: normalize(tag), htmlURL: htmlURL)
    }

    private func postUpdateNotification(version: String, url: URL) async {
        let center = UNUserNotificationCenter.current()

        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
            return
        }

        let content = UNMutableNotificationContent()
        content.title = "Fixie \(version) is available"
        content.body = "Click to download the latest version."
        content.categoryIdentifier = Self.notificationCategoryID
        content.userInfo = [Self.urlUserInfoKey: url.absoluteString]

        let request = UNNotificationRequest(identifier: "fixie.update.\(version)", content: content, trigger: nil)
        try? await center.add(request)
    }

    /// Strip a leading "v" or "V" if present (GitHub tags are often "v1.2.3" or "V1.2.3").
    private func normalize(_ tag: String) -> String {
        if let first = tag.first, first == "v" || first == "V" {
            return String(tag.dropFirst())
        }
        return tag
    }

    /// Component-wise integer comparison: "1.10.0" > "1.9.0".
    /// Non-numeric components fall back to lexicographic compare so pre-release
    /// tags like "1.0.0-beta" don't cause a crash.
    private func compareVersions(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let lhsParts = lhs.split(separator: ".").map(String.init)
        let rhsParts = rhs.split(separator: ".").map(String.init)
        let count = max(lhsParts.count, rhsParts.count)

        for i in 0..<count {
            let a = i < lhsParts.count ? lhsParts[i] : "0"
            let b = i < rhsParts.count ? rhsParts[i] : "0"
            if let ai = Int(a), let bi = Int(b) {
                if ai < bi { return .orderedAscending }
                if ai > bi { return .orderedDescending }
            } else {
                let cmp = a.compare(b)
                if cmp != .orderedSame { return cmp }
            }
        }
        return .orderedSame
    }
}

enum UpdateCheckError: LocalizedError {
    case invalidResponse
    case httpStatus(Int)
    case malformedPayload

    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "No response from the update server."
        case .httpStatus(let code): return "Update server returned HTTP \(code)."
        case .malformedPayload: return "Could not parse the latest release."
        }
    }
}
