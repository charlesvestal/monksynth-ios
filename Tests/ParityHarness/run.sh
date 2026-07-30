#!/usr/bin/env bash
# Renders the parity script and compares against the committed golden.
# Set RECORD_GOLDEN=1 to intentionally (re)capture the golden — only ever
# from known-good code. Without RECORD_GOLDEN=1, a missing golden is a
# hard failure rather than a silent recapture, so an accidentally deleted
# or gitignored golden can't make this gate quietly stop comparing
# anything while still reporting success.
set -euo pipefail
cd "$(dirname "$0")/../.."
OUT=$(mktemp -d)
trap 'rm -rf "$OUT"' EXIT     # else every run leaks a temp dir of build output
GOLD=Tests/ParityHarness/golden_44k.f32
EXPECTED_BYTES=1411200         # 352800 floats * 4 bytes

clang -std=c99 -O2 -Wall -Werror -Idsp -ITests/ParityHarness \
  Tests/ParityHarness/render_golden.c dsp/synth.c dsp/voice.c dsp/delay.c \
  -lm -o "$OUT/render_golden"

if [ ! -f "$GOLD" ]; then
  if [ "${RECORD_GOLDEN:-}" != "1" ]; then
    echo "error: golden missing — re-run with RECORD_GOLDEN=1 to intentionally regenerate from known-good code" >&2
    exit 1
  fi
  "$OUT/render_golden" "$GOLD" >/dev/null
  actual_bytes=$(stat -f%z "$GOLD")
  if [ "$actual_bytes" -ne "$EXPECTED_BYTES" ]; then
    echo "PARITY FAILURE: captured golden is $actual_bytes bytes, expected $EXPECTED_BYTES" >&2
    exit 1
  fi
  echo "captured new golden: $GOLD ($actual_bytes bytes, size check passed)"
  exit 0
fi

"$OUT/render_golden" "$OUT/fresh.f32" >/dev/null
cmp -s "$OUT/fresh.f32" "$GOLD" \
  && echo "golden matches ($(( $(stat -f%z "$GOLD") / 4 )) samples)" \
  || { echo "PARITY FAILURE: render differs from golden" >&2; exit 1; }
