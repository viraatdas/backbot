#!/usr/bin/env bash
# Build BackbotBar.swift into a menu bar app bundle (LSUIElement agent).
# Usage: ./build.sh [output-dir]   (default: ~/.backbot)
set -euo pipefail

SRC_DIR="$(cd "$(dirname "$0")" && pwd)"
OUT_DIR="${1:-$HOME/.backbot}"
APP="$OUT_DIR/BackbotBar.app"
BUNDLE_ID="dev.viraat.backbot.menubar"

echo "Building BackbotBar.app -> $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

# Target macOS 13: SMAppService (the Login Items API) needs it.
ARCHS="-target arm64-apple-macos13"
if /usr/bin/uname -m | grep -q x86_64; then ARCHS="-target x86_64-apple-macos13"; fi

# ── App icon ───────────────────────────────────────────────────────────
# Drawn from BackbotMark.swift at build time, so there is no binary art in
# the repo and the icon can never drift from the menu bar glyph.
BUILD_TMP="$(mktemp -d)"
trap 'rm -rf "$BUILD_TMP"' EXIT

# Which side of the icon-masking change this machine is on. macOS 26 rounds and
# shadows app icons itself, but only for art that fills its canvas edge to edge;
# feed it art with transparent margins and it insets that onto a light backdrop
# tile instead (verified A/B on this bundle — the effect shows on an ad-hoc
# signed app like this one, which is what `codesign --sign -` below produces).
# macOS 13-15 do no masking at all and draw the icns as-is, so they need us to
# supply the rounded shape or they would get a hard square. The icon is
# generated on the installing machine, so this tracks whoever is installing.
MACOS_MAJOR="$(/usr/bin/sw_vers -productVersion | cut -d. -f1)"
if [[ "${MACOS_MAJOR:-0}" -ge 26 ]]; then
    ICON_SHAPE="fullbleed"
else
    ICON_SHAPE="rounded"
fi

if swiftc -O $ARCHS "$SRC_DIR/BackbotMark.swift" "$SRC_DIR/MakeIcon.swift" \
        -o "$BUILD_TMP/makeicon" -framework Cocoa 2>/dev/null \
   && "$BUILD_TMP/makeicon" "$BUILD_TMP/AppIcon.iconset" --shape "$ICON_SHAPE" >/dev/null \
   && /usr/bin/iconutil -c icns "$BUILD_TMP/AppIcon.iconset" \
        -o "$APP/Contents/Resources/AppIcon.icns"; then
    echo "  Icon: AppIcon.icns ($ICON_SHAPE, macOS $MACOS_MAJOR)"
else
    echo "  Icon generation failed — continuing without one."
fi

# ── App binary ─────────────────────────────────────────────────────────
swiftc -O $ARCHS "$SRC_DIR/BackbotMark.swift" "$SRC_DIR/BackbotBar.swift" \
    -o "$APP/Contents/MacOS/BackbotBar" \
    -framework Cocoa

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>backbot</string>
    <key>CFBundleDisplayName</key><string>backbot</string>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundleVersion</key><string>1.1</string>
    <key>CFBundleShortVersionString</key><string>1.1</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleExecutable</key><string>BackbotBar</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundleIconName</key><string>AppIcon</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

# Ad-hoc codesign so the status item is allowed to appear and so SMAppService
# will accept the bundle as a login item.
/usr/bin/codesign --force --deep --sign - "$APP" 2>/dev/null || true

# Let Launch Services pick up the new bundle + icon straight away, otherwise
# System Settings can keep showing a stale (or missing) icon.
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
    -f "$APP" 2>/dev/null || true

echo "Built: $APP"
