import UIKit

/// A little girl: a deliberately small head over a larger triangular dress,
/// two round pigtails, and big friendly eyes. First pass; the user will
/// iterate on the art with the render harness.
struct GirlCharacter: Character {
    let id = "girl"
    let displayName = "Little Girl"

    private static let hair = UIColor(red: 0.36, green: 0.20, blue: 0.13, alpha: 1)
    private static let dress = UIColor(red: 0.80, green: 0.32, blue: 0.52, alpha: 1)
    private static let dressTrim = Self.dress.adjusted(brightnessScale: 0.75)
    private static let cheek = UIColor(red: 0.95, green: 0.55, blue: 0.55, alpha: 1)

    // MARK: - Mouth anchors — small throughout, unlike every other
    // character's sweep: a child's mouth barely opens at the low end and
    // stays compact even at the wide end.
    private static let mouthAnchors: [(w: CGFloat, h: CGFloat)] = [
        (0.10, 0.16), (0.16, 0.20), (0.22, 0.15), (0.26, 0.10), (0.30, 0.06),
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
    let mouthCentre: (fx: CGFloat, fy: CGFloat) = (0.5, 0.255)

    // Deliberately smaller than the monk's 0.17: the head-to-body ratio is
    // the character's whole point, per the design brief.
    private let headCenter = (fx: CGFloat(0.5), fy: CGFloat(0.20))
    private let headRadius: CGFloat = 0.115

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
        // --- Dress ---
        /// Stage position where the dress's shoulders meet the neckline.
        var dressNeckX: CGFloat = 0.5
        var dressNeckY: CGFloat = 0.34
        /// Control points that bow the dress's left/right silhouette
        /// outward on the way down to the hem corners.
        var dressLeftControlX: CGFloat = 0.22
        var dressLeftControlY: CGFloat = 0.62
        var dressRightControlX: CGFloat = 0.78
        var dressRightControlY: CGFloat = 0.62
        /// The dress's bottom-left / bottom-right hem corners (stage
        /// fractions).
        var dressHemLeftX: CGFloat = 0.08
        var dressHemRightX: CGFloat = 0.92
        var dressHemY: CGFloat = 0.99
        /// Top edge of the darker hem trim band.
        var hemTrimTopY: CGFloat = 0.92

        // --- Hands ---
        /// Stage X position of each hand/sleeve blob.
        var handLeftX: CGFloat = 0.26
        var handRightX: CGFloat = 0.74
        var handY: CGFloat = 0.46
        /// Hand blob radius, as a fraction of stage width.
        var handRadiusFraction: CGFloat = 0.05
        /// The hand blob is slightly taller than wide.
        var handHeightScale: CGFloat = 2.2

        // --- Pigtails ---
        /// How far out from head centre each pigtail bun sits, in head
        /// radii.
        var pigtailOffsetRadii: CGFloat = 1.5
        /// Pigtails sit very slightly above head centre (stage fraction).
        var pigtailYInset: CGFloat = 0.01
        /// Bun radius, as a fraction of `stage.width * headRadius`.
        var pigtailRadiusFraction: CGFloat = 0.62
        /// The trailing wisp below each bun: start/end/control distances
        /// from the bun's own centre, in bun-radius units.
        var wispStartRadii: CGFloat = 0.6
        var wispEndRadii: CGFloat = 2.0
        var wispControlRadii: CGFloat = 1.3
        var wispLineWidthFraction: CGFloat = 0.02

        // --- Hairline / fringe (bangs) ---
        /// How far round the head, in degrees from straight up, the
        /// fringe's outer corners meet the head's own outline. Pinning
        /// these exactly onto the head circle (see `drawBody`) is what
        /// keeps the cap flush with the head's edge at 10/2 o'clock instead
        /// of leaving a sliver of skin between hair and head.
        var hairlineSideAngleDeg: CGFloat = 60
        /// How far past the head's top edge the fringe's peak pokes, in
        /// head-radius units (>1 = past the top) — the poof at the crown.
        var hairlinePeakDepth: CGFloat = 1.15
        /// How far above the head the crown-rounding control points sit, in
        /// head-radius units — higher than the peak itself so the crown
        /// reads as a soft dome rather than a sharp tent.
        var hairlineTopControlDepth: CGFloat = 1.45
        /// Horizontal inset of the crown-rounding control points, in
        /// head-radius units from centre.
        var hairlineTopControlXInset: CGFloat = 0.4
        /// *** Vertical position of the hairline across the forehead ***:
        /// how far down the fringe's lower edge reaches at the centre of
        /// the forehead, in head-radius units above head centre. Smaller
        /// means the fringe reaches further down (more forehead covered).
        /// This is the single control point for one smooth arc spanning
        /// corner-to-corner — replacing the old two-segment dip that cut a
        /// sharp V/dent — so tuning it moves the whole lower edge as a
        /// gentle curve that follows the head's own curvature instead of
        /// fighting it.
        var hairlineCenterDepth: CGFloat = 0.32

        // --- Cheeks ---
        var cheekXOffset: CGFloat = 0.7
        var cheekYOffset: CGFloat = 0.35
        var cheekRadiusFraction: CGFloat = 0.28
        var cheekAlpha: CGFloat = 0.5

        // --- Eyes ---
        /// Horizontal offset of each eye from head centre, as a plain stage
        /// fraction (not head-radius units — matches the original code).
        var eyeXOffset: CGFloat = 0.045
        var lashHalfWidthFraction: CGFloat = 0.024
        var lashLineWidthFraction: CGFloat = 0.01
        var eyeRadiusFraction: CGFloat = 0.03
        var irisRadiusScale: CGFloat = 0.68
        var highlightRadiusScale: CGFloat = 0.34
        var highlightOffsetScale: CGFloat = 1.3

        // --- Arms ---
        /// Where each arm leaves the dress — a point pinned to the dress's
        /// own shoulder curve, stage fractions. This is what connects the
        /// hands to the body: without an arm between them, the hands used
        /// to render as two circles with nothing tying them to the dress.
        var armShoulderLeftX: CGFloat = 0.445
        var armShoulderRightX: CGFloat = 0.555
        var armShoulderY: CGFloat = 0.40
        /// Stroke width of the arm, as a fraction of stage width.
        var armLineWidthFraction: CGFloat = 0.045
    }

