#!/usr/bin/env bash
# Build BackbotBar.swift into a menu bar app bundle (LSUIElement agent).
# Usage: ./build.sh [output-dir]   (default: ~/.backbot)
set -euo pipefail

SRC_DIR="$(cd "$(dirname "$0")" && pwd)"
OUT_DIR="${1:-$HOME/.backbot}"
APP="$OUT_DIR/BackbotBar.app"

echo "Building BackbotBar.app -> $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"

# Compile (universal if possible)
ARCHS="-target arm64-apple-macos12"
if /usr/bin/uname -m | grep -q x86_64; then ARCHS="-target x86_64-apple-macos12"; fi
swiftc -O $ARCHS "$SRC_DIR/BackbotBar.swift" \
    -o "$APP/Contents/MacOS/BackbotBar" \
    -framework Cocoa

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>BackbotBar</string>
    <key>CFBundleDisplayName</key><string>backbot</string>
    <key>CFBundleIdentifier</key><string>dev.viraat.backbot.menubar</string>
    <key>CFBundleVersion</key><string>1.0</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleExecutable</key><string>BackbotBar</string>
    <key>LSMinimumSystemVersion</key><string>12.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

# Ad-hoc codesign so the status item is allowed to appear
/usr/bin/codesign --force --deep --sign - "$APP" 2>/dev/null || true

echo "Built: $APP"
