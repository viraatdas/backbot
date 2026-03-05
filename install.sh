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

echo "=== Backbot Installer ==="
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

# ── Check dependencies ────────────────────────────────────────────────
echo "Checking dependencies..."

missing=()
for cmd in duplicity gpg aws terminal-notifier; do
    if ! command -v "$cmd" &>/dev/null; then
        missing+=("$cmd")
    fi
done

if [[ ${#missing[@]} -gt 0 ]]; then
    echo "Missing: ${missing[*]}"
    echo

    if ! command -v brew &>/dev/null; then
        echo "Homebrew not found. Install it first: https://brew.sh"
        exit 1
    fi

    read -rp "Install via Homebrew? [Y/n] " answer
    if [[ "${answer:-Y}" =~ ^[Yy]?$ ]]; then
        brew_pkgs=()
        for cmd in "${missing[@]}"; do
            case "$cmd" in
                duplicity) brew_pkgs+=("duplicity") ;;
                gpg) brew_pkgs+=("gnupg") ;;
                aws) brew_pkgs+=("awscli") ;;
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

# ── Create directories ────────────────────────────────────────────────
echo "Creating directories..."
mkdir -p "$CONFIG_DIR" "$LOG_DIR" "$BIN_DIR" "$HOME/Library/LaunchAgents"
echo "  $CONFIG_DIR"
echo "  $LOG_DIR"
echo

# ── Copy config and exclude list ──────────────────────────────────────
if [[ ! -f "$CONFIG_DIR/backbot.conf" ]]; then
    cp "$INSTALL_DIR/backbot.conf.example" "$CONFIG_DIR/backbot.conf"
    echo "Config created: $CONFIG_DIR/backbot.conf"
else
    echo "Config already exists: $CONFIG_DIR/backbot.conf (keeping)"
fi

cp "$INSTALL_DIR/exclude.list" "$CONFIG_DIR/exclude.list"
echo "Exclude list: $CONFIG_DIR/exclude.list"
echo

# ── S3 bucket setup ───────────────────────────────────────────────────
read -rp "S3 bucket name: " bucket_name
if [[ -z "$bucket_name" ]]; then
    echo "Bucket name required."
    exit 1
fi

echo "Verifying bucket access..."
if aws s3 ls "s3://$bucket_name" &>/dev/null; then
    echo "Bucket accessible: s3://$bucket_name"
else
    echo "WARNING: Could not access s3://$bucket_name"
    echo "Make sure the bucket exists and your AWS credentials are configured."
    read -rp "Continue anyway? [y/N] " answer
    if [[ ! "${answer:-N}" =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

sed -i '' "s|^S3_BUCKET=.*|S3_BUCKET=\"$bucket_name\"|" "$CONFIG_DIR/backbot.conf"
echo

# ── GPG passphrase ────────────────────────────────────────────────────
if security find-generic-password -s "backbot-gpg" -a "backbot" -w &>/dev/null; then
    echo "GPG passphrase already in Keychain (keeping)"
else
    echo "Generating GPG passphrase for backup encryption..."
    PASSPHRASE="$(LC_ALL=C tr -dc 'A-Za-z0-9!@#$%^&*()_+-=' < /dev/urandom | head -c 64)"
    security add-generic-password \
        -s "backbot-gpg" \
        -a "backbot" \
        -w "$PASSPHRASE" \
        -U \
        -T "" 2>/dev/null || true

    if security find-generic-password -s "backbot-gpg" -a "backbot" -w &>/dev/null; then
        echo "Passphrase stored in macOS Keychain (service: backbot-gpg)"
    else
        echo "WARNING: Failed to store passphrase in Keychain."
        echo "You may need to set GPG_MODE=env and export PASSPHRASE manually."
    fi
fi
echo

# ── Install launchd plist ─────────────────────────────────────────────
echo "Installing launchd job..."

sed "s|/Users/viraat|$HOME|g" "$INSTALL_DIR/com.backbot.nightly.plist" > "$PLIST_DEST"

# Also update the binary path in the plist to point to our install
sed -i '' "s|$HOME/.local/bin/backbot|$BIN_DIR/backbot|g" "$PLIST_DEST"

launchctl bootout "gui/$(id -u)/$PLIST_NAME" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST_DEST"

echo "Launchd job installed: daily at 23:59"
echo

# ── Symlink CLI ────────────────────────────────────────────────────────
echo "Creating symlink..."
chmod +x "$INSTALL_DIR/backbot"
ln -sf "$INSTALL_DIR/backbot" "$BIN_DIR/backbot"
echo "  $BIN_DIR/backbot -> $INSTALL_DIR/backbot"

# Check if BIN_DIR is in PATH
if ! echo "$PATH" | tr ':' '\n' | grep -q "$BIN_DIR"; then
    echo
    echo "NOTE: Add $BIN_DIR to your PATH:"
    echo "  echo 'export PATH=\"$BIN_DIR:\$PATH\"' >> ~/.zshrc"
fi
echo

# ── Done ───────────────────────────────────────────────────────────────
echo "=== Installation Complete ==="
echo
echo "Next steps:"
echo "  1. Review config: $CONFIG_DIR/backbot.conf"
echo "  2. Review exclusions: $CONFIG_DIR/exclude.list"
echo "  3. Run initial backup: backbot backup --full"
echo

read -rp "Run initial full backup now? [y/N] " answer
if [[ "${answer:-N}" =~ ^[Yy]$ ]]; then
    "$BIN_DIR/backbot" backup --full
fi
