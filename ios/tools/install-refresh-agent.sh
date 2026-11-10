#!/bin/bash
# Optional: run refresh-iphone.sh automatically in the background (every 6 hours while you are
# logged in). It only rebuilds when the last refresh is 4+ days old, so most runs do nothing.
# Needs this folder to stay on the Mac. Remove with:  tools/install-refresh-agent.sh --remove
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
LABEL="com.bookland.refresh"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"

if [ "${1:-}" = "--remove" ]; then
  launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
  rm -f "$PLIST"
  echo "Removed the automatic refresh."
  exit 0
fi

mkdir -p "$HOME/Library/LaunchAgents"
cat > "$PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key><array><string>/bin/bash</string><string>$HERE/refresh-iphone.sh</string></array>
  <key>StartInterval</key><integer>21600</integer>
  <key>RunAtLoad</key><true/>
  <key>StandardOutPath</key><string>$HOME/Library/Logs/bookland-refresh.log</string>
  <key>StandardErrorPath</key><string>$HOME/Library/Logs/bookland-refresh.log</string>
</dict>
</plist>
PLIST
launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST"
echo "Installed. Log: ~/Library/Logs/bookland-refresh.log"
