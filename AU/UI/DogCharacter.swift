import AVFoundation
import UIKit

/// A front-facing dog head over simple shoulders: floppy drooping ears, a
/// protruding tan snout with a dark nose, and a wide panting mouth. Its
/// voice is upstream's "Monastary" factory preset, verbatim — the single
/// darkest of the six measured presets, matched to the largest/deepest
/// archetype of the six new characters (see `FactoryVoiceTable`'s doc
/// comment for the measurement and the full mapping). Placeholder art, like
/// every character added by this task — the user is replacing all
/// character art with their own later, so this deliberately stays a first
/// pass: an instantly-readable silhouette and a mouth that sweeps
/// distinctly across the vowel range, nothing more.
struct DogCharacter: Character {
    let id = "dog"
    let displayName = "Dog"

    var savedParameters: [Param: AUValue]? { FactoryVoiceTable.values(for: id) }

    private static let coat = UIColor(red: 0.78, green: 0.56, blue: 0.30, alpha: 1)
    private static let coatShadow = Self.coat.adjusted(brightnessScale: 0.72)
    private static let snout = UIColor(red: 0.92, green: 0.82, blue: 0.66, alpha: 1)
    private static let nose = UIColor(red: 0.16, green: 0.13, blue: 0.12, alpha: 1)

    // MARK: - Mouth anchors — a panting mouth: opens progressively wider AND
    // taller across the whole sweep, unlike every other character's
    // narrow-then-flattening trend.
    private static let mouthAnchors: [(w: CGFloat, h: CGFloat)] = [
        (0.20, 0.14), (0.32, 0.24), (0.44, 0.34), (0.52, 0.40), (0.58, 0.44),
    ]

    func mouthShape(vowel v: Float) -> (w: CGFloat, h: CGFloat) {
        let clamped = min(max(v, 0), 1)
        let scaled = CGFloat(clamped) * CGFloat(Self.mouthAnchors.count - 1)
        let i = min(Int(scaled), Self.mouthAnchors.count - 2)
        let t = scaled - CGFloat(i)
        let a = Self.mouthAnchors[i], b = Self.mouthAnchors[i + 1]
        return (a.w + (b.w - a.w) * t, a.h + (b.h - a.h) * t)
    }

    let mouthBoxFraction: CGFloat = 0.30
    let mouthCentre: (fx: CGFloat, fy: CGFloat) = (0.5, 0.56)

    private let headCenter = (fx: CGFloat(0.5), fy: CGFloat(0.30))
    private let headRadius: CGFloat = 0.185

    // MARK: - Tunable geometry
    //
    // Everything `drawBody`/`drawEyes` position or size, gathered here so
    // the rig can be tuned by editing one block instead of hunting through
    // Bezier paths — and so `Tests/MonkSynthTests/RenderSweep.swift` can
    // mutate a single field on a copy of the character before rendering it,
    // without touching the drawing code at all (that's why this is a
    // `struct` held in a `var`, not baked in as `let` constants). Most
    // fields are head-radius units measured from `headCenter` — i.e. the
    // value the original inline literal multiplied `headRadius` by; a few
    // (noted individually) are plain stage fractions instead, matching
    // whatever the original code did.
    struct Geometry {
        // --- Shoulders ---
        var bodyShoulderLeftX: CGFloat = 0.24
        var bodyShoulderY: CGFloat = 0.62
        var bodyHemLeftX: CGFloat = 0.06
        var bodyHemY: CGFloat = 0.99
        var bodyLeftControlX: CGFloat = 0.08
        var bodyLeftControlY: CGFloat = 0.82
        var bodyHemRightX: CGFloat = 0.94
        var bodyShoulderRightX: CGFloat = 0.76
        var bodyRightControlX: CGFloat = 0.92
        var bodyRightControlY: CGFloat = 0.82
        var bodyNeckX: CGFloat = 0.5
        var bodyNeckY: CGFloat = 0.56
        var bodyNeckControlY: CGFloat = 0.62

