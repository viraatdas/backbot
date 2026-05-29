#!/usr/bin/env bash
set -euo pipefail

# ── Constants ──────────────────────────────────────────────────────────
REPO="viraatdas/backbot"
INSTALL_DIR="$HOME/.backbot"
CONFIG_DIR="$HOME/.config/backbot"
LOG_DIR="$HOME/.local/share/backbot/logs"
PLIST_NAME="com.backbot.nightly"
PLIST_DEST="$HOME/Library/LaunchAgents/$PLIST_NAME.plist"
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

# ── Done ─────────────────────────────────────────────────────────────────
echo "=== Installation Complete ==="
echo
read -rp "Run initial backup now? [y/N] " answer
if [[ "${answer:-N}" =~ ^[Yy]$ ]]; then
    "$BIN_DIR/backbot" backup
fi
