# Fixie

A lightweight macOS menu bar app for instant grammar and spelling correction. Select text anywhere, press a hotkey, and see corrections with a visual diff.

![macOS](https://img.shields.io/badge/macOS-13.0+-blue)
![Swift](https://img.shields.io/badge/Swift-5.9-orange)
![License](https://img.shields.io/badge/License-MIT-green)

## Features

- **Global Hotkey**: Trigger grammar check from any app (default: `⌥⌘G`)
- **Visual Diff**: See exactly what changed with color-coded additions and removals
- **Multiple LLM Providers**: Choose between Claude, OpenAI, or Ollama (local)
- **Lightweight**: Native SwiftUI app with minimal resource usage
- **Privacy-First**: Ollama option keeps all data on your machine

## Installation

### Option 1: Download Release

1. Download the latest `.dmg` from [Releases](https://github.com/gogomiche/Fixie/releases)
2. Drag `Fixie.app` to your Applications folder
3. Open Fixie and grant Accessibility permissions when prompted

### Option 2: Build from Source

```bash
# Clone the repository
git clone https://github.com/gogomiche/Fixie.git
cd Fixie

# Open in Xcode
open Fixie.xcodeproj

# Build and run (⌘R)
```

### Option 3: Homebrew (coming soon)

```bash
brew install --cask fixie
```

## Setup

1. **Launch Fixie** - It appears as an icon in your menu bar
2. **Grant Accessibility Permissions** - Required for capturing selected text
   - System Settings → Privacy & Security → Accessibility → Enable Fixie
3. **Configure LLM Provider** - Click the menu bar icon → Settings
   - **Claude**: Get API key from [console.anthropic.com](https://console.anthropic.com/)
   - **OpenAI**: Get API key from [platform.openai.com](https://platform.openai.com/api-keys)
   - **Ollama**: Install [Ollama](https://ollama.ai/) and run a model locally

## Usage

1. **Select text** in any application
2. **Press the hotkey** (`⌥⌘G` by default)
3. **Review changes** in the popup:
   - Red strikethrough = removed text
   - Green highlight = added text
4. **Press Enter** to accept and replace, or **Escape** to cancel

## Requirements

- macOS 13.0 (Ventura) or later
- Accessibility permissions
- API key for Claude/OpenAI, or Ollama installed locally

## Privacy

- **Cloud providers (Claude/OpenAI)**: Selected text is sent to the API for processing
- **Ollama**: All processing happens locally on your machine
- **No telemetry**: Fixie does not collect any usage data

## Troubleshooting

### "No text selected" message
- Ensure the target app supports text selection
- Try selecting text again before pressing the hotkey

### Hotkey doesn't work
- Check Accessibility permissions in System Settings
- Make sure another app isn't using the same hotkey

### API errors
- Verify your API key is correct in Settings
- Check your API quota/billing status

### Ollama not working
- Ensure Ollama is running (`ollama serve`)
- Verify the model is downloaded (`ollama pull llama3.2`)

## Contributing

Contributions are welcome! Please:

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request


## Acknowledgments

- Inspired by [Raycast](https://raycast.com/) grammar fix feature
- Built with SwiftUI and native macOS APIs
