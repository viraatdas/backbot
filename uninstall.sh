#!/usr/bin/env bash
set -euo pipefail

PLIST_NAME="com.backbot.nightly"
PLIST_PATH="$HOME/Library/LaunchAgents/$PLIST_NAME.plist"
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
read -rp "Remove GPG passphrase from Keychain? [y/N] " answer
if [[ "${answer:-N}" =~ ^[Yy]$ ]]; then
    security delete-generic-password -s "backbot-gpg" -a "backbot" 2>/dev/null || true
    echo "  Removed"
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
echo "Note: Duplicity cache (~/.cache/duplicity) was NOT removed."
