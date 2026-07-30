#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
OUT=$(mktemp -d)
for t in synth voice delay; do
  clang -std=c99 -Wall -Werror -Idsp \
    "Tests/CTests/test_$t.c" dsp/synth.c dsp/voice.c dsp/delay.c \
    -lm -o "$OUT/test_$t"
  "$OUT/test_$t" || { echo "FAILED: test_$t" >&2; exit 1; }
done
echo "all C DSP tests passed"
