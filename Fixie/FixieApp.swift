import SwiftUI

@main
struct FixieApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // Use MenuBarExtra for a pure menu bar app (macOS 13+)
        MenuBarExtra {
            MenuBarContent(appDelegate: appDelegate)
        } label: {
            Image(systemName: "bicycle")
        }
    }
}

private struct MenuBarContent: View {
    let appDelegate: AppDelegate
    @ObservedObject var settings: SettingsManager

    init(appDelegate: AppDelegate) {
        self.appDelegate = appDelegate
        self.settings = appDelegate.settingsManager
    }

    var body: some View {
        Button("Fix Grammar (\(settings.hotkey(for: .grammar).displayString))") {
            appDelegate.triggerGrammarCheck(mode: .grammar)
        }
        Button("Improve Phrasing (\(settings.hotkey(for: .improve).displayString))") {
            appDelegate.triggerGrammarCheck(mode: .improve)
        }
        Divider()
        Button("Settings...") {
            appDelegate.openSettings()
        }
        .keyboardShortcut(",", modifiers: .command)
        Button("Check for Updates…") {
            appDelegate.checkForUpdates()
        }
        Divider()
        Button("Quit Fixie") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q", modifiers: .command)
    }
}