        // --- Neck ---
        /// How far above the head's own bottom edge the fur-coloured neck
        /// patch's top sits, in head-radius units — kept slightly INSIDE
        /// the head circle so there is no seam. An earlier version had no
        /// neck at the sides of the head at all: only the snout (which
        /// reaches down far enough to reach the coat on its own) visually
        /// connected head to body, leaving a vague, gappy junction either
        /// side of it.
        var neckTopOffsetRadii: CGFloat = 0.90
        var neckHalfWidthFraction: CGFloat = 0.10

        // --- Ears ---
        var earRootRadii: CGFloat = 0.92
        var earRootYOffsetRadii: CGFloat = 0.15
        var earTipXOffsetRadii: CGFloat = 0.15
        var earTipYOffsetRadii: CGFloat = 1.55
        var earOuterControlXRadii: CGFloat = 0.62
        var earOuterControlYRadii: CGFloat = 0.55
        var earInnerControlXRadii: CGFloat = 0.05
        var earInnerControlYRadii: CGFloat = 1.05

        // --- Snout ---
        var snoutOffsetRadii: CGFloat = 1.20
        var snoutWidthFraction: CGFloat = 0.30
        var snoutHeightFraction: CGFloat = 0.26
        var noseWidthFraction: CGFloat = 0.07
        var noseYOffsetScale: CGFloat = 0.28
        var noseYInsetScale: CGFloat = 0.7
        var noseHeightScale: CGFloat = 1.1

        // --- Eyes ---
        var eyeXOffset: CGFloat = 0.07
        var eyeYOffset: CGFloat = 0.02
        var eyeLashHalfWidthFraction: CGFloat = 0.038
        var eyeLashLineWidthFraction: CGFloat = 0.013
        var eyeRadiusFraction: CGFloat = 0.042
        var pupilRadiusScale: CGFloat = 0.6
    }

    var geometry = Geometry()

