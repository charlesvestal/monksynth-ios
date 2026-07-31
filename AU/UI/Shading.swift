import UIKit

/// The whole "90s pre-rendered 3D" style spec, in code — see
/// `docs/superpowers/specs/2026-07-31-character-style-spec.md`. Every
/// character composes its body from these five primitives instead of flat
/// `UIBezierPath` fills, and none of them ever stroke a silhouette: rendered
/// 3D has no linework, and a hand-picked highlight colour per character is
/// exactly the kind of drift that makes six characters stop reading as one
/// set. Highlight/shadow/rim tones are always *derived* from the caller's
/// base colour via `UIColor.adjusted(hueShift:saturationScale:brightnessScale:)`
/// (see `Theme.swift`), and every gradient's hot spot is offset toward the
/// same fixed `lightDirection` — that consistency is the single biggest
/// lever for a set of primitives to actually read as a set.
enum Shading {

    /// Which way a `capsule`'s long axis runs. The bright band always sits
    /// on the cross-axis side nearest `lightDirection`.
    enum Axis { case horizontal, vertical }

    /// One light, upper-left, in the same unit-square-ish sense every
    /// character's own geometry uses: negative x is toward the stage's
    /// left edge, negative y is toward its top (UIKit's y grows downward).
    /// Fixed and shared — no character overrides it (see the spec's "one
    /// light... do not let individual characters override it").
    static let lightDirection = CGVector(dx: -0.55, dy: -0.66)

    // MARK: - Derived tones
    //
    // Every primitive below pulls its highlight/shadow/rim from these three
    // functions rather than a hand-tuned literal, so a character passing a
    // single base colour gets a self-consistent tonal family for free.

    private static func highlightTone(_ base: UIColor) -> UIColor {
        base.adjusted(saturationScale: 0.55, brightnessScale: 1.55)
    }
    private static func shadowTone(_ base: UIColor) -> UIColor {
        base.adjusted(saturationScale: 1.15, brightnessScale: 0.46)
    }
    private static func rimTone(_ base: UIColor) -> UIColor {
        base.adjusted(saturationScale: 1.25, brightnessScale: 0.24)
    }

    private static func makeGradient(_ stops: [(UIColor, CGFloat)]) -> CGGradient? {
        let space = CGColorSpaceCreateDeviceRGB()
        let colors = stops.map(\.0.cgColor) as CFArray
        let locations = stops.map(\.1)
        return CGGradient(colorsSpace: space, colors: colors, locations: locations)
    }

    // MARK: - Core recipes
    //
    // The actual gradient math behind `sphere`/`capsule`, factored out and
    // exposed directly (no clip management of their own) for two cases the
    // shape-specific wrappers below can't cover: a bespoke silhouette that
    // isn't a plain ellipse/stadium/taper (`freeform`), and a form that
    // needs a *compound* clip — e.g. a patch of colour that must stay inside
    // both its own blob AND its parent shape's silhouette. Both still go
    // through this exact recipe, so the lighting stays consistent even where
    // the geometry is one-off.

    /// The radial "ball" recipe against whatever clip is already established
    /// on `context` — lit hot spot toward `lightDirection` relative to
    /// `boundingBox`, fall-off to a shadowed edge, darkened rim, specular
    /// dot. Pass the *parent* form's bounding box (not a small patch's own
    /// tiny bounds) when shading a patch of colour on a larger form, so the
    /// patch reveals the parent's lighting rather than getting its own
    /// independent hot spot.
    static func radialShade(in boundingBox: CGRect, color: UIColor, into context: CGContext) {
        guard boundingBox.width > 0, boundingBox.height > 0 else { return }
        let center = CGPoint(x: boundingBox.midX, y: boundingBox.midY)
        let diagonal = (boundingBox.width * boundingBox.width + boundingBox.height * boundingBox.height).squareRoot()
        let litCenter = CGPoint(x: center.x + lightDirection.dx * boundingBox.width * 0.30,
                                 y: center.y + lightDirection.dy * boundingBox.height * 0.30)

        if let base = makeGradient([
            (highlightTone(color), 0),
            (color, 0.52),
            (shadowTone(color), 1),
        ]) {
            context.drawRadialGradient(base, startCenter: litCenter, startRadius: 0,
                                        endCenter: litCenter, endRadius: diagonal * 0.62,
                                        options: [.drawsAfterEndLocation])
        }

        // Darkened rim: transparent through the middle, thickening to a
        // translucent dark ring right at the silhouette edge.
        if let rim = makeGradient([
            (rimTone(color).withAlphaComponent(0), 0.74),
            (rimTone(color).withAlphaComponent(0.55), 1),
        ]) {
            context.drawRadialGradient(rim, startCenter: center, startRadius: 0,
                                        endCenter: center, endRadius: diagonal * 0.52, options: [])
        }

        // Plastic specular highlight, offset further toward the light than
        // the base gradient's own hot spot.
        let specCenter = CGPoint(x: center.x + lightDirection.dx * boundingBox.width * 0.34,
                                  y: center.y + lightDirection.dy * boundingBox.height * 0.34)
        let specRadius = min(boundingBox.width, boundingBox.height) * 0.15
        if let spec = makeGradient([
            (UIColor.white.withAlphaComponent(0.80), 0),
            (UIColor.white.withAlphaComponent(0), 1),
        ]) {
            context.drawRadialGradient(spec, startCenter: specCenter, startRadius: 0,
                                        endCenter: specCenter, endRadius: specRadius, options: [])
        }
    }

