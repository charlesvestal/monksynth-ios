#!/usr/bin/env bash
# Renders the parity script and compares against the committed golden.
# Delete golden_44k.f32 to recapture — only ever from known-good code.
set -euo pipefail
cd "$(dirname "$0")/../.."
OUT=$(mktemp -d)
trap 'rm -rf "$OUT"' EXIT     # else every run leaks a temp dir of build output
GOLD=Tests/ParityHarness/golden_44k.f32

clang -std=c99 -O2 -Wall -Werror -Idsp -ITests/ParityHarness \
  Tests/ParityHarness/render_golden.c dsp/synth.c dsp/voice.c dsp/delay.c \
  -lm -o "$OUT/render_golden"

if [ ! -f "$GOLD" ]; then
  "$OUT/render_golden" "$GOLD" >/dev/null
  echo "captured new golden: $GOLD"
  exit 0
fi

"$OUT/render_golden" "$OUT/fresh.f32" >/dev/null
cmp -s "$OUT/fresh.f32" "$GOLD" \
  && echo "golden matches ($(( $(stat -f%z "$GOLD") / 4 )) samples)" \
  || { echo "PARITY FAILURE: render differs from golden" >&2; exit 1; }