    var geometry = Geometry()

    func drawBody(in stage: CGRect) {
        func p(_ fx: CGFloat, _ fy: CGFloat) -> CGPoint { point(fx, fy, in: stage) }
        let g = geometry

        // Dress: a big, simple triangle/cone — most of the stage is body,
        // not head, on purpose.
        let dress = UIBezierPath()
        dress.move(to: p(g.dressNeckX, g.dressNeckY))
        dress.addQuadCurve(to: p(g.dressHemLeftX, g.dressHemY), controlPoint: p(g.dressLeftControlX, g.dressLeftControlY))
        dress.addLine(to: p(g.dressHemRightX, g.dressHemY))
        dress.addQuadCurve(to: p(g.dressNeckX, g.dressNeckY), controlPoint: p(g.dressRightControlX, g.dressRightControlY))
        dress.close()
        Self.dress.setFill()
        dress.fill()

        // Hem trim.
        let hem = UIBezierPath()
        hem.move(to: p(g.dressHemLeftX, g.hemTrimTopY))
        hem.addLine(to: p(g.dressHemRightX, g.hemTrimTopY))
        hem.addLine(to: p(g.dressHemRightX, g.dressHemY))
        hem.addLine(to: p(g.dressHemLeftX, g.dressHemY))
        hem.close()
        Self.dressTrim.setFill()
        hem.fill()

        // Arms: a short dress-coloured stroke from the dress's own
        // shoulder out to each hand, so the hands read as attached to the
        // body rather than floating free with no arm between them.
        for (shoulderX, handX) in [(g.armShoulderLeftX, g.handLeftX), (g.armShoulderRightX, g.handRightX)] {
            let arm = UIBezierPath()
            arm.move(to: p(shoulderX, g.armShoulderY))
            arm.addLine(to: p(handX, g.handY))
            arm.lineWidth = stage.width * g.armLineWidthFraction
            arm.lineCapStyle = .round
            Self.dress.setStroke()
            arm.stroke()
        }

        // Two hands as simple rounded blobs, connected to the dress by the
        // arms drawn above.
        for cx: CGFloat in [g.handLeftX, g.handRightX] {
            let c = p(cx, g.handY)
            let r = stage.width * g.handRadiusFraction
            let hand = UIBezierPath(ovalIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * g.handHeightScale))
            Self.dress.setFill()
            hand.fill()
        }

