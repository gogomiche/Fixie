# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build Commands

```bash
# Open in Xcode
open Fixie.xcodeproj

# Build from command line
xcodebuild -project Fixie.xcodeproj -scheme Fixie -configuration Debug build

# Build for release
xcodebuild -project Fixie.xcodeproj -scheme Fixie -configuration Release build

# Clean build
xcodebuild -project Fixie.xcodeproj -scheme Fixie clean
```

Run and test via Xcode (⌘R). No test suite exists - manual testing is required.

## Architecture

Fixie is a macOS menu bar app for grammar correction using LLMs. The workflow:

1. **Text Capture**: User selects text, presses global hotkey (⌥⌘G)
2. **Capture Method**: Accessibility API (preferred) or clipboard fallback via Cmd+C simulation
3. **LLM Request**: Sends text to configured provider with streaming enabled
4. **Diff Display**: Shows word-level diff in floating popup (red=removed, green=added)
5. **Accept/Reject**: Enter accepts (pastes correction), Escape cancels

### Key Files

- `AppDelegate.swift` - Core logic: hotkey handling, text capture/paste via Accessibility API or CGEvent simulation, streaming response handling
- `FixieApp.swift` - SwiftUI entry point, MenuBarExtra definition

### Services Layer (`Services/`)

All services implement `LLMService` protocol with async streaming support:
- `ClaudeService.swift` - Claude Sonnet 4 (`claude-sonnet-4-20250514`)
- `OpenAIService.swift` - GPT-4o Mini
- `OllamaService.swift` - Local models (default: llama3.2 at localhost:11434)

Factory pattern via `LLMServiceFactory.createService(for:settings:)`.

### Other Components

- `Models/Settings.swift` - `SettingsManager` class with UserDefaults persistence, `LLMProvider` enum
- `Utilities/HotkeyManager.swift` - Global hotkey via Carbon.HIToolbox
- `Utilities/DiffCalculator.swift` - LCS-based word-level diff algorithm
- `Views/DiffPopupView.swift` - Streaming diff display with keyboard handling
- `Views/SettingsView.swift` - Tab-based settings UI

## Platform Requirements

- macOS 13.0+ (Ventura)
- Xcode 15.0+
- Swift 5.9
- No external dependencies - native Apple frameworks only

## App Characteristics

- Menu bar only (`LSUIElement: true` in Info.plist - no dock icon)
- Sandbox disabled (required for global hotkey and Accessibility API)
- Requires Accessibility permissions for text capture/paste
