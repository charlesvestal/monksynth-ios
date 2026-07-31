# Character style spec — 90s CGI

**Date:** 2026-07-31
**Status:** approved
**Supersedes the ad-hoc art in:** `MonkCharacter`, `FishCharacter`, `UnicornCharacter`, `GirlCharacter`, `OldManCharacter`, `CowCharacter`

## The look

Early-2000s pre-rendered 3D, as in the original Delay Lama — and as in Poser,
Bryce and 3DS Max character work of that era. Smooth Gouraud-style shading over
simple primitive forms, plastic specular highlights, no linework.

This is a homage, so the dated quality is the point. Do not modernise it into
flat design, and do not chase photorealism.

**Reference cues:**
- Bodies built from a small vocabulary of primitives — sphere, capsule, cone,
  torus — visibly assembled rather than sculpted.
- One light, upper-left, identical for every character. Consistent lighting is
  the single biggest reason a set reads as a set.
- Each form: a base radial gradient from lit to shadowed, a specular highlight
  offset toward the light, and a darkened rim at the silhouette edge.
- Saturated, slightly plastic colour. Period palette.
- **No outlines.** Rendered 3D has no linework; the current flat characters use
  strokes and that is the strongest thing making them look like vector art.
- The mouth is a *recessed opening* with an inner shadow, not a flat black oval
  pasted on the face.

## The system

A shared primitive library, `AU/UI/Shading.swift`, is the whole spec in code:

```swift
enum Shading {
    static let lightDirection: CGVector   // fixed, upper-left, all characters

    static func sphere(in: CGRect, color: UIColor, into: CGContext)
    static func capsule(in: CGRect, color: UIColor, axis: Axis, into: CGContext)
    static func cone(in: CGRect, color: UIColor, into: CGContext)
    static func recess(in: CGRect, into: CGContext)      // mouths, eye sockets
    static func occlusion(under: CGRect, into: CGContext) // contact shadow
}
```

Every character composes from these and passes only geometry and a base colour.
A character that needs a bespoke shape still shades it through the same
gradient helpers, so the lighting stays consistent.

This is also why the style comes before the roster: once the primitives exist, a
new character is an arrangement of them rather than an art project.

## Performance

Gradients cost more than flat fills, and `CharacterView` currently redraws
everything on every animation tick — up to 120Hz on ProMotion.

**The body is static; only the mouth and eyes animate.** So:

- Render the body once into a cached `UIImage`, keyed by character id, size and
  screen scale.
- Each frame, draw the cached body and composite only the mouth and eyes.
- Invalidate the cache on character change, bounds change, or scale change.

Without this, six shaded primitives per character per frame is a real battery
and thermal cost inside a host that is already doing audio work.

## Non-negotiables carried over

- The mouth still advances in **24 discrete quantised frames** (`quantisedVowel`).
  The stepped, sprite-like motion is deliberate — see the port design doc.
- The idle state machine (HOLD, blinks at ticks 14–17 and 31–34, 24-step
  SHUFFLE) is unchanged.
- Reduce Motion still freezes idle animation.
- Nothing distorts at extreme aspect ratios; everything stays in the centred
  square stage via stage-relative coordinates.
- Each character must remain instantly distinguishable in silhouette at ~120pt.

## Scope

Rewrite the existing six against this spec. The roster expands afterwards, once
the language is settled.
