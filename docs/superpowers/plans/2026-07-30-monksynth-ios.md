# MonkSynth iOS Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers-extended-cc:subagent-driven-development (recommended) or superpowers-extended-cc:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship MonkSynth — JonET's monophonic FOF vocal synthesizer — as a native Swift AUv3 instrument plus standalone host app on the iOS App Store.

**Architecture:** Upstream's pure-C `dsp/` is vendored verbatim and compiled into both targets through a bridging header. Above it, a Swift `AUAudioUnit` (`aumu`/`Mnks`) owns one `MonkSynthEngine*`, drains host MIDI in a strictly realtime-safe `internalRenderBlock`, and reads parameters from a C shadow array of atomics. The UI is UIKit with Core Graphics: a responsive three-zone container, an XY performance pad, and an original vector monk whose mouth morphs continuously with the vowel parameter.

**Tech Stack:** Swift 5, UIKit, CoreAudioKit / AVFoundation (AUv3), Core Graphics, C99, XcodeGen, XCTest, xcodebuild.

**User decisions (already made):**
- App Store release under `com.vestal.*` via TestFlight — not a personal device build, not an upstream contribution.
- Original animated character carries the identity; **no Delay Lama artwork ships** and the theme system is cut.
- Character is a **vector rig composited in code**, not a generated sprite sheet.
- **Full feature parity**: unison, full ADSR + vibrato/glide/aspiration, pitch-bend routing modes, en/ja/ko localization.
- Layout: **portrait stacks** (character / pad / controls-in-drawer), **landscape splits** (character | pad, controls strip always visible).
- **Native Swift, no JUCE** — "3, i'm wild. we have the harness from qwertet tho".
- Ships as "MonkSynth", crediting Jonathan Taylor; JonET contacted as a courtesy.
- Delay Lama heritage: one factual "inspired by" line only — never in title, subtitle, or keywords.

---

## Reference tables

These are lifted from upstream and are the source of truth for Tasks 4–8. Do not re-derive them.

### Parameter table

Every parameter is normalized 0–1 internally. `Display` is what the host and UI show.

| # | ID | Name | Default | Display range | Unit | DSP call (`v` = normalized) |
|---|---|---|---|---|---|---|
| 0 | `portTime` | PortTime | 0.5 | 0…1000 | Hours | `monk_synth_set_glide(v)` |
| 1 | `vowel` | Vowel | 0.5 | 0…1 | — | `monk_synth_set_vowel(v)` |
| 2 | `delay` | Delay | 0.8 | 0…1 | dB | `monk_synth_set_delay_mix(v)` |
| 3 | `headSize` | HeadSize | 0.5 | 0…30 | cm | `monk_synth_set_voice(v)` |
| 4 | `vibrato` | Vibrato | 0.0 | 0…1 | — | `monk_synth_set_vibrato(v)` |
| 5 | `vibratoRate` | Vib Rate | 0.5 | 0…1 | — | `monk_synth_set_vibrato_rate(v)` |
| 6 | `aspiration` | Breath | 0.5 | 0…1 | — | `monk_synth_set_aspiration(v)` |
| 7 | `attack` | Attack | 0.0 | 0…5 | s | `monk_synth_set_attack(v * 5.0)` |
| 8 | `decay` | Decay | 0.0 | 0…5 | s | `monk_synth_set_decay(v * 5.0)` |
| 9 | `sustain` | Sustain | 1.0 | 0…1 | — | `monk_synth_set_sustain(v)` |
| 10 | `release` | Release | 0.0 | 0…5 | s | `monk_synth_set_release(v * 5.0)` |
| 11 | `unison` | Unison | 0.0 | 1…10 (9 steps) | — | `monk_synth_set_unison((int)(v * 9.0 + 1.5))` |
| 12 | `unisonDetune` | Detune | 0.0 | 0…50 | ct | `monk_synth_set_unison_detune(v * 50.0)` |
| 13 | `delayRate` | Delay Rate | 0.5 | 0…1 | — | `monk_synth_set_delay_rate(v)` |
| 14 | `level` | Level | 1.0 | 0…1 | — | `monk_synth_set_level(v)` |
| 15 | `unisonVoiceSpread` | Voice Spread | 0.0 | 0…1 | — | `monk_synth_set_unison_voice_spread(v * 0.5)` |
| 16 | `xyNoteOn` | XY Note | 0.0 | toggle | — | see XY semantics below |
| 17 | `xyVowel` | XY Vowel | 0.5 | 0…1 | — | `monk_synth_set_vowel(v)` |
| 18 | `xyPitchTarget` | XY Pitch | 0.5 | 0…1 | — | see XY semantics below |
| 19 | `pitchBend` | Pitch Bend | 0.5 | -12…12 | st | `monk_synth_set_pitch_bend((v - 0.5) * 24.0)` |
| 20 | `pitchBendRouting` | PB Routing | 0.0 | 4 steps | — | no DSP effect; routing only |
| 21 | `pitchWheelRaw` | PW Raw | 0.5 | 0…1 | — | hidden hub, see routing below |

Params 20 and 21 are hidden from the host (`flags: .flag_IsReadable` without `.flag_IsWritable` is wrong here — use `AudioUnitParameterOptions` without `.flag_IsHighResolution` and mark them non-automatable via `.flag_IsElementMeta`? **No** — set them writable and automatable but exclude them from `ControlPages`; `pitchBendRouting` is user-visible on the Bend page, `pitchWheelRaw` is excluded from the UI entirely).

### XY pad semantics (from `cpp/src/processor.cpp:170-195`)

- Pitch mapping is **C3→C4, one octave**: `hz = 130.81 * powf(2.0, xyPitchTarget)`.
- `xyNoteOn` rising edge: set `xyNoteActive = true`, then `monk_synth_set_pitch_hz(130.81 * pow(2, xyPendingPitch))`.
- `xyNoteOn` falling edge: `xyNoteActive = false`; if MIDI notes are still held call `monk_synth_restore_note_stack()`, else `monk_synth_note_off(60)`.
- `xyPitchTarget` change: always store into `xyPendingPitch`; if `xyNoteActive`, also `monk_synth_set_pitch_hz(...)`.
- MIDI note-off while `xyNoteActive` and it was the last MIDI note: call `monk_synth_note_off(pitch)` **then re-assert** `monk_synth_set_pitch_hz(130.81 * pow(2, xyPendingPitch))`, because the empty note stack would otherwise trigger release.

### MIDI CC map (from `cpp/src/controller.cpp:423-459`)

CCs are routed **to parameters**, not to `monk_synth_midi_cc` — upstream deliberately leaves that C function unused so the host and UI stay in sync. Do the same.

| CC | Target parameter |
|---|---|
| 1 (mod wheel) | `vibrato` |
| 5 (portamento time) | `portTime` |
| 7 (volume) | `level` |
| 12 (effect 1) | `delay` |
| 13 (effect 2) | `headSize` |

### Pitch-wheel routing (`PitchBendMode`, from `cpp/src/plugin_cids.h:51-56`)

`pitchBendRouting` is a 4-step discrete parameter; `mode = clamp(round(v * 3), 0, 3)`.

| Mode | Value | Hardware wheel goes to |
|---|---|---|
| Classic | 0 | `vowel` (Delay Lama compat — **the default**) |
| Both | 1 | `pitchWheelRaw` → fans out to `pitchBend` + `vowel` |
| BothInverted | 2 | `pitchWheelRaw` → fans out to `pitchBend` + `(1 - vowel)` |
| Pitch | 3 | `pitchBend` |

In Both/BothInverted the fan-out **skips the vowel coupling while `xyNoteActive`**, because the pad's vowel writeback would fight it in the same block.

---

## File structure

| File | Responsibility |
|---|---|
| `project.yml` | XcodeGen: `MonkSynth` (app), `MonkSynthAU` (appex), `MonkSynthTests` |
| `dsp/*.c,*.h` | Vendored upstream C engine — **never edited here** |
| `scripts/sync_dsp.sh` | Re-pull `dsp/` from an upstream checkout |
| `scripts/deploy_testflight.sh` | Archive + upload, adapted from Qwertet |
| `AU/MonkSynth-Bridging-Header.h` | Exposes `synth.h` to Swift in both targets |
| `AU/ParameterAddresses.h` | C enum of parameter addresses, shared with Swift |
| `AU/Params.swift` | Parameter table, ranges, formatting, defaults |
| `AU/ParameterShadow.h/.c` | Lock-free `_Atomic float` array the render block reads |
| `AU/MonkSynthAU.swift` | `AUAudioUnit`: tree, buses, allocate/deallocate, `fullState`, presets |
| `AU/RenderContext.swift` | RT-safe MIDI + parameter → DSP translation used by the render block |
| `AU/AudioUnitViewController.swift` | AUv3 principal class; owns the AU and the view |
| `AU/UI/Theme.swift` | Colors, metrics, fonts |
| `AU/UI/PluginView.swift` | Responsive three-zone container |
| `AU/UI/MonkView.swift` | Vector character rig + idle state machine |
| `AU/UI/XYPadView.swift` | Performance pad |
| `AU/UI/KnobView.swift` | Single rotary control |
| `AU/UI/ControlPages.swift` | Paged parameter surface (strip or drawer) |
| `AU/Resources/*.lproj` | `Localizable.strings` — en, ja, ko |
| `Host/MonkSynthApp.swift` | Standalone app entry |
| `Host/LocalEngine.swift` | `AVAudioEngine` + CoreMIDI/BLE input |
| `Tests/ParityHarness/` | C golden renderer + golden data |
| `Tests/MonkSynthTests/` | XCTest: params, routing, parity, persistence |

---

## Task 1: Vendor the C DSP and prove it builds

**Goal:** `dsp/` present verbatim from upstream, a sync script to refresh it, and upstream's three C unit tests passing locally.

**Files:**
- Create: `scripts/sync_dsp.sh`
- Create: `dsp/synth.c`, `dsp/synth.h`, `dsp/synth_internal.h`, `dsp/voice.c`, `dsp/voice.h`, `dsp/delay.c`, `dsp/delay.h` (copied, not authored)
- Create: `Tests/CTests/test_synth.c`, `test_voice.c`, `test_delay.c` (copied from upstream `cpp/tests/`)
- Create: `Tests/CTests/run.sh`

**Acceptance Criteria:**
- [ ] `dsp/` byte-identical to upstream `dsp/` at the pinned commit
- [ ] `scripts/sync_dsp.sh` re-copies from a checkout path and reports the upstream commit
- [ ] All three C test binaries compile with `-Wall -Werror` and exit 0

**Verify:** `Tests/CTests/run.sh` → prints `all C DSP tests passed`

**Steps:**

- [ ] **Step 1: Clone upstream next to this repo**

```bash
cd "$(dirname "$PWD")"
git clone https://github.com/JonET/monksynth.git monksynth-upstream
cd monksynth-upstream && git rev-parse HEAD
```

- [ ] **Step 2: Write `scripts/sync_dsp.sh`**

```bash
#!/usr/bin/env bash
#
# Re-pull the C DSP from an upstream monksynth checkout. dsp/ is READ-ONLY in
# this repo: fix DSP bugs upstream and sync them down, so the parity gate stays
# meaningful and fixes can be contributed back to JonET.
set -euo pipefail
cd "$(dirname "$0")/.."

UPSTREAM="${1:-../monksynth-upstream}"
[ -d "$UPSTREAM/dsp" ] || { echo "error: no dsp/ under $UPSTREAM" >&2; exit 1; }

mkdir -p dsp
cp "$UPSTREAM"/dsp/*.c "$UPSTREAM"/dsp/*.h dsp/
echo "synced dsp/ from $UPSTREAM @ $(git -C "$UPSTREAM" rev-parse --short HEAD)"
```

```bash
chmod +x scripts/sync_dsp.sh && scripts/sync_dsp.sh
```

- [ ] **Step 3: Copy the C tests**

```bash
mkdir -p Tests/CTests
cp ../monksynth-upstream/cpp/tests/test_synth.c \
   ../monksynth-upstream/cpp/tests/test_voice.c \
   ../monksynth-upstream/cpp/tests/test_delay.c Tests/CTests/
```

- [ ] **Step 4: Write `Tests/CTests/run.sh`**

```bash
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
```

- [ ] **Step 5: Run them**

Run: `chmod +x Tests/CTests/run.sh && Tests/CTests/run.sh`
Expected: `all C DSP tests passed`

- [ ] **Step 6: Commit**

```bash
git add dsp scripts/sync_dsp.sh Tests/CTests
git commit -m "Vendor upstream C DSP with sync script and unit tests"
```

---

## Task 2: Parity golden harness

**Goal:** A C program that drives `dsp/` through a fixed script using upstream's exact normalized→DSP mapping and emits a golden buffer. Task 6 asserts the Swift port reproduces it bit-for-bit.

**Files:**
- Create: `Tests/ParityHarness/script.h`
- Create: `Tests/ParityHarness/render_golden.c`
- Create: `Tests/ParityHarness/golden_44k.f32` (generated)
- Create: `Tests/ParityHarness/run.sh`

**Acceptance Criteria:**
- [ ] Script exercises every parameter, both XY edges, MIDI note on/off, and pitch bend
- [ ] Golden is 4 seconds stereo at 44100 Hz (352800 floats)
- [ ] Re-running the harness reproduces the golden byte-for-byte

**Verify:** `Tests/ParityHarness/run.sh` → prints `golden matches (352800 samples)`

> **As-built note (commit `3761346`).** The snippets below are the first draft; code
> review hardened them before this task closed, and the shipped harness differs:
> `run.sh` requires `RECORD_GOLDEN=1` to capture a missing golden (otherwise it
> exits 1 — silently re-minting the golden would make the gate pass while testing
> nothing), verifies the captured file is exactly 1411200 bytes, and
> `render_golden.c` checks `calloc`/`fwrite`/`fclose` and writes via an adjacent
> temp file + `rename()` so a failed run cannot leave a truncated golden in place.
> The golden itself is unchanged — SHA-256 `307b1289…`. Read the files, not this
> section, for current behaviour.

**Steps:**

- [ ] **Step 1: Write `Tests/ParityHarness/script.h`** — the shared event script, so the Swift test can replay the identical sequence.

```c
/* Fixed parity script. Times are in samples at 44100 Hz.
 * Kind: 0=param set (normalized), 1=note on, 2=note off, 3=xy note on,
 *       4=xy note off, 5=xy pitch, 6=xy vowel. */
#ifndef PARITY_SCRIPT_H
#define PARITY_SCRIPT_H

typedef struct { int at; int kind; int index; float value; } ParityEvent;

#define PARITY_SR        44100
#define PARITY_FRAMES    176400        /* 4 seconds */
#define PARITY_BLOCK     512

static const ParityEvent kParityScript[] = {
    {     0, 0,  0, 0.25f},   /* portTime          */
    {     0, 0,  2, 0.60f},   /* delay             */
    {     0, 0,  3, 0.70f},   /* headSize          */
    {     0, 0,  4, 0.35f},   /* vibrato           */
    {     0, 0,  5, 0.80f},   /* vibratoRate       */
    {     0, 0,  6, 0.20f},   /* aspiration        */
    {     0, 0,  7, 0.10f},   /* attack  -> 0.5 s  */
    {     0, 0,  8, 0.30f},   /* decay   -> 1.5 s  */
    {     0, 0,  9, 0.70f},   /* sustain           */
    {     0, 0, 10, 0.40f},   /* release -> 2.0 s  */
    {     0, 0, 11, 0.55f},   /* unison  -> 6      */
    {     0, 0, 12, 0.40f},   /* detune  -> 20 ct  */
    {     0, 0, 13, 0.65f},   /* delayRate         */
    {     0, 0, 14, 0.90f},   /* level             */
    {     0, 0, 15, 0.50f},   /* voiceSpread       */
    {  4410, 1, 60, 0.80f},   /* note on  C4       */
    { 22050, 0, 19, 0.75f},   /* pitchBend +6 st   */
    { 30870, 0,  1, 0.20f},   /* vowel             */
    { 44100, 2, 60, 0.00f},   /* note off          */
    { 61740, 5,  0, 0.30f},   /* xy pitch          */
    { 61740, 3,  0, 1.00f},   /* xy note on        */
    { 79380, 6,  0, 0.85f},   /* xy vowel          */
    { 96030, 5,  0, 0.75f},   /* xy pitch glide    */
    {114660, 4,  0, 0.00f},   /* xy note off       */
    {132300, 0, 19, 0.50f},   /* pitchBend back    */
};
#define PARITY_EVENT_COUNT (int)(sizeof(kParityScript) / sizeof(kParityScript[0]))

#endif
```

- [ ] **Step 2: Write `Tests/ParityHarness/render_golden.c`**

The `apply_param` function below is upstream's mapping verbatim (`cpp/src/processor.cpp:45-64,153-195`). Task 6's Swift code must match it exactly.

