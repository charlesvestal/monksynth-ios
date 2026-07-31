# Selectable characters — design

**Date:** 2026-07-31
**Status:** approved
**Follows:** `2026-07-30-monksynth-ios-port-design.md`

Ship five selectable characters instead of a single fixed monk.

## Decisions

| Question | Decision |
|---|---|
| Roster | Monk, fish, unicorn, little girl, old man |
| Default | Monk |
| Custom import | **Out of scope for now** — bundled and baked only |
| Character structure | A background/body plus a set of mouth shapes |
| Selection storage | `fullState`, not an `AUParameter` |
| Picker | Tap the character to cycle |
| Sequencing | System first; art iterated afterwards with the render harness |

## Why no import (and why that matters)

An AUv3 extension is sandboxed and cannot reach the Files app, so importing
would have to happen in the host app and cross to the extension through an
**app group container**. That entitlement was deliberately removed during the
port: nothing consumed it and it reproducibly failed `xcodebuild archive` with
"Provisioning profile doesn't include the App Groups capability". Keeping
import out of scope keeps that hazard closed. If import is ever added, register
the group in the Developer portal *first*.

## On the monk

The roster deliberately makes the monk one option among five rather than the
product's sole face. The concern raised was the objectification of a religious
figure — a robed Buddhist monk as a puppet you make vocalise by dragging a
finger reads differently in 2026 than it did in 2002. It stays because it is
upstream's identity, the app's name, and the Delay Lama lineage; it is no
longer the only thing the instrument can be. Revisit if it still sits wrong.

## Architecture

```
protocol Character {
    var id: String { get }          // stable, persisted in fullState
    var displayName: String { get } // shown briefly when cycling
    func drawBody(in stage: CGRect)
    func mouthShape(vowel: Float) -> (w: CGFloat, h: CGFloat)
    func drawEyes(in stage: CGRect, blinking: Bool)
    var mouthCentre: (fx: CGFloat, fy: CGFloat) { get }
    var mouthBoxFraction: CGFloat { get }
}
```

`MonkView` becomes `CharacterView` — a renderer that owns animation and
delegates appearance. Everything already built stays put and works for every
character unchanged:

- `IdleAnimator` — upstream's HOLD/blink/SHUFFLE state machine
- `quantisedVowel` — 24 discrete frames, because stepped motion is the point
- display-link gating, Reduce Motion, the detach-when-collapsed behaviour
- the published-value data flow from the render thread

Only appearance is per-character.

## Selection

Stored in `fullState` under `characterID`, defaulting to `monk` when absent or
unrecognised — so an old session, or one saved after a character is renamed,
degrades to the default rather than to a blank stage.

Not an `AUParameter`: it is cosmetic, and a host automating "which character"
would be strange. It still travels with sessions and presets via `fullState`.

## Picker

Tapping the character advances to the next and briefly overlays its name. No
new chrome, works at every size including the AUM strip where there is no room
for a control, and the character is the most obviously tappable thing on
screen. The tap must not fight the pad: they are separate views.

## Out of scope

- Importing custom characters (see above)
- Per-character mouth *timing* — every character uses the same 24-frame
  quantisation and the same idle state machine
- Changing the app icon (still the monk, matching the default)
