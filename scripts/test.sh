#!/usr/bin/env bash
# Run the XCTest bundle on a simulator. Optional arg filters to one test class.
set -euo pipefail
cd "$(dirname "$0")/.."

# Resolve a simulator destination dynamically instead of hardcoding a device
# name + "OS:latest": on this machine the installed "iPhone 16" simulator
# runs iOS 18.5, and "OS:latest" resolves to the newest installed runtime
# (iOS 26.x), so `platform=iOS Simulator,name=iPhone 16,OS:latest` fails to
# resolve to any booted-or-bootable device. Instead, ask simctl for every
# *available* iPhone across all installed runtimes and pick by UDID, which
# always resolves regardless of which runtimes happen to be installed.
SIMCTL_JSON="$(xcrun simctl list devices available --json)"

# List "<version>\t<udid>\t<name>" for every available iPhone simulator,
# then sort by runtime version descending so we prefer the newest runtime
# (closest to the installed Xcode toolchain) and take the first match.
BEST_SIM="$(echo "$SIMCTL_JSON" | jq -r '
    .devices | to_entries[] | .key as $runtime | .value[] |
    select(.name | test("^iPhone")) |
    "\($runtime)\t\(.udid)\t\(.name)"
  ' | sed -E 's/^com\.apple\.CoreSimulator\.SimRuntime\.iOS-([0-9]+)-([0-9]+)\t/\1.\2\t/' \
    | sort -t $'\t' -k1,1 -rn \
    | head -n 1)"

if [ -z "$BEST_SIM" ]; then
  echo "error: no available iPhone simulator found. Install one via Xcode > Settings > Platforms, or check 'xcrun simctl list devices available'." >&2
  exit 1
fi

SIM_UDID="$(echo "$BEST_SIM" | cut -f2)"
SIM_NAME="$(echo "$BEST_SIM" | cut -f3)"
echo "Using simulator: $SIM_NAME ($SIM_UDID)"

DEST="platform=iOS Simulator,id=$SIM_UDID"

xcodegen generate
ARGS=(test -project MonkSynth.xcodeproj -scheme MonkSynth
      -destination "$DEST"
      CODE_SIGNING_ALLOWED=NO)
[ $# -gt 0 ] && ARGS+=(-only-testing:"$1")
xcodebuild "${ARGS[@]}"
