import UIKit

/// The sticker-cartoon drawing kit every character and scene shares: bold
/// ink outlines, flat fills, one hard shadow tone offset up-left so the
/// shadow reads as a crescent on the lower right.
///
/// Characters draw in a 300×300 "stage unit" space (see `inStage`) — the
/// same space the approved mockups in `docs/mockups/stage-redesign/gen.mjs`
/// use — so their path data ports number-for-number. Backdrops draw in
/// point space and pass `unit` so their outlines match the character's.
enum Toon {
    static let ink = UIColor(hex: 0x2B1D1A)

    /// Outline widths in stage units.
    static let bold: CGFloat = 7
    static let medium: CGFloat = 5
    static let fine: CGFloat = 3.5

    static let stageUnits: CGFloat = 300
    /// The shaded copy of a shape is the shape moved up-left by this much
    /// (in stage units); what it uncovers is the shadow.
    static let shadowOffset = CGSize(width: -9, height: -8)

    // MARK: - Stage mapping

    /// Runs `body` with the current context mapped so (0,0)…(300,300) covers
    /// `stage`. Nothing drawn inside leaks its transform.
    static func inStage(_ stage: CGRect, _ body: (CGContext) -> Void) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        ctx.saveGState()
        ctx.translateBy(x: stage.minX, y: stage.minY)
        ctx.scaleBy(x: stage.width / stageUnits, y: stage.height / stageUnits)
        body(ctx)
        ctx.restoreGState()
    }

    // MARK: - Shapes

    static func circle(_ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat) -> UIBezierPath {
        UIBezierPath(ovalIn: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2))
    }

    static func ellipse(_ cx: CGFloat, _ cy: CGFloat, _ rx: CGFloat, _ ry: CGFloat) -> UIBezierPath {
        UIBezierPath(ovalIn: CGRect(x: cx - rx, y: cy - ry, width: rx * 2, height: ry * 2))
    }

    static func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> UIBezierPath {
        UIBezierPath(rect: CGRect(x: x, y: y, width: w, height: h))
    }

    /// `path` rotated by `degrees` about (cx, cy) — gen.mjs's `rotate(a cx cy)`.
    static func rotated(_ path: UIBezierPath, degrees: CGFloat, cx: CGFloat, cy: CGFloat) -> UIBezierPath {
        let p = path.copy() as! UIBezierPath
        p.apply(CGAffineTransform(translationX: -cx, y: -cy))
        p.apply(CGAffineTransform(rotationAngle: degrees * .pi / 180))
        p.apply(CGAffineTransform(translationX: cx, y: cy))
        return p
    }

    /// gen.mjs `toon(...)`: fill, hard shadow, ink outline.
    /// `shadow` defaults to the fill at 80% brightness (gen.mjs `shade(base, 0.8)`).
    static func shape(_ path: UIBezierPath, fill: UIColor, lineWidth: CGFloat = bold,
                      shaded: Bool = true, shadow: UIColor? = nil, unit: CGFloat = 1) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        if shaded {
            (shadow ?? fill.adjusted(brightnessScale: 0.8)).setFill()
            path.fill()
            ctx.saveGState()
            path.addClip()
            let lit = path.copy() as! UIBezierPath
            lit.apply(CGAffineTransform(translationX: shadowOffset.width * unit, y: shadowOffset.height * unit))
            fill.setFill()
            lit.fill()
            ctx.restoreGState()
        } else {
            fill.setFill()
            path.fill()
        }
        stroke(path, width: lineWidth * unit)
    }

    /// gen.mjs `line(...)`: a round-capped, round-joined stroke.
    static func stroke(_ path: UIBezierPath, width: CGFloat, color: UIColor = ink) {
        color.setStroke()
        path.lineWidth = width
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        path.stroke()
    }

    /// A plain fill, for gen.mjs raw `<ellipse fill=… opacity=…>` details.
    static func fill(_ path: UIBezierPath, _ color: UIColor) {
        color.setFill()
        path.fill()
    }

    /// Draws `body` clipped to `path` (gen.mjs `clip-path` groups).
    static func clipped(to path: UIBezierPath, _ body: () -> Void) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        ctx.saveGState()
        path.addClip()
        body()
        ctx.restoreGState()
    }

    // MARK: - Face parts (gen.mjs eyeOpen / eyeClosed / cheek / hl)

    static func highlight(_ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat) {
        fill(circle(cx, cy, r), .white)
    }

    static func eyeOpen(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat,
                        iris: UIColor = ink, look: CGPoint = CGPoint(x: 2, y: 1)) {
        shape(circle(x, y, r), fill: .white, lineWidth: medium, shaded: false)
        fill(circle(x + look.x, y + look.y, r * 0.55), iris)
        if iris != ink { fill(circle(x + look.x, y + look.y, r * 0.28), ink) }
        highlight(x + look.x - r * 0.2, y + look.y - r * 0.22, r * 0.18)
    }

    static func eyeClosed(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat) {
        stroke(path("M\(x - w) \(y) Q\(x) \(y + w * 0.75) \(x + w) \(y)"), width: medium)
    }

    static func cheek(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat = 11, color: UIColor = UIColor(hex: 0xF28B9B)) {
        fill(ellipse(x, y, r, r * 0.65), color.withAlphaComponent(0.75))
    }

    // MARK: - SVG path parsing

    /// Parses the absolute SVG path subset gen.mjs emits: M L H V C Q Z, and
    /// A for circular arcs (rx == ry, no rotation).
    static func path(_ d: String) -> UIBezierPath {
        var scanner = PathScanner(d)
        let p = UIBezierPath()
        var current = CGPoint.zero
        var start = CGPoint.zero
        var command: Swift.Character = "M"
        while let next = scanner.nextCommandOrNumber() {
            if case .command(let c) = next { command = c }
            else { scanner.pushBack(next) }
            switch command {
            case "M":
                current = scanner.point(); start = current; p.move(to: current)
                command = "L"   // subsequent pairs are implicit lineTos
            case "L":
                current = scanner.point(); p.addLine(to: current)
            case "H":
                current.x = scanner.number(); p.addLine(to: current)
            case "V":
                current.y = scanner.number(); p.addLine(to: current)
            case "C":
                let c1 = scanner.point(), c2 = scanner.point(); current = scanner.point()
                p.addCurve(to: current, controlPoint1: c1, controlPoint2: c2)
            case "Q":
                let c = scanner.point(); current = scanner.point()
                p.addQuadCurve(to: current, controlPoint: c)
            case "A":
                let r = scanner.number(); _ = scanner.number(); _ = scanner.number()
                let large = scanner.number() != 0, sweep = scanner.number() != 0
                let end = scanner.point()
                addArc(to: p, from: current, to: end, radius: r, largeArc: large, sweep: sweep)
                current = end
            case "Z", "z":
                p.close(); current = start
            default:
                return p
            }
        }
        return p
    }

    /// SVG arc (endpoint form, rx == ry, no rotation) → centre form.
    /// SVG spec F.6.5 with the rotation terms dropped.
    private static func addArc(to p: UIBezierPath, from p0: CGPoint, to p1: CGPoint,
                               radius: CGFloat, largeArc: Bool, sweep: Bool) {
        let x1p = (p0.x - p1.x) / 2, y1p = (p0.y - p1.y) / 2
        let d2 = x1p * x1p + y1p * y1p
        guard d2 > 0 else { return }
        var r = radius
        if d2 > r * r { r = sqrt(d2) }   // radius too small: SVG scales it up
        let coef = (largeArc != sweep ? 1 : -1) * sqrt(max(0, (r * r - d2) / d2))
        let cxp = coef * y1p, cyp = -coef * x1p
        let c = CGPoint(x: cxp + (p0.x + p1.x) / 2, y: cyp + (p0.y + p1.y) / 2)
        let a0 = atan2((y1p - cyp) / r, (x1p - cxp) / r)
        let a1 = atan2((-y1p - cyp) / r, (-x1p - cxp) / r)
        var delta = a1 - a0
        if sweep && delta < 0 { delta += 2 * .pi }
        if !sweep && delta > 0 { delta -= 2 * .pi }
        p.addArc(withCenter: c, radius: r, startAngle: a0, endAngle: a0 + delta, clockwise: sweep)
    }

    private struct PathScanner {
        enum Token { case command(Swift.Character), number(CGFloat) }
        private let chars: [Swift.Character]
        private var i = 0
        private var pending: Token?
        init(_ s: String) { chars = Array(s) }

        mutating func pushBack(_ t: Token) { pending = t }

        mutating func nextCommandOrNumber() -> Token? {
            if let t = pending { pending = nil; return t }
            while i < chars.count, chars[i] == " " || chars[i] == "," || chars[i] == "\n" { i += 1 }
            guard i < chars.count else { return nil }
            let c = chars[i]
            if c.isLetter { i += 1; return .command(c) }
            // Anything that isn't a number start (digit, sign or decimal
            // point) is unparseable: stop instead of looping with `i`
            // stuck, which would hang path()'s caller forever.
            guard c.isNumber || c == "-" || c == "+" || c == "." else { return nil }
            return .number(scanNumber())
        }

        /// Reads a number, or leaves an unexpected command token for the
        /// caller to see on its next read instead of silently discarding it.
        mutating func number() -> CGFloat {
            guard let t = nextCommandOrNumber() else { return 0 }
            if case .number(let n) = t { return n }
            pending = t
            return 0
        }

        mutating func point() -> CGPoint { CGPoint(x: number(), y: number()) }

        private mutating func scanNumber() -> CGFloat {
            let startIndex = i
            if i < chars.count, chars[i] == "-" || chars[i] == "+" { i += 1 }
            var seenDot = false
            while i < chars.count {
                let c = chars[i]
                if c.isNumber { i += 1 }
                else if c == ".", !seenDot { seenDot = true; i += 1 }
                else if c == "e" || c == "E" {
                    i += 1
                    if i < chars.count, chars[i] == "-" || chars[i] == "+" { i += 1 }
                } else { break }
            }
            return CGFloat(Double(String(chars[startIndex..<i])) ?? 0)
        }
    }
}

extension UIColor {
    /// 0xRRGGBB.
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: alpha)
    }
}

/// A character's colours: the scene's sky and ground, and the accent the
/// chrome (active tab, knob arcs, touch marker, selector chevron) takes on
/// while that character is loaded.
struct Palette: Equatable {
    var accent: UIColor
    var skyTop: UIColor
    var skyBottom: UIColor
    var ground: UIColor

    static let neutral = Palette(accent: UIColor(hex: 0xF0A020),
                                 skyTop: UIColor(hex: 0x3A3040),
                                 skyBottom: UIColor(hex: 0x2A2230),
                                 ground: UIColor(hex: 0x4A3D41))
}

/// Everything a face reacts to, already stepped by `CharacterView` so it
/// moves in frames: blink state, loudness (0…1, four steps) and the
/// quantised vowel.
struct Expression: Equatable {
    var blinking: Bool
    var loudness: CGFloat
    var vowel: Float

    static let rest = Expression(blinking: false, loudness: 0, vowel: 0.5)
}
