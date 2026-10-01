# Character art guide

MonkSynth's on-screen character can be built two ways: drawn in Swift code,
or assembled from images you supply. This document is for the second path —
**you do not need to write or read any Swift to produce character art**,
except for one short, copy-paste registration step at the very end.

If you just want to see a real, working example before reading further: the
test suite generates one automatically from the built-in monk character —
see "A concrete example" near the end.

## What a character is made of

Four kinds of image, plus a small amount of placement data:

1. **One body image** — the whole character except its eyes and mouth:
   head, body, clothes, props, background details, whatever you want. This
   is the only truly static image; everything else composites on top of it
   every frame.
2. **Two eye images** — `eyeOpen` and `eyeClosed`. Whichever one is
   currently "on" is drawn on top of the body, in the exact same place,
   every frame. There is no "half-closed" — just those two states, swapped
   for the blink.
3. **Mouth frames** — a set of images, one per mouth shape, swapped in and
   out as the character "talks". You can supply as few or as many as you
   like (see "How many mouth frames" below); MonkSynth maps whatever count
   you give it onto its own internal animation steps.
4. **Mouth placement** — four numbers saying where, within the body image,
   the mouth frames get drawn, and how big.

Nothing else is required. If your character doesn't blink, `eyeOpen` and
`eyeClosed` can be identical images — but both files still need to exist.

## Image format and size

- **PNG, with an alpha channel.** Everywhere that isn't part of the
  character must be fully transparent, not white or black — these images
  are composited on top of each other and on top of the app's own
  background.
- **One resolution, reasonably large.** MonkSynth scales your image down
  smoothly at whatever size it's actually shown at — from roughly 120
  points tall (a cramped host strip) up to a full-size iPad. There's no
  need to export `@1x`/`@2x`/`@3x` variants; a single source around
  **1024 px** on its longest side is more than enough detail at every size
  this ever renders at, and is simpler to manage than a multi-resolution
  set.
- **Any aspect ratio for the body image.** Square, portrait, whatever suits
  the character. MonkSynth always fits it into a centred square area
  without ever stretching or cropping it — if your image isn't square,
  you'll see even margins on two sides (like a letterboxed photo), not
  distortion. Design around this: keep anything important away from the
  very edges of the canvas, since a very tall or very wide host window can
  shrink the effective square down to a small fraction of the screen.
- **The two eye images and the mouth frame images do not need to be the
  same resolution as the body image.** They just need to be internally
  consistent with each other (see below).

## The body image

Draw the whole character **except** the eyes and the mouth aperture. Leave
blank/skin-toned space where the mouth normally sits — the mouth frames are
drawn on top of that space every frame, so it doesn't need anything special
underneath, just don't leave a distracting painted-in mouth that would show
through gaps in an open mouth frame.

## The eye images

`eyeOpen.png` and `eyeClosed.png` must be:

- **Exactly the same pixel dimensions as `body.png`.** They're drawn using
  the identical placement as the body — full-canvas overlays, not small
  cropped sprites — so a mismatched size will misalign or distort them.
- **Transparent everywhere except the eye artwork itself.** Only the pixels
  that make up the eyes should be opaque; everything else must be
  transparent so the body shows through underneath.

Whichever one is "current" is drawn on top of the body every frame — there
is no partial blend between them, so keep the two versions visually
distinct enough that the blink actually reads.

## The mouth frames

Each mouth frame is a **small image of just the mouth shape** — not a
full-body canvas. Think of it as a sprite: enough canvas to contain the
open/closed/whatever shape for that frame, transparent everywhere else,
sized so it comfortably fits inside the mouth placement box described
below without needing to be scaled up dramatically.

You can package these two ways:

- **Separate images**, one per frame, in vowel order (frame 0 = mouth
  closed/resting, the last frame = mouth at its widest/most open — the
  usual convention, though it's entirely up to your character's own
  design).
- **One grid/strip sheet**: a single image sliced into equal cells,
  left-to-right then top-to-bottom, reading the first N cells (in that same
  order) as your frames. Useful if your tooling exports sprite sheets
  naturally.

Either is fine — there's no quality or performance difference. Pick
whichever fits your art pipeline.

### How many mouth frames, and how they map to the animation

