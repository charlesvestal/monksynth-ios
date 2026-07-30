# MonkSynth iOS — port design

**Date:** 2026-07-30
**Status:** approved

Port [JonET/monksynth](https://github.com/JonET/monksynth) — a monophonic FOF vocal
synthesizer in the spirit of AudioNerdz's Delay Lama — to iOS as a native Swift
AUv3 instrument plus standalone host app, for App Store release.

## Decisions

| Question | Decision |
|---|---|
| Destination | App Store release under `com.vestal.*`, via TestFlight |
| Visual identity | Original animated character (no Delay Lama artwork ships) |
| Art pipeline | Vector rig, composited and interpolated in code |
| Feature scope | Full parity: unison, ADSR, vibrato/glide/aspiration, pitch-bend routing, en/ja/ko |
| Layout | Portrait stacks; landscape splits |
| Implementation | Native Swift / UIKit AUv3 — no JUCE |
| Naming | Ships as "MonkSynth", crediting Jonathan Taylor; contact him first |
| Heritage | One factual "inspired by Delay Lama" line; not in title, subtitle, or keywords |

## Why native Swift rather than JUCE

The obvious path was a JUCE port modelled on `ambiotica-plugin` / `chordism-ios`,
which would also have thrown in a macOS AU/VST3 build for free. It was rejected
because the two halves of a native harness already exist in this portfolio:

- **`qwerty-keys` (Qwertet)** — XcodeGen `project.yml` with app + app-extension +
  preview targets, an `AUAudioUnit` with `AUParameterTree` and `fullState`,
  custom-drawn UIKit plugin UI with a `Theme`, C-into-Swift bridging already proven
  (`tsf.h` / `tsf_impl.c` → `LocalSynth.swift`), `scripts/deploy_testflight.sh`, and
  the `AppStore/` screenshot and metadata pipeline.
- **`CV-12` (Punchline)** — an `aumu` instrument AUv3 with a real
  `internalRenderBlock` (`CV12AU/Common/Audio Unit/CV12AUAudioUnit.swift:183`),
  bridging header, and Apple's parameter-address header pattern.

Qwertet's AU is a MIDI processor with no DSP in the extension; CV-12 supplies
exactly that missing piece. So the usual cost of going native — hand-writing AUv3
boilerplate and a release pipeline — has already been paid twice.

**Accepted trade-off:** no macOS build. A Mac version later means Mac Catalyst or a
separate JUCE target. In exchange, UIKit + Core Graphics is a better home for the
vector character rig than `juce::Path`, and native multitouch, VoiceOver and a
small binary come along.

## What ports and what does not

Upstream is MIT (Copyright (c) 2026 Jonathan Taylor). The notice ships in the
about screen.

**Ports verbatim — `dsp/`, 1,345 lines of pure C.** `synth.c`, `voice.c`, `delay.c`
depend on nothing but `<math.h>`, `<stdlib.h>`, `<string.h>`, `<stdint.h>`,
`<stdbool.h>`. The engine is a single flat struct whose only allocation is a
`calloc` in `monk_synth_new` (`dsp/synth.c:38`), freed in `monk_synth_free`
(`dsp/synth.c:68`), so `monk_synth_process` is allocation-free and realtime-safe
as written.

**Does not port — `cpp/`, 5,140 lines of VST3 SDK + VSTGUI.** VSTGUI has no iOS
path and iOS loads only AUv3. Processor, controller, XY pad, sprite-sheet monk
view, i18n plumbing and the `editor.uidesc` are all rebuilt.

**Dropped entirely.** Every PNG in `cpp/resources/` is a 67-byte 1×1 placeholder;
the real Delay Lama look is extracted at runtime from the original AudioNerdz DLL
by `dll_extractor.cpp`. That artwork is copyrighted freeware — it cannot ship in an
App Store binary, and directing users to fetch a Windows DLL is a dead end on iOS.
So `theme_manager`, `dll_extractor` and the first-launch `setup_view` are cut
(~500 lines), and the app ships an original character instead.

**Reference only.** Parameter ranges, curves, units and CC routing are lifted from
`cpp/src/controller.cpp:566-660` and `cpp/src/processor.cpp`. This is where a port
silently drifts from the original sound, which is what the parity gate exists to
prevent.

## Repository layout

```
monksynth-ios/
  project.yml                  XcodeGen: MonkSynth (app) + MonkSynthAU (appex)
  dsp/                         vendored VERBATIM from upstream — never edited here
    synth.c/h  voice.c/h  delay.c/h  synth_internal.h
  AU/
    Info.plist                 type aumu, subtype Mnks, manufacturer Vstl
    MonkSynthAU.swift          AUAudioUnit: param tree, fullState, render block
    MonkSynth-Bridging-Header.h
    ParameterAddresses.h       Apple's shadow-array pattern (as in CV-12)
    Params.swift               the 22 params, ranges from controller.cpp
    UI/
      PluginView.swift         responsive three-zone container
      MonkView.swift           vector character rig
      XYPadView.swift
      ControlPages.swift
      Theme.swift
    Resources/                 Localizable.strings — en, ja, ko
  Host/                        standalone: same UI + AVAudioEngine + CoreMIDI/BLE in
  Tests/ParityTests/           golden-render gate + ported DSP unit tests
  scripts/  sync_dsp.sh · deploy_testflight.sh
  AppStore/                    lifted from Qwertet's pipeline
  docs/
```

The AUv3 extension is the product; the host app embeds it and compiles the same
`AU/` sources with a few exclusions, which is exactly how Qwertet's `project.yml`
is arranged.

`dsp/` is read-only in this repo. `sync_dsp.sh` re-pulls from an upstream checkout,
so DSP bugs get fixed upstream and pulled back rather than patched locally. That
keeps the parity gate meaningful and keeps the door open to contributing fixes to
JonET.

## Audio architecture

One `MonkSynthEngine*` per AU instance: `monk_synth_new(sampleRate)` in
`allocateRenderResources` (where the sample rate is finally known),
`monk_synth_free` in `deallocateRenderResources`.

`internalRenderBlock` drains the host's MIDI event list, translates note on/off,
pitch bend and CC 1 (vibrato), 5 (glide), 7 (volume), 12 (delay), 13 (voice) into
`monk_synth_*` calls, then makes one `monk_synth_process(l, r, frames)` call. No
allocation, no locks, no I/O on the render thread.

Parameters reach the render thread through a C shadow array of atomics keyed by
`ParameterAddress` — the render block never reads `AUParameter.value` directly.

The XY pad writes the same three parameters upstream uses — `XYNoteOn`,
`XYVowel`, `XYPitchTarget` (`cpp/src/plugin_cids.h:32-34`) — so touch performance
is host-automatable and recordable rather than a UI-only side channel.

### UI data flow

The render thread owns the engine, so the UI must **not** call
`monk_synth_get_vowel()`, `get_pitch_normalized()`, `amplitude()` or `is_active()`
directly — that would be a data race. After each `monk_synth_process` the render
block publishes vowel, amplitude and note-active into atomics; `MonkView` reads
only those, driven by a `CADisplayLink` that idles when nothing is sounding.

## UI design

### Responsive container

`PluginView` holds three zones — Stage (character), Pad, Controls — and one
`ControlPages` component that renders two ways rather than two separate layouts:

| Aspect | Stage + Pad | Controls |
|---|---|---|
| Portrait / tall | stacked vertically | pull-up drawer |
| Landscape / wide | side by side | always-visible strip |

The breakpoint is aspect ratio, not device class, because an AUv3 host hands the
plugin an arbitrary rect — AUM can give a wide, short strip on an iPhone. Below a
minimum height the Stage yields space first: the pad must stay playable even when
the monk gets cropped.

### MonkView — the vector rig

Layered `UIBezierPath` parts — robe, hood, head, eyes, mouth — composited in
`draw(_:)`, with the mouth the only continuously-morphing element. Five anchor
mouth shapes (the classic A/E/I/O/U positions) with the vowel parameter
interpolating control points between them, replacing upstream's 24 discrete sprite
frames. Smoother than the original, and resolution-independent from iPhone SE to
iPad Pro.

Idle animation ports the state machine in `cpp/src/monk_view.h` but drives the rig
rather than frame indices: HOLD for ~4.8s with blinks at ~1.45s and ~3.1s lasting
~300ms, then SHUFFLE through the 24-step vowel sequence at ~200ms/step. Upstream's
`kShuffleSeq` is already a list of vowel positions, so it maps onto the rig
directly. Gated on Reduce Motion, as `ambiotica-plugin` does.

### XYPadView

X = pitch target, Y = vowel. Touch-down is note on, release is note off. The engine
is monophonic, so multitouch is last-touch-wins with legato — which is what the
existing note stack already does.

### ControlPages

18 user-facing parameters across five pages — Main, Envelope, Unison, Delay, Bend.
(Of upstream's 22: three are XY-pad channels and `PitchWheelRaw` is a hidden
routing hub, leaving 16 knobs plus `PitchBend` and `PitchBendRouting`.)
The knob supports vertical drag, a fine mode, double-tap-to-default and VoiceOver.
Units come straight from upstream, including the Delay Lama jokes: portamento in
*Hours*, voice in *cm* of head size.

### Localization and presets

`strings_en.h` / `strings_ja.h` / `strings_ko.h` become `Localizable.strings` in
three lexicons. The 6 upstream `.vstpreset` files are parsed once, offline, into a
Swift table exposed as AUv3 factory presets.

## Testing

- **Parity gate.** A C harness renders a fixed MIDI-and-parameter script through
  `dsp/` and asserts bit-for-bit equality against a golden captured from upstream's
  tree. This converts "did I map the parameters correctly?" from a listening
  judgment into a failing test. Same pattern as `ambiotica-plugin`'s 44.1kHz parity
  gate (pitfall #13).
- **DSP unit tests.** Upstream's `cpp/tests/test_synth.c`, `test_voice.c`,
  `test_delay.c` ported to an XCTest target.
- **Realtime safety.** Assert no allocation, locks or I/O inside the render block.
- **Layout.** Verify every responsive breakpoint, not just the default
  (pitfall #14) — including a deliberately short AUv3 host rect.

## Release

- Qwertet's `scripts/deploy_testflight.sh` and `AppStore/` pipeline.
- Team `J4722B5MJW`, iOS 16.0 floor, `TARGETED_DEVICE_FAMILY 1,2`.
- Pre-declare `ITSAppUsesNonExemptEncryption=false` so TestFlight stops asking.
- Bump `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` before every upload.
- App Store Connect records for `com.vestal.monksynth` and the `.AU` appex bundle
  id must exist before the first upload.
- Work `ambiotica-plugin/docs/PLUGIN-RELEASE-PITFALLS.md` before shipping.

## Out of scope for v1

- macOS build (AU / VST3 / Catalyst).
- Scale-snapping on the XY pad — an obvious iOS-native win, but not in the
  original; parity ships first.
- The theme system and user-loadable skins.
- In-app purchases; the app is paid-up-front or free with no StoreKit code.

## Open items

- Contact Jonathan Taylor as a courtesy before listing.
- Author the vector rig; the character's actual look will be iterated visually
  during implementation.
- `/Users/charlesvestal/github/monksynth-ios` becomes a symlink to the ExtFS
  working copy, matching the `schwung-clap` convention.