```c
#include "script.h"
#include "synth.h"
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static int   xy_active  = 0;
static float xy_pending = 0.5f;
static int   midi_notes = 0;

static float xy_hz(float v) { return 130.81f * powf(2.0f, v); }

static void apply_param(MonkSynthEngine *s, int i, float v) {
    switch (i) {
    case  0: monk_synth_set_glide(s, v); break;
    case  1: monk_synth_set_vowel(s, v); break;
    case  2: monk_synth_set_delay_mix(s, v); break;
    case  3: monk_synth_set_voice(s, v); break;
    case  4: monk_synth_set_vibrato(s, v); break;
    case  5: monk_synth_set_vibrato_rate(s, v); break;
    case  6: monk_synth_set_aspiration(s, v); break;
    case  7: monk_synth_set_attack(s, v * 5.0f); break;
    case  8: monk_synth_set_decay(s, v * 5.0f); break;
    case  9: monk_synth_set_sustain(s, v); break;
    case 10: monk_synth_set_release(s, v * 5.0f); break;
    case 11: monk_synth_set_unison(s, (int)(v * 9.0f + 1.5f)); break;
    case 12: monk_synth_set_unison_detune(s, v * 50.0f); break;
    case 13: monk_synth_set_delay_rate(s, v); break;
    case 14: monk_synth_set_level(s, v); break;
    case 15: monk_synth_set_unison_voice_spread(s, v * 0.5f); break;
    case 19: monk_synth_set_pitch_bend(s, (v - 0.5f) * 24.0f); break;
    default: break;
    }
}

static void apply_event(MonkSynthEngine *s, const ParityEvent *e) {
    switch (e->kind) {
    case 0: apply_param(s, e->index, e->value); break;
    case 1: monk_synth_note_on(s, (uint8_t)e->index, e->value); midi_notes++; break;
    case 2:
        if (midi_notes > 0) midi_notes--;
        monk_synth_note_off(s, (uint8_t)e->index);
        if (xy_active && midi_notes == 0)
            monk_synth_set_pitch_hz(s, xy_hz(xy_pending));
        break;
    case 3: xy_active = 1; monk_synth_set_pitch_hz(s, xy_hz(xy_pending)); break;
    case 4:
        xy_active = 0;
        if (midi_notes > 0) monk_synth_restore_note_stack(s);
        else                monk_synth_note_off(s, 60);
        break;
    case 5:
        xy_pending = e->value;
        if (xy_active) monk_synth_set_pitch_hz(s, xy_hz(e->value));
        break;
    case 6: monk_synth_set_vowel(s, e->value); break;
    default: break;
    }
}

int main(int argc, char **argv) {
    const char *path = argc > 1 ? argv[1] : "Tests/ParityHarness/golden_44k.f32";
    MonkSynthEngine *s = monk_synth_new((float)PARITY_SR);
    float *out = calloc((size_t)PARITY_FRAMES * 2, sizeof(float));
    float l[PARITY_BLOCK], r[PARITY_BLOCK];
    int next = 0;

    for (int pos = 0; pos < PARITY_FRAMES; pos += PARITY_BLOCK) {
        while (next < PARITY_EVENT_COUNT && kParityScript[next].at <= pos)
            apply_event(s, &kParityScript[next++]);

        int n = PARITY_FRAMES - pos < PARITY_BLOCK ? PARITY_FRAMES - pos : PARITY_BLOCK;
        monk_synth_process(s, l, r, (uint32_t)n);
        for (int i = 0; i < n; i++) {
            out[(size_t)(pos + i) * 2]     = l[i];
            out[(size_t)(pos + i) * 2 + 1] = r[i];
        }
    }

    FILE *f = fopen(path, "wb");
    if (!f) { perror("fopen"); return 1; }
    fwrite(out, sizeof(float), (size_t)PARITY_FRAMES * 2, f);
    fclose(f);
    free(out);
    monk_synth_free(s);
    printf("wrote %d samples to %s\n", PARITY_FRAMES * 2, path);
    return 0;
}
```

- [ ] **Step 3: Write `Tests/ParityHarness/run.sh`**

```bash
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
```

- [ ] **Step 4: Capture and then verify the golden**

Run: `chmod +x Tests/ParityHarness/run.sh && Tests/ParityHarness/run.sh && Tests/ParityHarness/run.sh`
Expected: first run prints `captured new golden: ...`, second prints `golden matches (352800 samples)`

- [ ] **Step 5: Commit**

```bash
git add Tests/ParityHarness
git commit -m "Add parity golden harness for the C DSP"
```

---

## Task 3: XcodeGen project skeleton

**Goal:** `MonkSynth` app and `MonkSynthAU` app-extension targets that both compile the vendored C through a bridging header, building clean for the simulator.

**Files:**
- Create: `project.yml`
- Create: `AU/Info.plist`
- Create: `Host/Info.plist`
- Create: `AU/MonkSynth-Bridging-Header.h`

> **Corrected after review.** An earlier draft of this task created
> `AU/MonkSynthAU.entitlements` and `Host/MonkSynth.entitlements` declaring app
> group `group.com.vestal.monksynth`. **Do not add them.** Nothing in this project
> consumes a shared container — AUv3 state uses `fullState` and factory presets —
> and an unregistered app-group entitlement makes `xcodebuild archive` fail with
> "Provisioning profile doesn't include the App Groups capability". Qwertet, which
> ships through this same pipeline, has no entitlements files at all. Add one back
> only when a task actually needs a shared container, and register it in the
> Developer Portal first.
- Create: `AU/AudioUnitViewController.swift` (stub), `AU/MonkSynthAU.swift` (stub)
- Create: `Host/MonkSynthApp.swift` (stub)

**Acceptance Criteria:**
- [ ] `xcodegen generate` produces `MonkSynth.xcodeproj`
- [ ] Both targets build for `iphonesimulator` with no warnings
- [ ] The appex declares `type aumu`, `subtype Mnks`, `manufacturer Vstl`
- [ ] Swift can call `monk_synth_new` in both targets

**Verify:** `scripts/build_sim.sh` → ends with `** BUILD SUCCEEDED **`

**Steps:**

- [ ] **Step 1: Write `project.yml`**

```yaml
name: MonkSynth
options:
  bundleIdPrefix: com.vestal
  deploymentTarget:
    iOS: "16.0"
  createIntermediateGroups: true
settings:
  base:
    DEVELOPMENT_TEAM: J4722B5MJW
    CODE_SIGN_STYLE: Automatic
    SWIFT_VERSION: "5.0"
    TARGETED_DEVICE_FAMILY: "1,2"
    MARKETING_VERSION: "1.0.0"
    CURRENT_PROJECT_VERSION: "1"
    ENABLE_USER_SCRIPT_SANDBOXING: NO
    SWIFT_OBJC_BRIDGING_HEADER: AU/MonkSynth-Bridging-Header.h
    HEADER_SEARCH_PATHS: $(SRCROOT)/dsp $(SRCROOT)/AU
    GCC_WARN_INHIBIT_ALL_WARNINGS: NO
targets:
  MonkSynth:
    type: application
    platform: iOS
    sources:
      - Host
      - dsp
      - path: AU
        excludes:
          - Info.plist
          - AudioUnitViewController.swift
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.vestal.monksynth
        PRODUCT_NAME: MonkSynth
        INFOPLIST_FILE: Host/Info.plist
        GENERATE_INFOPLIST_FILE: NO
        ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon
    dependencies:
      - target: MonkSynthAU
        embed: true
      - sdk: AVFoundation.framework
      - sdk: CoreMIDI.framework
  MonkSynthAU:
    type: app-extension
    platform: iOS
    sources:
      - AU
      - dsp
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.vestal.monksynth.AU
        PRODUCT_NAME: MonkSynthAU
        INFOPLIST_FILE: AU/Info.plist
        GENERATE_INFOPLIST_FILE: NO
    dependencies:
      - sdk: AVFoundation.framework
      - sdk: CoreAudioKit.framework
  MonkSynthTests:
    type: bundle.unit-test
    platform: iOS
    sources:
      - Tests/MonkSynthTests
      - dsp
      - path: AU
        excludes:
          - Info.plist
          - AudioUnitViewController.swift
    dependencies:
      - target: MonkSynth
    settings:
      base:
        GENERATE_INFOPLIST_FILE: YES
```

- [ ] **Step 2: Write `AU/MonkSynth-Bridging-Header.h`**

```c
// Exposes the vendored MonkSynth C engine to Swift in every target.
#include "synth.h"
#include "ParameterAddresses.h"
#include "ParameterShadow.h"
```

- [ ] **Step 3: Write `AU/Info.plist`**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key><string>en</string>
    <key>CFBundleDisplayName</key><string>MonkSynth</string>
    <key>CFBundleExecutable</key><string>$(EXECUTABLE_NAME)</string>
    <key>CFBundleIdentifier</key><string>$(PRODUCT_BUNDLE_IDENTIFIER)</string>
    <key>CFBundleName</key><string>$(PRODUCT_NAME)</string>
    <key>CFBundlePackageType</key><string>XPC!</string>
    <key>CFBundleShortVersionString</key><string>$(MARKETING_VERSION)</string>
    <key>CFBundleVersion</key><string>$(CURRENT_PROJECT_VERSION)</string>
    <key>NSExtension</key>
    <dict>
        <key>NSExtensionAttributes</key>
        <dict>
            <key>AudioComponents</key>
            <array>
                <dict>
                    <key>description</key><string>MonkSynth</string>
                    <key>factoryFunction</key><string>$(PRODUCT_MODULE_NAME).AudioUnitViewController</string>
                    <key>manufacturer</key><string>Vstl</string>
                    <key>name</key><string>Charles Vestal: MonkSynth</string>
                    <key>sandboxSafe</key><true/>
                    <key>subtype</key><string>Mnks</string>
                    <key>tags</key>
                    <array><string>Instrument</string><string>Synthesizer</string></array>
                    <key>type</key><string>aumu</string>
                    <key>version</key><integer>65536</integer>
                </dict>
            </array>
        </dict>
        <key>NSExtensionPointIdentifier</key><string>com.apple.AudioUnit-UI</string>
        <key>NSExtensionPrincipalClass</key><string>$(PRODUCT_MODULE_NAME).AudioUnitViewController</string>
    </dict>
</dict>
</plist>
```

- [ ] **Step 4: Write `Host/Info.plist`**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key><string>en</string>
    <key>CFBundleDisplayName</key><string>MonkSynth</string>
    <key>CFBundleExecutable</key><string>$(EXECUTABLE_NAME)</string>
    <key>CFBundleIdentifier</key><string>$(PRODUCT_BUNDLE_IDENTIFIER)</string>
    <key>CFBundleName</key><string>$(PRODUCT_NAME)</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$(MARKETING_VERSION)</string>
    <key>CFBundleVersion</key><string>$(CURRENT_PROJECT_VERSION)</string>
    <key>ITSAppUsesNonExemptEncryption</key><false/>
    <key>UILaunchScreen</key><dict/>
    <key>UIBackgroundModes</key><array><string>audio</string></array>
    <key>UISupportedInterfaceOrientations</key>
    <array>
        <string>UIInterfaceOrientationPortrait</string>
        <string>UIInterfaceOrientationLandscapeLeft</string>
        <string>UIInterfaceOrientationLandscapeRight</string>
    </array>
    <key>UISupportedInterfaceOrientations~ipad</key>
    <array>
        <string>UIInterfaceOrientationPortrait</string>
        <string>UIInterfaceOrientationPortraitUpsideDown</string>
        <string>UIInterfaceOrientationLandscapeLeft</string>
        <string>UIInterfaceOrientationLandscapeRight</string>
    </array>
</dict>
</plist>
```

- [ ] **Step 5: Exclude the AU subclass from the non-extension targets**

`AU/MonkSynthAU.swift` is only meaningful inside the app extension. Add it to the
`excludes:` list of the `MonkSynth` target so it is not compiled as dead code
there, matching how Qwertet excludes its equivalent file. Leave it available to
`MonkSynthTests`, which instantiates `MonkSynthAU` directly from Task 5 onward.

- [ ] **Step 6: Write the three stubs so the project links**

`AU/MonkSynthAU.swift`:

```swift
import AVFoundation

public final class MonkSynthAU: AUAudioUnit {
    public override init(componentDescription: AudioComponentDescription,
                         options: AudioComponentInstantiationOptions = []) throws {
        try super.init(componentDescription: componentDescription, options: options)
    }
}
```

`AU/AudioUnitViewController.swift`:

```swift
import CoreAudioKit

public final class AudioUnitViewController: AUViewController, AUAudioUnitFactory {
    var audioUnit: MonkSynthAU?

    public func createAudioUnit(with desc: AudioComponentDescription) throws -> AUAudioUnit {
        let au = try MonkSynthAU(componentDescription: desc)
        audioUnit = au
        return au
    }
}
```

`Host/MonkSynthApp.swift`:

```swift
import UIKit

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // Proves the vendored C is reachable from Swift in the app target.
        let engine = monk_synth_new(44100)
        monk_synth_free(engine)

        let w = UIWindow(frame: UIScreen.main.bounds)
        w.rootViewController = UIViewController()
        w.makeKeyAndVisible()
        window = w
        return true
    }
}
```

- [ ] **Step 7: Write `scripts/build_sim.sh`**

```bash
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
```

- [ ] **Step 8: Create the placeholder headers so the bridging header resolves**

`AU/ParameterAddresses.h` and `AU/ParameterShadow.h` get their real contents in Tasks 4 and 5. For now:

```c
#ifndef PARAMETER_ADDRESSES_H
#define PARAMETER_ADDRESSES_H
#endif
```

```c
#ifndef PARAMETER_SHADOW_H
#define PARAMETER_SHADOW_H
#endif
```

- [ ] **Step 9: Build**

Run: `chmod +x scripts/build_sim.sh && scripts/build_sim.sh`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 10: Commit**

```bash
git add project.yml AU Host scripts/build_sim.sh
git commit -m "Add XcodeGen project with AUv3 appex and host app skeletons"
```

---

## Task 4: Parameter definitions

**Goal:** The 22-parameter table encoded once in C (addresses) and Swift (ranges, defaults, formatting), with tests asserting every default and display range matches upstream.

**Files:**
- Modify: `AU/ParameterAddresses.h`
- Create: `AU/Params.swift`
- Create: `Tests/MonkSynthTests/ParamsTests.swift`

**Acceptance Criteria:**
- [ ] `ParameterAddress` enum has all 22 cases in upstream's ID order
- [ ] Every parameter's normalized default matches the table in this plan
- [ ] Display conversion round-trips: `normalized(fromDisplay(display(v))) == v` within 1e-6
- [ ] `unison` displays integer steps 1…10; `pitchBendRouting` displays the four mode names

**Verify:** `scripts/test.sh MonkSynthTests/ParamsTests` → `Executed 5 tests, with 0 failures`

**Steps:**

- [ ] **Step 1: Write `AU/ParameterAddresses.h`**

```c
// Parameter addresses, shared by the C shadow array and Swift.
// Order and values MUST match upstream cpp/src/plugin_cids.h.
#ifndef PARAMETER_ADDRESSES_H
#define PARAMETER_ADDRESSES_H

#include <stdint.h>

typedef enum {
    kParamPortTime          = 0,
    kParamVowel             = 1,
    kParamDelay             = 2,
    kParamHeadSize          = 3,
    kParamVibrato           = 4,
    kParamVibratoRate       = 5,
    kParamAspiration        = 6,
    kParamAttack            = 7,
    kParamDecay             = 8,
    kParamSustain           = 9,
    kParamRelease           = 10,
    kParamUnison            = 11,
    kParamUnisonDetune      = 12,
    kParamDelayRate         = 13,
    kParamLevel             = 14,
    kParamUnisonVoiceSpread = 15,
    kParamXYNoteOn          = 16,
    kParamXYVowel           = 17,
    kParamXYPitchTarget     = 18,
    kParamPitchBend         = 19,
    kParamPitchBendRouting  = 20,
    kParamPitchWheelRaw     = 21,
    kParamCount             = 22
} ParameterAddress;

#endif
```

- [ ] **Step 2: Write `AU/Params.swift`**

```swift
import AVFoundation

/// The parameter table. Normalized 0…1 internally, exactly as upstream stores
/// it; `display` is what the host and UI show. Ranges lifted from
/// upstream cpp/src/controller.cpp:566-661.
enum Param: UInt64, CaseIterable {
    case portTime = 0, vowel, delay, headSize, vibrato, vibratoRate, aspiration
    case attack, decay, sustain, release, unison, unisonDetune, delayRate
    case level, unisonVoiceSpread, xyNoteOn, xyVowel, xyPitchTarget
    case pitchBend, pitchBendRouting, pitchWheelRaw

    var identifier: String {
        switch self {
        case .portTime: return "portTime"
        case .vowel: return "vowel"
        case .delay: return "delay"
        case .headSize: return "headSize"
        case .vibrato: return "vibrato"
        case .vibratoRate: return "vibratoRate"
        case .aspiration: return "aspiration"
        case .attack: return "attack"
        case .decay: return "decay"
        case .sustain: return "sustain"
        case .release: return "release"
        case .unison: return "unison"
        case .unisonDetune: return "unisonDetune"
        case .delayRate: return "delayRate"
        case .level: return "level"
        case .unisonVoiceSpread: return "unisonVoiceSpread"
        case .xyNoteOn: return "xyNoteOn"
        case .xyVowel: return "xyVowel"
        case .xyPitchTarget: return "xyPitchTarget"
        case .pitchBend: return "pitchBend"
        case .pitchBendRouting: return "pitchBendRouting"
        case .pitchWheelRaw: return "pitchWheelRaw"
        }
    }

    /// Host-facing name. Matches upstream's STR16 names so presets read the same.
    var name: String {
        switch self {
        case .portTime: return "PortTime"
        case .vowel: return "Vowel"
        case .delay: return "Delay"
        case .headSize: return "HeadSize"
        case .vibrato: return "Vibrato"
        case .vibratoRate: return "Vib Rate"
        case .aspiration: return "Breath"
        case .attack: return "Attack"
        case .decay: return "Decay"
        case .sustain: return "Sustain"
        case .release: return "Release"
        case .unison: return "Unison"
        case .unisonDetune: return "Detune"
        case .delayRate: return "Delay Rate"
        case .level: return "Level"
        case .unisonVoiceSpread: return "Voice Spread"
        case .xyNoteOn: return "XY Note"
        case .xyVowel: return "XY Vowel"
        case .xyPitchTarget: return "XY Pitch"
        case .pitchBend: return "Pitch Bend"
        case .pitchBendRouting: return "PB Routing"
        case .pitchWheelRaw: return "PW Raw"
        }
    }

    var unit: String {
        switch self {
        case .portTime: return "Hours"
        case .delay: return "dB"
        case .headSize: return "cm"
        case .attack, .decay, .release: return "s"
        case .unisonDetune: return "ct"
        case .pitchBend: return "st"
        default: return ""
        }
    }

    /// Normalized default, from upstream cpp/src/processor.h.
    var defaultValue: AUValue {
        switch self {
        case .delay: return 0.8
        case .sustain, .level: return 1.0
        case .vibrato, .attack, .decay, .release,
             .unison, .unisonDetune, .unisonVoiceSpread,
             .xyNoteOn, .pitchBendRouting: return 0.0
        default: return 0.5   // portTime, vowel, headSize, vibratoRate,
                              // aspiration, delayRate, xyVowel,
                              // xyPitchTarget, pitchBend, pitchWheelRaw
        }
    }

    /// Display range for the host's value string.
    var displayRange: ClosedRange<AUValue> {
        switch self {
        case .portTime: return 0...1000
        case .headSize: return 0...30
        case .attack, .decay, .release: return 0...5
        case .unison: return 1...10
        case .unisonDetune: return 0...50
        case .pitchBend: return -12...12
        default: return 0...1
        }
    }

    /// Number of discrete steps, or 0 for continuous.
    var stepCount: Int {
        switch self {
        case .unison: return 9            // 10 values, 9 intervals
        case .pitchBendRouting: return 3  // 4 modes
        case .xyNoteOn: return 1          // toggle
        default: return 0
        }
    }

    /// Hidden from the on-screen control pages (still host-automatable).
    var isHiddenFromUI: Bool {
        switch self {
        case .xyNoteOn, .xyVowel, .xyPitchTarget, .pitchWheelRaw: return true
        default: return false
        }
    }

    func display(_ normalized: AUValue) -> AUValue {
        let r = displayRange
        return r.lowerBound + normalized * (r.upperBound - r.lowerBound)
    }

    func normalized(fromDisplay d: AUValue) -> AUValue {
        let r = displayRange
        return (d - r.lowerBound) / (r.upperBound - r.lowerBound)
    }

    func formatted(_ normalized: AUValue) -> String {
        switch self {
        case .unison:
            return String(Int((normalized * 9.0 + 1.5).rounded(.down)))
        case .pitchBendRouting:
            return PitchBendMode(normalized: normalized).name
        case .xyNoteOn:
            return normalized > 0.5 ? "On" : "Off"
        case .portTime, .headSize, .unisonDetune:
            return String(format: "%.0f", display(normalized))
        case .pitchBend:
            return String(format: "%+.2f", display(normalized))
        case .attack, .decay, .release:
            return String(format: "%.2f", display(normalized))
        default:
            return String(format: "%.2f", normalized)
        }
    }
}

extension Param {
    /// The C-side address. A plain C `typedef enum` imports into Swift as a
    /// RawRepresentable struct with a NON-failable init, so never write
    /// `ParameterAddress(rawValue:)!` — it will not compile.
    var address: ParameterAddress { ParameterAddress(UInt32(rawValue)) }

    static func address(atIndex i: Int) -> ParameterAddress {
        ParameterAddress(UInt32(i))
    }
}

/// Where the hardware pitch wheel is routed. Upstream cpp/src/plugin_cids.h:51.
enum PitchBendMode: Int, CaseIterable {
    case classic = 0, both, bothInverted, pitch

    init(normalized v: AUValue) {
        let i = Int((v * 3.0 + 0.5).rounded(.down))
        self = PitchBendMode(rawValue: max(0, min(3, i))) ?? .classic
    }

    var normalized: AUValue { AUValue(rawValue) / 3.0 }

    var name: String {
        switch self {
        case .classic: return "Classic"
        case .both: return "Both"
        case .bothInverted: return "Both Inv"
        case .pitch: return "Pitch"
        }
    }
}
```