MonkSynth's mouth always advances through **24 discrete positions** across
the vowel range — this is a deliberate, stepped, puppet-like motion (part
of the character's charm, not a limitation), not a smooth blend.

- **Supply 24 frames** and each one of those 24 positions gets its own,
  distinct image — a direct one-to-one match.
- **Supply fewer than 24** (say, 6) and MonkSynth maps each of its 24
  internal positions to whichever of your frames is *nearest*. With 6
  frames, several adjacent internal positions will end up showing the same
  frame — the animation still runs through all 24 steps, it just repeats
  frames along the way instead of every step being unique. This is a
  completely normal, supported way to do less work: a character that talks
  in broad "closed / half / open" shapes might only need 3–5 frames.
- The mapping always lands frame 0 exactly on the mouth's resting/closed
  position and your last frame exactly on its most-open position — the two
  extremes are never blended or skipped, however many frames you supply.
- Supplying *more* than 24 frames is harmless but pointless — only 24
  positions are ever shown, so anything past the first 24 in reading order
  never gets used. There's no reason to supply more.

## Mouth placement

Four numbers, all fractions from 0 to 1, all measured **against your body
image's own canvas** — not the screen, not any particular render size, so
they stay correct no matter how large or small MonkSynth actually draws the
character:

| Field     | Meaning                                                        |
|-----------|------------------------------------------------------------------|
| `centerX` | Horizontal centre of the mouth box, as a fraction of body width  |
| `centerY` | Vertical centre of the mouth box, as a fraction of body height   |
| `width`   | Width of the mouth box, as a fraction of body width               |
| `height`  | Height of the mouth box, as a fraction of body height              |

For example, if your body image is 1000×1200 px and the mouth should be
centred 500 px from the left, 470 px from the top, and sit inside a roughly
270×270 px area:

```
centerX = 500 / 1000 = 0.5
centerY = 470 / 1200 = 0.39
width   = 270 / 1000 = 0.27
height  = 270 / 1200 = 0.225
```

The mouth box doesn't have to be square — `width` and `height` are
independent. Whatever frame image ends up in it is scaled down (never
stretched or distorted) to fit inside that box while keeping its own
proportions, and centred there. A louder note opens the mouth box a little
further, uniformly in both directions, so a frame never gets squashed or
stretched by loudness either.

## Where the files go

Real character art ships in the app's asset catalog, so it's bundled and
looked up by name at runtime rather than loaded from loose files. The
convention:

```
AU/Resources/Characters.xcassets/
  <character-id>-body.imageset/
  <character-id>-eyeOpen.imageset/
  <character-id>-eyeClosed.imageset/
  <character-id>-mouth0.imageset/
  <character-id>-mouth1.imageset/
  ...
```

(or `<character-id>-mouthstrip.imageset/` for the single-sheet packaging).
Each `.imageset` is a folder Xcode understands, containing your PNG plus a
small `Contents.json` — the easiest way to create these is to drag your PNG
into an empty image set slot in Xcode's asset catalog editor, which writes
that file for you. Since a single high-resolution source is enough (see
"Image format and size" above), you only need to fill the "Universal" /
`1x` slot, not `2x`/`3x`.

`AU/Resources` is shared by every MonkSynth build target, so art placed
there is automatically available everywhere the app runs — nothing else to
wire up.

## Registering a new character

This is the one step that touches Swift, and it's short. Two pieces:

**1. Describe the character as data** — a `SpriteManifest` value (see
`AU/UI/SpriteCharacter.swift`):

```swift
let opera = SpriteManifest(
    id: "opera",                       // unique, permanent — see the doc
    displayName: "Opera Singer",       //   comment on SpriteManifest.id
    bodyImageName: "opera-body",
    eyeOpenImageName: "opera-eyeOpen",
    eyeClosedImageName: "opera-eyeClosed",
    mouthPlacement: .init(centerX: 0.5, centerY: 0.39, width: 0.27, height: 0.30),
    mouthFrameNames: (0..<24).map { "opera-mouth\($0)" })
    // — or, for the strip packaging, instead of mouthFrameNames:
    // mouthStripName: "opera-mouthstrip",
    // mouthStripColumns: 6, mouthStripRows: 4, mouthStripFrameCount: 24
```

**2. Add it to the roster** — one line near the top of
`AU/UI/Character.swift`:

```swift
enum CharacterRegistry {
    static let all: [Character] = [
        MonkCharacter(),
        // ...
        SpriteCharacter(manifest: opera, loader: BundleImageLoader(bundle: Bundle(for: CharacterView.self))),
    ]
```

Where it sits in that list is where it sits in the picker and the arrow
order — it's independent of `id`. That's the whole integration: no new
protocol conformance, no drawing code.

## If art is missing or broken

If any required image for a character fails to load — a name that doesn't
resolve in the asset catalog, or an image that decodes but comes out at
zero size — **the entire character falls back to drawing as the default
monk** (body, eyes, and mouth together), rather than showing a broken or
half-finished character. This is deliberate and total: a correct body next
to the monk's drawn-on eyes would look more broken, not less, than a clean
fallback. So while you're iterating on a new character's art, a typo'd
image name or a bad export doesn't crash the app or leave a blank stage —
it just quietly shows the monk instead, which is your signal that
something in that character's asset set didn't resolve.

## Drawn characters

The twelve built-in characters are drawn in code, not images. Each is a
`ToonCharacter` (`AU/UI/ToonCharacter.swift`): it draws its body and face
with the `Toon` kit (`AU/UI/Toon.swift`) in a 300×300 "stage unit" space,
names where its mouth sits (`mouthStyle`), and draws its own scene
(`drawBackdrop`). The mouth itself is shared (`AU/UI/ToonMouth.swift`).

The shapes were designed in `docs/mockups/stage-redesign/gen.mjs`, which
renders the same path data as SVG — edit a character there first
(`node gen.mjs` writes `out/`), then copy the numbers across; `Toon.path`
reads the same path syntax.

`CharacterArtTests` keeps every drawn character honest: one connected figure
(nothing floating), nothing clipped at the stage edge, and a mouth at least
0.11 of the stage tall at AH and 0.14 wide at EE.

## A concrete example

You don't have to take any of the above on faith — there's a real,
working, non-hand-drawn example already in the codebase, generated
automatically every time the tests run: `Tests/MonkSynthTests/SpriteCharacterFixture.swift`
renders the built-in monk's own drawing code into a body image, 24 mouth
frames, and both eye states, then builds a real `SpriteCharacter` out of
them entirely in memory (no files, no asset catalog — see
`DictionaryImageLoader`). `Tests/MonkSynthTests/SpriteCharacterTests.swift`
exercises it: rendering at many sizes, selecting mouth frames by vowel,
blinking, and the missing/corrupt-art fallback. It is **not** part of the
shipping character roster — it exists purely to prove the image-backed path
works end to end.
