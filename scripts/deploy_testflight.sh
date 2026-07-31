#!/usr/bin/env bash
#
# Archive the MonkSynth host app (which embeds the MonkSynthAU AUv3) and upload
# it to TestFlight. Adapted from qwerty-keys/scripts/deploy_testflight.sh.
#
# Prereqs (one-time):
#   * App IDs com.vestal.monksynth AND com.vestal.monksynth.AU registered.
#     `-allowProvisioningUpdates` below creates them automatically on the first
#     archive, so normally you do not have to do this by hand.
#   * An App Store Connect app record for com.vestal.monksynth. This CANNOT be
#     created by the build — make it at appstoreconnect.apple.com first, or the
#     export step fails with "No suitable application records were found".
#   * An ADMIN-role ASC API key at ~/.appstoreconnect/private_keys/AuthKey_<ID>.p8.
#     An App Manager key fails with "Cloud signing permission error /
#     No signing certificate iOS Distribution".
#
# Config comes from scripts/.deploy.local (gitignored).
#
# Usage:
#   scripts/deploy_testflight.sh            # archive, export and upload
#   scripts/deploy_testflight.sh --archive-only
#       Stop after archiving. Useful for the very first run: archiving registers
#       the Bundle IDs, after which you can create the App Store Connect record
#       and re-run without the flag.
set -euo pipefail
cd "$(dirname "$0")/.."

[ -f scripts/.deploy.local ] && source scripts/.deploy.local

ARCHIVE_ONLY=0
[ "${1:-}" = "--archive-only" ] && ARCHIVE_ONLY=1

SCHEME="${SCHEME:-MonkSynth}"
ARCHIVE="${ARCHIVE:-/tmp/MonkSynth.xcarchive}"
EXPORT_DIR="${EXPORT_DIR:-/tmp/MonkSynth_export}"
DEVELOPMENT_TEAM="${DEVELOPMENT_TEAM:-J4722B5MJW}"
ASC_KEY_ID="${ASC_KEY_ID:?set ASC_KEY_ID in scripts/.deploy.local}"
ASC_ISSUER_ID="${ASC_ISSUER_ID:?set ASC_ISSUER_ID in scripts/.deploy.local}"
ASC_KEY_PATH="${ASC_KEY_PATH:-$HOME/.appstoreconnect/private_keys/AuthKey_${ASC_KEY_ID}.p8}"
# Build number from the commit count, so every upload is unique without anyone
# having to remember to bump MARKETING_VERSION.
BUILD_NUMBER="${BUILD_NUMBER:-$(git rev-list --count HEAD)}"

[ -f "$ASC_KEY_PATH" ] || { echo "error: ASC key not found at $ASC_KEY_PATH" >&2; exit 1; }

# A Homebrew rsync shadows /usr/bin/rsync and breaks IPA packaging with
# "Copy failed" — force the system one to the front of PATH.
export PATH="/usr/bin:$PATH"

AUTH=(-allowProvisioningUpdates
      -authenticationKeyPath "$ASC_KEY_PATH"
      -authenticationKeyID "$ASC_KEY_ID"
      -authenticationKeyIssuerID "$ASC_ISSUER_ID")

echo "==> [1/3] Generating project"
xcodegen generate

echo "==> [2/3] Archiving $SCHEME (build $BUILD_NUMBER)"
rm -rf "$ARCHIVE" "$EXPORT_DIR"
xcodebuild archive \
  -project MonkSynth.xcodeproj \
  -scheme "$SCHEME" \
  -sdk iphoneos \
  -configuration Release \
  -archivePath "$ARCHIVE" \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
  DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM" \
  DEBUG_INFORMATION_FORMAT=dwarf-with-dsym \
  "${AUTH[@]}"

if [ "$ARCHIVE_ONLY" = "1" ]; then
  echo "==> archived only, at $ARCHIVE (build $BUILD_NUMBER)"
  echo "    Bundle IDs are now registered. Create the App Store Connect record"
  echo "    for com.vestal.monksynth, then re-run without --archive-only."
  exit 0
fi

echo "==> [3/3] Exporting and uploading"
cat > /tmp/monksynth_export.plist <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key><string>app-store-connect</string>
    <key>teamID</key><string>$DEVELOPMENT_TEAM</string>
    <key>uploadSymbols</key><true/>
    <key>destination</key><string>upload</string>
</dict>
</plist>
PLIST

xcodebuild -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportPath "$EXPORT_DIR" \
  -exportOptionsPlist /tmp/monksynth_export.plist \
  "${AUTH[@]}"

echo "uploaded build $BUILD_NUMBER to TestFlight"
