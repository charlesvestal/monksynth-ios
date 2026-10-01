import UIKit

/// The one mouth every drawn character sings with: five anchors —
/// OO (small pucker), OH (round), AH (tall, tongue), EH (wide, top teeth),
/// EE (slit, both rows of teeth) — interpolated linearly. Ported from
/// gen.mjs `ANCHORS` / `mouthPath` / `mouth`. All sizes are stage units
/// (the 300-unit space of `Toon.inStage`) at scale 1.
enum ToonMouth {
    struct Params: Equatable {
        var w, h, round, tongue, top, bottom: CGFloat
    }

    enum Variant { case lips, muzzle, bare }

    struct Style {
        var x: CGFloat
        var y: CGFloat
        var scale: CGFloat
        var variant: Variant
        var lip: UIColor = .clear
    }

    static let anchors: [Params] = [
        Params(w: 24, h: 26, round: 1.0, tongue: 0.0, top: 0, bottom: 0),   // OO
        Params(w: 34, h: 40, round: 1.0, tongue: 0.3, top: 0, bottom: 0),   // OH
        Params(w: 50, h: 56, round: 0.9, tongue: 1.0, top: 0, bottom: 0),   // AH
        Params(w: 64, h: 34, round: 0.45, tongue: 0.8, top: 1, bottom: 0),  // EH
        Params(w: 74, h: 18, round: 0.12, tongue: 0.0, top: 1, bottom: 1),  // EE
    ]

    static let cavity = UIColor(hex: 0x4A1622)
    static let tongue = UIColor(hex: 0xE8607A)
    static let teeth = UIColor(hex: 0xFFFAF0)

    static func params(vowel: Float) -> Params {
        let t = CGFloat(min(max(vowel, 0), 1)) * 4
        let i = min(3, Int(t))
        let f = t - CGFloat(i)
        let a = anchors[i], b = anchors[i + 1]
        func mix(_ x: CGFloat, _ y: CGFloat) -> CGFloat { x + (y - x) * f }
        return Params(w: mix(a.w, b.w), h: mix(a.h, b.h), round: mix(a.round, b.round),
                      tongue: mix(a.tongue, b.tongue), top: mix(a.top, b.top), bottom: mix(a.bottom, b.bottom))
    }

    /// The aperture: four cubics, the bottom dropping further than the top.
    /// `round` 1 is an ellipse; toward 0 the corners pinch to points.
    static func path(cx: CGFloat, cy: CGFloat, w: CGFloat, h: CGFloat, round: CGFloat) -> UIBezierPath {
        let l = cx - w / 2, r = cx + w / 2
        let t = cy - h * 0.42, b = cy + h * 0.58
        let kx = (w / 2) * 0.552, kyT = h * 0.42 * 0.552 * round, kyB = h * 0.58 * 0.552 * round
        let p = UIBezierPath()
        p.move(to: CGPoint(x: l, y: cy))
        p.addCurve(to: CGPoint(x: cx, y: t), controlPoint1: CGPoint(x: l, y: cy - kyT), controlPoint2: CGPoint(x: cx - kx, y: t))
        p.addCurve(to: CGPoint(x: r, y: cy), controlPoint1: CGPoint(x: cx + kx, y: t), controlPoint2: CGPoint(x: r, y: cy - kyT))
        p.addCurve(to: CGPoint(x: cx, y: b), controlPoint1: CGPoint(x: r, y: cy + kyB), controlPoint2: CGPoint(x: cx + kx, y: b))
        p.addCurve(to: CGPoint(x: l, y: cy), controlPoint1: CGPoint(x: cx - kx, y: b), controlPoint2: CGPoint(x: l, y: cy + kyB))
        p.close()
        return p
    }

    /// Draws in stage units; call inside `Toon.inStage`.
    /// `boost` is `CharacterView`'s stepped amplitude swell (≥ 1), applied to height.
    static func draw(_ s: Style, vowel: Float, boost: CGFloat) {
        let p = params(vowel: vowel)
        let w = p.w * s.scale, h = p.h * s.scale * boost
        let path = path(cx: s.x, cy: s.y, w: w, h: h, round: p.round)
        if s.variant == .lips {
            Toon.stroke(path, width: 17 * s.scale)
            Toon.stroke(path, width: 10 * s.scale, color: s.lip)
        }
        Toon.fill(path, cavity)
        Toon.clipped(to: path) {
            if p.tongue > 0.02 {
                Toon.fill(Toon.ellipse(s.x + w * 0.08, s.y + h * 0.58, w * 0.38, h * 0.42 * p.tongue), tongue)
            }
            if p.top > 0.02 {
                Toon.fill(Toon.rect(s.x - w, s.y - h, w * 2, h * 0.42 + h * 0.3 * p.top - h * 0.12), teeth)
            }
            if p.bottom > 0.02 {
                Toon.fill(Toon.rect(s.x - w, s.y + h * 0.58 - h * 0.28 * p.bottom, w * 2, h), teeth)
            }
        }
        Toon.stroke(path, width: (s.variant == .lips ? Toon.fine : Toon.medium) * max(0.8, s.scale))
    }
}
