#!/bin/bash
# BookLand — re-sign with a fresh 7-day profile and install over the copy on your iPhone.
#
# A free Apple ID gives every app a provisioning profile that is valid for 7 days. Nothing inside
# the app can extend it, so this script does what pressing Run in Xcode does, in one command, and
# can also be run on a schedule (see install-refresh-agent.sh). Installing over the existing app
# keeps your library, highlights and notes.
#
#   tools/refresh-iphone.sh            refresh if the last refresh is older than 4 days
#   tools/refresh-iphone.sh --force    refresh now
#
# Needs: Xcode signed in to your Apple ID, the iPhone paired with this Mac (cable once, then
# "Connect via network" in Xcode > Window > Devices and Simulators), and the iPhone on the same Wi-Fi.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
IOS_DIR="$(cd "$HERE/.." && pwd)"
BUNDLE_ID="local.bookland.ios"
MAX_AGE_DAYS="${MAX_AGE_DAYS:-4}"
STAMP="$HOME/.bookland-last-refresh"
BUILD_DIR="${TMPDIR:-/tmp}/bookland-refresh-build"
FORCE=0
[ "${1:-}" = "--force" ] && FORCE=1

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }

if [ "$FORCE" -eq 0 ] && [ -f "$STAMP" ]; then
  age=$(( ( $(date +%s) - $(stat -f %m "$STAMP") ) / 86400 ))
  if [ "$age" -lt "$MAX_AGE_DAYS" ]; then
    log "Last refresh was $age day(s) ago; nothing to do (use --force to refresh anyway)."
    exit 0
  fi
fi

# Pick the paired physical iPhone.
JSON="$(mktemp)"
xcrun devicectl list devices --json-output "$JSON" >/dev/null 2>&1
UDID="$(python3 - "$JSON" <<'PY'
import json, sys
try:
    devices = json.load(open(sys.argv[1]))["result"]["devices"]
except Exception:
    sys.exit(0)
for d in devices:
    hw, conn = d.get("hardwareProperties", {}), d.get("connectionProperties", {})
    if hw.get("reality") == "physical" and hw.get("platform") == "iOS" and conn.get("pairingState") == "paired":
        print(hw.get("udid", "")); break
PY
)"
rm -f "$JSON"
if [ -z "$UDID" ]; then
  log "No paired iPhone found. Connect it once with a cable and trust this Mac."
  exit 1
fi

# Drop the cached profile for this app so Xcode must fetch a new 7-day one.
for dir in "$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles" "$HOME/Library/MobileDevice/Provisioning Profiles"; do
  [ -d "$dir" ] || continue
  for f in "$dir"/*.mobileprovision; do
    [ -e "$f" ] || continue
    if security cms -D -i "$f" 2>/dev/null | grep -q "$BUNDLE_ID"; then rm -f "$f"; fi
  done
done

log "Building BookLand (Release, signed with your development team)…"
if ! xcodebuild -project "$IOS_DIR/BookLand-iOS.xcodeproj" -scheme BookLand-iOS -configuration Release \
      -destination 'generic/platform=iOS' -derivedDataPath "$BUILD_DIR" -allowProvisioningUpdates build >"$BUILD_DIR.log" 2>&1; then
  log "Build failed. Last lines of $BUILD_DIR.log:"; tail -15 "$BUILD_DIR.log"
  exit 1
fi
APP="$BUILD_DIR/Build/Products/Release-iphoneos/BookLand.app"
EXPIRY="$(security cms -D -i "$APP/embedded.mobileprovision" 2>/dev/null | plutil -extract ExpirationDate raw - 2>/dev/null || echo unknown)"

log "Installing over the existing app on the iPhone ($UDID)…"
if ! xcrun devicectl device install app --device "$UDID" "$APP" >"$BUILD_DIR.install.log" 2>&1; then
  log "Install failed (is the iPhone unlocked, on the same Wi-Fi, and awake?):"; tail -8 "$BUILD_DIR.install.log"
  exit 1
fi

touch "$STAMP"
log "Done. BookLand now opens until $EXPIRY."
