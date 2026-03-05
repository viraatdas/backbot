#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_DIR="$HOME/.config/backbot"
LOG_DIR="$HOME/.local/share/backbot/logs"
PLIST_NAME="com.backbot.nightly"
PLIST_SRC="$SCRIPT_DIR/com.backbot.nightly.plist"
PLIST_DEST="$HOME/Library/LaunchAgents/$PLIST_NAME.plist"
SYMLINK_DEST="/usr/local/bin/backbot"

echo "=== Backbot Installer ==="
echo

# ── Check dependencies ─────────────────────────────────────────────────
echo "Checking dependencies..."

missing=()
for cmd in duplicity gpg aws terminal-notifier python3; do
    if ! command -v "$cmd" &>/dev/null; then
        missing+=("$cmd")
    fi
done

if [[ ${#missing[@]} -gt 0 ]]; then
    echo "Missing: ${missing[*]}"
    echo
    read -rp "Install via Homebrew? [Y/n] " answer
    if [[ "${answer:-Y}" =~ ^[Yy]?$ ]]; then
        brew_pkgs=()
        for cmd in "${missing[@]}"; do
            case "$cmd" in
                duplicity) brew_pkgs+=("duplicity") ;;
                gpg) brew_pkgs+=("gnupg") ;;
                aws) brew_pkgs+=("awscli") ;;
                terminal-notifier) brew_pkgs+=("terminal-notifier") ;;
                python3) brew_pkgs+=("python3") ;;
            esac
        done
        brew install "${brew_pkgs[@]}"
    else
        echo "Please install missing dependencies and re-run."
        exit 1
    fi
fi

# Check boto3
if ! python3 -c "import boto3" 2>/dev/null; then
    echo "Python boto3 not found (required by duplicity for S3)."
    read -rp "Install boto3 via pip? [Y/n] " answer
    if [[ "${answer:-Y}" =~ ^[Yy]?$ ]]; then
        pip3 install boto3
    else
        echo "Please install boto3 and re-run."
        exit 1
    fi
fi

echo "All dependencies OK."
echo

# ── Create directories ─────────────────────────────────────────────────
echo "Creating directories..."
mkdir -p "$CONFIG_DIR"
mkdir -p "$LOG_DIR"
echo "  $CONFIG_DIR"
echo "  $LOG_DIR"
echo

# ── Copy config and exclude list ───────────────────────────────────────
if [[ ! -f "$CONFIG_DIR/backbot.conf" ]]; then
    cp "$SCRIPT_DIR/backbot.conf.example" "$CONFIG_DIR/backbot.conf"
    echo "Config created: $CONFIG_DIR/backbot.conf"
else
    echo "Config already exists: $CONFIG_DIR/backbot.conf (keeping)"
fi

cp "$SCRIPT_DIR/exclude.list" "$CONFIG_DIR/exclude.list"
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

# Write bucket to config
sed -i '' "s|^S3_BUCKET=.*|S3_BUCKET=\"$bucket_name\"|" "$CONFIG_DIR/backbot.conf"
echo

# ── GPG passphrase ─────────────────────────────────────────────────────
echo "Generating GPG passphrase for backup encryption..."
PASSPHRASE="$(LC_ALL=C tr -dc 'A-Za-z0-9!@#$%^&*()_+-=' < /dev/urandom | head -c 64)"

security add-generic-password \
    -s "backbot-gpg" \
    -a "backbot" \
    -w "$PASSPHRASE" \
    -U \
    -T "" 2>/dev/null || true

# Verify it's stored
if security find-generic-password -s "backbot-gpg" -a "backbot" -w &>/dev/null; then
    echo "Passphrase stored in macOS Keychain (service: backbot-gpg)"
else
    echo "WARNING: Failed to store passphrase in Keychain."
    echo "You may need to set GPG_MODE=env and export PASSPHRASE manually."
fi
echo

# ── Install launchd plist ──────────────────────────────────────────────
echo "Installing launchd job..."

# Update plist with correct user home
sed "s|/Users/viraat|$HOME|g" "$PLIST_SRC" > "$PLIST_DEST"

# Unload first if already loaded
launchctl bootout "gui/$(id -u)/$PLIST_NAME" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST_DEST"

echo "Launchd job installed: $PLIST_DEST"
echo "Scheduled: daily at 23:59"
echo

# ── Symlink CLI ────────────────────────────────────────────────────────
echo "Creating symlink..."
if [[ -L "$SYMLINK_DEST" || -f "$SYMLINK_DEST" ]]; then
    rm -f "$SYMLINK_DEST"
fi
chmod +x "$SCRIPT_DIR/backbot"
ln -s "$SCRIPT_DIR/backbot" "$SYMLINK_DEST"
echo "  $SYMLINK_DEST -> $SCRIPT_DIR/backbot"
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
    "$SCRIPT_DIR/backbot" backup --full
fi
