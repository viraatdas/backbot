#!/bin/bash
# backbot menu bar plugin for SwiftBar (https://swiftbar.app)
# Filename interval ".5m." = refresh every 5 minutes.
#
# <xbar.title>backbot</xbar.title>
# <xbar.version>v1.0</xbar.version>
# <xbar.author>Viraat Das</xbar.author>
# <xbar.desc>Status of nightly Mac backups to S3 Glacier (restic).</xbar.desc>
# <xbar.dependencies>backbot</xbar.dependencies>
# <swiftbar.hideAbout>true</swiftbar.hideAbout>
# <swiftbar.hideRunInTerminal>true</swiftbar.hideRunInTerminal>
# <swiftbar.hideLastUpdated>false</swiftbar.hideLastUpdated>
# <swiftbar.hideDisablePlugin>true</swiftbar.hideDisablePlugin>

export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"

BACKBOT="$HOME/.local/bin/backbot"
LOG_DIR="$HOME/.local/share/backbot/logs"

# ── Detect state from the latest log + running process ──────────────────
running=false
pgrep -f "restic backup" >/dev/null 2>&1 && running=true

latest="$(ls -t "$LOG_DIR"/backup-*.log 2>/dev/null | head -1)"
status="none"; when=""; snap=""
if [[ -n "$latest" ]]; then
    when="$(stat -f '%Sm' -t '%b %-d, %-I:%M %p' "$latest" 2>/dev/null)"
    snap="$(grep -oE 'snapshot [a-f0-9]+ saved' "$latest" 2>/dev/null | tail -1 | awk '{print $2}')"
    if grep -q "FAILED" "$latest" 2>/dev/null; then
        status="failed"
    elif grep -q "Warning: at least one source file could not be read" "$latest" 2>/dev/null; then
        status="warnings"
    elif [[ -n "$snap" ]]; then
        status="ok"
    else
        status="partial"
    fi
fi

# ── Menu bar icon (inline SF Symbol = the menu bar title) ───────────────
# Icon-only title uses the :symbolname: inline syntax. State shown via color.
if $running; then
    echo ":arrow.triangle.2.circlepath: | sfcolor=#3b82f6 color=#3b82f6 sfsize=15"
elif [[ "$status" == "failed" ]]; then
    echo ":externaldrive.fill.badge.xmark: | sfcolor=#ef4444 color=#ef4444 sfsize=15"
elif [[ "$status" == "ok" || "$status" == "warnings" ]]; then
    echo ":externaldrive.fill.badge.checkmark: | sfcolor=#22c55e color=#22c55e sfsize=15"
else
    echo ":externaldrive.fill: | sfsize=15"
fi

echo "---"

# ── Status line ─────────────────────────────────────────────────────────
echo "backbot — nightly Mac backup | size=13"
if $running; then
    echo "Backing up now… | color=#3b82f6 sfimage=arrow.triangle.2.circlepath"
fi
case "$status" in
    ok)       echo "Last backup: $when ✓ | sfimage=checkmark.circle.fill sfcolor=#22c55e" ;;
    warnings) echo "Last backup: $when ✓ | sfimage=checkmark.circle.fill sfcolor=#22c55e"
              echo "(some files unreadable — normal for open/iCloud files) | size=11 color=#8a8a8a" ;;
    failed)   echo "Last backup FAILED: $when | sfimage=exclamationmark.triangle.fill sfcolor=#ef4444" ;;
    partial)  echo "Last run incomplete: $when | sfimage=questionmark.circle" ;;
    none)     echo "No backups yet | sfimage=questionmark.circle color=#8a8a8a" ;;
esac
[[ -n "$snap" ]] && echo "Snapshot $snap | size=11 color=#8a8a8a font=Menlo"

echo "---"

# ── Actions ─────────────────────────────────────────────────────────────
echo "Back up now | bash=\"$BACKBOT\" param1=backup terminal=true refresh=true sfimage=icloud.and.arrow.up"
echo "Show status | bash=\"$BACKBOT\" param1=status terminal=true sfimage=info.circle"
if [[ -n "$latest" ]]; then
    echo "Open latest log | bash=/usr/bin/open param1=\"$latest\" terminal=false sfimage=doc.text"
fi
echo "Open logs folder | bash=/usr/bin/open param1=\"$LOG_DIR\" terminal=false sfimage=folder"

echo "---"
echo "Refresh | refresh=true sfimage=arrow.clockwise"
echo "backbot.viraat.dev | href=https://backbot.viraat.dev sfimage=safari"
echo "GitHub | href=https://github.com/viraatdas/backbot sfimage=chevron.left.forwardslash.chevron.right"
