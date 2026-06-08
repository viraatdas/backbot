#!/usr/bin/env bash
set -euo pipefail

PLIST_NAME="com.backbot.nightly"
PLIST_PATH="$HOME/Library/LaunchAgents/$PLIST_NAME.plist"
MENUBAR_NAME="com.backbot.menubar"
MENUBAR_PATH="$HOME/Library/LaunchAgents/$MENUBAR_NAME.plist"
SYMLINK_PATH="$HOME/.local/bin/backbot"
INSTALL_DIR="$HOME/.backbot"
CONFIG_DIR="$HOME/.config/backbot"
LOG_DIR="$HOME/.local/share/backbot/logs"

echo "=== Backbot Uninstaller ==="
echo

# ── Unload launchd job ─────────────────────────────────────────────────
if launchctl list 2>/dev/null | grep -q "$PLIST_NAME"; then
    echo "Unloading launchd job..."
    launchctl bootout "gui/$(id -u)/$PLIST_NAME" 2>/dev/null || true
    echo "  Unloaded"
else
    echo "Launchd job not loaded (skipping)"
fi

if [[ -f "$PLIST_PATH" ]]; then
    rm -f "$PLIST_PATH"
    echo "  Removed: $PLIST_PATH"
fi
echo

# ── Unload menu bar app ────────────────────────────────────────────────
if launchctl list 2>/dev/null | grep -q "$MENUBAR_NAME"; then
    echo "Unloading menu bar app..."
    launchctl bootout "gui/$(id -u)/$MENUBAR_NAME" 2>/dev/null || true
    echo "  Unloaded"
fi
pkill -f BackbotBar 2>/dev/null || true
if [[ -f "$MENUBAR_PATH" ]]; then
    rm -f "$MENUBAR_PATH"
    echo "  Removed: $MENUBAR_PATH"
fi
echo

# ── Remove symlink ─────────────────────────────────────────────────────
if [[ -L "$SYMLINK_PATH" ]]; then
    rm -f "$SYMLINK_PATH"
    echo "Removed symlink: $SYMLINK_PATH"
else
    echo "Symlink not found (skipping)"
fi
echo

# ── Optional: remove config ───────────────────────────────────────────
read -rp "Remove config directory ($CONFIG_DIR)? [y/N] " answer
if [[ "${answer:-N}" =~ ^[Yy]$ ]]; then
    rm -rf "$CONFIG_DIR"
    echo "  Removed"
fi

# ── Optional: remove logs ─────────────────────────────────────────────
read -rp "Remove log directory ($LOG_DIR)? [y/N] " answer
if [[ "${answer:-N}" =~ ^[Yy]$ ]]; then
    rm -rf "$LOG_DIR"
    echo "  Removed"
fi

# ── Optional: remove Keychain entry ───────────────────────────────────
read -rp "Remove restic repo password from Keychain? [y/N] " answer
if [[ "${answer:-N}" =~ ^[Yy]$ ]]; then
    echo "WARNING: without this password your S3 backup is unrecoverable."
    read -rp "Really delete it? [y/N] " confirm
    if [[ "${confirm:-N}" =~ ^[Yy]$ ]]; then
        security delete-generic-password -s "backbot-restic" -a "backbot" 2>/dev/null || true
        echo "  Removed"
    fi
fi

echo
echo "=== Uninstall Complete ==="
echo
# ── Optional: remove install directory ─────────────────────────────────
read -rp "Remove backbot install directory ($INSTALL_DIR)? [y/N] " answer
if [[ "${answer:-N}" =~ ^[Yy]$ ]]; then
    rm -rf "$INSTALL_DIR"
    echo "  Removed"
fi

echo
echo "Note: Your S3 backup data was NOT removed."
echo "Note: Your AWS 'backbot' profile (~/.aws) was NOT removed."
