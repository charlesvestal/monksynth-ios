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

    func drawBody(in stage: CGRect) {
        func p(_ fx: CGFloat, _ fy: CGFloat) -> CGPoint { point(fx, fy, in: stage) }

        // Dress: a big, simple triangle/cone — most of the stage is body,
        // not head, on purpose.
        let dress = UIBezierPath()
        dress.move(to: p(0.5, 0.34))
        dress.addQuadCurve(to: p(0.08, 0.99), controlPoint: p(0.22, 0.62))
        dress.addLine(to: p(0.92, 0.99))
        dress.addQuadCurve(to: p(0.5, 0.34), controlPoint: p(0.78, 0.62))
        dress.close()
        Self.dress.setFill()
        dress.fill()

        // Hem trim.
        let hem = UIBezierPath()
        hem.move(to: p(0.08, 0.92))
        hem.addLine(to: p(0.92, 0.92))
        hem.addLine(to: p(0.92, 0.99))
        hem.addLine(to: p(0.08, 0.99))
        hem.close()
        Self.dressTrim.setFill()
        hem.fill()

        // Two short arms/sleeves as simple rounded blobs at the shoulders.
        for cx: CGFloat in [0.26, 0.74] {
            let c = p(cx, 0.46)
            let r = stage.width * 0.05
            let sleeve = UIBezierPath(ovalIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2.2))
            Self.dress.setFill()
            sleeve.fill()
        }

        // Pigtails: round buns on either side, drawn before the head so
        // the head sits on top of their inner edge.
        for cx: CGFloat in [headCenter.fx - headRadius * 1.5, headCenter.fx + headRadius * 1.5] {
            let c = point(cx, headCenter.fy - 0.01, in: stage)
            let r = stage.width * headRadius * 0.62
            let bun = UIBezierPath(ovalIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
            Self.hair.setFill()
            bun.fill()
            // A little wisp trailing down from each bun.
            let wisp = UIBezierPath()
            wisp.move(to: CGPoint(x: c.x, y: c.y + r * 0.6))
            wisp.addQuadCurve(to: CGPoint(x: c.x, y: c.y + r * 2.0),
                               controlPoint: CGPoint(x: c.x + (cx < headCenter.fx ? -r : r), y: c.y + r * 1.3))
            wisp.lineWidth = stage.width * 0.02
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

        // Fringe/bangs across the forehead.
        let bangs = UIBezierPath()
        bangs.move(to: point(headCenter.fx - headRadius * 0.95, headCenter.fy - headRadius * 0.25, in: stage))
        bangs.addQuadCurve(to: point(headCenter.fx, headCenter.fy - headRadius * 0.85, in: stage),
                            controlPoint: point(headCenter.fx - headRadius * 0.4, headCenter.fy - headRadius * 1.15, in: stage))
        bangs.addQuadCurve(to: point(headCenter.fx + headRadius * 0.95, headCenter.fy - headRadius * 0.25, in: stage),
                            controlPoint: point(headCenter.fx + headRadius * 0.4, headCenter.fy - headRadius * 1.15, in: stage))
        bangs.addQuadCurve(to: point(headCenter.fx, headCenter.fy - headRadius * 0.42, in: stage),
                            controlPoint: point(headCenter.fx, headCenter.fy - headRadius * 0.55, in: stage))
        bangs.close()
        Self.hair.setFill()
        bangs.fill()

        // Rosy cheeks.
        for cx: CGFloat in [headCenter.fx - headRadius * 0.7, headCenter.fx + headRadius * 0.7] {
            let c = point(cx, headCenter.fy + headRadius * 0.35, in: stage)
            let r = stage.width * headRadius * 0.28
            let blush = UIBezierPath(ovalIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
            Self.cheek.withAlphaComponent(0.5).setFill()
            blush.fill()
        }
    }

    func drawEyes(in stage: CGRect, blinking: Bool) {
        for cx: CGFloat in [headCenter.fx - 0.045, headCenter.fx + 0.045] {
            let c = point(cx, headCenter.fy, in: stage)
            if blinking {
                let lash = UIBezierPath()
                lash.move(to: CGPoint(x: c.x - stage.width * 0.024, y: c.y))
                lash.addLine(to: CGPoint(x: c.x + stage.width * 0.024, y: c.y))
                lash.lineWidth = stage.width * 0.01
                lash.lineCapStyle = .round
                Theme.robeShadow.setStroke()
                lash.stroke()
                continue
            }
            let r = stage.width * 0.03
            let eye = UIBezierPath(ovalIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
            UIColor.white.setFill()
            eye.fill()
            let irisR = r * 0.68
            let iris = UIBezierPath(ovalIn: CGRect(x: c.x - irisR, y: c.y - irisR, width: irisR * 2, height: irisR * 2))
            UIColor(red: 0.20, green: 0.42, blue: 0.30, alpha: 1).setFill()
            iris.fill()
            let hl = irisR * 0.34
            let highlight = UIBezierPath(ovalIn: CGRect(x: c.x - hl * 1.3, y: c.y - hl * 1.3, width: hl * 2, height: hl * 2))
            UIColor.white.setFill()
            highlight.fill()
        }
    }
}