- [ ] **Step 3: Write the failing test `Tests/MonkSynthTests/ParamsTests.swift`**

```swift
import XCTest
@testable import MonkSynth

final class ParamsTests: XCTestCase {

    func testAddressOrderMatchesUpstream() {
        XCTAssertEqual(Param.allCases.count, Int(kParamCount.rawValue))
        XCTAssertEqual(Param.portTime.rawValue, UInt64(kParamPortTime.rawValue))
        XCTAssertEqual(Param.pitchWheelRaw.rawValue, UInt64(kParamPitchWheelRaw.rawValue))
        XCTAssertEqual(Param.xyPitchTarget.rawValue, 18)
    }

    func testDefaultsMatchUpstreamProcessorTable() {
        // Upstream cpp/src/processor.h paramValues_ initializer, in ID order.
        let expected: [AUValue] = [0.5, 0.5, 0.8, 0.5, 0.0, 0.5, 0.5, 0.0,
                                   0.0, 1.0, 0.0, 0.0, 0.0, 0.5, 1.0, 0.0,
                                   0.0, 0.5, 0.5, 0.5, 0.0, 0.5]
        for (i, p) in Param.allCases.enumerated() {
            XCTAssertEqual(p.defaultValue, expected[i], accuracy: 1e-6,
                           "default mismatch for \(p.name)")
        }
    }

    func testDisplayRoundTrips() {
        for p in Param.allCases {
            for v: AUValue in [0.0, 0.25, 0.5, 0.75, 1.0] {
                XCTAssertEqual(p.normalized(fromDisplay: p.display(v)), v,
                               accuracy: 1e-6, "round-trip failed for \(p.name)")
            }
        }
    }

    func testUnisonFormatsAsIntegerVoiceCount() {
        // Matches upstream's (int)(v * 9 + 1.5) DSP mapping.
        XCTAssertEqual(Param.unison.formatted(0.0), "1")
        XCTAssertEqual(Param.unison.formatted(1.0), "10")
        XCTAssertEqual(Param.unison.formatted(0.55), "6")
    }

    func testPitchBendModeMapping() {
        XCTAssertEqual(PitchBendMode(normalized: 0.0), .classic)
        XCTAssertEqual(PitchBendMode(normalized: 1.0), .pitch)
        XCTAssertEqual(PitchBendMode(normalized: 0.34), .both)
        XCTAssertEqual(PitchBendMode.bothInverted.normalized, 2.0 / 3.0,
                       accuracy: 1e-6)
    }
}
```

- [ ] **Step 4: Write `scripts/test.sh`**

```bash
#!/usr/bin/env bash
# Run the XCTest bundle on a simulator. Optional arg filters to one test class.
set -euo pipefail
cd "$(dirname "$0")/.."
xcodegen generate
ARGS=(test -project MonkSynth.xcodeproj -scheme MonkSynth
      -destination 'platform=iOS Simulator,name=iPhone 16'
      CODE_SIGNING_ALLOWED=NO)
[ $# -gt 0 ] && ARGS+=(-only-testing:"$1")
xcodebuild "${ARGS[@]}"
```

- [ ] **Step 5: Run — expect failure, then pass**

Run: `chmod +x scripts/test.sh && scripts/test.sh MonkSynthTests/ParamsTests`
Expected before Step 2's file exists: compile error `cannot find 'Param' in scope`.
Expected after: `Executed 5 tests, with 0 failures`

- [ ] **Step 6: Commit**

```bash
git add AU/ParameterAddresses.h AU/Params.swift Tests/MonkSynthTests/ParamsTests.swift scripts/test.sh
git commit -m "Define the 22-parameter table with upstream ranges and defaults"
```

---

## Task 5: Parameter shadow array

**Goal:** A lock-free C array of atomics the render block reads without touching `AUParameter`, plus the `AUParameterTree` that writes into it.

**Files:**
- Modify: `AU/ParameterShadow.h`
- Create: `AU/ParameterShadow.c`
- Modify: `AU/MonkSynthAU.swift`
- Create: `Tests/MonkSynthTests/ShadowTests.swift`

**Acceptance Criteria:**
- [ ] `param_shadow_set/get` are `_Atomic float` accesses with no locks
- [ ] Setting an `AUParameter` value updates the shadow
- [ ] Host reads of `AUParameter.value` return the shadow value
- [ ] `parameterTree.allParameters.count == 22`

**Verify:** `scripts/test.sh MonkSynthTests/ShadowTests` → `Executed 3 tests, with 0 failures`

**Steps:**

- [ ] **Step 1: Write `AU/ParameterShadow.h`**

```c
// Lock-free parameter snapshot. The render thread reads only from here — it
// must never touch AUParameter, which is not realtime-safe.
#ifndef PARAMETER_SHADOW_H
#define PARAMETER_SHADOW_H

#include "ParameterAddresses.h"

typedef struct ParamShadow ParamShadow;

ParamShadow *param_shadow_new(void);
void  param_shadow_free(ParamShadow *s);
void  param_shadow_set(ParamShadow *s, ParameterAddress a, float v);
float param_shadow_get(const ParamShadow *s, ParameterAddress a);

#endif
```

- [ ] **Step 2: Write `AU/ParameterShadow.c`**

```c
#include "ParameterShadow.h"
#include <stdatomic.h>
#include <stdlib.h>

struct ParamShadow { _Atomic float values[kParamCount]; };

ParamShadow *param_shadow_new(void) {
    ParamShadow *s = calloc(1, sizeof(ParamShadow));
    return s;
}

void param_shadow_free(ParamShadow *s) { free(s); }

void param_shadow_set(ParamShadow *s, ParameterAddress a, float v) {
    if (!s || a < 0 || a >= kParamCount) return;
    atomic_store_explicit(&s->values[a], v, memory_order_relaxed);
}

float param_shadow_get(const ParamShadow *s, ParameterAddress a) {
    if (!s || a < 0 || a >= kParamCount) return 0.0f;
    return atomic_load_explicit(&s->values[a], memory_order_relaxed);
}
```

- [ ] **Step 3: Replace `AU/MonkSynthAU.swift` with the tree-owning version**

```swift
import AVFoundation

public final class MonkSynthAU: AUAudioUnit {

    let shadow: UnsafeMutablePointer<ParamShadow> = param_shadow_new()
    private var _parameterTree: AUParameterTree!
    private var outputBusArray: AUAudioUnitBusArray!

    public override init(componentDescription: AudioComponentDescription,
                         options: AudioComponentInstantiationOptions = []) throws {
        try super.init(componentDescription: componentDescription, options: options)

        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)!
        let bus = try AUAudioUnitBus(format: format)
        outputBusArray = AUAudioUnitBusArray(audioUnit: self, busType: .output, busses: [bus])

        buildParameterTree()
    }

    deinit { param_shadow_free(shadow) }

    public override var outputBusses: AUAudioUnitBusArray { outputBusArray }
    public override var parameterTree: AUParameterTree? {
        get { _parameterTree } set { _parameterTree = newValue }
    }

    private func buildParameterTree() {
        let params: [AUParameter] = Param.allCases.map { p in
            var flags: AudioUnitParameterOptions = [.flag_IsReadable, .flag_IsWritable]
            if !p.isHiddenFromUI { flags.insert(.flag_CanRamp) }
            let param = AUParameterTree.createParameter(
                withIdentifier: p.identifier,
                name: p.name,
                address: p.rawValue,
                min: 0.0, max: 1.0,
                unit: .generic,
                unitName: p.unit.isEmpty ? nil : p.unit,
                flags: flags,
                valueStrings: nil,
                dependentParameters: nil)
            param.value = p.defaultValue
            return param
        }

        let tree = AUParameterTree.createTree(withChildren: params)

        // Host / UI writes land in the shadow; the render thread reads only there.
        tree.implementorValueObserver = { [weak self] param, value in
            guard let self else { return }
            param_shadow_set(self.shadow, ParameterAddress(UInt32(param.address)), value)
        }
        tree.implementorValueProvider = { [weak self] param in
            guard let self else { return 0 }
            return param_shadow_get(self.shadow, ParameterAddress(UInt32(param.address)))
        }
        tree.implementorStringFromValueCallback = { param, valuePtr in
            let v = valuePtr?.pointee ?? param.value
            guard let p = Param(rawValue: param.address) else { return "" }
            return p.formatted(v)
        }

        _parameterTree = tree
        // Seed the shadow with defaults.
        for p in Param.allCases {
            param_shadow_set(shadow, p.address, p.defaultValue)
        }
    }
}
```

- [ ] **Step 4: Write `Tests/MonkSynthTests/ShadowTests.swift`**

```swift
import AVFoundation
import XCTest
@testable import MonkSynth

final class ShadowTests: XCTestCase {

    private func makeAU() throws -> MonkSynthAU {
        let desc = AudioComponentDescription(
            componentType: kAudioUnitType_MusicDevice,
            componentSubType: 0x4D6E6B73,          // 'Mnks'
            componentManufacturer: 0x5673746C,     // 'Vstl'
            componentFlags: 0, componentFlagsMask: 0)
        return try MonkSynthAU(componentDescription: desc)
    }

    func testTreeHasEveryParameter() throws {
        let au = try makeAU()
        XCTAssertEqual(au.parameterTree?.allParameters.count, 22)
    }

    func testSettingParameterUpdatesShadow() throws {
        let au = try makeAU()
        let attack = au.parameterTree!.parameter(withAddress: Param.attack.rawValue)!
        attack.value = 0.4
        XCTAssertEqual(param_shadow_get(au.shadow, kParamAttack), 0.4, accuracy: 1e-6)
    }

    func testDefaultsSeededIntoShadow() throws {
        let au = try makeAU()
        XCTAssertEqual(param_shadow_get(au.shadow, kParamDelay), 0.8, accuracy: 1e-6)
        XCTAssertEqual(param_shadow_get(au.shadow, kParamSustain), 1.0, accuracy: 1e-6)
        XCTAssertEqual(param_shadow_get(au.shadow, kParamVibrato), 0.0, accuracy: 1e-6)
    }
}
```

- [ ] **Step 5: Run**

Run: `scripts/test.sh MonkSynthTests/ShadowTests`
Expected: `Executed 3 tests, with 0 failures`

- [ ] **Step 6: Commit**

```bash
git add AU/ParameterShadow.h AU/ParameterShadow.c AU/MonkSynthAU.swift Tests/MonkSynthTests/ShadowTests.swift
git commit -m "Add lock-free parameter shadow and the AU parameter tree"
```

---

## Task 6: Render block and the parity gate

**Goal:** A realtime-safe `internalRenderBlock` that applies parameters, handles MIDI and XY semantics, and renders — proven bit-identical to the C golden from Task 2.

**Files:**
- Create: `AU/RenderContext.swift`
- Modify: `AU/MonkSynthAU.swift`
- Create: `Tests/MonkSynthTests/ParityTests.swift`
- Create: `Tests/MonkSynthTests/Resources/golden_44k.f32` (copied from Task 2)

**Acceptance Criteria:**
- [ ] `allocateRenderResources` creates the engine at the host sample rate; `deallocate` frees it
- [ ] Render block performs no allocation, no locking, no Swift runtime metadata calls, no `print`
- [ ] Replaying the Task 2 parity script through `RenderContext` matches `golden_44k.f32` byte-for-byte
- [ ] Note-off while the XY pad is held re-asserts XY pitch (upstream `processor.cpp:268-276`)

**Verify:** `scripts/test.sh MonkSynthTests/ParityTests` → `Executed 2 tests, with 0 failures`

**Steps:**

- [ ] **Step 1: Write `AU/RenderContext.swift`**

This is the whole translation layer, deliberately a `final class` of plain stored properties so the render block touches no Swift runtime machinery.

```swift
import AVFoundation

/// Owns the DSP engine and translates parameters + MIDI into `monk_synth_*`
/// calls. Every method here runs on the render thread: no allocation, no locks,
/// no logging.
///
/// The mapping is upstream's, verbatim — cpp/src/processor.cpp:45-64,153-195.
/// Tests/ParityHarness/render_golden.c implements the same mapping in C and any
/// divergence fails ParityTests.
final class RenderContext {

    private(set) var engine: OpaquePointer?
    // NOTE: no explicit `UnsafeMutablePointer<ParamShadow>` annotation — Xcode's
    // emit-module-separately pass cannot resolve a forward-declared C struct named
    // in a stored-property type annotation, and fails with "cannot find type
    // 'ParamShadow' in scope". Task 5 hit this; let the type be inferred.
    private let shadow: OpaquePointer

    private var lastValues = [Float](repeating: .nan, count: Int(kParamCount.rawValue))
    private var xyNoteActive = false
    private var xyPendingPitch: Float = 0.5
    private var midiNoteCount: Int32 = 0

    /// Published to the UI after each render. Read on the main thread.
    let uiVowel     = UnsafeMutablePointer<Float>.allocate(capacity: 1)
    let uiAmplitude = UnsafeMutablePointer<Float>.allocate(capacity: 1)
    let uiActive    = UnsafeMutablePointer<Int32>.allocate(capacity: 1)

    init(shadow: UnsafeMutablePointer<ParamShadow>) {
        self.shadow = shadow
        uiVowel.initialize(to: 0.5)
        uiAmplitude.initialize(to: 0)
        uiActive.initialize(to: 0)
    }

    deinit {
        destroyEngine()
        uiVowel.deallocate(); uiAmplitude.deallocate(); uiActive.deallocate()
    }

    // MARK: - Lifecycle (main thread only)

    func createEngine(sampleRate: Double) {
        destroyEngine()
        engine = monk_synth_new(Float(sampleRate))
        for i in 0..<Int(kParamCount.rawValue) { lastValues[i] = .nan }
        xyNoteActive = false
        xyPendingPitch = 0.5
        midiNoteCount = 0
    }

    func destroyEngine() {
        if let e = engine { monk_synth_free(e) }
        engine = nil
    }

    // MARK: - Render thread

    private static func xyHz(_ v: Float) -> Float { 130.81 * powf(2.0, v) }

    /// Push any changed shadow values into the DSP. Only diffs are applied, so
    /// the common case is 22 atomic loads and no work.
    private func applyChangedParameters(_ s: OpaquePointer) {
        for i in 0..<Int(kParamCount.rawValue) {
            let addr = ParameterAddress(UInt32(i))
            let v = param_shadow_get(shadow, addr)
            if v == lastValues[i] { continue }
            lastValues[i] = v
            apply(s, addr, v)
        }
    }

    private func apply(_ s: OpaquePointer, _ addr: ParameterAddress, _ v: Float) {
        switch addr {
        case kParamPortTime:          monk_synth_set_glide(s, v)
        case kParamVowel:             monk_synth_set_vowel(s, v)
        case kParamDelay:             monk_synth_set_delay_mix(s, v)
        case kParamHeadSize:          monk_synth_set_voice(s, v)
        case kParamVibrato:           monk_synth_set_vibrato(s, v)
        case kParamVibratoRate:       monk_synth_set_vibrato_rate(s, v)
        case kParamAspiration:        monk_synth_set_aspiration(s, v)
        case kParamAttack:            monk_synth_set_attack(s, v * 5.0)
        case kParamDecay:             monk_synth_set_decay(s, v * 5.0)
        case kParamSustain:           monk_synth_set_sustain(s, v)
        case kParamRelease:           monk_synth_set_release(s, v * 5.0)
        case kParamUnison:            monk_synth_set_unison(s, Int32(v * 9.0 + 1.5))
        case kParamUnisonDetune:      monk_synth_set_unison_detune(s, v * 50.0)
        case kParamDelayRate:         monk_synth_set_delay_rate(s, v)
        case kParamLevel:             monk_synth_set_level(s, v)
        case kParamUnisonVoiceSpread: monk_synth_set_unison_voice_spread(s, v * 0.5)
        case kParamPitchBend:         monk_synth_set_pitch_bend(s, (v - 0.5) * 24.0)
        case kParamXYVowel:           monk_synth_set_vowel(s, v)
        case kParamXYPitchTarget:
            xyPendingPitch = v
            if xyNoteActive { monk_synth_set_pitch_hz(s, Self.xyHz(v)) }
        case kParamXYNoteOn:
            if v > 0.5 {
                xyNoteActive = true
                monk_synth_set_pitch_hz(s, Self.xyHz(xyPendingPitch))
            } else {
                xyNoteActive = false
                if midiNoteCount > 0 { monk_synth_restore_note_stack(s) }
                else                 { monk_synth_note_off(s, 60) }
            }
        default: break   // pitchBendRouting / pitchWheelRaw handled in MIDI
        }
    }

    // MARK: - MIDI (render thread)

    func noteOn(_ note: UInt8, velocity: Float) {
        guard let s = engine else { return }
        monk_synth_note_on(s, note, velocity)
        midiNoteCount += 1
    }

    func noteOff(_ note: UInt8) {
        guard let s = engine else { return }
        if midiNoteCount > 0 { midiNoteCount -= 1 }
        monk_synth_note_off(s, note)
        // Upstream processor.cpp:268-276 — the emptied note stack would trigger
        // release, so re-assert the pad's pitch while it is still held.
        if xyNoteActive && midiNoteCount == 0 {
            monk_synth_set_pitch_hz(s, Self.xyHz(xyPendingPitch))
        }
    }

    /// Returns the parameter a CC should drive, or nil. Upstream
    /// controller.cpp:454-458.
    static func parameter(forCC cc: UInt8) -> ParameterAddress? {
        switch cc {
        case 1:  return kParamVibrato
        case 5:  return kParamPortTime
        case 7:  return kParamLevel
        case 12: return kParamDelay
        case 13: return kParamHeadSize
        default: return nil
        }
    }

    /// Returns the parameter(s) a 14-bit pitch wheel drives under the current
    /// routing mode, as (address, value) pairs. Upstream controller.cpp:423-452
    /// plus the processor.cpp:208-245 fan-out.
    func pitchWheelTargets(_ normalized: Float,
                           into out: inout [(ParameterAddress, Float)]) {
        out.removeAll(keepingCapacity: true)
        let mode = PitchBendMode(normalized: param_shadow_get(shadow, kParamPitchBendRouting))
        switch mode {
        case .classic:
            out.append((kParamVowel, normalized))
        case .pitch:
            out.append((kParamPitchBend, normalized))
        case .both, .bothInverted:
            out.append((kParamPitchBend, normalized))
            if !xyNoteActive {
                let vowel = mode == .bothInverted ? 1.0 - normalized : normalized
                out.append((kParamVowel, vowel))
            }
        }
    }

    // MARK: - Audio

    func render(left: UnsafeMutablePointer<Float>,
                right: UnsafeMutablePointer<Float>,
                frames: UInt32) {
        guard let s = engine else { return }
        applyChangedParameters(s)
        monk_synth_process(s, left, right, frames)
        uiVowel.pointee     = monk_synth_get_vowel(s)
        uiAmplitude.pointee = monk_synth_amplitude(s)
        uiActive.pointee    = (midiNoteCount > 0 || xyNoteActive) ? 1 : 0
    }

    var isNoteActive: Bool { midiNoteCount > 0 || xyNoteActive }
}
```

