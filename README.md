# backbot

Nightly Mac backup to S3 Glacier Deep Archive. ~$8/year for 500GB.

Uses `duplicity` for incremental, encrypted, tar-based backups — fewer S3 PUTs, local signature cache (never reads from Glacier), GPG encryption built in.

## Quick Start

```bash
# Install dependencies + configure
./install.sh

# Run first full backup
backbot backup --full

# Check status
backbot status
```

## CLI Reference

### `backbot backup`

Run an incremental backup. Only uploads changes since the last backup. Automatically does a full backup if none exists or if the last full is older than 1 month.

```bash
backbot backup          # incremental (fast, daily use)
backbot backup --full   # force a full backup
```

On success, sends a macOS notification and cleans up old backup sets. Logs are saved to `~/.local/share/backbot/logs/`.

### `backbot list`

Show all available backup snapshots (full and incremental chains) stored in S3.

```bash
backbot list
```

### `backbot status`

Quick health check — shows last backup time, log tail, duplicity cache size, and whether the nightly schedule is active.

```bash
backbot status
```

### `backbot restore`

Restore files from backup. Since Glacier Deep Archive requires a thaw period, this is a two-step process:

```bash
# Step 1: Initiate Glacier thaw (Bulk tier: 12-48 hours)
backbot restore Documents/important.txt

# Step 2: After thaw completes, download and decrypt
backbot restore --continue
```

Options:

```bash
# Restore from a specific point in time
backbot restore Documents/ --time 2025-06-15

# Restore to a custom directory (default: /tmp/backbot-restore)
backbot restore Documents/ --dest ~/Desktop/restored

# Use Standard thaw tier (3-5 hours instead of 12-48, costs more)
backbot restore Documents/ --expedite
```

### `backbot install`

Run first-time setup: installs Homebrew dependencies, creates config, generates encryption passphrase, stores it in macOS Keychain, sets up the nightly launchd job.

```bash
backbot install
```

### `backbot uninstall`

Remove the launchd job and optionally clean up config, logs, and Keychain entry. Does NOT delete your S3 backup data.

```bash
backbot uninstall
```

### `backbot help`

Show available commands.

### `backbot version`

Print version number.

## Schedule

Runs nightly at 23:59 via launchd. If your Mac is asleep at that time, launchd runs the job on wake.

```bash
# Check if scheduled
launchctl list | grep backbot

# Manually load/unload
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.backbot.nightly.plist
launchctl bootout gui/$(id -u)/com.backbot.nightly
```

## File Layout

```
~/.config/backbot/backbot.conf    # Configuration
~/.config/backbot/exclude.list    # Exclusion patterns
~/.local/share/backbot/logs/      # Backup logs
~/.cache/duplicity/               # Duplicity signature cache (DO NOT DELETE)
```

## Cost Breakdown

| Item | Annual Cost |
|------|-------------|
| Storage (500GB Deep Archive @ $0.00099/GB/mo) | ~$6 |
| PUT requests (monthly full + daily incrementals) | ~$1-2 |
| **Total** | **~$7-8/year** |
| Restore (Bulk tier, if needed) | ~$46 per full restore |

## Configuration

Edit `~/.config/backbot/backbot.conf`:

| Variable | Default | Description |
|----------|---------|-------------|
| `S3_BUCKET` | — | Your S3 bucket name |
| `S3_REGION` | `us-west-1` | AWS region |
| `FULL_IF_OLDER_THAN` | `1M` | Force full backup interval |
| `REMOVE_OLDER_THAN` | `12M` | Delete full backups older than this |
| `VOLSIZE` | `250` | Tar volume size in MB |
| `GPG_MODE` | `keychain` | `keychain` or `env` |
| `NOTIFY` | `terminal-notifier` | `terminal-notifier` or `none` |
| `LOG_RETENTION_DAYS` | `90` | Auto-delete logs older than this |

## Troubleshooting

**"Could not retrieve passphrase from Keychain"**
Re-run `./install.sh` or manually add:
```bash
security add-generic-password -s backbot-gpg -a backbot -w "YOUR_PASSPHRASE"
```

**Backup fails with boto3 error**
Homebrew's duplicity bundles boto3. If using a different install: `pip3 install boto3`

**Launchd not running**
```bash
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.backbot.nightly.plist
```

**Check logs**
```bash
ls -lt ~/.local/share/backbot/logs/
tail -50 ~/.local/share/backbot/logs/backup-*.log
```

## What Gets Backed Up

Your entire home directory, minus caches and build artifacts. Key exclusions:

- `node_modules`, `.git`, `__pycache__`, `build/`, `dist/`
- `~/Library/Caches`, `~/Library/Logs`, `~/Library/Developer`
- `.cache`, `.npm`, `.yarn/cache`, `.cargo/registry`
- Docker data, Steam games, browser caches
- Virtual machines (`.vmdk`, `.vdi`, `.qcow2`)

Your macOS preferences (keyboard shortcuts, app settings, etc.) in `~/Library/Preferences/` **are** included.

Edit exclusions: `~/.config/backbot/exclude.list`

## Why duplicity over restic/kopia?

restic and kopia store metadata as individual objects that need frequent reads. With Glacier Deep Archive, reading metadata requires a 12-48hr thaw cycle, making these tools unusable. duplicity stores everything as tar archives with a local signature cache — it never needs to read back from S3 during normal backups.
