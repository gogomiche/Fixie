#!/bin/bash
# Renders the popup and Settings with sample data, in dark and light appearance,
# and saves one PNG per scene (no Xcode needed, Command Line Tools suffice).
# Windows show on screen for ~25 s: the harness captures its own windows, so it
# needs no Screen Recording permission. The Keychain is stubbed out.
# Usage: Tools/UIPreview/run.sh [output-dir]   (default: Tools/UIPreview/out)
set -euo pipefail
cd "$(dirname "$0")/../.."

OUT="${1:-Tools/UIPreview/out}"
BUILD="$(mktemp -d)"
trap 'rm -rf "$BUILD"' EXIT

# From the macOS 27 SDK on, @State is a macro whose plugin ships with Xcode
# only: prefer a macOS 26 SDK (Liquid Glass APIs, @State still a property
# wrapper). Override with SDK=/path/to/MacOSX.sdk.
SDKS_DIR="$(dirname "$(xcrun --show-sdk-path)")"
SDK="${SDK:-$(ls -d "$SDKS_DIR"/MacOSX26*.sdk 2>/dev/null | tail -1)}"
SDK="${SDK:-$(xcrun --show-sdk-path)}"

# App sources minus the @main entry point and the real Keychain; #Preview
# blocks are dropped (their macro plugin also ships with Xcode only).
mkdir -p "$BUILD/src"
find Fixie -name '*.swift' ! -name FixieApp.swift ! -name KeychainManager.swift | while read -r f; do
  awk '/^#Preview/ { skip = 1 } !skip { print } skip && /^}/ { skip = 0 }' "$f" > "$BUILD/src/$(basename "$f")"
done

# Embedded Info.plist: Bundle.main gets the app version and its own defaults domain.
VERSION="$(grep -m1 'MARKETING_VERSION' Fixie.xcodeproj/project.pbxproj | sed -E 's/.*= ([^;]+);/\1/')"
cat > "$BUILD/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>com.fixie.ui-preview</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
</dict></plist>
PLIST

swiftc -Onone -sdk "$SDK" -target "$(uname -m)-apple-macos13.0" -swift-version 5 \
  -Xlinker -sectcreate -Xlinker __TEXT -Xlinker __info_plist -Xlinker "$BUILD/Info.plist" \
  -o "$BUILD/ui-preview" \
  "$BUILD"/src/*.swift Tools/UIPreview/KeychainStub.swift Tools/UIPreview/main.swift \
  2>&1 | { grep -E ': error:' || true; }

"$BUILD/ui-preview" Fixie/Assets.xcassets/AppIcon.appiconset/icon_512x512@2x.png "$OUT"
