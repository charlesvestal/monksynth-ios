#!/usr/bin/env bash
#
# Build signed for a connected device, install, and launch.
#
# Device builds use their own derived-data dir so the simulator cache's
# CODE_SIGNING_ALLOWED=NO can never leak in and produce an unsigned,
# uninstallable app — a trap that has bitten the sibling projects.
#
# Usage:
#   scripts/run_device.sh              # first connected device
#   UDID=<udid> scripts/run_device.sh  # a specific one
set -euo pipefail
cd "$(dirname "$0")/.."

[ -f scripts/.deploy.local ] && source scripts/.deploy.local

DEVELOPMENT_TEAM="${DEVELOPMENT_TEAM:-J4722B5MJW}"
DERIVED=build-device
BUNDLE_ID=com.vestal.monksynth

xcodegen generate

if [ -z "${UDID:-}" ]; then
  UDID=$(xcrun devicectl list devices --quiet --json-output /dev/stdout 2>/dev/null \
    | python3 -c 'import json,sys
d = json.load(sys.stdin)["result"]["devices"]
conn = [x for x in d if x.get("connectionProperties", {}).get("tunnelState") != "unavailable"]
if not conn:
    sys.exit("no connected device found — plug one in and trust this Mac")
print(conn[0]["hardwareProperties"]["udid"])')
fi
echo "==> device $UDID"

xcodebuild build \
  -project MonkSynth.xcodeproj \
  -scheme MonkSynth \
  -sdk iphoneos \
  -configuration Release \
  -derivedDataPath "$DERIVED" \
  -allowProvisioningUpdates \
  DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM" \
  CODE_SIGN_STYLE=Automatic

APP="$DERIVED/Build/Products/Release-iphoneos/MonkSynth.app"
xcrun devicectl device install app --device "$UDID" "$APP"
xcrun devicectl device process launch --device "$UDID" "$BUNDLE_ID"
echo "launched $BUNDLE_ID"
