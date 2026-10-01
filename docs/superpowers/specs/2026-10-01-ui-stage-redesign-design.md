# UI pass: the stage is the instrument, and twelve redrawn characters

Date: 2026-10-01

## Problem

The UI reads as a default dark iOS panel: grey pills, small plain knobs, an
empty XY-pad box that takes half the screen, and characters floating on
nothing. The characters themselves are inconsistent — some bust-framed and
cropped by the stage edge (monk, cow, cat), Little Girl a tiny full figure,
Fish/Ghost/Pizza at their own scales — and several mouths barely change
between OO and EE (Ghost, Pizza, Old Man, Punk), which is the one thing a
Delay Lama homage has to sell.

## Direction (decided)

- **Stage/scene.** Each character performs in its own small illustrated
  scene, and the scene *is* the XY pad.
- **Full redesign** of all twelve characters.
- **Bold sticker cartoon** style for characters and scenes: thick ink
  outlines, flat fills, one hard-edged shadow tone, big heads on small
  bodies. Chosen because it is the style code-drawn Core Graphics can hit
  most reliably — no gradient lighting to get muddy, outlines hide shape
  seams, and it stays legible at the 375×180 AUM strip.

Out of scope: DSP, parameters, presets/persistence, the Schwung back-ports
(stuck bend on routing change, pressure → routing). Those are a separate
change.

## 1. Art kit — `AU/UI/Toon.swift`

One small drawing vocabulary every character and scene uses, so the twelve
read as one set.

- `Toon.ink` — the outline colour (near-black warm, not pure black).
- `Toon.line(_ stage: CGRect, _ weight: Weight)` — outline width as a
  fraction of stage width; three weights (`.bold` for silhouettes,
  `.medium` for interior features, `.fine` for details). No character picks
  its own widths.
- `Toon.shape(_ path:, fill:, shadow:, outline:)` — fills `path`, then
  clips to it and fills a shadow tone using a caller-supplied shadow path
  (the hard-edged "lit from upper-left" crescent), then strokes the
  outline. Shadow tone is derived from the fill via `UIColor.adjusted`
  (existing helper) so palettes stay one colour per part.
- `Toon.highlight(...)` — the single small specular dot/streak on glossy
  parts (eyes, nose, horn). Optional per part.

### Framing rule (all twelve)

In the unit-square stage `CharacterView` already uses:

- Ground line at `fy = 0.96`; the body is cropped by it (bust framing).
- Head centre at roughly `fy = 0.40`, head width about `0.46` of the
  stage — big-head proportions. Each character may vary within ±0.06 for
  silhouette, but the eye line sits in `0.34...0.42` for all.
- Nothing outside `fx 0.04...0.96` and `fy 0.04...0.96`, so the bold
  outline never clips at the stage edge.

These are encoded as constants in `Toon.Frame` and checked by a test that
draws each character into an offscreen context and asserts no opaque pixel
lands outside the safe box and that the opaque bounding box's height/width
fall within tolerances.

### Mouth — `AU/UI/ToonMouth.swift`

Replaces the default dark-oval `drawMouth` for every drawn character.

- Five anchors across vowel 0…1: **OO** (small puckered round), **OH**
  (round, medium), **AH** (tall open, tongue visible), **EH** (wide, mid
  open, tongue + top teeth), **EE** (wide slit, top and bottom teeth).
  `ToonMouth.shape(vowel:)` interpolates width, height, corner pull, lip
  thickness, tongue and teeth visibility between adjacent anchors. It stays
  continuous; `CharacterView.quantisedVowel` still does the 24-frame
  stepping and the amplitude swell is still applied on top.
- Parts drawn in order: cavity (dark), tongue (clipped to cavity), teeth
  (clipped), lips/outline.
- Per-character `ToonMouth.Style`: centre, scale, lip colour, and a variant
  — `.lips` (coloured lip ring), `.muzzle` (mouth set on a snout patch:
  cow, dog, unicorn, cat), or `.bare` (cavity and ink outline only: ghost,
  pizza, fish).
- Size target: at AH the mouth's height is at least 0.16 of the stage; at
  EE its width is at least 0.24. Tested by measuring `shape(vowel:)` at the
  anchors for every character, plus an OO-vs-EE aspect-ratio difference
  test so no mouth can collapse back into "barely changes".

### Faces react

`Character` gets an `expression` input alongside `blinking`:
`struct Expression { blinking: Bool; loudness: CGFloat /* 0...1, stepped */; vowel: Float }`.
`drawEyes` becomes `drawFace(in:expression:)` — eyes plus brows/cheeks —
and brows lift with loudness, eyes squint slightly at EE. Same stepping as
the mouth so it moves in frames, not glides. Reduce Motion behaviour is
unchanged (frozen HOLD pose).

`SpriteCharacter` (image-based) keeps its own eye/mouth frames and ignores
the expression beyond `blinking`.

## 2. The twelve

Same `id`s, voices, roster order and display names (no persistence change).
Each file is rewritten against the kit. One-line briefs:

| id | Character | Silhouette idea | Mouth | Scene |
|---|---|---|---|---|
| monk | Monk | round shaved head, saffron/maroon robe over one shoulder, prayer beads | lips | Himalayan peaks, prayer flags, low sun |
| fish | Fish | goldfish facing camera, fan fins, big glossy eyes | bare | underwater, bubbles, kelp |
| unicorn | Unicorn | white head, spiral gold horn, rainbow mane | muzzle | pastel hills, clouds, rainbow |
| girl | Little Girl | bust (no longer full figure), pigtail buns, collar dress | lips | park, tree, kite |
| oldman | Old Man | bald dome, huge white beard and brows, cardigan | lips set in beard | living room: lamp, window |
| cow | Cow | wide head, patches, horns, pink muzzle, bell | muzzle | pasture, fence, barn |
| firefighter | Fire Fighter | helmet with badge, yellow coat with reflective band | lips | brick wall, hydrant |
| punk | Punk | green mohawk, studded leather jacket, piercings | lips | stage with amp stack, spotlights |
| dog | Dog | floppy ears, big nose, collar tag | muzzle | backyard, doghouse |
| pizza | Pizza | slice with crust "hat", pepperoni cheeks | bare | checkered tablecloth, candle |
| ghost | Ghost | sheet ghost, wavy hem, rosy cheeks | bare | night graveyard, moon |
| cat | Cat | big ears, whiskers, striped, tail curling into frame | muzzle | windowsill at night, moon |

Every character must pass the framing and mouth tests above, and get a
render-sheet review (see Verification).

## 3. Scenes and the playable stage

### Palette

Each `Character` provides a `palette: Palette`:
`accent` (UI highlight), `skyTop`, `skyBottom`, `ground`, `groundShadow`,
`ink` (defaults to `Toon.ink`). The whole UI recolours from this on
character change (see section 4).

### Backdrop

`Character` gains `func drawBackdrop(in rect: CGRect, stage: CGRect)`. `rect` is the full
(non-square) scene area; `stage` is where the character's square sits, so
props can avoid it. Backdrops are flat sky (two-stop vertical gradient —
the only gradient in the system), horizon, ground band at the stage's
ground line, and two or three sticker props. Wide scenes extend the sky and
ground to fill; props are anchored to the scene edges. A default
implementation draws sky + ground from `palette` only (used by
`SpriteCharacter`/`UserCharacter` via their face's character).

### `StageView` replaces the separate stage + pad zones

New `AU/UI/StageView.swift`, a container with three layers:

1. `BackdropView` — draws `character.drawBackdrop`. Redraws only on
   character change or resize, not per frame.
2. `CharacterView` (existing, unchanged responsibilities) — the square
   stage anchored bottom-centre, sized to the scene height (capped so it
   never exceeds ~70% of a wide scene's width). Still non-interactive.
3. `XYPadView` (existing) as a transparent overlay covering the whole
   scene. It keeps its parameter-writing behaviour exactly (pitch/vowel
   before note-on, last-touch-wins). Its drawing changes: no box, no
   crosshair; instead a touch marker (sticker ring in `accent` with a
   shadow) while touching, faint pitch ticks along the ground line, and a
   slim OO·OH·AH·EH·EE scale on the right edge. When idle, a one-line hint
   "touch to sing" fades in after the first launch only until first touch
   (stored in `UserDefaults`; AU and standalone each keep their own).

`ZoneLayout` changes: `stage` and `pad` are replaced by a single `scene`
frame plus a `showsCharacter: Bool` (false where the stage used to
collapse — the scene stays playable, only the character hides). The
existing open/closed drawer, header, safe-area and AUM-strip rules carry
over unchanged; `LayoutTests` are updated to the new zone names and keep
every existing invariant (handle travels, selector never hits info button,
strip floor, nothing in the home-indicator band).

Accessibility: the scene keeps `XYPadView`'s existing accessibility
element and label; the character remains non-accessible.

## 4. Controls and chrome

- `Theme` becomes static tokens plus a `Theme.current: Palette` the
  chrome reads; `PluginView` sets it on character change and calls a
  `applyPalette()` on the strip, selector and handle. Panel colours stay
  dark-neutral so the scene carries the colour; `accent` tints the active
  tab, knob arcs, touch marker and selector arrows.
- **Typography:** `Theme.display(_:)` = SF Rounded heavy (system
  `.rounded` design, no bundled font) for the character name and tab
  labels; `Theme.label(_:)` = SF Rounded semibold for captions/values.
- **Knobs (`KnobView.draw`)**: sticker dial — cream face with a bold ink
  outline and a hard drop shadow, a thick value arc in `accent` around a
  dark track, an ink pointer notch. Name and value captions in the rounded
  face. Interaction code untouched.
- **Tabs (`ControlPages`)**: the five buttons become one segmented bar —
  ink-outlined capsule with a sliding `accent` indicator (animated, instant
  under Reduce Motion).
- **Header (`CharacterSelector`)**: name in `display` type; arrows become
  round sticker buttons (cream, ink outline). Behaviour and the
  fixed-width/truncation rules are unchanged.
- **Drawer handle**: restyled to a small ink-outlined tab; geometry
  unchanged.
- **Overlays** (`AboutView`, `MoreAppsView`, `CharacterDropdownView`):
  same tokens and type; the dropdown's rows show a small rendered face
  thumbnail of each character (if not already present) on its scene sky.

## Verification

- Existing suite (`scripts/test.sh`) passes, with `LayoutTests` updated to
  the new zones and the new framing/mouth tests added.
- Render harnesses:
  - `RenderMonkSnapshot.testWriteAllCharactersSweep` now renders each
    character *in its scene* at the five vowel anchors, plus a loud and a
    blink column.
  - `RenderUISnapshot` size sheet at the six host sizes, for at least
    three characters with different palettes.
  - Each sheet is looked at after every character/surface change; a
    character is done only when its sheet has been reviewed.
- App icon (`RenderAppIcon`) regenerated from the new monk.
