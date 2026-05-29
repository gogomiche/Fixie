# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build Commands

```bash
# Build from command line
xcodebuild -project Fixie.xcodeproj -scheme Fixie -configuration Debug build

# Build for release
xcodebuild -project Fixie.xcodeproj -scheme Fixie -configuration Release build

# Run tests
xcodebuild -project Fixie.xcodeproj -scheme Fixie -destination 'platform=macOS' test

# Clean build
xcodebuild -project Fixie.xcodeproj -scheme Fixie clean
```

Run the app via Xcode (`open Fixie.xcodeproj`, then ⌘R).

## Architecture

Fixie is a macOS menu bar app for grammar correction using LLMs.

### Modes

Fixie supports two modes via the `GrammarMode` enum (`Fixie/Models/GrammarMode.swift`):
- **`.grammar`** — default hotkey ⌥⌘F. Strict grammar/spelling correction without changing meaning, tone, or formatting.
- **`.improve`** — default hotkey ⌥⌘G. Light rewrite for clarity and fluidity.

Each mode has its own base system prompt + a user-editable custom appendix (Settings → Prompts). The appendix is appended at runtime via `PromptBuilder.systemPrompt(for:customAppendix:)`. Settings stores per-mode hotkeys and prompts; `SettingsManager` exposes `hotkey(for:)` and `customPrompt(for:)`.

### Core Flow

1. User selects text, presses one of the global hotkeys
2. `HotkeyManager` dispatches by `EventHotKeyID.id` and calls `AppDelegate.triggerGrammarCheck(mode:)`
3. `AppDelegate` captures text via `AccessibilityManager` (native apps) or clipboard fallback (browsers/Electron, auto-detected)
4. `LLMServiceFactory.create()` instantiates the configured provider
5. `processText(text:mode:)` resolves the system prompt via `PromptBuilder.systemPrompt(for:customAppendix:)` and calls `llmService.streamCorrection(text:systemPrompt:)`
6. Streaming response → `StreamingState` → `PopupWindowManager`'s floating `NSPanel`
7. `GrammarPopupView` shows the popup title from `mode.popupTitle` plus a word-level diff (via `DiffCalculator`, LCS-based)
8. Enter accepts → text is pasted back via Accessibility API or clipboard+paste fallback; Escape cancels

### Text Insertion Strategy

`AppDelegate.acceptCorrection()` uses two paths based on `AccessibilityManager.savedAppRequiresTypingFallback`:
- **Native apps** (TextEdit, Notes, Mail, Pages…): Accessibility API. Before writing, `AccessibilityManager.writeReplacingSelection(_:element:range:)` re-sets the saved `CFRange` on `kAXSelectedTextRangeAttribute` so the replacement works even if focus changes collapsed the selection. Falls back to clipboard+paste if AX reports failure.
- **Electron + browsers**: always clipboard+paste. Auto-detected:
  - Electron: presence of `Contents/Frameworks/Electron Framework.framework` in the bundle (`isElectronApp`)
  - Browser: app's `Info.plist` declares `http`/`https` in `CFBundleURLTypes` (`isBrowser`)
- `KeyboardSimulator.simulateCopy()` and `simulatePaste()` poll `CGEventSource.flagsState` until Cmd/Option/Shift/Control are released, then settle 60ms, before posting — avoids leaking hotkey modifiers into the synthesized event.
- Clipboard read polls `NSPasteboard.changeCount` (no fixed delay).

The previous frontmost app is saved at hotkey press time (`previousApp`) and re-activated before pasting back.

### Services Layer

All LLM services inherit from `BaseLLMService` (common HTTP/streaming logic) which implements the `LLMService` protocol. Each subclass overrides: `providerName`, `apiURL`, `streamParser`, `configureRequest()`, `buildRequestBody()`, `parseResponse()`.