        // Pigtails: round buns on either side, drawn before the head so
        // the head sits on top of their inner edge.
        for cx: CGFloat in [headCenter.fx - headRadius * g.pigtailOffsetRadii, headCenter.fx + headRadius * g.pigtailOffsetRadii] {
            let c = point(cx, headCenter.fy - g.pigtailYInset, in: stage)
            let r = stage.width * headRadius * g.pigtailRadiusFraction
            let bun = UIBezierPath(ovalIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
            Self.hair.setFill()
            bun.fill()
            // A little wisp trailing down from each bun.
            let wisp = UIBezierPath()
            wisp.move(to: CGPoint(x: c.x, y: c.y + r * g.wispStartRadii))
            wisp.addQuadCurve(to: CGPoint(x: c.x, y: c.y + r * g.wispEndRadii),
                               controlPoint: CGPoint(x: c.x + (cx < headCenter.fx ? -r : r), y: c.y + r * g.wispControlRadii))
            wisp.lineWidth = stage.width * g.wispLineWidthFraction
            wisp.lineCapStyle = .round
            Self.hair.setStroke()
            wisp.stroke()
        }

        // Head.
        let head = UIBezierPath(arcCenter: point(headCenter.fx, headCenter.fy, in: stage),
                                 radius: stage.width * headRadius,
                                 startAngle: 0, endAngle: .pi * 2, clockwise: true)
        Theme.skin.setFill()
        head.fill()

        // Fringe/bangs across the forehead: a dome from side to side whose
        // outer corners are pinned exactly onto the head's own circle (so
        // there's no sliver of skin between hair and head edge at 10/2
        // o'clock), and whose lower edge is a single smooth arc — not the
        // old two-segment dip that cut a V/dent across the forehead — so it
        // follows the head's curve instead of fighting it.
        let sideAngle = g.hairlineSideAngleDeg * .pi / 180
        let leftCorner = point(headCenter.fx - sin(sideAngle) * headRadius,
                                headCenter.fy - cos(sideAngle) * headRadius, in: stage)
        let rightCorner = point(headCenter.fx + sin(sideAngle) * headRadius,
                                 headCenter.fy - cos(sideAngle) * headRadius, in: stage)
        let peak = point(headCenter.fx, headCenter.fy - headRadius * g.hairlinePeakDepth, in: stage)
        let leftTopControl = point(headCenter.fx - headRadius * g.hairlineTopControlXInset,
                                    headCenter.fy - headRadius * g.hairlineTopControlDepth, in: stage)
        let rightTopControl = point(headCenter.fx + headRadius * g.hairlineTopControlXInset,
                                     headCenter.fy - headRadius * g.hairlineTopControlDepth, in: stage)
        let bottomControl = point(headCenter.fx, headCenter.fy - headRadius * g.hairlineCenterDepth, in: stage)

        let bangs = UIBezierPath()
        bangs.move(to: leftCorner)
        bangs.addQuadCurve(to: peak, controlPoint: leftTopControl)
        bangs.addQuadCurve(to: rightCorner, controlPoint: rightTopControl)
        bangs.addQuadCurve(to: leftCorner, controlPoint: bottomControl)
        bangs.close()
        Self.hair.setFill()
        bangs.fill()

        // Rosy cheeks.
        for cx: CGFloat in [headCenter.fx - headRadius * g.cheekXOffset, headCenter.fx + headRadius * g.cheekXOffset] {
            let c = point(cx, headCenter.fy + headRadius * g.cheekYOffset, in: stage)
            let r = stage.width * headRadius * g.cheekRadiusFraction
            let blush = UIBezierPath(ovalIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
            Self.cheek.withAlphaComponent(g.cheekAlpha).setFill()
            blush.fill()
        }
    }

    func drawEyes(in stage: CGRect, blinking: Bool) {
        let g = geometry
        for cx: CGFloat in [headCenter.fx - g.eyeXOffset, headCenter.fx + g.eyeXOffset] {
            let c = point(cx, headCenter.fy, in: stage)
            if blinking {
                let lash = UIBezierPath()
                lash.move(to: CGPoint(x: c.x - stage.width * g.lashHalfWidthFraction, y: c.y))
                lash.addLine(to: CGPoint(x: c.x + stage.width * g.lashHalfWidthFraction, y: c.y))
                lash.lineWidth = stage.width * g.lashLineWidthFraction
                lash.lineCapStyle = .round
                Theme.robeShadow.setStroke()
                lash.stroke()
                continue
            }
            let r = stage.width * g.eyeRadiusFraction
            let eye = UIBezierPath(ovalIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
            UIColor.white.setFill()
            eye.fill()
            let irisR = r * g.irisRadiusScale
            let iris = UIBezierPath(ovalIn: CGRect(x: c.x - irisR, y: c.y - irisR, width: irisR * 2, height: irisR * 2))
            UIColor(red: 0.20, green: 0.42, blue: 0.30, alpha: 1).setFill()
            iris.fill()
            let hl = irisR * g.highlightRadiusScale
            let highlight = UIBezierPath(ovalIn: CGRect(x: c.x - hl * g.highlightOffsetScale, y: c.y - hl * g.highlightOffsetScale, width: hl * 2, height: hl * 2))
            UIColor.white.setFill()
            highlight.fill()
        }
    }
}