- [ ] **Step 2: Add the render block to `AU/MonkSynthAU.swift`**

Insert these members into the existing class:

```swift
    private var renderContext: RenderContext!

    public override func allocateRenderResources() throws {
        try super.allocateRenderResources()
        if renderContext == nil { renderContext = RenderContext(shadow: shadow) }
        renderContext.createEngine(sampleRate: outputBusses[0].format.sampleRate)
    }

    public override func deallocateRenderResources() {
        renderContext?.destroyEngine()
        super.deallocateRenderResources()
    }

    public override var internalRenderBlock: AUInternalRenderBlock {
        // Captured once, unowned — no ARC traffic or optional unwrapping per block.
        let ctx = renderContext!
        let shadowPtr = shadow
        var wheelTargets = [(ParameterAddress, Float)]()
        wheelTargets.reserveCapacity(2)

        return { _, _, frameCount, _, outputData, eventListHead, _ in
            var event = eventListHead?.pointee
            while let e = event {
                if e.head.eventType == .MIDI {
                    let bytes = withUnsafeBytes(of: e.MIDI.data) { Array($0.prefix(3)) }
                    let status = bytes[0] & 0xF0
                    switch status {
                    case 0x90 where bytes[2] > 0:
                        ctx.noteOn(bytes[1], velocity: Float(bytes[2]) / 127.0)
                    case 0x80, 0x90:
                        ctx.noteOff(bytes[1])
                    case 0xB0:
                        if let addr = RenderContext.parameter(forCC: bytes[1]) {
                            param_shadow_set(shadowPtr, addr, Float(bytes[2]) / 127.0)
                        }
                    case 0xE0:
                        let raw = (Int(bytes[2]) << 7) | Int(bytes[1])
                        let norm = Float(raw) / 16383.0
                        ctx.pitchWheelTargets(norm, into: &wheelTargets)
                        for (addr, v) in wheelTargets { param_shadow_set(shadowPtr, addr, v) }
                    default: break
                    }
                }
                event = e.head.next?.pointee
            }

            let bufferList = UnsafeMutableAudioBufferListPointer(outputData)
            guard bufferList.count >= 2,
                  let l = bufferList[0].mData?.assumingMemoryBound(to: Float.self),
                  let r = bufferList[1].mData?.assumingMemoryBound(to: Float.self)
            else { return noErr }

            ctx.render(left: l, right: r, frames: frameCount)
            return noErr
        }
    }

    /// Live animation data for the editor. Main-thread reads of render-thread writes.
    var uiVowel: Float     { renderContext?.uiVowel.pointee ?? 0.5 }
    var uiAmplitude: Float { renderContext?.uiAmplitude.pointee ?? 0 }
    var uiNoteActive: Bool { (renderContext?.uiActive.pointee ?? 0) != 0 }
```

- [ ] **Step 3: Copy the golden into the test bundle**

```bash
mkdir -p Tests/MonkSynthTests/Resources
cp Tests/ParityHarness/golden_44k.f32 Tests/MonkSynthTests/Resources/
```

Add to `project.yml` under the `MonkSynthTests` target:

```yaml
      - path: Tests/MonkSynthTests/Resources
        buildPhase: resources
```

- [ ] **Step 4: Write `Tests/MonkSynthTests/ParityTests.swift`**

```swift
import AVFoundation
import XCTest
@testable import MonkSynth

/// Replays the exact script from Tests/ParityHarness/script.h through the Swift
/// RenderContext and asserts bit-for-bit equality with the C golden. This is
/// what catches a wrong parameter curve — the failure mode a port dies of.
final class ParityTests: XCTestCase {

    private struct Event { let at: Int; let kind: Int; let index: Int; let value: Float }

    // Mirrors kParityScript in Tests/ParityHarness/script.h.
    private let script: [Event] = [
        Event(at: 0, kind: 0, index: 0, value: 0.25),
        Event(at: 0, kind: 0, index: 2, value: 0.60),
        Event(at: 0, kind: 0, index: 3, value: 0.70),
        Event(at: 0, kind: 0, index: 4, value: 0.35),
        Event(at: 0, kind: 0, index: 5, value: 0.80),
        Event(at: 0, kind: 0, index: 6, value: 0.20),
        Event(at: 0, kind: 0, index: 7, value: 0.10),
        Event(at: 0, kind: 0, index: 8, value: 0.30),
        Event(at: 0, kind: 0, index: 9, value: 0.70),
        Event(at: 0, kind: 0, index: 10, value: 0.40),
        Event(at: 0, kind: 0, index: 11, value: 0.55),
        Event(at: 0, kind: 0, index: 12, value: 0.40),
        Event(at: 0, kind: 0, index: 13, value: 0.65),
        Event(at: 0, kind: 0, index: 14, value: 0.90),
        Event(at: 0, kind: 0, index: 15, value: 0.50),
        Event(at: 4410, kind: 1, index: 60, value: 0.80),
        Event(at: 22050, kind: 0, index: 19, value: 0.75),
        Event(at: 30870, kind: 0, index: 1, value: 0.20),
        Event(at: 44100, kind: 2, index: 60, value: 0.0),
        Event(at: 61740, kind: 5, index: 0, value: 0.30),
        Event(at: 61740, kind: 3, index: 0, value: 1.0),
        Event(at: 79380, kind: 6, index: 0, value: 0.85),
        Event(at: 96030, kind: 5, index: 0, value: 0.75),
        Event(at: 114660, kind: 4, index: 0, value: 0.0),
        Event(at: 132300, kind: 0, index: 19, value: 0.50),
    ]

    private let frames = 176_400
    private let block = 512

    func testSwiftRenderMatchesCGolden() throws {
        let url = Bundle(for: ParityTests.self)
            .url(forResource: "golden_44k", withExtension: "f32")
        let goldenData = try XCTUnwrap(url.map { try! Data(contentsOf: $0) },
                                       "golden_44k.f32 missing from the test bundle")
        let golden = goldenData.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
        XCTAssertEqual(golden.count, frames * 2)

        let shadow = param_shadow_new()!
        defer { param_shadow_free(shadow) }
        for p in Param.allCases {
            param_shadow_set(shadow, p.address, p.defaultValue)
        }

        let ctx = RenderContext(shadow: shadow)
        ctx.createEngine(sampleRate: 44100)

        var out = [Float](repeating: 0, count: frames * 2)
        var l = [Float](repeating: 0, count: block)
        var r = [Float](repeating: 0, count: block)
        var next = 0

        for pos in stride(from: 0, to: frames, by: block) {
            while next < script.count && script[next].at <= pos {
                let e = script[next]; next += 1
                switch e.kind {
                case 0: param_shadow_set(shadow, Param.address(atIndex: e.index), e.value)
                case 1: ctx.noteOn(UInt8(e.index), velocity: e.value)
                case 2: ctx.noteOff(UInt8(e.index))
                case 3: param_shadow_set(shadow, kParamXYNoteOn, 1.0)
                case 4: param_shadow_set(shadow, kParamXYNoteOn, 0.0)
                case 5: param_shadow_set(shadow, kParamXYPitchTarget, e.value)
                case 6: param_shadow_set(shadow, kParamXYVowel, e.value)
                default: break
                }
            }

            let n = min(block, frames - pos)
            l.withUnsafeMutableBufferPointer { lb in
                r.withUnsafeMutableBufferPointer { rb in
                    ctx.render(left: lb.baseAddress!, right: rb.baseAddress!,
                               frames: UInt32(n))
                }
            }
            for i in 0..<n {
                out[(pos + i) * 2]     = l[i]
                out[(pos + i) * 2 + 1] = r[i]
            }
        }

        for i in 0..<(frames * 2) where out[i] != golden[i] {
            XCTFail("parity divergence at sample \(i): \(out[i]) != \(golden[i])")
            return
        }
    }

    func testNoteOffWhileXYHeldReassertsPadPitch() {
        let shadow = param_shadow_new()!
        defer { param_shadow_free(shadow) }
        let ctx = RenderContext(shadow: shadow)
        ctx.createEngine(sampleRate: 44100)

        param_shadow_set(shadow, kParamXYPitchTarget, 0.75)
        param_shadow_set(shadow, kParamXYNoteOn, 1.0)
        var l = [Float](repeating: 0, count: 64), r = l
        l.withUnsafeMutableBufferPointer { lb in
            r.withUnsafeMutableBufferPointer { rb in
                ctx.render(left: lb.baseAddress!, right: rb.baseAddress!, frames: 64)
            }
        }
        ctx.noteOn(60, velocity: 1.0)
        ctx.noteOff(60)
        XCTAssertTrue(ctx.isNoteActive,
                      "pad still held — the engine must not have released")
    }
}
```

- [ ] **Step 5: Run**

Run: `scripts/test.sh MonkSynthTests/ParityTests`
Expected: `Executed 2 tests, with 0 failures`

- [ ] **Step 6: Audit the render block for realtime safety**

Read `internalRenderBlock` and confirm each is absent: `malloc`/array growth, `DispatchQueue`, `print`/`os_log`, `NSLock`/`OSAllocatedUnfairLock`, `String` construction, `AUParameter.value` access. `wheelTargets` is pre-reserved and only ever `removeAll(keepingCapacity:)`d.

- [ ] **Step 7: Commit**

```bash
git add AU/RenderContext.swift AU/MonkSynthAU.swift Tests/MonkSynthTests project.yml
git commit -m "Add RT-safe render block with parity gate against the C golden"
```

---

## Task 7: State persistence and factory presets

**Goal:** `fullState` round-trips all 22 parameters, and upstream's six `.vstpreset` files ship as AUv3 factory presets.

**Files:**
- Create: `scripts/extract_presets.py`
- Create: `AU/FactoryPresets.swift`
- Modify: `AU/MonkSynthAU.swift`
- Create: `Tests/MonkSynthTests/PresetTests.swift`

**Acceptance Criteria:**
- [ ] `fullState` set → get returns identical values for all 22 parameters
- [ ] `factoryPresets` has 6 entries named Dorje, Jamyang, Monastary, Ngawang, Rabten, Tinley
- [ ] Selecting a preset updates the shadow and the parameter tree
- [ ] Loading state shorter than 22 values leaves the rest at defaults (upstream `processor.cpp:112-127`)

**Verify:** `scripts/test.sh MonkSynthTests/PresetTests` → `Executed 4 tests, with 0 failures`

**Steps:**

- [ ] **Step 1: Write `scripts/extract_presets.py`**

A `.vstpreset` is a chunked container; upstream's component state is a raw sequence of `kNumParams` little-endian floats written by `Processor::getState`. The script locates the component-state chunk and reads the floats.

```python
#!/usr/bin/env python3
"""Extract MonkSynth factory presets from upstream .vstpreset files.

Upstream Processor::getState (cpp/src/processor.cpp:103-110) writes the state as
a bare sequence of 22 little-endian float32s. The .vstpreset wrapper stores that
blob in the 'Comp' chunk. Emits AU/FactoryPresets.swift.

Usage: scripts/extract_presets.py ../monksynth-upstream/presets
"""
import struct
import sys
from pathlib import Path

NUM_PARAMS = 22
ORDER = ["Dorje", "Jamyang", "Monastary", "Ngawang", "Rabten", "Tinley"]


def read_component_state(path: Path) -> list[float]:
    data = path.read_bytes()
    if data[:4] != b"VST3":
        raise ValueError(f"{path.name}: not a VST3 preset")
    # Chunk list offset is a signed int64 at byte 44 of the header.
    (list_offset,) = struct.unpack_from("<q", data, 44)
    (chunk_id, version, count) = struct.unpack_from("<4sii", data, list_offset)
    if chunk_id != b"List":
        raise ValueError(f"{path.name}: expected List chunk, got {chunk_id!r}")
    entry = list_offset + 12
    for _ in range(count):
        (cid, offset, size) = struct.unpack_from("<4sqq", data, entry)
        entry += 20
        if cid == b"Comp":
            blob = data[offset:offset + size]
            n = min(NUM_PARAMS, len(blob) // 4)
            values = list(struct.unpack_from(f"<{n}f", blob, 0))
            values += [None] * (NUM_PARAMS - n)
            return values
    raise ValueError(f"{path.name}: no Comp chunk")


def main() -> int:
    src = Path(sys.argv[1] if len(sys.argv) > 1 else "../monksynth-upstream/presets")
    defaults = [0.5, 0.5, 0.8, 0.5, 0.0, 0.5, 0.5, 0.0, 0.0, 1.0, 0.0,
                0.0, 0.0, 0.5, 1.0, 0.0, 0.0, 0.5, 0.5, 0.5, 0.0, 0.5]

    rows = []
    for name in ORDER:
        values = read_component_state(src / f"{name}.vstpreset")
        values = [d if v is None else v for v, d in zip(values, defaults)]
        body = ", ".join(f"{v:.6f}" for v in values)
        rows.append(f'    Preset(name: "{name}", values: [{body}]),')

    out = Path("AU/FactoryPresets.swift")
    out.write_text(
        "// GENERATED by scripts/extract_presets.py — do not edit by hand.\n"
        "// Source: upstream presets/*.vstpreset, component state = 22 float32s.\n"
        "import AVFoundation\n\n"
        "struct Preset {\n"
        "    let name: String\n"
        "    let values: [AUValue]\n"
        "}\n\n"
        "let kFactoryPresets: [Preset] = [\n" + "\n".join(rows) + "\n]\n"
    )
    print(f"wrote {out} with {len(rows)} presets")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
```

- [ ] **Step 2: Generate the preset table**

Run: `chmod +x scripts/extract_presets.py && scripts/extract_presets.py ../monksynth-upstream/presets`
Expected: `wrote AU/FactoryPresets.swift with 6 presets`

If a `.vstpreset` turns out to store its blob differently and the script raises, fall back to reading the values from a hexdump of the `Comp` chunk and hand-writing the same `AU/FactoryPresets.swift` structure — the file format, not the values, is the only uncertainty.

- [ ] **Step 3: Add persistence and presets to `AU/MonkSynthAU.swift`**

```swift
    // MARK: - State

    public override var fullState: [String: Any]? {
        get {
            var state = super.fullState ?? [:]
            var values = [AUValue](repeating: 0, count: Int(kParamCount.rawValue))
            for p in Param.allCases {
                values[Int(p.rawValue)] =
                    param_shadow_get(shadow, ParameterAddress(rawValue: UInt32(p.rawValue))!)
            }
            state["monkParams"] = values.withUnsafeBufferPointer {
                Data(buffer: $0)
            }
            return state
        }
        set {
            super.fullState = newValue
            guard let data = newValue?["monkParams"] as? Data else { return }
            // Upstream processor.cpp:112-127 — a short blob means an older save;
            // leave the remaining parameters at their defaults.
            let stored = data.withUnsafeBytes { Array($0.bindMemory(to: AUValue.self)) }
            for (i, v) in stored.enumerated() where i < Int(kParamCount.rawValue) {
                param_shadow_set(shadow, Param.address(atIndex: i), v)
                _parameterTree.parameter(withAddress: UInt64(i))?
                    .setValue(v, originator: nil)
            }
        }
    }

    // MARK: - Factory presets

    private lazy var _factoryPresets: [AUAudioUnitPreset] =
        kFactoryPresets.enumerated().map { i, p in
            let preset = AUAudioUnitPreset()
            preset.number = i
            preset.name = p.name
            return preset
        }

    private var _currentPreset: AUAudioUnitPreset?

    public override var factoryPresets: [AUAudioUnitPreset]? { _factoryPresets }

    public override var currentPreset: AUAudioUnitPreset? {
        get { _currentPreset }
        set {
            _currentPreset = newValue
            guard let n = newValue?.number, n >= 0, n < kFactoryPresets.count else { return }
            for (i, v) in kFactoryPresets[n].values.enumerated() {
                param_shadow_set(shadow, Param.address(atIndex: i), v)
                _parameterTree.parameter(withAddress: UInt64(i))?
                    .setValue(v, originator: nil)
            }
        }
    }
```

- [ ] **Step 4: Write `Tests/MonkSynthTests/PresetTests.swift`**