    /// The linear "cylinder" recipe against whatever clip is already
    /// established on `context` — a bright band across the cross-axis,
    /// offset toward the light, dark toward both edges.
    static func linearShade(in rect: CGRect, color: UIColor, axis: Axis, into context: CGContext) {
        guard rect.width > 0, rect.height > 0 else { return }
        let bandShift: CGFloat = axis == .vertical ? lightDirection.dx : lightDirection.dy
        let band = min(max(0.5 + bandShift * 0.32, 0.14), 0.86)

        let stops: [(UIColor, CGFloat)] = [
            (rimTone(color), 0),
            (shadowTone(color), max(band - 0.30, 0.02)),
            (highlightTone(color), band),
            (shadowTone(color), min(band + 0.32, 0.98)),
            (rimTone(color), 1),
        ]
        guard let gradient = makeGradient(stops) else { return }

        let start: CGPoint
        let end: CGPoint
        switch axis {
        case .vertical:
            start = CGPoint(x: rect.minX, y: rect.midY)
            end = CGPoint(x: rect.maxX, y: rect.midY)
        case .horizontal:
            start = CGPoint(x: rect.midX, y: rect.minY)
            end = CGPoint(x: rect.midX, y: rect.maxY)
        }
        context.drawLinearGradient(gradient, start: start, end: end, options: [])
    }

    // MARK: - Sphere

    /// Ball shading for anything roughly round: heads, cheeks, eyeballs,
    /// buns, patches. A radial gradient hot-spots toward `lightDirection`
    /// and falls off to a shadowed far edge, a soft darkened rim vignettes
    /// the silhouette (an inner-shadow gradient, not a stroke), and a small
    /// bright specular dot sits just inside the hot spot — the "plastic"
    /// cue every Poser/Bryce render has.
    static func sphere(in rect: CGRect, color: UIColor, into context: CGContext) {
        guard rect.width > 0, rect.height > 0 else { return }
        context.saveGState()
        context.addEllipse(in: rect)
        context.clip()
        radialShade(in: rect, color: color, into: context)
        context.restoreGState()
    }

    // MARK: - Freeform

    /// `sphere`'s exact radial-gradient recipe, applied to an arbitrary
    /// silhouette instead of a plain ellipse — a robe's asymmetric drape, a
    /// dress cone, a muzzle. A bespoke shape still needs its own one-off
    /// `CGPath`, but it must still shade through this identical recipe
    /// rather than a hand-tuned one-off gradient, so the lighting stays
    /// consistent across the set even where the geometry can't be.
    /// `boundingBox` drives the light-direction math and is usually just
    /// `path`'s own bounds, but pass a parent shape's bounds instead when
    /// this path is a small patch that should read as part of a bigger lit
    /// form rather than getting its own independent hot spot. `fillRule`
    /// defaults to non-zero winding; pass `.evenOdd` for a ring/torus shape
    /// built from two nested subpaths (an outer contour and an inner "hole"
    /// wound the same direction) — e.g. the fish's puckered lips.
    static func freeform(_ path: CGPath, boundingBox: CGRect, color: UIColor,
                          fillRule: CGPathFillRule = .winding, into context: CGContext) {
        guard boundingBox.width > 0, boundingBox.height > 0 else { return }
        context.saveGState()
        context.addPath(path)
        if fillRule == .evenOdd {
            context.clip(using: .evenOdd)
        } else {
            context.clip()
        }
        radialShade(in: boundingBox, color: color, into: context)
        context.restoreGState()
    }

    // MARK: - Capsule

