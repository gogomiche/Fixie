import SwiftUI

@main
struct FixieApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // Use MenuBarExtra for a pure menu bar app (macOS 13+)
        MenuBarExtra {
            Button("Check Grammar (⌥⌘G)") {
                appDelegate.triggerGrammarCheck()
            }
            Divider()
            Button("Settings...") {
                appDelegate.openSettings()
            }
            .keyboardShortcut(",", modifiers: .command)
            Divider()
            Button("Quit Fixie") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: .command)
        } label: {
            Image("MenuBarIcon")
                .resizable()
                .renderingMode(.original)
                .aspectRatio(contentMode: .fit)
                .frame(height: 18)
        }
    }
}
