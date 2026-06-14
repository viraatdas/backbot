#!/usr/bin/env bash
set -euo pipefail

# ── Constants ──────────────────────────────────────────────────────────
REPO="viraatdas/backbot"
INSTALL_DIR="$HOME/.backbot"
CONFIG_DIR="$HOME/.config/backbot"
LOG_DIR="$HOME/.local/share/backbot/logs"
PLIST_NAME="com.backbot.nightly"
PLIST_DEST="$HOME/Library/LaunchAgents/$PLIST_NAME.plist"
MENUBAR_NAME="com.backbot.menubar"
MENUBAR_DEST="$HOME/Library/LaunchAgents/$MENUBAR_NAME.plist"
BIN_DIR="$HOME/.local/bin"

echo "=== Backbot Installer (restic) ==="
echo

# ── Download backbot ───────────────────────────────────────────────────
if [[ -d "$INSTALL_DIR/.git" ]]; then
    echo "Updating backbot in $INSTALL_DIR..."
    git -C "$INSTALL_DIR" pull --quiet
else
    echo "Downloading backbot to $INSTALL_DIR..."
    rm -rf "$INSTALL_DIR"
    git clone --quiet "https://github.com/$REPO.git" "$INSTALL_DIR"
fi
echo

# ── Check dependencies ─────────────────────────────────────────────────
echo "Checking dependencies..."
missing=()
for cmd in restic aws terminal-notifier; do
    command -v "$cmd" &>/dev/null || missing+=("$cmd")
done

if [[ ${#missing[@]} -gt 0 ]]; then
    echo "Missing: ${missing[*]}"
    if ! command -v brew &>/dev/null; then
        echo "Homebrew not found. Install it first: https://brew.sh"
        exit 1
    fi
    read -rp "Install via Homebrew? [Y/n] " answer
    if [[ "${answer:-Y}" =~ ^[Yy]?$ ]]; then
        brew_pkgs=()
        for cmd in "${missing[@]}"; do
            case "$cmd" in
                restic)            brew_pkgs+=("restic") ;;
                aws)               brew_pkgs+=("awscli") ;;
                terminal-notifier) brew_pkgs+=("terminal-notifier") ;;
            esac
        done
        brew install "${brew_pkgs[@]}"
    else
        echo "Please install missing dependencies and re-run."
        exit 1
    fi
fi
echo "All dependencies OK."
echo

# ── Create directories ─────────────────────────────────────────────────
mkdir -p "$CONFIG_DIR" "$LOG_DIR" "$BIN_DIR" "$HOME/Library/LaunchAgents"

# ── Exclude list ─────────────────────────────────────────────────────────
cp "$INSTALL_DIR/exclude.list" "$CONFIG_DIR/exclude.list"
echo "Exclude list: $CONFIG_DIR/exclude.list"
echo

# ── Symlink CLI ──────────────────────────────────────────────────────────
chmod +x "$INSTALL_DIR/backbot"
ln -sf "$INSTALL_DIR/backbot" "$BIN_DIR/backbot"
echo "Linked $BIN_DIR/backbot -> $INSTALL_DIR/backbot"

if ! echo "$PATH" | tr ':' '\n' | grep -q "$BIN_DIR"; then
    echo
    echo "NOTE: add $BIN_DIR to your PATH:"
    echo "  echo 'export PATH=\"$BIN_DIR:\$PATH\"' >> ~/.zshrc"
fi
echo

# ── AWS keys + bucket + repo (interactive) ─────────────────────────────
echo "Now let's configure your AWS keys and backup bucket."
"$BIN_DIR/backbot" configure
echo

# ── Install launchd plist ──────────────────────────────────────────────
echo "Installing launchd job (nightly 23:59 + at login)..."
sed "s|/Users/viraat|$HOME|g" "$INSTALL_DIR/com.backbot.nightly.plist" > "$PLIST_DEST"
sed -i '' "s|$HOME/.local/bin/backbot|$BIN_DIR/backbot|g" "$PLIST_DEST"

launchctl bootout "gui/$(id -u)/$PLIST_NAME" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST_DEST"
echo "Launchd job installed."
echo

# ── Menu bar app (optional, needs swiftc / Xcode CLT) ──────────────────
if command -v swiftc &>/dev/null; then
    echo "Building the menu bar app (BackbotBar)..."
    if bash "$INSTALL_DIR/menubar/build.sh" "$INSTALL_DIR"; then
        sed "s|/Users/viraat|$HOME|g" "$INSTALL_DIR/com.backbot.menubar.plist" > "$MENUBAR_DEST"
        # The launchd agent is the ONLY autostart mechanism. Remove any stray
        # "BackbotBar" login item so it can't be launched a second time at login
        # (that double-launch is what spawned two menu bar icons).
        osascript -e 'tell application "System Events" to delete (every login item whose name is "BackbotBar")' 2>/dev/null || true
        launchctl bootout "gui/$(id -u)/$MENUBAR_NAME" 2>/dev/null || true
        launchctl bootstrap "gui/$(id -u)" "$MENUBAR_DEST"
        launchctl kickstart "gui/$(id -u)/$MENUBAR_NAME" 2>/dev/null || true
        echo "Menu bar app installed (starts at every login)."
    else
        echo "Menu bar build failed — skipping (backups still work)."
    fi
else
    echo "swiftc not found — skipping the menu bar app."
    echo "  Install Xcode Command Line Tools (xcode-select --install) and re-run to add it."
fi
echo

# ── Done ─────────────────────────────────────────────────────────────────
echo "=== Installation Complete ==="
echo
read -rp "Run initial backup now? [y/N] " answer
if [[ "${answer:-N}" =~ ^[Yy]$ ]]; then
    "$BIN_DIR/backbot" backup
fi
