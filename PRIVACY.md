# Privacy Policy

**Last Updated: December 2024**

## Overview

Fixie is a grammar correction application that processes text using AI language models. This privacy policy explains what data Fixie collects, how it's used, and your choices.

## Data Collection

### Text You Correct
- When you use Fixie's grammar correction feature, the selected text is sent to your chosen AI provider (Claude, OpenAI, or Ollama)
- Fixie does **not** store or log any text you correct
- Text is transmitted directly to the AI provider and is not retained by Fixie

### API Keys
- API keys for Claude and OpenAI are stored securely in the macOS Keychain
- Keys are never transmitted anywhere except to their respective API endpoints
- Keys are not logged or stored in plain text

### Usage Data
- Fixie does **not** collect analytics, telemetry, or usage statistics
- No data is sent to the Fixie developers

## Third-Party Services

Depending on your configuration, text may be sent to:

### Claude (Anthropic)
- Privacy Policy: https://www.anthropic.com/privacy
- Data is processed according to Anthropic's terms

### OpenAI
- Privacy Policy: https://openai.com/privacy
- Data is processed according to OpenAI's terms

### Ollama (Local)
- When using Ollama, all processing happens locally on your machine
- No data is sent to external servers

## Permissions

Fixie requires certain macOS permissions:

### Accessibility Permission
- Required to read and replace selected text in other applications
- Fixie only accesses the text you explicitly select when triggering correction
- No background monitoring occurs

### Network Access
- Required to communicate with AI API endpoints
- Only connects to the configured AI provider

## Data Security

- API keys are encrypted using macOS Keychain
- All API communications use HTTPS encryption
- No data persists after the correction is complete

## Your Choices

- **Use Ollama**: For maximum privacy, use Ollama which runs entirely locally
- **Delete API Keys**: Remove stored keys at any time in Settings
- **Revoke Permissions**: Disable Accessibility permission in System Settings to stop Fixie from functioning

## Children's Privacy

Fixie is not intended for users under 13 years of age.

## Changes to This Policy

We may update this privacy policy. Changes will be noted in the "Last Updated" date.

## Contact

For privacy questions, please open an issue on GitHub: https://github.com/gogomiche/Fixie

---

**Summary**: Fixie sends your selected text to AI providers for correction. It stores API keys securely and collects no other data.