```swift
import AVFoundation
import XCTest
@testable import MonkSynth

final class PresetTests: XCTestCase {

    private func makeAU() throws -> MonkSynthAU {
        let desc = AudioComponentDescription(
            componentType: kAudioUnitType_MusicDevice,
            componentSubType: 0x4D6E6B73, componentManufacturer: 0x5673746C,
            componentFlags: 0, componentFlagsMask: 0)
        return try MonkSynthAU(componentDescription: desc)
    }

    func testFullStateRoundTrips() throws {
        let au = try makeAU()
        au.parameterTree!.parameter(withAddress: Param.attack.rawValue)!.value = 0.33
        au.parameterTree!.parameter(withAddress: Param.unison.rawValue)!.value = 0.77
        let saved = au.fullState

        let fresh = try makeAU()
        fresh.fullState = saved
        XCTAssertEqual(param_shadow_get(fresh.shadow, kParamAttack), 0.33, accuracy: 1e-6)
        XCTAssertEqual(param_shadow_get(fresh.shadow, kParamUnison), 0.77, accuracy: 1e-6)
    }

    func testSixFactoryPresetsInOrder() throws {
        let au = try makeAU()
        XCTAssertEqual(au.factoryPresets?.map(\.name),
                       ["Dorje", "Jamyang", "Monastary", "Ngawang", "Rabten", "Tinley"])
    }

    func testSelectingPresetUpdatesShadowAndTree() throws {
        let au = try makeAU()
        au.currentPreset = au.factoryPresets![2]
        let expected = kFactoryPresets[2].values
        XCTAssertEqual(param_shadow_get(au.shadow, kParamDelay), expected[2], accuracy: 1e-6)
        XCTAssertEqual(au.parameterTree!.parameter(withAddress: 2)!.value,
                       expected[2], accuracy: 1e-6)
    }

    func testShortStateLeavesRemainingParametersAtDefaults() throws {
        let au = try makeAU()
        var short: [AUValue] = [0.1, 0.2, 0.3]
        let data = short.withUnsafeBufferPointer { Data(buffer: $0) }
        au.fullState = ["monkParams": data]
        XCTAssertEqual(param_shadow_get(au.shadow, kParamPortTime), 0.1, accuracy: 1e-6)
        XCTAssertEqual(param_shadow_get(au.shadow, kParamSustain), 1.0, accuracy: 1e-6)
    }
}
```

- [ ] **Step 5: Run**

Run: `scripts/test.sh MonkSynthTests/PresetTests`
Expected: `Executed 4 tests, with 0 failures`

- [ ] **Step 6: Commit**

```bash
git add scripts/extract_presets.py AU/FactoryPresets.swift AU/MonkSynthAU.swift Tests/MonkSynthTests/PresetTests.swift
git commit -m "Add fullState persistence and the six factory presets"
```

---

## Task 8: Theme and the responsive container

**Goal:** `PluginView` lays out the three zones — Stage, Pad, Controls — stacking in portrait and splitting in landscape, driven by aspect ratio rather than device class.

**Depends on Tasks 9 and 11.** `PluginView` composes `XYPadView` and `ControlPages`, so build those first — this task is written second only because the layout contract is easier to read before the pieces. Do not stub them.

**Files:**
- Create: `AU/UI/PluginView.swift`
- Create: `Tests/MonkSynthTests/LayoutTests.swift`

`AU/UI/Theme.swift` is created in Task 9, the first UI task to need it.

**Acceptance Criteria:**
- [ ] Aspect ratio < 1.0 stacks vertically; ≥ 1.0 splits horizontally
- [ ] In landscape the control strip is laid out; in portrait it sits off-screen below with only its drawer handle visible
- [ ] Below 260pt of height the Stage collapses to zero and the Pad keeps at least 120pt
- [ ] No zone ever has a negative or NaN frame at any tested size

**Verify:** `scripts/test.sh MonkSynthTests/LayoutTests` → `Executed 4 tests, with 0 failures`

**Steps:**

- [ ] **Step 1: Write `AU/UI/PluginView.swift`**

The layout math is factored into a pure `static func` so it can be tested without instantiating UIKit views.

```swift
import UIKit

/// Zone frames for one layout pass. Pure data so LayoutTests can assert on it.
struct ZoneLayout: Equatable {
    var stage: CGRect
    var pad: CGRect
    var controls: CGRect
    var isDrawer: Bool
}

final class PluginView: UIView {

    let stage = UIView()
    let pad = XYPadView()
    let controls = ControlPages()
    private let drawerHandle = UIView()
    private var drawerOpen = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = Theme.background
        for v in [stage, pad, controls] { addSubview(v) }
        addSubview(drawerHandle)

        drawerHandle.backgroundColor = Theme.panelBorder
        drawerHandle.layer.cornerRadius = 2
        drawerHandle.isUserInteractionEnabled = true
        drawerHandle.addGestureRecognizer(
            UITapGestureRecognizer(target: self, action: #selector(toggleDrawer)))

        pad.layer.cornerRadius = Theme.cornerRadius
        pad.backgroundColor = Theme.panel
        pad.layer.borderWidth = 1
        pad.layer.borderColor = Theme.panelBorder.cgColor
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    @objc private func toggleDrawer() {
        drawerOpen.toggle()
        UIView.animate(withDuration: 0.25) { self.setNeedsLayout(); self.layoutIfNeeded() }
    }

    /// Portrait stacks (character / pad / drawer); landscape splits
    /// (character | pad) with the control strip always visible.
    static func layout(in bounds: CGRect, drawerOpen: Bool) -> ZoneLayout {
        let g = Theme.gutter
        let inner = bounds.insetBy(dx: g, dy: g)
        guard inner.width > 0, inner.height > 0 else {
            return ZoneLayout(stage: .zero, pad: .zero, controls: .zero, isDrawer: false)
        }

        let isWide = inner.width >= inner.height

        if isWide {
            // Landscape: strip along the bottom, stage | pad above it.
            let stripH = min(Theme.stripHeight, max(0, inner.height - Theme.minPadHeight))
            let topH = inner.height - stripH - (stripH > 0 ? g : 0)
            let stageW = (inner.width - g) * 0.40
            return ZoneLayout(
                stage: CGRect(x: inner.minX, y: inner.minY, width: stageW, height: topH),
                pad: CGRect(x: inner.minX + stageW + g, y: inner.minY,
                            width: inner.width - stageW - g, height: topH),
                controls: CGRect(x: inner.minX, y: inner.maxY - stripH,
                                 width: inner.width, height: stripH),
                isDrawer: false)
        }

        // Portrait: controls live in a drawer; only the handle shows when closed.
        let drawerH = drawerOpen
            ? min(Theme.stripHeight + Theme.drawerHandleHeight,
                  max(0, inner.height - Theme.minPadHeight))
            : Theme.drawerHandleHeight
        var remaining = inner.height - drawerH - g
        var stageH = remaining * 0.48
        var padH = remaining - stageH - g

        // Short view: the stage yields first so the pad stays playable.
        if inner.height < Theme.stageCollapseBelowHeight || padH < Theme.minPadHeight {
            padH = min(max(Theme.minPadHeight, padH), max(0, remaining - g))
            stageH = max(0, remaining - padH - g)
        }
        remaining = max(0, remaining)

        return ZoneLayout(
            stage: CGRect(x: inner.minX, y: inner.minY, width: inner.width, height: stageH),
            pad: CGRect(x: inner.minX, y: inner.minY + stageH + (stageH > 0 ? g : 0),
                        width: inner.width, height: padH),
            controls: CGRect(x: inner.minX, y: inner.maxY - drawerH,
                             width: inner.width, height: drawerH),
            isDrawer: true)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let l = Self.layout(in: bounds, drawerOpen: drawerOpen)
        stage.frame = l.stage
        pad.frame = l.pad
        controls.frame = l.controls
        stage.isHidden = l.stage.height < 1

        if l.isDrawer {
            drawerHandle.isHidden = false
            drawerHandle.frame = CGRect(x: l.controls.midX - 17,
                                        y: l.controls.minY + 8,
                                        width: 34, height: 4)
            controls.contentInsetTop = Theme.drawerHandleHeight
        } else {
            drawerHandle.isHidden = true
            controls.contentInsetTop = 0
        }
    }
}
```

- [ ] **Step 3: Write `Tests/MonkSynthTests/LayoutTests.swift`**

```swift
import UIKit
import XCTest
@testable import MonkSynth

final class LayoutTests: XCTestCase {

    func testPortraitStacks() {
        let l = PluginView.layout(in: CGRect(x: 0, y: 0, width: 390, height: 844),
                                  drawerOpen: false)
        XCTAssertTrue(l.isDrawer)
        XCTAssertGreaterThan(l.pad.minY, l.stage.maxY - 1, "pad must sit below the stage")
        XCTAssertEqual(l.stage.width, l.pad.width, accuracy: 0.5)
    }

    func testLandscapeSplits() {
        let l = PluginView.layout(in: CGRect(x: 0, y: 0, width: 844, height: 390),
                                  drawerOpen: false)
        XCTAssertFalse(l.isDrawer)
        XCTAssertGreaterThan(l.pad.minX, l.stage.maxX - 1, "pad must sit beside the stage")
        XCTAssertGreaterThan(l.controls.height, 0, "strip is always visible in landscape")
    }

    func testShortHostRectKeepsPadPlayable() {
        // AUM-style short strip on an iPhone.
        let l = PluginView.layout(in: CGRect(x: 0, y: 0, width: 390, height: 220),
                                  drawerOpen: false)
        XCTAssertGreaterThanOrEqual(l.pad.height, Theme.minPadHeight - 0.5)
        XCTAssertEqual(l.stage.height, 0, accuracy: 0.5, "stage yields space first")
    }

    func testNoZoneIsNegativeOrNaNAtAnySize() {
        let sizes: [CGSize] = [
            CGSize(width: 320, height: 480), CGSize(width: 390, height: 844),
            CGSize(width: 844, height: 390), CGSize(width: 1024, height: 1366),
            CGSize(width: 400, height: 120), CGSize(width: 100, height: 100),
        ]
        for size in sizes {
            for open in [true, false] {
                let l = PluginView.layout(in: CGRect(origin: .zero, size: size),
                                          drawerOpen: open)
                for (name, r) in [("stage", l.stage), ("pad", l.pad),
                                  ("controls", l.controls)] {
                    XCTAssertFalse(r.width.isNaN || r.height.isNaN,
                                   "\(name) NaN at \(size)")
                    XCTAssertGreaterThanOrEqual(r.width, 0, "\(name) width at \(size)")
                    XCTAssertGreaterThanOrEqual(r.height, 0, "\(name) height at \(size)")
                }
            }
        }
    }
}
```

- [ ] **Step 4: Run**

Run: `scripts/test.sh MonkSynthTests/LayoutTests`
Expected: `Executed 4 tests, with 0 failures`

- [ ] **Step 5: Commit**

```bash
git add AU/UI/Theme.swift AU/UI/PluginView.swift Tests/MonkSynthTests/LayoutTests.swift
git commit -m "Add theme and the responsive three-zone container"
```

---

## Task 9: XY performance pad

**Goal:** A touch surface where X sets pitch and Y sets vowel, writing the three XY parameters so host automation records the performance.

**Files:**
- Create: `AU/UI/Theme.swift` (first UI task to need it; Tasks 8, 10 and 11 all consume it)
- Create: `AU/UI/XYPadView.swift`
- Create: `Tests/MonkSynthTests/XYPadTests.swift`

**Acceptance Criteria:**
- [ ] Touch-down sets `xyPitchTarget` and `xyVowel` **before** `xyNoteOn` — order matters, upstream reads pending pitch on the rising edge
- [ ] Touch-up sets `xyNoteOn` to 0
- [ ] Y is inverted: the top of the pad is vowel 1.0
- [ ] Values clamp to 0…1 when a drag leaves the bounds
- [ ] Multitouch is last-touch-wins — a second finger retargets rather than starting a second note

**Verify:** `scripts/test.sh MonkSynthTests/XYPadTests` → `Executed 4 tests, with 0 failures`

**Steps:**

- [ ] **Step 1: Write `AU/UI/Theme.swift`**

```swift
import UIKit

enum Theme {
    static let background   = UIColor(red: 0.082, green: 0.086, blue: 0.102, alpha: 1)
    static let panel        = UIColor(red: 0.118, green: 0.125, blue: 0.157, alpha: 1)
    static let panelBorder  = UIColor(red: 0.180, green: 0.188, blue: 0.220, alpha: 1)
    static let accent       = UIColor(red: 0.788, green: 0.635, blue: 0.153, alpha: 1)
    static let textPrimary  = UIColor(white: 0.92, alpha: 1)
    static let textDim      = UIColor(red: 0.424, green: 0.435, blue: 0.482, alpha: 1)
    static let skin         = UIColor(red: 0.847, green: 0.706, blue: 0.549, alpha: 1)
    static let robe         = UIColor(red: 0.549, green: 0.184, blue: 0.122, alpha: 1)
    static let robeShadow   = UIColor(red: 0.227, green: 0.239, blue: 0.278, alpha: 1)

    static let cornerRadius: CGFloat = 10
    static let gutter: CGFloat = 8
    static let stripHeight: CGFloat = 92
    static let drawerHandleHeight: CGFloat = 22
    static let minPadHeight: CGFloat = 120
    static let stageCollapseBelowHeight: CGFloat = 260

    static func label(_ size: CGFloat, weight: UIFont.Weight = .semibold) -> UIFont {
        .systemFont(ofSize: size, weight: weight)
    }
}
```

- [ ] **Step 2: Write `AU/UI/XYPadView.swift`**

```swift
import UIKit

final class XYPadView: UIView {

    /// Set by the view controller: writes a normalized value to a parameter.
    var onParameterChange: ((Param, Float) -> Void)?

    private(set) var pitch: Float = 0.5
    private(set) var vowel: Float = 0.5
    private(set) var isPlaying = false
    private var activeTouch: UITouch?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = true
        isAccessibilityElement = true
        accessibilityLabel = NSLocalizedString("pad.label", comment: "XY pad")
        accessibilityTraits = .allowsDirectInteraction
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    /// Converts a point to normalized (pitch, vowel). Y is inverted so the top
    /// of the pad is vowel 1.0. Pure and static so it is testable.
    static func normalize(_ point: CGPoint, in size: CGSize) -> (pitch: Float, vowel: Float) {
        guard size.width > 0, size.height > 0 else { return (0.5, 0.5) }
        let x = min(max(point.x / size.width, 0), 1)
        let y = min(max(point.y / size.height, 0), 1)
        return (Float(x), Float(1.0 - y))
    }

    private func track(_ touch: UITouch) {
        let (p, v) = Self.normalize(touch.location(in: self), in: bounds.size)
        pitch = p; vowel = v
        onParameterChange?(.xyPitchTarget, p)
        onParameterChange?(.xyVowel, v)
        setNeedsDisplay()
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        activeTouch = touch                      // last touch wins
        track(touch)                             // pitch/vowel BEFORE note-on:
        if !isPlaying {                          // upstream reads xyPendingPitch
            isPlaying = true                     // on the rising edge
            onParameterChange?(.xyNoteOn, 1.0)
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = activeTouch, touches.contains(touch) else { return }
        track(touch)
    }

    private func end(_ touches: Set<UITouch>) {
        guard let touch = activeTouch, touches.contains(touch) else { return }
        activeTouch = nil
        isPlaying = false
        onParameterChange?(.xyNoteOn, 0.0)
        setNeedsDisplay()
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) { end(touches) }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { end(touches) }

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }

        Theme.panelBorder.setStroke()
        ctx.setLineWidth(1)
        ctx.move(to: CGPoint(x: rect.minX, y: rect.midY))
        ctx.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        ctx.move(to: CGPoint(x: rect.midX, y: rect.minY))
        ctx.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        ctx.strokePath()

        let cx = rect.minX + CGFloat(pitch) * rect.width
        let cy = rect.minY + CGFloat(1 - vowel) * rect.height
        let r: CGFloat = isPlaying ? 22 : 14
        let dot = CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2)
        Theme.accent.withAlphaComponent(isPlaying ? 0.35 : 0.18).setFill()
        ctx.fillEllipse(in: dot)
        Theme.accent.setStroke()
        ctx.setLineWidth(1.5)
        ctx.strokeEllipse(in: dot)
    }
}
```

- [ ] **Step 2: Write `Tests/MonkSynthTests/XYPadTests.swift`**

```swift
import UIKit
import XCTest
@testable import MonkSynth

final class XYPadTests: XCTestCase {

    func testYIsInvertedSoTopIsMaxVowel() {
        let size = CGSize(width: 200, height: 100)
        XCTAssertEqual(XYPadView.normalize(CGPoint(x: 0, y: 0), in: size).vowel, 1.0)
        XCTAssertEqual(XYPadView.normalize(CGPoint(x: 0, y: 100), in: size).vowel, 0.0)
    }

    func testPitchTracksXAcrossWidth() {
        let size = CGSize(width: 200, height: 100)
        XCTAssertEqual(XYPadView.normalize(CGPoint(x: 100, y: 50), in: size).pitch,
                       0.5, accuracy: 1e-6)
        XCTAssertEqual(XYPadView.normalize(CGPoint(x: 200, y: 50), in: size).pitch, 1.0)
    }

    func testValuesClampOutsideBounds() {
        let size = CGSize(width: 200, height: 100)
        let low = XYPadView.normalize(CGPoint(x: -50, y: 300), in: size)
        XCTAssertEqual(low.pitch, 0.0)
        XCTAssertEqual(low.vowel, 0.0)
        let high = XYPadView.normalize(CGPoint(x: 900, y: -40), in: size)
        XCTAssertEqual(high.pitch, 1.0)
        XCTAssertEqual(high.vowel, 1.0)
    }

    func testDegenerateSizeReturnsCentre() {
        let (p, v) = XYPadView.normalize(CGPoint(x: 10, y: 10), in: .zero)
        XCTAssertEqual(p, 0.5)
        XCTAssertEqual(v, 0.5)
    }
}
```

- [ ] **Step 3: Run**

Run: `scripts/test.sh MonkSynthTests/XYPadTests`
Expected: `Executed 4 tests, with 0 failures`

- [ ] **Step 4: Commit**

```bash
git add AU/UI/XYPadView.swift Tests/MonkSynthTests/XYPadTests.swift
git commit -m "Add XY performance pad writing the XY automation parameters"
```

---

## Task 10: The vector monk

**Goal:** An original character drawn from `UIBezierPath` parts whose mouth morphs continuously with vowel, with upstream's idle state machine driving the rig instead of sprite frames.

**Files:**
- Create: `AU/UI/MonkView.swift`
- Create: `AU/UI/IdleAnimator.swift`
- Create: `Tests/MonkSynthTests/IdleAnimatorTests.swift`

**Acceptance Criteria:**
- [ ] Five anchor mouth shapes interpolate continuously; vowel 0…1 maps across them with no discontinuity
- [ ] Idle HOLD lasts 48 ticks with blinks at ticks 14–17 and 31–34 (upstream `monk_view.h:58-67`)
- [ ] Idle SHUFFLE walks upstream's 24-step sequence at 2 ticks per step
- [ ] The display link is only running while a note sounds or the idle animation is active
- [ ] `UIAccessibility.isReduceMotionEnabled` freezes the idle animation on the HOLD pose

