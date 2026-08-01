#!/usr/bin/env bash
#
# Re-pull the C DSP from an upstream monksynth checkout. dsp/ is READ-ONLY in
# this repo: fix DSP bugs upstream and sync them down, so the parity gate stays
# meaningful and fixes can be contributed back to JonET.
set -euo pipefail
cd "$(dirname "$0")/.."

UPSTREAM="${1:-../monksynth-upstream}"
[ -d "$UPSTREAM/dsp" ] || { echo "error: no dsp/ under $UPSTREAM" >&2; exit 1; }

HASH=$(git -C "$UPSTREAM" rev-parse --short HEAD) || {
  echo "error: $UPSTREAM is not a git checkout" >&2; exit 1; }

mkdir -p dsp
find dsp -maxdepth 1 \( -name '*.c' -o -name '*.h' \) -delete
cp "$UPSTREAM"/dsp/*.c "$UPSTREAM"/dsp/*.h dsp/
echo "synced dsp/ from $UPSTREAM @ $HASH"
