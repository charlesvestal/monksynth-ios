#!/usr/bin/env bash
# Simulator build — the fast "is it still iOS-clean?" check. No signing.
set -euo pipefail
cd "$(dirname "$0")/.."
xcodegen generate
xcodebuild build \
  -project MonkSynth.xcodeproj \
  -scheme MonkSynth \
  -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' \
  -configuration Debug \
  CODE_SIGNING_ALLOWED=NO
