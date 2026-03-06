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

### Core Flow

1. User selects text in any app, presses global hotkey (default: ⌥⌘G)
2. `AppDelegate.triggerGrammarCheck()` captures text via `AccessibilityManager` (preferred) or clipboard fallback (`ClipboardManager` + `KeyboardSimulator.simulateCopy()`)
3. `LLMServiceFactory.create()` instantiates the configured provider
4. Streaming response is piped through `StreamingState` (ObservableObject) into `PopupWindowManager`'s floating `NSPanel`
5. `GrammarPopupView` displays a word-level diff (via `DiffCalculator`, LCS-based) with red=removed, green=added
6. Enter accepts → text is pasted back via Accessibility API or clipboard+paste fallback; Escape cancels

### Text Insertion Strategy

`AppDelegate.acceptCorrection()` uses two paths:
- **Native apps**: Accessibility API (`AXUIElementSetAttributeValue` on saved focused element), falling back to clipboard+paste
- **Electron/web apps**: Always clipboard+paste (listed in `AccessibilityManager.appsRequiringTypingFallback`)

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
