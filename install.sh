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
# The shipped list uses __HOME__ for the few patterns that must anchor at the
# top of $HOME; expand it here so the installed copy has real paths. An
# existing list is backed up rather than silently clobbered — a stale copy in
# the repo must never be able to drop a user's exclusions on reinstall.
excl_tmp="$(mktemp)"
sed "s|__HOME__|$HOME|g" "$INSTALL_DIR/exclude.list" > "$excl_tmp"
if [[ -f "$CONFIG_DIR/exclude.list" ]] && ! cmp -s "$excl_tmp" "$CONFIG_DIR/exclude.list"; then
    excl_bak="$CONFIG_DIR/exclude.list.bak-$(date +%Y%m%d-%H%M%S)"
    cp "$CONFIG_DIR/exclude.list" "$excl_bak"
    echo "Existing exclude list differs — backed up to $excl_bak"
fi
mv "$excl_tmp" "$CONFIG_DIR/exclude.list"
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

    # Retire the old launchd agent first. BackbotBar now registers itself as a
    # real Login Item (SMAppService) and appears in System Settings > General >
    # Login Items & Extensions under its own name and icon; leaving both
    # autostart mechanisms in place is what used to launch it twice and spawn
    # two menu bar icons.
    launchctl bootout "gui/$(id -u)/$MENUBAR_NAME" 2>/dev/null || true
    rm -f "$MENUBAR_DEST"
    osascript -e 'tell application "System Events" to delete (every login item whose name is "BackbotBar")' 2>/dev/null || true

    # Stop the running copy before the build replaces its bundle, and wait for
    # it to actually exit — the new instance exits on its own if it sees a
    # duplicate still running, which would leave no icon at all.
    pkill -f "BackbotBar.app/Contents/MacOS/BackbotBar" 2>/dev/null || true
    for _ in 1 2 3 4 5 6 7 8 9 10; do
        pgrep -f "BackbotBar.app/Contents/MacOS/BackbotBar" >/dev/null || break
        sleep 0.5
    done

    if bash "$INSTALL_DIR/menubar/build.sh" "$INSTALL_DIR"; then
        open -a "$INSTALL_DIR/BackbotBar.app"
        echo "Menu bar app installed (opens at login as a Login Item)."
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
