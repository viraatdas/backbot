# backbot

Nightly Mac backup to Amazon S3 Glacier, powered by [restic](https://restic.net). End-to-end encrypted, deduplicated, incremental. ~$8/year for 500 GB.

Defaults to the **Glacier Instant Retrieval** storage class — cheap *and* restorable in seconds (no thaw wait), which keeps restic's metadata reads fast.

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/viraatdas/backbot/main/install.sh | bash
```

This will:

- Clone backbot to `~/.backbot/` and symlink `backbot` into `~/.local/bin/`
- Install dependencies via Homebrew (`restic`, `awscli`, `terminal-notifier`)
- Run `backbot configure` — set your AWS keys, S3 bucket, repo password, and init the repo
- Install the nightly launchd job (11:59 PM **and at every login**)

Then run your first backup:

```bash
backbot backup
```

To uninstall:

```bash
backbot uninstall
```

## Configure your AWS keys

backbot uses **your own** AWS account and bucket. `backbot configure` walks you through it:

```bash
backbot configure
```

It will:

1. Prompt for your **AWS Access Key ID / Secret Access Key / region** and save them to a dedicated `backbot` AWS CLI profile (`~/.aws/credentials`) — never inside this repo or the backup.
2. Ask for your **S3 bucket** and offer to create it if it doesn't exist.
3. Generate a **restic repository password** and store it in the macOS Keychain.
4. Run `restic init` to set up the encrypted repository.

Re-run it anytime to rotate keys or point at a different bucket — it only changes what you confirm.

Prefer to manage credentials yourself? Any standard AWS credential source works (`aws configure`, env vars, SSO, instance roles). Just set `AWS_PROFILE` (or leave it for the default profile) and `RESTIC_REPOSITORY` in `~/.config/backbot/restic.conf`.

> **Minimal IAM permissions** for the backup user: `s3:ListBucket`, `s3:GetObject`, `s3:PutObject`, `s3:DeleteObject` on the bucket (plus `s3:CreateBucket` if you want backbot to create it).

## CLI Reference

| Command | What it does |
|---------|--------------|
| `backbot configure` | Set up AWS keys, bucket, repo password, and init the repo |
| `backbot backup` | Incremental backup, then apply retention (forget; prune on Sundays) |
| `backbot snapshots` | List snapshots |
| `backbot ls <snap-id> [path]` | List files inside a snapshot |
| `backbot restore <snap-id> --target <dir> [--include <path>]` | Restore files |
| `backbot mount <dir>` | FUSE-mount the repo and browse it like a folder |
| `backbot diff <a> <b>` | Diff two snapshots |
| `backbot check` | Verify repository integrity |
| `backbot forget` / `prune` | Manual retention / space reclaim |
| `backbot stats` | Repository size stats |
| `backbot status` | Config, latest snapshot, launchd state, recent logs |
| `backbot uninstall` | Remove the launchd job and wrapper |
| `backbot version` | Show version |

Pass-through subcommands (`snapshots`, `ls`, `restore`, `mount`, `diff`, `check`, `forget`, `prune`, `stats`) forward their arguments straight to `restic`.

### Restore example

Because Glacier IR is instantly retrievable, restores are immediate:

```bash
backbot snapshots                                  # find the snapshot id
backbot restore <snap-id> --target ~/restored \
    --include /Users/you/Documents/important.txt
```

## Schedule

Runs nightly at **23:59** and **at every login** via launchd. If your Mac is asleep at 23:59, launchd runs the job on wake.

```bash
launchctl list | grep backbot      # is it loaded?

# manually load / unload
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.backbot.nightly.plist
launchctl bootout   gui/$(id -u)/com.backbot.nightly
```

## File Layout

```
~/.config/backbot/restic.conf     # configuration (written by `backbot configure`)
~/.config/backbot/exclude.list    # exclusion patterns
~/.local/share/backbot/logs/      # backup logs
~/.aws/credentials                # AWS keys (profile: backbot)
macOS Keychain                    # restic repo password (service: backbot-restic)
```

## Configuration

`~/.config/backbot/restic.conf`:

| Variable | Default | Description |
|----------|---------|-------------|
| `RESTIC_REPOSITORY` | — | `s3:s3.<region>.amazonaws.com/<bucket>` |
| `AWS_PROFILE` | `backbot` | AWS CLI profile holding your keys |
| `BACKUP_SOURCE` | `$HOME` | Directory to back up |
| `STORAGE_CLASS` | `GLACIER_IR` | `GLACIER_IR` (instant) or `DEEP_ARCHIVE` (cheapest, 12–48h thaw) |
| `KEEP_LAST` / `KEEP_DAILY` / `KEEP_WEEKLY` / `KEEP_MONTHLY` | `3 / 7 / 4 / 12` | Retention policy |
| `PRUNE_DAY` | `7` | Day (1–7) to run the heavier `forget --prune` |
| `NOTIFY` | `terminal-notifier` | `terminal-notifier` or `none` |
| `LOG_RETENTION_DAYS` | `90` | Auto-delete local logs older than this |

## Cost Breakdown (500 GB)

| Item | Annual Cost |
|------|-------------|
| Storage (Glacier IR @ ~$0.004/GB/mo) | ~$24 |
| Storage (Deep Archive @ ~$0.00099/GB/mo) | ~$6 |
| PUT/API requests | ~$1–2 |

Glacier IR costs a bit more than Deep Archive but restores instantly. Set `STORAGE_CLASS="DEEP_ARCHIVE"` for the cheapest possible storage if you can tolerate a 12–48h thaw on restore.

## Encryption & recovery

restic encrypts everything client-side. The repository password lives in your macOS Keychain (`backbot-restic`). **Without it your backup cannot be decrypted — not even by you.** Save a copy somewhere safe:

```bash
security find-generic-password -s backbot-restic -a backbot -w
```

## Troubleshooting

**Check logs**
```bash
ls -lt ~/.local/share/backbot/logs/
tail -50 ~/.local/share/backbot/logs/backup-*.log
```

**`Operation not permitted` while reading files**
macOS Full Disk Access. Grant it to whatever runs backbot (Terminal, or the launchd context):
System Settings → Privacy & Security → Full Disk Access.

**Launchd not running**
```bash
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.backbot.nightly.plist
```

## What Gets Backed Up

Your entire home directory, minus caches and build artifacts (`node_modules`, `.git`, `__pycache__`, `build/`, `dist/`, `~/Library/Caches`, Docker data, VM images, etc.). Edit `~/.config/backbot/exclude.list` to adjust.

`--exclude-caches` also skips any directory tagged with a `CACHEDIR.TAG` file.

## Why restic + Glacier Instant Retrieval?

restic gives you deduplication, client-side encryption, and snapshot browsing/mounting out of the box. Glacier IR keeps storage cheap while staying instantly restorable — so restic's periodic metadata reads (and your restores) never hit a multi-hour thaw, unlike Deep Archive.