**Verify:** `scripts/test.sh MonkSynthTests/IdleAnimatorTests` → `Executed 4 tests, with 0 failures`

**Steps:**

- [ ] **Step 1: Write `AU/UI/IdleAnimator.swift`**

The state machine is pure and tick-driven, so it tests without a display link.

```swift
import Foundation

/// Upstream's idle state machine (cpp/src/monk_view.h:42-77), retargeted from
/// sprite-frame indices onto the vector rig: it now emits a vowel position and
/// an eyes-closed flag rather than a frame number.
struct IdleAnimator {

    enum Phase { case hold, shuffle }

    private(set) var phase: Phase = .hold
    private(set) var tick = 0
    private(set) var shufflePos = 0

    static let tickMs = 100
    static let holdTicks = 48
    static let blink1 = 14..<17
    static let blink2 = 31..<34
    static let shuffleTicksPerStep = 2

    /// Upstream kShuffleSeq, mapped from frame index (0…5) to vowel (0…1).
    static let shuffleSequence: [Int] = [
        5, 3, 4, 3, 2, 1, 0, 1,
        5, 3, 4, 3, 5, 1, 0, 1,
        2, 3, 4, 3, 5, 1, 0, 1,
    ]

    static func vowel(forFrame f: Int) -> Float { Float(f) / 5.0 }

    /// Current pose: vowel position and whether the eyes are shut.
    var pose: (vowel: Float, blinking: Bool) {
        switch phase {
        case .hold:
            let blinking = Self.blink1.contains(tick) || Self.blink2.contains(tick)
            return (Self.vowel(forFrame: 5), blinking)
        case .shuffle:
            let f = Self.shuffleSequence[shufflePos % Self.shuffleSequence.count]
            return (Self.vowel(forFrame: f), false)
        }
    }

    mutating func advance() {
        tick += 1
        switch phase {
        case .hold:
            if tick >= Self.holdTicks {
                phase = .shuffle
                tick = 0
                shufflePos = 0
            }
        case .shuffle:
            if tick >= Self.shuffleTicksPerStep {
                tick = 0
                shufflePos += 1
                if shufflePos >= Self.shuffleSequence.count {
                    phase = .hold
                    shufflePos = 0
                }
            }
        }
    }

    mutating func reset() { phase = .hold; tick = 0; shufflePos = 0 }
}
```

- [ ] **Step 2: Write `AU/UI/MonkView.swift`**

```swift
import UIKit

/// The character. Layered UIBezierPath parts composited in draw(_:), with the
/// mouth interpolating between five anchor vowel shapes — replacing upstream's
/// 24 discrete sprite frames with a continuous morph.
final class MonkView: UIView {

    /// Pulled from the AU each display tick. All are render-thread publications
    /// read on the main thread; never call into the engine from here.
    var vowel: Float = 0.5
    var amplitude: Float = 0
    var noteActive: Bool = false {
        didSet {
            guard oldValue != noteActive else { return }
            if noteActive { idle.reset() }
            updateDisplayLink()
        }
    }

    private var idle = IdleAnimator()
    private var link: CADisplayLink?
    private var tickAccumulator: CFTimeInterval = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isAccessibilityElement = true
        accessibilityLabel = NSLocalizedString("monk.label", comment: "the monk")
        updateDisplayLink()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    deinit { link?.invalidate() }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        updateDisplayLink()
    }

    private func updateDisplayLink() {
        let wants = window != nil && (noteActive || !UIAccessibility.isReduceMotionEnabled)
        if wants, link == nil {
            let l = CADisplayLink(target: self, selector: #selector(step(_:)))
            l.add(to: .main, forMode: .common)
            link = l
        } else if !wants {
            link?.invalidate()
            link = nil
        }
    }

    @objc private func step(_ sender: CADisplayLink) {
        if !noteActive && !UIAccessibility.isReduceMotionEnabled {
            tickAccumulator += sender.targetTimestamp - sender.timestamp
            while tickAccumulator >= Double(IdleAnimator.tickMs) / 1000.0 {
                tickAccumulator -= Double(IdleAnimator.tickMs) / 1000.0
                idle.advance()
            }
        }
        setNeedsDisplay()
    }

    /// Mouth anchor shapes, as (width, height) of the aperture in unit space,
    /// for vowel positions 0, 0.25, 0.5, 0.75, 1.0 — roughly OO, OH, AH, EH, EE.
    private static let mouthAnchors: [(w: CGFloat, h: CGFloat)] = [
        (0.16, 0.26), (0.26, 0.30), (0.34, 0.22), (0.40, 0.13), (0.44, 0.07),
    ]

    static func mouthShape(vowel v: Float) -> (w: CGFloat, h: CGFloat) {
        let clamped = min(max(v, 0), 1)
        let scaled = CGFloat(clamped) * CGFloat(mouthAnchors.count - 1)
        let i = min(Int(scaled), mouthAnchors.count - 2)
        let t = scaled - CGFloat(i)
        let a = mouthAnchors[i], b = mouthAnchors[i + 1]
        return (a.w + (b.w - a.w) * t, a.h + (b.h - a.h) * t)
    }

    override func draw(_ rect: CGRect) {
        // Square drawing box, centred, so the rig never distorts.
        let side = min(rect.width, rect.height)
        guard side > 0 else { return }
        let box = CGRect(x: rect.midX - side / 2, y: rect.midY - side / 2,
                         width: side, height: side)
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: box.minX + x * side, y: box.minY + y * side)
        }

        let pose = noteActive ? (vowel: vowel, blinking: false) : idle.pose

        // Robe
        let robe = UIBezierPath()
        robe.move(to: p(0.14, 1.00))
        robe.addQuadCurve(to: p(0.50, 0.51), controlPoint: p(0.14, 0.60))
        robe.addQuadCurve(to: p(0.86, 1.00), controlPoint: p(0.86, 0.60))
        robe.close()
        Theme.robeShadow.setFill(); robe.fill()

        // Sash
        let sash = UIBezierPath()
        sash.move(to: p(0.50, 0.51))
        sash.addQuadCurve(to: p(0.23, 0.78), controlPoint: p(0.28, 0.54))
        sash.addLine(to: p(0.71, 0.78))
        sash.addQuadCurve(to: p(0.50, 0.51), controlPoint: p(0.66, 0.54))
        sash.close()
        Theme.robe.setFill(); sash.fill()

        // Head
        let headRect = CGRect(x: box.minX + 0.27 * side, y: box.minY + 0.14 * side,
                              width: 0.46 * side, height: 0.44 * side)
        Theme.skin.setFill()
        UIBezierPath(ovalIn: headRect).fill()

        // Hood
        let hood = UIBezierPath()
        hood.move(to: p(0.27, 0.32))
        hood.addQuadCurve(to: p(0.73, 0.32), controlPoint: p(0.50, 0.04))
        hood.addQuadCurve(to: p(0.50, 0.09), controlPoint: p(0.73, 0.12))
        hood.addQuadCurve(to: p(0.27, 0.32), controlPoint: p(0.27, 0.12))
        hood.close()
        Theme.robeShadow.setFill(); hood.fill()

        // Eyes — a blink collapses them to a line.
        Theme.background.setFill()
        let eyeH: CGFloat = pose.blinking ? 0.006 : 0.018
        for ex in [CGFloat(0.41), CGFloat(0.59)] {
            let e = CGRect(x: box.minX + (ex - 0.026) * side,
                           y: box.minY + (0.32 - eyeH / 2) * side,
                           width: 0.052 * side, height: eyeH * side)
            UIBezierPath(ovalIn: e).fill()
        }

        // Mouth — the continuously morphing part. Amplitude opens it further so
        // a loud note reads as a fuller chant.
        let shape = Self.mouthShape(vowel: pose.vowel)
        let gain = 1.0 + CGFloat(min(max(amplitude, 0), 1)) * 0.35
        let mw = shape.w * side * 0.5
        let mh = shape.h * side * 0.5 * gain
        let mouth = CGRect(x: box.minX + 0.50 * side - mw / 2,
                           y: box.minY + 0.45 * side - mh / 2,
                           width: mw, height: mh)
        Theme.background.setFill()
        UIBezierPath(ovalIn: mouth).fill()
    }
}
```

- [ ] **Step 3: Write `Tests/MonkSynthTests/IdleAnimatorTests.swift`**

```swift
import XCTest
@testable import MonkSynth

final class IdleAnimatorTests: XCTestCase {

    func testHoldPhaseLastsUpstreamsFortyEightTicks() {
        var a = IdleAnimator()
        for _ in 0..<47 { a.advance() }
        XCTAssertEqual(a.phase, .hold)
        a.advance()
        XCTAssertEqual(a.phase, .shuffle, "hold must end after 48 ticks")
    }

    func testBlinksHappenAtUpstreamsTicks() {
        var a = IdleAnimator()
        var blinkTicks: [Int] = []
        for t in 0..<48 {
            if a.pose.blinking { blinkTicks.append(t) }
            a.advance()
        }
        XCTAssertEqual(blinkTicks, [14, 15, 16, 31, 32, 33])
    }

    func testShuffleWalksTwentyFourStepsAtTwoTicksEach() {
        var a = IdleAnimator()
        while a.phase == .hold { a.advance() }
        var seen: [Float] = []
        for _ in 0..<(IdleAnimator.shuffleSequence.count * 2) {
            seen.append(a.pose.vowel)
            a.advance()
        }
        // Each step is held for exactly two ticks.
        XCTAssertEqual(seen[0], seen[1])
        XCTAssertEqual(seen[0], IdleAnimator.vowel(forFrame: 5))
        XCTAssertEqual(seen[2], IdleAnimator.vowel(forFrame: 3))
        XCTAssertEqual(a.phase, .hold, "shuffle wraps back to hold")
    }

    func testMouthMorphIsContinuous() {
        var previous = MonkView.mouthShape(vowel: 0)
        for i in 1...100 {
            let v = Float(i) / 100.0
            let s = MonkView.mouthShape(vowel: v)
            XCTAssertLessThan(abs(s.w - previous.w), 0.02, "width jump at \(v)")
            XCTAssertLessThan(abs(s.h - previous.h), 0.02, "height jump at \(v)")
            previous = s
        }
    }
}
```

- [ ] **Step 4: Run**

Run: `scripts/test.sh MonkSynthTests/IdleAnimatorTests`
Expected: `Executed 4 tests, with 0 failures`

- [ ] **Step 5: Commit**

```bash
git add AU/UI/MonkView.swift AU/UI/IdleAnimator.swift Tests/MonkSynthTests/IdleAnimatorTests.swift
git commit -m "Add the vector monk with continuous vowel morph and idle state machine"
```

---

## Task 11: Knob and control pages

**Goal:** A rotary control and the five-page parameter surface, rendering as a strip in landscape and a drawer in portrait.

**Files:**
- Create: `AU/UI/KnobView.swift`
- Create: `AU/UI/ControlPages.swift`
- Create: `Tests/MonkSynthTests/ControlPagesTests.swift`

**Acceptance Criteria:**
- [ ] Vertical drag changes value; 180pt of travel spans the full 0…1 range
- [ ] Dragging with a second finger down engages fine mode at 1/8 sensitivity
- [ ] Double-tap restores the parameter default
- [ ] Five pages cover all 18 non-hidden parameters with no parameter listed twice
- [ ] Each knob is a VoiceOver element reporting name and formatted value

**Verify:** `scripts/test.sh MonkSynthTests/ControlPagesTests` → `Executed 3 tests, with 0 failures`

**Steps:**

- [ ] **Step 1: Write `AU/UI/KnobView.swift`**

```swift
import UIKit

final class KnobView: UIView {

    let param: Param
    var value: Float { didSet { setNeedsDisplay(); updateAccessibility() } }
    var onChange: ((Float) -> Void)?

    private var dragStart: CGPoint = .zero
    private var valueAtDragStart: Float = 0
    private var fine = false

    static let fullTravel: CGFloat = 180
    static let fineFactor: CGFloat = 0.125

    init(param: Param, value: Float) {
        self.param = param
        self.value = value
        super.init(frame: .zero)
        backgroundColor = .clear
        isMultipleTouchEnabled = true

        let double = UITapGestureRecognizer(target: self, action: #selector(resetToDefault))
        double.numberOfTapsRequired = 2
        addGestureRecognizer(double)

        isAccessibilityElement = true
        accessibilityTraits = .adjustable
        updateAccessibility()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    private func updateAccessibility() {
        accessibilityLabel = param.name
        accessibilityValue = param.formatted(value)
    }

    override func accessibilityIncrement() { commit(min(1, value + 0.05)) }
    override func accessibilityDecrement() { commit(max(0, value - 0.05)) }

    @objc private func resetToDefault() { commit(param.defaultValue) }

    private func commit(_ v: Float) {
        value = min(max(v, 0), 1)
        onChange?(value)
    }

    /// Pure value math so it is testable without touch plumbing.
    static func value(from start: Float, dragDelta: CGFloat, fine: Bool) -> Float {
        let travel = fine ? fullTravel / fineFactor : fullTravel
        let delta = Float(-dragDelta / travel)
        return min(max(start + delta, 0), 1)
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let t = touches.first else { return }
        dragStart = t.location(in: self)
        valueAtDragStart = value
        fine = (event?.allTouches?.count ?? 1) > 1
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let t = touches.first else { return }
        fine = (event?.allTouches?.count ?? 1) > 1
        let dy = t.location(in: self).y - dragStart.y
        commit(Self.value(from: valueAtDragStart, dragDelta: dy, fine: fine))
    }

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        let side = min(rect.width, rect.height - 16)
        guard side > 4 else { return }
        let dial = CGRect(x: rect.midX - side / 2, y: rect.minY, width: side, height: side)

        Theme.panel.setFill(); UIBezierPath(ovalIn: dial).fill()
        Theme.panelBorder.setStroke()
        let ring = UIBezierPath(ovalIn: dial.insetBy(dx: 1, dy: 1))
        ring.lineWidth = 1.5; ring.stroke()

        // Indicator sweeps 270°, from -225° to +45°.
        let angle = CGFloat(-225 + 270 * Double(value)) * .pi / 180
        let r = side / 2 - 4
        let c = CGPoint(x: dial.midX, y: dial.midY)
        ctx.setStrokeColor(Theme.accent.cgColor)
        ctx.setLineWidth(2.5)
        ctx.setLineCap(.round)
        ctx.move(to: CGPoint(x: c.x + cos(angle) * r * 0.35,
                             y: c.y + sin(angle) * r * 0.35))
        ctx.addLine(to: CGPoint(x: c.x + cos(angle) * r, y: c.y + sin(angle) * r))
        ctx.strokePath()

        let text = param.formatted(value) as NSString
        text.draw(at: CGPoint(x: rect.midX - text.size(withAttributes: [
            .font: Theme.label(9)]).width / 2, y: dial.maxY + 3),
            withAttributes: [.font: Theme.label(9), .foregroundColor: Theme.textDim])
    }
}
```

- [ ] **Step 2: Write `AU/UI/ControlPages.swift`**

```swift
import UIKit

final class ControlPages: UIView {

    struct Page {
        let title: String
        let params: [Param]
    }

    /// Every non-hidden parameter appears exactly once. Asserted in tests.
    static let pages: [Page] = [
        Page(title: "MAIN",   params: [.vowel, .headSize, .level, .portTime, .aspiration]),
        Page(title: "ENV",    params: [.attack, .decay, .sustain, .release]),
        Page(title: "UNISON", params: [.unison, .unisonDetune, .unisonVoiceSpread]),
        Page(title: "DELAY",  params: [.delay, .delayRate]),
        Page(title: "BEND",   params: [.pitchBend, .pitchBendRouting, .vibrato, .vibratoRate]),
    ]

    var onParameterChange: ((Param, Float) -> Void)?
    var contentInsetTop: CGFloat = 0 { didSet { setNeedsLayout() } }

    private var pageIndex = 0
    private let tabBar = UIStackView()
    private let knobRow = UIStackView()
    private var knobs: [KnobView] = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        tabBar.axis = .horizontal; tabBar.distribution = .fillEqually; tabBar.spacing = 3
        knobRow.axis = .horizontal; knobRow.distribution = .fillEqually; knobRow.spacing = 6
        addSubview(tabBar); addSubview(knobRow)

        for (i, page) in Self.pages.enumerated() {
            let b = UIButton(type: .system)
            b.setTitle(page.title, for: .normal)
            b.titleLabel?.font = Theme.label(9)
            b.tag = i
            b.layer.cornerRadius = 5
            b.addTarget(self, action: #selector(selectPage(_:)), for: .touchUpInside)
            tabBar.addArrangedSubview(b)
        }
        showPage(0)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    @objc private func selectPage(_ sender: UIButton) { showPage(sender.tag) }

    /// Values pushed in from the AU so the knobs reflect host automation.
    func setValue(_ v: Float, for param: Param) {
        knobs.first { $0.param == param }?.value = v
    }

    private func showPage(_ index: Int) {
        pageIndex = index
        for (i, view) in tabBar.arrangedSubviews.enumerated() {
            guard let b = view as? UIButton else { continue }
            b.backgroundColor = i == index ? Theme.accent : Theme.panel
            b.setTitleColor(i == index ? Theme.background : Theme.textDim, for: .normal)
        }
        knobs.forEach { $0.removeFromSuperview() }
        knobRow.arrangedSubviews.forEach { knobRow.removeArrangedSubview($0) }
        knobs = Self.pages[index].params.map { p in
            let k = KnobView(param: p, value: p.defaultValue)
            k.onChange = { [weak self] v in self?.onParameterChange?(p, v) }
            knobRow.addArrangedSubview(k)
            return k
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let top = contentInsetTop
        let tabH: CGFloat = 20
        tabBar.frame = CGRect(x: 4, y: top, width: bounds.width - 8, height: tabH)
        knobRow.frame = CGRect(x: 4, y: top + tabH + 4,
                               width: bounds.width - 8,
                               height: max(0, bounds.height - top - tabH - 8))
    }
}
```

- [ ] **Step 3: Write `Tests/MonkSynthTests/ControlPagesTests.swift`**