    /// Cylinder shading for limbs, necks, tails, sleeves: a linear gradient
    /// across the tube's cross-axis, a bright band offset toward the light,
    /// dark toward both edges, clipped to a stadium/pill shape so it reads
    /// as a rounded tube rather than a flat bar with a gradient on it.
    static func capsule(in rect: CGRect, color: UIColor, axis: Axis, into context: CGContext) {
        guard rect.width > 0, rect.height > 0 else { return }
        context.saveGState()
        let radius = min(rect.width, rect.height) / 2
        context.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
        context.clip()
        linearShade(in: rect, color: color, axis: axis, into: context)
        context.restoreGState()
    }

    // MARK: - Cone

    /// Tapered shading for a triangular prop — horns, hat points, noses,
    /// fins — apex-up within `rect`. Same bright-band-toward-the-light
    /// treatment as `capsule`, clipped to the taper instead of a stadium. A
    /// caller wanting the point aimed anywhere other than up rotates the
    /// context around the shape's own centre first (the same way every
    /// character already positions geometry through stage-relative
    /// `point(_:_:in:)`), calls this, then restores.
    static func cone(in rect: CGRect, color: UIColor, into context: CGContext) {
        guard rect.width > 0, rect.height > 0 else { return }
        context.saveGState()
        let path = CGMutablePath()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        context.addPath(path)
        context.clip()

        let band = min(max(0.5 + lightDirection.dx * 0.38, 0.14), 0.86)
        let stops: [(UIColor, CGFloat)] = [
            (rimTone(color), 0),
            (shadowTone(color), max(band - 0.26, 0.02)),
            (highlightTone(color), band),
            (shadowTone(color), 1),
        ]
        if let gradient = makeGradient(stops) {
            context.drawLinearGradient(gradient, start: CGPoint(x: rect.minX, y: rect.midY),
                                        end: CGPoint(x: rect.maxX, y: rect.midY), options: [])
        }
        context.restoreGState()
    }

    // MARK: - Recess

    /// A recessed opening — mouths, eye sockets: dark, with an inner shadow
    /// hugging the top edge so it reads as a hole let INTO the face rather
    /// than a flat shape painted on top of it. This is deliberately the
    /// opposite construction from `sphere`/`capsule`/`cone`: no highlight,
    /// no rim lift, because the whole point is that light doesn't reach
    /// into it evenly.
    static func recess(in rect: CGRect, into context: CGContext) {
        guard rect.width > 0, rect.height > 0 else { return }
        context.saveGState()
        context.addEllipse(in: rect)
        context.clip()

        if let base = makeGradient([
            (UIColor.black.withAlphaComponent(0.92), 0),
            (UIColor.black.withAlphaComponent(0.58), 0.55),
            (UIColor.black.withAlphaComponent(0.72), 1),
        ]) {
            context.drawLinearGradient(base, start: CGPoint(x: rect.midX, y: rect.minY),
                                        end: CGPoint(x: rect.midX, y: rect.maxY), options: [])
        }

        // Inner shadow: a soft dark wash from the top edge down partway
        // into the opening, as though whatever rims it above (a lip, a
        // brow) casts a shadow down into the hole.
        if let inner = makeGradient([
            (UIColor.black.withAlphaComponent(0.80), 0),
            (UIColor.black.withAlphaComponent(0), 1),
        ]) {
            let innerBottom = rect.minY + rect.height * 0.60
            context.drawLinearGradient(inner, start: CGPoint(x: rect.midX, y: rect.minY),
                                        end: CGPoint(x: rect.midX, y: innerBottom), options: [])
        }

        context.restoreGState()
    }

    // MARK: - Occlusion

    /// A soft contact shadow where one form meets another — under a chin,
    /// at an ear or horn's root, at a head-to-collar seam. `under` is the
    /// (typically thin, crescent-ish) region the shadow occupies; rendered
    /// as a soft dark-to-clear gradient inside an elliptical clip, denser
    /// at the top of the region than the bottom.
    static func occlusion(under rect: CGRect, into context: CGContext) {
        guard rect.width > 0, rect.height > 0 else { return }
        context.saveGState()
        context.addEllipse(in: rect)
        context.clip()

        if let gradient = makeGradient([
            (UIColor.black.withAlphaComponent(0.30), 0),
            (UIColor.black.withAlphaComponent(0), 1),
        ]) {
            context.drawLinearGradient(gradient, start: CGPoint(x: rect.midX, y: rect.minY),
                                        end: CGPoint(x: rect.midX, y: rect.maxY), options: [])
        }
        context.restoreGState()
    }
}
