#!/usr/bin/env bash
#
# There is no build system yet, so each test binary links directly against
# dsp/*.c rather than an intermediate library or object files.
set -euo pipefail
cd "$(dirname "$0")/../.."
OUT=$(mktemp -d)
trap 'rm -rf "$OUT"' EXIT
for t in synth voice delay; do
  clang -std=c99 -Wall -Werror -Idsp \
    "Tests/CTests/test_$t.c" dsp/synth.c dsp/voice.c dsp/delay.c \
    -lm -o "$OUT/test_$t"
  "$OUT/test_$t" || { echo "FAILED: test_$t" >&2; exit 1; }
done
echo "all C DSP tests passed"