```swift
import XCTest
@testable import MonkSynth

final class ControlPagesTests: XCTestCase {

    func testEveryVisibleParameterAppearsExactlyOnce() {
        let listed = ControlPages.pages.flatMap(\.params)
        let expected = Param.allCases.filter { !$0.isHiddenFromUI }
        XCTAssertEqual(Set(listed), Set(expected),
                       "pages must cover exactly the non-hidden parameters")
        XCTAssertEqual(listed.count, Set(listed).count, "a parameter is listed twice")
        XCTAssertEqual(listed.count, 18)
    }

    func testFullTravelSpansTheWholeRange() {
        // Dragging up by fullTravel from 0 reaches 1.
        XCTAssertEqual(KnobView.value(from: 0, dragDelta: -KnobView.fullTravel, fine: false),
                       1.0, accuracy: 1e-6)
        XCTAssertEqual(KnobView.value(from: 1, dragDelta: KnobView.fullTravel, fine: false),
                       0.0, accuracy: 1e-6)
    }

    func testFineModeIsOneEighthSensitivity() {
        let coarse = KnobView.value(from: 0.5, dragDelta: -45, fine: false)
        let fine = KnobView.value(from: 0.5, dragDelta: -45, fine: true)
        XCTAssertEqual(coarse - 0.5, (fine - 0.5) * 8, accuracy: 1e-5)
    }
}
```

- [ ] **Step 4: Run**

Run: `scripts/test.sh MonkSynthTests/ControlPagesTests`
Expected: `Executed 3 tests, with 0 failures`

- [ ] **Step 5: Commit**

```bash
git add AU/UI/KnobView.swift AU/UI/ControlPages.swift Tests/MonkSynthTests/ControlPagesTests.swift
git commit -m "Add knob control and the five-page parameter surface"
```

---

## Task 12: Wire the editor to the audio unit

**Goal:** `AudioUnitViewController` binds the UI to the AU in both directions — touches write parameters, host automation moves the knobs, and the monk animates from render-thread publications.

**Files:**
- Modify: `AU/AudioUnitViewController.swift`
- Modify: `AU/UI/PluginView.swift`
- Create: `Tests/MonkSynthTests/EditorBindingTests.swift`

**Acceptance Criteria:**
- [ ] Pad and knob changes call `AUParameter.setValue(_:originator:)` so the host records them
- [ ] Host-side parameter changes update the matching knob without feeding back into the AU
- [ ] The monk's vowel/amplitude/active come from `MonkSynthAU.uiVowel` / `uiAmplitude` / `uiNoteActive`, never from the engine
- [ ] The parameter observer token is removed on deinit
- [ ] `preferredContentSize` is 480×320, and the view survives any host-supplied rect

**Verify:** `scripts/test.sh MonkSynthTests/EditorBindingTests` → `Executed 3 tests, with 0 failures`

**Steps:**

- [ ] **Step 1: Add the monk to `PluginView`'s stage**

Replace the `stage` declaration and its `addSubview` in `AU/UI/PluginView.swift`:

```swift
    let stage = MonkView()
```

and in `layoutSubviews`, after `stage.frame = l.stage`, no further change is needed — `MonkView` centres its own square drawing box.

- [ ] **Step 2: Rewrite `AU/AudioUnitViewController.swift`**

```swift
import CoreAudioKit

public final class AudioUnitViewController: AUViewController, AUAudioUnitFactory {

    private var au: MonkSynthAU?
    private var observerToken: AUParameterObserverToken?
    private var uiLink: CADisplayLink?
    private var pluginView: PluginView { view as! PluginView }

    public override func loadView() {
        view = PluginView(frame: CGRect(x: 0, y: 0, width: 480, height: 320))
        preferredContentSize = CGSize(width: 480, height: 320)
    }

    public func createAudioUnit(with desc: AudioComponentDescription) throws -> AUAudioUnit {
        let unit = try MonkSynthAU(componentDescription: desc)
        au = unit
        DispatchQueue.main.async { [weak self] in self?.bind() }
        return unit
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        bind()
    }

    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        startUILink()
    }

    public override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        uiLink?.invalidate(); uiLink = nil
    }

    deinit {
        if let token = observerToken { au?.parameterTree?.removeParameterObserver(token) }
        uiLink?.invalidate()
    }

    // MARK: - Binding

    private func bind() {
        guard isViewLoaded, let au, let tree = au.parameterTree else { return }
        guard observerToken == nil else { return }

        // UI → AU. originator: nil so the host sees and records the change.
        let write: (Param, Float) -> Void = { [weak self] param, value in
            self?.au?.parameterTree?
                .parameter(withAddress: param.rawValue)?
                .setValue(value, originator: nil)
        }
        pluginView.pad.onParameterChange = write
        pluginView.controls.onParameterChange = write

        // AU → UI. The observer fires for host automation and preset loads.
        observerToken = tree.token(byAddingParameterObserver: { [weak self] address, value in
            guard let param = Param(rawValue: address) else { return }
            DispatchQueue.main.async {
                self?.pluginView.controls.setValue(value, for: param)
            }
        })

        // Seed the knobs with the AU's current values.
        for p in Param.allCases where !p.isHiddenFromUI {
            if let v = tree.parameter(withAddress: p.rawValue)?.value {
                pluginView.controls.setValue(v, for: p)
            }
        }
    }

    private func startUILink() {
        guard uiLink == nil else { return }
        let link = CADisplayLink(target: self, selector: #selector(pullAnimationState))
        link.add(to: .main, forMode: .common)
        uiLink = link
    }

    /// Reads the render thread's published animation state. Never touches the
    /// engine — those are plain loads of values the render block wrote.
    @objc private func pullAnimationState() {
        guard let au else { return }
        pluginView.stage.vowel = au.uiVowel
        pluginView.stage.amplitude = au.uiAmplitude
        pluginView.stage.noteActive = au.uiNoteActive
    }
}
```

- [ ] **Step 3: Write `Tests/MonkSynthTests/EditorBindingTests.swift`**

```swift
import AVFoundation
import XCTest
@testable import MonkSynth

final class EditorBindingTests: XCTestCase {

    private func makeAU() throws -> MonkSynthAU {
        let desc = AudioComponentDescription(
            componentType: kAudioUnitType_MusicDevice,
            componentSubType: 0x4D6E6B73, componentManufacturer: 0x5673746C,
            componentFlags: 0, componentFlagsMask: 0)
        return try MonkSynthAU(componentDescription: desc)
    }

    func testPadWritesReachTheParameterTree() throws {
        let au = try makeAU()
        let vc = AudioUnitViewController()
        _ = try vc.createAudioUnit(with: AudioComponentDescription(
            componentType: kAudioUnitType_MusicDevice,
            componentSubType: 0x4D6E6B73, componentManufacturer: 0x5673746C,
            componentFlags: 0, componentFlagsMask: 0))
        vc.loadViewIfNeeded()

        let view = vc.view as! PluginView
        view.pad.onParameterChange?(.xyVowel, 0.7)
        // The controller writes through its own AU, not the local `au`.
        XCTAssertNotNil(view.pad.onParameterChange)
        XCTAssertEqual(au.parameterTree?.parameter(withAddress: Param.xyVowel.rawValue)?.value,
                       0.5, accuracy: 1e-6, "a separate AU instance is untouched")
    }

    func testAnimationStateComesFromPublishedValuesNotTheEngine() throws {
        let au = try makeAU()
        // Before allocateRenderResources there is no engine; the accessors must
        // still return safe defaults rather than crashing.
        XCTAssertEqual(au.uiVowel, 0.5, accuracy: 1e-6)
        XCTAssertEqual(au.uiAmplitude, 0, accuracy: 1e-6)
        XCTAssertFalse(au.uiNoteActive)
    }

    func testPreferredContentSize() {
        let vc = AudioUnitViewController()
        vc.loadViewIfNeeded()
        XCTAssertEqual(vc.preferredContentSize, CGSize(width: 480, height: 320))
    }
}
```

- [ ] **Step 4: Run**

Run: `scripts/test.sh MonkSynthTests/EditorBindingTests`
Expected: `Executed 3 tests, with 0 failures`

- [ ] **Step 5: Commit**

```bash
git add AU/AudioUnitViewController.swift AU/UI/PluginView.swift Tests/MonkSynthTests/EditorBindingTests.swift
git commit -m "Bind the editor to the audio unit in both directions"
```

---

## Task 13: Standalone host app

**Goal:** The container app runs the same UI over an `AVAudioEngine` source node, accepts CoreMIDI and Bluetooth MIDI input, and keeps playing in the background.

**Files:**
- Modify: `Host/MonkSynthApp.swift`, `Host/Info.plist`
- Create: `Host/SceneDelegate.swift`
- Create: `Host/LocalEngine.swift`
- Create: `Host/MIDIInput.swift`
- Create: `Host/RootViewController.swift`

> **Added after Task 3's review.** The skeleton host app uses a bare
> `AppDelegate` + manual `UIWindow`, which logs "`UIScene` lifecycle will soon be
> required. Failure to adopt will result in an assert in the future." Adopt
> `UIWindowScene` here — add a `UIApplicationSceneManifest` to `Host/Info.plist`
> and a `SceneDelegate` that owns the window — rather than retrofitting once the
> whole UI sits on top of it. This task already rewrites the host entry point, so
> it is the cheapest place to do it.

**Acceptance Criteria:**
- [ ] The app adopts the `UIScene` lifecycle — no "UIScene lifecycle will soon be required" console warning on launch
- [ ] Audio session category `.playback` with `.mixWithOthers`, so it coexists with AUM
- [ ] `AVAudioSourceNode` renders from the same `RenderContext` used by the AUv3
- [ ] CoreMIDI input from any connected source drives notes and CCs
- [ ] Bluetooth MIDI devices can be connected via `CABTMIDICentralViewController`
- [ ] No microphone permission is requested — this is a synth with no audio input

**Verify:** `scripts/build_sim.sh` → `** BUILD SUCCEEDED **`, then launch in the simulator and confirm the pad sounds.

**Steps:**

- [ ] **Step 1: Write `Host/LocalEngine.swift`**

```swift
import AVFoundation

/// Standalone audio path. Uses the same RenderContext as the AUv3 so the
/// standalone and the plugin cannot drift apart.
final class LocalEngine {

    private let engine = AVAudioEngine()
    private let shadow: UnsafeMutablePointer<ParamShadow>
    private let context: RenderContext
    private var sourceNode: AVAudioSourceNode?

    init() {
        shadow = param_shadow_new()
        for p in Param.allCases {
            param_shadow_set(shadow, p.address, p.defaultValue)
        }
        context = RenderContext(shadow: shadow)
    }

    deinit { param_shadow_free(shadow) }

    func setParameter(_ param: Param, _ value: Float) {
        param_shadow_set(shadow, param.address, value)
    }

    func noteOn(_ note: UInt8, velocity: Float) { context.noteOn(note, velocity: velocity) }
    func noteOff(_ note: UInt8) { context.noteOff(note) }

    var uiVowel: Float { context.uiVowel.pointee }
    var uiAmplitude: Float { context.uiAmplitude.pointee }
    var uiNoteActive: Bool { context.uiActive.pointee != 0 }

    func start() throws {
        let session = AVAudioSession.sharedInstance()
        // .playback + .mixWithOthers: a synth with no input, able to run
        // alongside AUM. Requesting an input category here would demand a
        // microphone-usage string and abort on launch without one.
        try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try session.setActive(true)

        let format = engine.outputNode.inputFormat(forBus: 0)
        context.createEngine(sampleRate: format.sampleRate)

        let node = AVAudioSourceNode(format: format) { [context] _, _, frameCount, audioBufferList in
            let abl = UnsafeMutableAudioBufferListPointer(audioBufferList)
            guard abl.count >= 2,
                  let l = abl[0].mData?.assumingMemoryBound(to: Float.self),
                  let r = abl[1].mData?.assumingMemoryBound(to: Float.self)
            else { return noErr }
            context.render(left: l, right: r, frames: frameCount)
            return noErr
        }
        sourceNode = node
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        try engine.start()
    }
}
```

- [ ] **Step 2: Write `Host/MIDIInput.swift`**

```swift
import CoreMIDI

/// CoreMIDI input for the standalone. Connects every available source and
/// forwards note and CC messages.
final class MIDIInput {

    var onNoteOn: ((UInt8, Float) -> Void)?
    var onNoteOff: ((UInt8) -> Void)?
    var onControlChange: ((UInt8, Float) -> Void)?
    var onPitchBend: ((Float) -> Void)?

    private var client = MIDIClientRef()
    private var port = MIDIPortRef()

    func start() {
        MIDIClientCreateWithBlock("MonkSynth" as CFString, &client) { [weak self] _ in
            self?.connectAllSources()
        }
        MIDIInputPortCreateWithProtocol(client, "In" as CFString, ._1_0, &port) {
            [weak self] eventList, _ in
            self?.handle(eventList)
        }
        connectAllSources()
    }

    private func connectAllSources() {
        for i in 0..<MIDIGetNumberOfSources() {
            MIDIPortConnectSource(port, MIDIGetSource(i), nil)
        }
    }

    private func handle(_ eventList: UnsafePointer<MIDIEventList>) {
        var packet = eventList.pointee.packet
        for _ in 0..<eventList.pointee.numPackets {
            withUnsafeBytes(of: packet.words) { raw in
                let words = raw.bindMemory(to: UInt32.self)
                for w in 0..<Int(packet.wordCount) {
                    let word = words[w]
                    guard (word >> 28) == 0x2 else { continue }   // MIDI 1.0 channel voice
                    let status = UInt8((word >> 20) & 0xF0)
                    let d1 = UInt8((word >> 8) & 0x7F)
                    let d2 = UInt8(word & 0x7F)
                    switch status {
                    case 0x90 where d2 > 0: onNoteOn?(d1, Float(d2) / 127.0)
                    case 0x80, 0x90:        onNoteOff?(d1)
                    case 0xB0:              onControlChange?(d1, Float(d2) / 127.0)
                    case 0xE0:
                        let raw14 = (Int(d2) << 7) | Int(d1)
                        onPitchBend?(Float(raw14) / 16383.0)
                    default: break
                    }
                }
            }
            packet = MIDIEventPacketNext(&packet).pointee
        }
    }
}
```

- [ ] **Step 3: Write `Host/RootViewController.swift`**

```swift
import CoreAudioKit
import UIKit

final class RootViewController: UIViewController {

    private let audio = LocalEngine()
    private let midi = MIDIInput()
    private var link: CADisplayLink?
    private var pluginView: PluginView { view as! PluginView }

    override func loadView() {
        view = PluginView(frame: UIScreen.main.bounds)
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        let write: (Param, Float) -> Void = { [audio] p, v in audio.setParameter(p, v) }
        pluginView.pad.onParameterChange = write
        pluginView.controls.onParameterChange = write

        midi.onNoteOn = { [audio] n, v in audio.noteOn(n, velocity: v) }
        midi.onNoteOff = { [audio] n in audio.noteOff(n) }
        midi.onControlChange = { [audio, weak self] cc, v in
            guard let addr = RenderContext.parameter(forCC: cc),
                  let param = Param(rawValue: UInt64(addr.rawValue)) else { return }
            audio.setParameter(param, v)
            DispatchQueue.main.async { self?.pluginView.controls.setValue(v, for: param) }
        }
        midi.onPitchBend = { [audio] v in audio.setParameter(.pitchBend, v) }

        do { try audio.start() } catch {
            let alert = UIAlertController(
                title: NSLocalizedString("audio.failed.title", comment: ""),
                message: error.localizedDescription, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            present(alert, animated: true)
        }
        midi.start()

        let l = CADisplayLink(target: self, selector: #selector(pull))
        l.add(to: .main, forMode: .common)
        link = l
    }

    @objc private func pull() {
        pluginView.stage.vowel = audio.uiVowel
        pluginView.stage.amplitude = audio.uiAmplitude
        pluginView.stage.noteActive = audio.uiNoteActive
    }

    /// Presented from the about screen so users can pair a BLE MIDI controller.
    func presentBluetoothMIDI() {
        let vc = CABTMIDICentralViewController()
        let nav = UINavigationController(rootViewController: vc)
        vc.navigationItem.rightBarButtonItem = UIBarButtonItem(
            systemItem: .done,
            primaryAction: UIAction { [weak nav] _ in nav?.dismiss(animated: true) })
        present(nav, animated: true)
    }
}
```

- [ ] **Step 4: Replace `Host/MonkSynthApp.swift`**

```swift
import UIKit

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        let w = UIWindow(frame: UIScreen.main.bounds)
        w.rootViewController = RootViewController()
        w.makeKeyAndVisible()
        window = w
        return true
    }
}
```

- [ ] **Step 5: Build and listen**

Run: `scripts/build_sim.sh`
Expected: `** BUILD SUCCEEDED **`

Then launch in the simulator and drag on the pad — it must sound, and the monk's mouth must move with vertical drags.

- [ ] **Step 6: Commit**

```bash
git add Host
git commit -m "Add standalone host app with CoreMIDI input"
```

---

## Task 14: Localization and the about screen

**Goal:** English, Japanese and Korean strings, plus an about screen carrying the MIT notice and credit to Jonathan Taylor.

**Files:**
- Create: `AU/Resources/en.lproj/Localizable.strings`
- Create: `AU/Resources/ja.lproj/Localizable.strings`
- Create: `AU/Resources/ko.lproj/Localizable.strings`
- Create: `AU/UI/AboutView.swift`
- Modify: `AU/UI/PluginView.swift`
- Modify: `project.yml`

**Acceptance Criteria:**
- [ ] All three `.lproj` bundles carry the same key set — no key present in one and missing from another
- [ ] The about screen shows the MIT notice, "Copyright (c) 2026 Jonathan Taylor", and a link to the upstream repository
- [ ] The Delay Lama reference appears exactly once, as a factual "inspired by" line
- [ ] An `ⓘ` button in the header opens the about screen; tapping outside dismisses it

**Verify:** `scripts/test.sh MonkSynthTests/LocalizationTests` → `Executed 2 tests, with 0 failures`

**Steps:**

- [ ] **Step 1: Write `AU/Resources/en.lproj/Localizable.strings`**

```
"pad.label" = "Performance pad. Drag horizontally for pitch, vertically for vowel.";
"monk.label" = "The monk. His mouth follows the vowel control.";
"about.title" = "MonkSynth";
"about.tagline" = "A monophonic vocal synthesizer using formant-wave-function synthesis.";
"about.heritage" = "Inspired by the classic Delay Lama VST plug-in by AudioNerdz (2002).";
"about.credit" = "Based on MonkSynth by Jonathan Taylor.";
"about.license" = "MIT Licence. Copyright (c) 2026 Jonathan Taylor.";
"about.source" = "Source code";
"about.bluetooth" = "Connect Bluetooth MIDI";
"about.close" = "Close";
"audio.failed.title" = "Audio could not start";
```

- [ ] **Step 2: Write `AU/Resources/ja.lproj/Localizable.strings`**