Stream parsing uses the Strategy pattern:
- `SSEStreamParser` — Server-Sent Events for Claude and OpenAI
- `JSONLStreamParser` — JSON Lines for Ollama

Factory: `LLMServiceFactory.create(provider:settings:)`

### Settings & Security

- `SettingsManager` persists non-sensitive settings in UserDefaults, API keys in macOS Keychain via `KeychainManager`
- One-time migration from UserDefaults to Keychain happens in `SettingsManager.init()`
- `ServiceConfiguration` validates API key formats (prefix checks: `sk-ant-` for Claude, `sk-` for OpenAI)

### Singleton Managers

`AccessibilityManager.shared`, `ClipboardManager.shared`, `KeyboardSimulator.shared`, `PopupWindowManager.shared`, `KeychainManager.shared` — all use private `init()`.

## Tests

Test target: `FixieTests/` with 5 test files covering `DiffCalculator`, `GrammarCheckState`, `KeychainManager`, `LLMService` (stream parsers + input sanitization), and `Settings` (configuration validation). No UI tests. `KeychainManager` tests use real Keychain with UUID-based keys and tearDown cleanup.

## Platform Requirements

- macOS 13.0+ (Ventura), Xcode 15.0+, Swift 5.9
- No external dependencies — native Apple frameworks only
- Sandbox disabled (required for global hotkey and Accessibility API)
- `LSUIElement: true` in Info.plist (menu bar only, no dock icon)
- Global hotkey registered via Carbon HIToolbox (`HotkeyManager`)

## Releasing

### Version source of truth

`GENERATE_INFOPLIST_FILE = YES` is set in `Fixie.xcodeproj/project.pbxproj`, which means **Xcode overrides any version values in `Fixie/Info.plist` at build time**. The source of truth for the app version is in `project.pbxproj` build settings:

- `MARKETING_VERSION` (→ `CFBundleShortVersionString`, e.g. `1.3.0`) — user-facing version shown in About + read by `UpdateChecker.currentVersion`
- `CURRENT_PROJECT_VERSION` (→ `CFBundleVersion`, e.g. `3`) — strictly increasing build number

Both values live in two places inside `project.pbxproj`: the Debug and Release configurations of the `Fixie` target (search for `MARKETING_VERSION`). The `FixieTests` target has its own values — don't touch those.

After bumping, verify with:
```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Fixie.xcodeproj -scheme Fixie -configuration Debug clean build
/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" ~/Library/Developer/Xcode/DerivedData/Fixie-*/Build/Products/Debug/Fixie.app/Contents/Info.plist
```

### Build, sign, and package the DMG

There is no Apple Developer Program account — the app is **ad-hoc signed**. Users get a Gatekeeper warning on first launch (right-click → Open).

```bash
# 1. Clean Release build
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project Fixie.xcodeproj -scheme Fixie -configuration Release clean build

# 2. Stage and ad-hoc sign
STAGING=/tmp/fixie-release && rm -rf "$STAGING" && mkdir -p "$STAGING"
cp -R ~/Library/Developer/Xcode/DerivedData/Fixie-*/Build/Products/Release/Fixie.app "$STAGING/Fixie.app"
codesign --force --deep --sign - "$STAGING/Fixie.app"

# 3. Add Applications symlink and create DMG
(cd "$STAGING" && ln -s /Applications Applications)
hdiutil create -volname "Fixie" -srcfolder "$STAGING" -ov -format UDZO "$STAGING/Fixie.dmg"
```

### Publish to GitHub Releases

```bash
gh release create vX.Y.Z /tmp/fixie-release/Fixie.dmg \
  --title "Fixie vX.Y.Z" \
  --notes "$(cat <<'EOF'
## Changes
- ...
EOF
)"
```

The auto-update check in `UpdateChecker` reads `tag_name` from the latest release. Tags are stripped of a leading `v` or `V` before semver comparison. Use lowercase `v` for new tags (`v1.3.1`).