    func drawBody(in stage: CGRect) {
        func p(_ fx: CGFloat, _ fy: CGFloat) -> CGPoint { point(fx, fy, in: stage) }
        let g = geometry

        // Shoulders.
        let body = UIBezierPath()
        body.move(to: p(g.bodyShoulderLeftX, g.bodyShoulderY))
        body.addQuadCurve(to: p(g.bodyHemLeftX, g.bodyHemY), controlPoint: p(g.bodyLeftControlX, g.bodyLeftControlY))
        body.addLine(to: p(g.bodyHemRightX, g.bodyHemY))
        body.addQuadCurve(to: p(g.bodyShoulderRightX, g.bodyShoulderY), controlPoint: p(g.bodyRightControlX, g.bodyRightControlY))
        body.addQuadCurve(to: p(g.bodyNeckX, g.bodyNeckY), controlPoint: p(g.bodyNeckX, g.bodyNeckControlY))
        body.addQuadCurve(to: p(g.bodyShoulderLeftX, g.bodyShoulderY), controlPoint: p(g.bodyNeckX, g.bodyNeckControlY))
        body.close()
        Self.coat.setFill()
        body.fill()

        // Neck: a fur-coloured patch bridging the head's own bottom edge
        // down to the coat's own collar point, so the sides of the head
        // read as attached to the body rather than floating over empty
        // background either side of the snout.
        let neckTop = headCenter.fy + headRadius * g.neckTopOffsetRadii
        let neck = UIBezierPath()
        neck.move(to: p(headCenter.fx - g.neckHalfWidthFraction, neckTop))
        neck.addLine(to: p(headCenter.fx - g.neckHalfWidthFraction, g.bodyNeckY))
        neck.addLine(to: p(headCenter.fx + g.neckHalfWidthFraction, g.bodyNeckY))
        neck.addLine(to: p(headCenter.fx + g.neckHalfWidthFraction, neckTop))
        neck.close()
        Self.coat.setFill()
        neck.fill()

        // Floppy, drooping ears — the strongest "dog, not cow/unicorn" cue,
        // hanging DOWN past the jawline rather than jutting sideways (cow)
        // or standing tall and pointed (unicorn). Drawn before the head so
        // it overlaps their root.
        for sign: CGFloat in [-1, 1] {
            let rootX = headCenter.fx + sign * headRadius * g.earRootRadii
            let root = point(rootX, headCenter.fy - headRadius * g.earRootYOffsetRadii, in: stage)
            let tip = point(rootX + sign * headRadius * g.earTipXOffsetRadii, headCenter.fy + headRadius * g.earTipYOffsetRadii, in: stage)
            let outerCtrl = point(rootX + sign * headRadius * g.earOuterControlXRadii, headCenter.fy + headRadius * g.earOuterControlYRadii, in: stage)
            let innerCtrl = point(rootX + sign * headRadius * g.earInnerControlXRadii, headCenter.fy + headRadius * g.earInnerControlYRadii, in: stage)
            let ear = UIBezierPath()
            ear.move(to: root)
            ear.addQuadCurve(to: tip, controlPoint: outerCtrl)
            ear.addQuadCurve(to: root, controlPoint: innerCtrl)
            ear.close()
            Self.coatShadow.setFill()
            ear.fill()
        }

        // Head.
        let head = UIBezierPath(arcCenter: point(headCenter.fx, headCenter.fy, in: stage),
                                 radius: stage.width * headRadius,
                                 startAngle: 0, endAngle: .pi * 2, clockwise: true)
        Self.coat.setFill()
        head.fill()

        // Snout: a tan oval protruding below the head, the mouth aperture's
        // own local frame — with a dark nose at its tip.
        let snoutCenter = point(mouthCentre.fx, headCenter.fy + headRadius * g.snoutOffsetRadii, in: stage)
        let snoutW = stage.width * g.snoutWidthFraction
        let snoutH = stage.width * g.snoutHeightFraction
        let snout = UIBezierPath(ovalIn: CGRect(x: snoutCenter.x - snoutW / 2, y: snoutCenter.y - snoutH / 2,
                                                 width: snoutW, height: snoutH))
        Self.snout.setFill()
        snout.fill()

        let noseW = stage.width * g.noseWidthFraction
        let noseCenter = CGPoint(x: snoutCenter.x, y: snoutCenter.y - snoutH * g.noseYOffsetScale)
        let nose = UIBezierPath(ovalIn: CGRect(x: noseCenter.x - noseW / 2, y: noseCenter.y - noseW * g.noseYInsetScale,
                                                width: noseW, height: noseW * g.noseHeightScale))
        Self.nose.setFill()
        nose.fill()
    }

    func drawEyes(in stage: CGRect, blinking: Bool) {
        let g = geometry
        for cx: CGFloat in [headCenter.fx - g.eyeXOffset, headCenter.fx + g.eyeXOffset] {
            let c = point(cx, headCenter.fy - g.eyeYOffset, in: stage)
            if blinking {
                let lash = UIBezierPath()
                lash.move(to: CGPoint(x: c.x - stage.width * g.eyeLashHalfWidthFraction, y: c.y))
                lash.addLine(to: CGPoint(x: c.x + stage.width * g.eyeLashHalfWidthFraction, y: c.y))
                lash.lineWidth = stage.width * g.eyeLashLineWidthFraction
                lash.lineCapStyle = .round
                Theme.robeShadow.setStroke()
                lash.stroke()
                continue
            }
            let r = stage.width * g.eyeRadiusFraction
            let eye = UIBezierPath(ovalIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
            UIColor.white.setFill()
            eye.fill()
            let pupilR = r * g.pupilRadiusScale
            let pupil = UIBezierPath(ovalIn: CGRect(x: c.x - pupilR, y: c.y - pupilR, width: pupilR * 2, height: pupilR * 2))
            Self.nose.setFill()
            pupil.fill()
        }
    }
}