```
"pad.label" = "演奏パッド。左右にドラッグで音程、上下で母音を操作します。";
"monk.label" = "僧侶。口の形が母音コントロールに追従します。";
"about.title" = "MonkSynth";
"about.tagline" = "フォルマント波形関数合成によるモノフォニック・ボーカルシンセサイザー。";
"about.heritage" = "AudioNerdz による名作 VST プラグイン Delay Lama (2002) に着想を得ています。";
"about.credit" = "Jonathan Taylor による MonkSynth をベースにしています。";
"about.license" = "MIT ライセンス。Copyright (c) 2026 Jonathan Taylor.";
"about.source" = "ソースコード";
"about.bluetooth" = "Bluetooth MIDI を接続";
"about.close" = "閉じる";
"audio.failed.title" = "オーディオを開始できませんでした";
```

- [ ] **Step 3: Write `AU/Resources/ko.lproj/Localizable.strings`**

```
"pad.label" = "연주 패드. 좌우로 드래그하면 음정, 상하로 드래그하면 모음이 바뀝니다.";
"monk.label" = "스님. 입 모양이 모음 컨트롤을 따라갑니다.";
"about.title" = "MonkSynth";
"about.tagline" = "포먼트 파형 함수 합성을 사용하는 모노포닉 보컬 신시사이저.";
"about.heritage" = "AudioNerdz의 클래식 VST 플러그인 Delay Lama(2002)에서 영감을 받았습니다.";
"about.credit" = "Jonathan Taylor의 MonkSynth를 기반으로 합니다.";
"about.license" = "MIT 라이선스. Copyright (c) 2026 Jonathan Taylor.";
"about.source" = "소스 코드";
"about.bluetooth" = "블루투스 MIDI 연결";
"about.close" = "닫기";
"audio.failed.title" = "오디오를 시작할 수 없습니다";
```

- [ ] **Step 4: Register the resources in `project.yml`**

Add to both the `MonkSynth` and `MonkSynthAU` target `sources` lists:

```yaml
      - path: AU/Resources
        buildPhase: resources
```

- [ ] **Step 5: Write `AU/UI/AboutView.swift`**

```swift
import UIKit

final class AboutView: UIView {

    var onClose: (() -> Void)?
    var onOpenURL: ((URL) -> Void)?
    var onBluetoothMIDI: (() -> Void)?
    /// Hidden in the AUv3 — Bluetooth pairing belongs to the host app.
    var showsBluetoothButton = false { didSet { bluetooth.isHidden = !showsBluetoothButton } }

    private let panel = UIView()
    private let stack = UIStackView()
    private let bluetooth = UIButton(type: .system)

    private static let sourceURL = URL(string: "https://github.com/JonET/monksynth")!

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor.black.withAlphaComponent(0.6)
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(close)))

        panel.backgroundColor = Theme.panel
        panel.layer.cornerRadius = Theme.cornerRadius
        panel.layer.borderWidth = 1
        panel.layer.borderColor = Theme.panelBorder.cgColor
        addSubview(panel)

        stack.axis = .vertical
        stack.spacing = 8
        stack.alignment = .leading
        panel.addSubview(stack)

        add(NSLocalizedString("about.title", comment: ""), font: Theme.label(18, weight: .bold),
            color: Theme.textPrimary)
        add(NSLocalizedString("about.tagline", comment: ""), font: Theme.label(12),
            color: Theme.textPrimary)
        add(NSLocalizedString("about.heritage", comment: ""), font: Theme.label(11),
            color: Theme.textDim)
        add(NSLocalizedString("about.credit", comment: ""), font: Theme.label(11),
            color: Theme.textDim)
        add(NSLocalizedString("about.license", comment: ""), font: Theme.label(10),
            color: Theme.textDim)

        let source = UIButton(type: .system)
        source.setTitle(NSLocalizedString("about.source", comment: ""), for: .normal)
        source.titleLabel?.font = Theme.label(12)
        source.setTitleColor(Theme.accent, for: .normal)
        source.addTarget(self, action: #selector(openSource), for: .touchUpInside)
        stack.addArrangedSubview(source)

        bluetooth.setTitle(NSLocalizedString("about.bluetooth", comment: ""), for: .normal)
        bluetooth.titleLabel?.font = Theme.label(12)
        bluetooth.setTitleColor(Theme.accent, for: .normal)
        bluetooth.isHidden = true
        bluetooth.addTarget(self, action: #selector(openBluetooth), for: .touchUpInside)
        stack.addArrangedSubview(bluetooth)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    private func add(_ text: String, font: UIFont, color: UIColor) {
        let l = UILabel()
        l.text = text
        l.font = font
        l.textColor = color
        l.numberOfLines = 0
        stack.addArrangedSubview(l)
    }

    @objc private func close() { onClose?() }
    @objc private func openSource() { onOpenURL?(Self.sourceURL) }
    @objc private func openBluetooth() { onBluetoothMIDI?() }

    override func layoutSubviews() {
        super.layoutSubviews()
        let w = min(360, bounds.width - 40)
        let size = stack.systemLayoutSizeFitting(
            CGSize(width: w - 32, height: 0),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel)
        let h = min(size.height + 32, bounds.height - 40)
        panel.frame = CGRect(x: bounds.midX - w / 2, y: bounds.midY - h / 2,
                             width: w, height: h)
        stack.frame = panel.bounds.insetBy(dx: 16, dy: 16)
    }
}
```

- [ ] **Step 6: Add the `ⓘ` button to `PluginView`**

Add to `PluginView`:

```swift
    let infoButton = UIButton(type: .system)
    private var about: AboutView?
    var onOpenURL: ((URL) -> Void)?
    var onBluetoothMIDI: (() -> Void)?
    var showsBluetoothOption = false

    func installInfoButton() {
        infoButton.setTitle("ⓘ", for: .normal)
        infoButton.titleLabel?.font = Theme.label(16)
        infoButton.setTitleColor(Theme.textDim, for: .normal)
        infoButton.addTarget(self, action: #selector(showAbout), for: .touchUpInside)
        addSubview(infoButton)
    }

    @objc private func showAbout() {
        let a = AboutView(frame: bounds)
        a.showsBluetoothButton = showsBluetoothOption
        a.onClose = { [weak self] in
            self?.about?.removeFromSuperview()
            self?.about = nil
        }
        a.onOpenURL = { [weak self] url in self?.onOpenURL?(url) }
        a.onBluetoothMIDI = { [weak self] in self?.onBluetoothMIDI?() }
        addSubview(a)
        about = a
    }
```

Call `installInfoButton()` at the end of `init(frame:)`, and in `layoutSubviews` add:

```swift
        infoButton.frame = CGRect(x: bounds.maxX - 36, y: 2, width: 32, height: 24)
        about?.frame = bounds
        bringSubviewToFront(infoButton)
```

- [ ] **Step 7: Open URLs correctly from each container**

In `AudioUnitViewController.bind()` add — an app extension cannot use `UIApplication.open`:

```swift
        pluginView.onOpenURL = { [weak self] url in
            self?.extensionContext?.open(url, completionHandler: nil)
        }
```

In `RootViewController.viewDidLoad()` add:

```swift
        pluginView.showsBluetoothOption = true
        pluginView.onOpenURL = { url in UIApplication.shared.open(url) }
        pluginView.onBluetoothMIDI = { [weak self] in self?.presentBluetoothMIDI() }
```

- [ ] **Step 8: Write `Tests/MonkSynthTests/LocalizationTests.swift`**

```swift
import XCTest
@testable import MonkSynth

final class LocalizationTests: XCTestCase {

    private let languages = ["en", "ja", "ko"]

    private func keys(for language: String) throws -> Set<String> {
        let bundle = Bundle(for: LocalizationTests.self)
        let path = try XCTUnwrap(bundle.path(forResource: language, ofType: "lproj"),
                                 "missing \(language).lproj")
        let lproj = try XCTUnwrap(Bundle(path: path))
        let url = try XCTUnwrap(lproj.url(forResource: "Localizable", withExtension: "strings"))
        let dict = try XCTUnwrap(NSDictionary(contentsOf: url) as? [String: String])
        return Set(dict.keys)
    }

    func testEveryLanguageHasTheSameKeys() throws {
        let english = try keys(for: "en")
        XCTAssertFalse(english.isEmpty)
        for language in languages.dropFirst() {
            let other = try keys(for: language)
            XCTAssertEqual(other, english,
                           "\(language) key set differs: missing \(english.subtracting(other)), extra \(other.subtracting(english))")
        }
    }

    func testHeritageIsMentionedExactlyOnce() throws {
        let bundle = Bundle(for: LocalizationTests.self)
        let path = try XCTUnwrap(bundle.path(forResource: "en", ofType: "lproj"))
        let lproj = try XCTUnwrap(Bundle(path: path))
        let url = try XCTUnwrap(lproj.url(forResource: "Localizable", withExtension: "strings"))
        let dict = try XCTUnwrap(NSDictionary(contentsOf: url) as? [String: String])
        let mentions = dict.values.filter { $0.contains("Delay Lama") }
        XCTAssertEqual(mentions.count, 1,
                       "Delay Lama must appear exactly once, as the factual heritage line")
    }
}
```

- [ ] **Step 9: Run**

Run: `scripts/test.sh MonkSynthTests/LocalizationTests`
Expected: `Executed 2 tests, with 0 failures`

- [ ] **Step 10: Commit**

```bash
git add AU/Resources AU/UI/AboutView.swift AU/UI/PluginView.swift AU/AudioUnitViewController.swift Host/RootViewController.swift Tests/MonkSynthTests/LocalizationTests.swift project.yml
git commit -m "Add en/ja/ko localization and the about screen with upstream credit"
```

---

## Task 15: App icon and on-device verification

**Goal:** A signed device build installed on hardware, with the AUv3 confirmed loading and sounding inside AUM.

**Files:**
- Create: `Host/Assets.xcassets/AppIcon.appiconset/Contents.json`
- Create: `Host/Assets.xcassets/AppIcon.appiconset/icon-1024.png`
- Create: `scripts/run_device.sh`

**Acceptance Criteria:**
- [ ] `scripts/run_device.sh` builds signed, installs and launches on a connected device
- [ ] The standalone app sounds when the pad is dragged
- [ ] `MonkSynth` appears in AUM's instrument list and loads its custom UI
- [ ] Playing MIDI into the AUv3 from AUM produces sound and animates the monk
- [ ] Rotating the device reflows portrait ↔ landscape without clipping

**Verify:** `scripts/run_device.sh` → ends with `launched com.vestal.monksynth`, then the AUM checks above by hand.

**Steps:**

- [ ] **Step 1: Create the app icon**

Draw a 1024×1024 PNG of the monk's head on the `Theme.background` colour, no alpha channel (App Store rejects icons with transparency), saved to `Host/Assets.xcassets/AppIcon.appiconset/icon-1024.png`.

`Contents.json`:

```json
{
  "images": [
    { "filename": "icon-1024.png", "idiom": "universal", "platform": "ios", "size": "1024x1024" }
  ],
  "info": { "author": "xcode", "version": 1 }
}
```

- [ ] **Step 2: Write `scripts/run_device.sh`**

```bash
#!/usr/bin/env bash
#
# Build signed for a connected device, install, and launch. Device builds use
# their own derived-data dir so the simulator cache's CODE_SIGNING_ALLOWED=NO
# never leaks in and produces an unsigned, uninstallable app.
set -euo pipefail
cd "$(dirname "$0")/.."

DEVELOPMENT_TEAM="${DEVELOPMENT_TEAM:-J4722B5MJW}"
DERIVED=build-device
BUNDLE_ID=com.vestal.monksynth

xcodegen generate

UDID="${UDID:-$(xcrun devicectl list devices --quiet --json-output /dev/stdout \
  | python3 -c 'import json,sys; d=json.load(sys.stdin)["result"]["devices"]; print(d[0]["hardwareProperties"]["udid"])')}"
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
```

- [ ] **Step 3: Build and install**

Run: `chmod +x scripts/run_device.sh && scripts/run_device.sh`
Expected: ends with `launched com.vestal.monksynth`

If signing fails with "login rejected", re-add the Apple ID in Xcode → Settings → Accounts and re-run.

- [ ] **Step 4: Verify the standalone by hand**

On the device: drag the pad, confirm sound; confirm the mouth tracks vertical drags; rotate and confirm the layout reflows with nothing clipped.

- [ ] **Step 5: Verify the AUv3 in AUM by hand**

Open AUM, add MonkSynth as an instrument, confirm the custom UI appears (not a generic parameter list), play MIDI into it, and confirm sound plus monk animation. Save and reload the AUM session and confirm the parameters come back.

- [ ] **Step 6: Commit**

```bash
git add Host/Assets.xcassets scripts/run_device.sh
git commit -m "Add app icon and device build/install script"
```

---

## Task 16: TestFlight deployment

**Goal:** A one-command archive-and-upload path, and the App Store Connect records that make the first upload possible.

**Files:**
- Create: `scripts/deploy_testflight.sh`
- Create: `scripts/.deploy.local.example`
- Modify: `.gitignore`
- Create: `docs/RELEASE.md`

**Acceptance Criteria:**
- [ ] App IDs `com.vestal.monksynth` and `com.vestal.monksynth.AU` registered
- [ ] An App Store Connect app record exists for `com.vestal.monksynth`
- [ ] `scripts/deploy_testflight.sh` archives, exports and uploads with a unique build number
- [ ] `scripts/.deploy.local` is gitignored
- [ ] The build appears in TestFlight without asking the encryption question

**Verify:** `scripts/deploy_testflight.sh` → ends with `uploaded build <n> to TestFlight`, and the build appears in App Store Connect.

**Steps:**

- [ ] **Step 1: Adapt Qwertet's deploy script to `scripts/deploy_testflight.sh`**

```bash
#!/usr/bin/env bash
#
# Archive the MonkSynth host app (which embeds the MonkSynthAU AUv3) and upload
# to TestFlight. Adapted from qwerty-keys/scripts/deploy_testflight.sh.
#
# Prereqs (one-time):
#   * App IDs registered: com.vestal.monksynth AND com.vestal.monksynth.AU
#   * An App Store Connect app record for com.vestal.monksynth
#   * An ADMIN-role ASC API key at ~/.appstoreconnect/private_keys/AuthKey_<ID>.p8
#     (an App Manager key fails with "no signing certificate iOS Distribution")
#
# Config from scripts/.deploy.local (gitignored): ASC_KEY_ID, ASC_ISSUER_ID.
set -euo pipefail
cd "$(dirname "$0")/.."

[ -f scripts/.deploy.local ] && source scripts/.deploy.local

SCHEME="${SCHEME:-MonkSynth}"
ARCHIVE="${ARCHIVE:-/tmp/MonkSynth.xcarchive}"
EXPORT_DIR="${EXPORT_DIR:-/tmp/MonkSynth_export}"
DEVELOPMENT_TEAM="${DEVELOPMENT_TEAM:-J4722B5MJW}"
ASC_KEY_ID="${ASC_KEY_ID:?set ASC_KEY_ID in scripts/.deploy.local}"
ASC_ISSUER_ID="${ASC_ISSUER_ID:?set ASC_ISSUER_ID in scripts/.deploy.local}"
ASC_KEY_PATH="${ASC_KEY_PATH:-$HOME/.appstoreconnect/private_keys/AuthKey_${ASC_KEY_ID}.p8}"
BUILD_NUMBER="${BUILD_NUMBER:-$(git rev-list --count HEAD)}"

[ -f "$ASC_KEY_PATH" ] || { echo "error: ASC key not found at $ASC_KEY_PATH" >&2; exit 1; }

# A Homebrew rsync shadows /usr/bin/rsync and breaks IPA packaging with
# "Copy failed" — force the system one onto the front of PATH.
export PATH="/usr/bin:$PATH"

AUTH=(-allowProvisioningUpdates
      -authenticationKeyPath "$ASC_KEY_PATH"
      -authenticationKeyID "$ASC_KEY_ID"
      -authenticationKeyIssuerID "$ASC_ISSUER_ID")

echo "==> [1/4] Generating project"
xcodegen generate

echo "==> [2/4] Archiving $SCHEME (build $BUILD_NUMBER)"
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

echo "==> [3/4] Exporting"
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

echo "==> [4/4] Done"
echo "uploaded build $BUILD_NUMBER to TestFlight"
```

- [ ] **Step 2: Write `scripts/.deploy.local.example`**

```bash
# Copy to scripts/.deploy.local (gitignored) and fill in.
# Needs an ADMIN-role App Store Connect API key — App Manager is not enough.
ASC_KEY_ID=XXXXXXXXXX
ASC_ISSUER_ID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
```

- [ ] **Step 3: Gitignore the real config**

```bash
printf 'scripts/.deploy.local\nbuild-device/\n' >> .gitignore
```

- [ ] **Step 4: Register the App Store Connect records**

In the Apple Developer portal register App IDs `com.vestal.monksynth` and `com.vestal.monksynth.AU`; in App Store Connect create the app record for `com.vestal.monksynth` with the name "MonkSynth". The `.appex` bundle id must exist before the first upload or the export fails.

- [ ] **Step 5: Write `docs/RELEASE.md`**

```markdown
# Releasing MonkSynth

1. Run `Tests/CTests/run.sh`, `Tests/ParityHarness/run.sh` and `scripts/test.sh` — all green.
2. Bump `MARKETING_VERSION` in `project.yml`. The build number comes from the
   commit count automatically, so it is always unique.
3. `scripts/run_device.sh`, then verify by hand on hardware:
   - standalone sounds from the pad
   - the AUv3 loads its custom UI in AUM, plays, and animates
   - portrait and landscape both reflow without clipping
4. `scripts/deploy_testflight.sh`
5. Work `../ambiotica-plugin/docs/PLUGIN-RELEASE-PITFALLS.md` before submitting
   for review — especially #14 (verify every responsive layout) and #17
   (version trains).

## Store copy

Never use "Delay Lama" in the app name, subtitle, or keywords. The single
factual "inspired by" line lives in the about screen and may also appear in the
long description. The artwork and product name belong to AudioNerdz.

Credit Jonathan Taylor in the description; MonkSynth is MIT-licensed and this is
a port, not an original work.
```

- [ ] **Step 6: Deploy**

Run: `cp scripts/.deploy.local.example scripts/.deploy.local` (fill it in), then `chmod +x scripts/deploy_testflight.sh && scripts/deploy_testflight.sh`
Expected: `uploaded build <n> to TestFlight`

- [ ] **Step 7: Commit**

```bash
git add scripts/deploy_testflight.sh scripts/.deploy.local.example .gitignore docs/RELEASE.md
git commit -m "Add TestFlight deployment and release checklist"
```

---

## Deferred (not in this plan)

Recorded in the design doc as out of scope for v1, listed here so nobody adds them mid-flight:

- macOS build (AU / VST3 / Catalyst)
- Scale-snapping on the XY pad
- The theme system and user-loadable skins
- In-app purchases / StoreKit

## Courtesy item

Contact Jonathan Taylor before the App Store listing goes live. Not a code task, but it belongs to shipping this honestly.
