# MonkSynth for iOS

[![MonkSynth UI UPdate](https://img.youtube.com/vi/kme24M9vaYA/0.jpg)](https://www.youtube.com/watch?v=kme24M9vaYA)

An iOS **AUv3 instrument** and standalone app built on
[MonkSynth](https://github.com/JonET/monksynth) by Jonathan Taylor — a
monophonic vocal synthesizer using formant-wave-function (FOF) synthesis,
itself an homage to the classic **Delay Lama** VST plug-in by AudioNerdz (2002).

MonkSynth is offered completely free of charge. If you enjoy it, you are kindly
requested to make a donation at [savetibet.org](https://www.savetibet.org).

- Upstream (desktop VST3/AU): **Jonathan Taylor** — <https://github.com/JonET/monksynth>
- iOS port: **Charles Vestal** — <https://charles.pizza>

## What it is

- **AUv3 instrument** (`aumu` / `Mnks` / `Vstl`) that loads in AUM, GarageBand,
  Logic and other iOS hosts, plus a **standalone app** that embeds it.
- A **playable scene** — the character sings on its own drawn stage, and the
  whole scene is the XY pad: drag for pitch (X) and vowel (Y). The engine is
  monophonic with a 16-deep note stack, so overlapping notes retune rather than
  retrigger, and releasing the top note falls back to the one still held.
- **Twelve characters**, one preset each, each with its own scene and accent
  colour. The character's mouth animates with the vowel parameter, and
  choosing a character loads its voice.
- **User presets** — save a patch with a name and the current character's face.
  Stored in a shared App Group container, so the standalone app and the AUv3
  extension see one bank.
- **MIDI**: notes (omni, all channels), CC 1 / 5 / 7 / 12 / 13 mapped to
  vibrato / portamento / level / delay / head size, and a 14-bit pitch wheel
  with upstream's four routing modes. The standalone also takes CoreMIDI and
  Bluetooth MIDI.
- Localized **en / ja / ko**. iOS 16+, universal.

## Architecture

Upstream's `dsp/` is vendored **verbatim and read-only** — pure C, no platform
dependencies. `scripts/sync_dsp.sh` re-pulls it from an upstream checkout; DSP
bugs get fixed upstream and synced down, never patched here.

Above it:

| | |
|---|---|
| `AU/RenderContext.swift` | realtime-safe MIDI + parameter → DSP translation |
| `AU/ParameterShadow.{h,c}` | lock-free `_Atomic float` array the render thread reads |
| `AU/MonkSynthAU.swift` | `AUAudioUnit`: parameter tree, `fullState`, presets |
| `AU/UI/` | responsive editor, scenes and XY pad, drawn characters, knobs |
| `Host/` | standalone app: `AVAudioEngine`, CoreMIDI, Bluetooth MIDI |

The render block does no allocation, no locking and no logging, and never
touches `AUParameter` — parameters reach it through the atomic shadow array.

### The parity gate

The riskiest part of any port like this is silently changing how the instrument
*sounds*. Upstream applies specific curves when pushing normalized parameters
into the DSP (`attack × 5`, `unison = (int)(v × 9 + 1.5)`,
`pitchBend = (v − 0.5) × 24`), and a wrong constant produces a synth that still
works, still sounds plausible, and simply isn't MonkSynth. You cannot hear it.

So `Tests/ParityHarness/` renders a fixed MIDI-and-parameter script through the
C engine and freezes the output as a golden. `ParityTests` replays the identical
script through the Swift path and asserts **bit-for-bit equality**:

```bash
Tests/ParityHarness/run.sh     # golden matches (352800 samples)
```

Perturbing a single curve by 0.02% fails it.

## Building

Requires Xcode and [XcodeGen](https://github.com/yonadev/xcodegen).

```bash
scripts/build_sim.sh                  # simulator build, unsigned
scripts/test.sh                       # full XCTest suite
Tests/CTests/run.sh                   # upstream's C DSP unit tests
Tests/ParityHarness/run.sh            # bit-exact audio parity gate

DEVELOPMENT_TEAM=XXXXXXXXXX scripts/run_device.sh   # build, install, launch
```

`MonkSynth.xcodeproj` is generated from `project.yml` and is not committed.

See [`docs/RELEASE.md`](docs/RELEASE.md) for the release checklist, and
[`docs/CHARACTER-ART.md`](docs/CHARACTER-ART.md) if you want to supply your own
character artwork — characters can be image-backed (a body image plus mouth
frames) without writing any Swift.

## Licence

MIT, following upstream. Copyright (c) 2026 Jonathan Taylor. See
[LICENSE](LICENSE).

"Delay Lama" is AudioNerdz's product name and their artwork is theirs; none of
it ships here. The characters in this port are original.
