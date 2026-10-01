import UIKit

/// Scene primitives. Everything draws in point space; `u` is the
/// character's stage-unit scale (stage width / 300) so outlines match.
enum Backdrop {
    /// Sky gradient over a ground band — the fallback scene.
    static func plain(in rect: CGRect, stage: CGRect, palette: Palette) {
        sky(rect, top: palette.skyTop, bottom: palette.skyBottom)
        let u = max(stage.width, 1) / Toon.stageUnits
        ground(rect, y: rect.minY + rect.height * 0.72, color: palette.ground, u: u)
    }

    /// Shared shell for every character's `drawBackdrop`: clips to `rect`,
    /// translates so scene coordinates start at (0,0), draws the sky, then
    /// hands `body` the local width/height and the stage-unit scale `u` for
    /// its own prop calls. Every gen.mjs `scene()` case draws its sky first,
    /// so this always does too.
    static func scene(in rect: CGRect, stage: CGRect, palette: Palette,
                      _ body: (_ W: CGFloat, _ H: CGFloat, _ u: CGFloat) -> Void) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        ctx.saveGState()
        ctx.clip(to: rect)
        ctx.translateBy(x: rect.minX, y: rect.minY)
        let W = rect.width, H = rect.height, u = stage.width / Toon.stageUnits
        sky(CGRect(x: 0, y: 0, width: W, height: H), top: palette.skyTop, bottom: palette.skyBottom)
        body(W, H, u)
        ctx.restoreGState()
    }

    static func sky(_ rect: CGRect, top: UIColor, bottom: UIColor) {
        guard let ctx = UIGraphicsGetCurrentContext(),
              let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                 colors: [top.cgColor, bottom.cgColor] as CFArray,
                                 locations: [0, 1]) else { return }
        ctx.saveGState()
        ctx.clip(to: rect)
        ctx.drawLinearGradient(g, start: CGPoint(x: rect.midX, y: rect.minY),
                               end: CGPoint(x: rect.midX, y: rect.maxY), options: [])
        ctx.restoreGState()
    }

    /// gen.mjs `ground(W, H, gy, col)`: a band from `y` to the bottom with an ink top edge.
    static func ground(_ rect: CGRect, y: CGFloat, color: UIColor, u: CGFloat) {
        let band = Toon.rect(rect.minX - 10, y, rect.width + 20, rect.maxY - y + 10)
        Toon.fill(band, color)
        Toon.stroke(band, width: Toon.medium * u)
    }

    // MARK: - Props (gen.mjs `prop`)

    static func mountain(_ x: CGFloat, _ y: CGFloat, _ k: CGFloat, u: CGFloat) {
        Toon.shape(Toon.path("M\(x - 90 * k) \(y) L\(x) \(y - 110 * k) L\(x + 90 * k) \(y) Z"),
                   fill: UIColor(hex: 0x8C8FB8), lineWidth: Toon.medium, unit: u)
        Toon.shape(Toon.path("M\(x - 30 * k) \(y - 73 * k) L\(x) \(y - 110 * k) L\(x + 30 * k) \(y - 73 * k) L\(x + 14 * k) \(y - 80 * k) L\(x) \(y - 70 * k) L\(x - 14 * k) \(y - 80 * k) Z"),
                   fill: .white, lineWidth: Toon.fine, shaded: false, unit: u)
    }

    static func sun(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat, u: CGFloat) {
        for i in 0..<12 {
            let a = CGFloat(i) * .pi / 6
            let p = UIBezierPath()
            p.move(to: CGPoint(x: x + cos(a) * r * 1.3, y: y + sin(a) * r * 1.3))
            p.addLine(to: CGPoint(x: x + cos(a) * r * 1.7, y: y + sin(a) * r * 1.7))
            Toon.stroke(p, width: 9 * u)
            Toon.stroke(p, width: 4.5 * u, color: UIColor(hex: 0xFFD35A))
        }
        Toon.shape(Toon.circle(x, y, r), fill: UIColor(hex: 0xFFD35A), lineWidth: Toon.medium, shaded: false, unit: u)
    }

    static func moon(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat, u: CGFloat) {
        Toon.shape(Toon.circle(x, y, r), fill: UIColor(hex: 0xFFF3C4), lineWidth: Toon.medium, shaded: false, unit: u)
        Toon.fill(Toon.circle(x + r * 0.3, y - r * 0.2, r * 0.2), UIColor(hex: 0xEFE0A8))
    }

    static func cloud(_ x: CGFloat, _ y: CGFloat, _ k: CGFloat, u: CGFloat) {
        let d = "M\(x - 40 * k) \(y) C\(x - 50 * k) \(y - 20 * k) \(x - 26 * k) \(y - 32 * k) \(x - 14 * k) \(y - 22 * k) " +
            "C\(x - 8 * k) \(y - 44 * k) \(x + 24 * k) \(y - 42 * k) \(x + 24 * k) \(y - 20 * k) " +
            "C\(x + 46 * k) \(y - 26 * k) \(x + 52 * k) \(y) \(x + 40 * k) \(y) Z"
        Toon.shape(Toon.path(d), fill: .white, lineWidth: Toon.medium, shaded: false, unit: u)
    }

    private static let flagColors: [UInt32] = [0x3B82F6, 0xFFFFFF, 0xE5463A, 0x3FB56B, 0xF5C33B]

    static func flags(_ x0: CGFloat, _ x1: CGFloat, _ y: CGFloat, u: CGFloat) {
        Toon.stroke(Toon.path("M\(x0) \(y) Q\((x0 + x1) / 2) \(y + 26) \(x1) \(y)"), width: 2.5 * u)
        let n = max(4, Int(((x1 - x0) / 34).rounded(.down)))
        for i in 1..<n {
            let t = CGFloat(i) / CGFloat(n)
            let x = x0 + (x1 - x0) * t
            let yq = y + 52 * t * (1 - t)
            let p = UIBezierPath()
            p.move(to: CGPoint(x: x - 10, y: yq))
            p.addLine(to: CGPoint(x: x + 10, y: yq))
            p.addLine(to: CGPoint(x: x + 8, y: yq + 22))
            p.addLine(to: CGPoint(x: x - 8, y: yq + 22))
            p.close()
            Toon.fill(p, UIColor(hex: flagColors[i % 5]))
            Toon.stroke(p, width: 2.5 * u)
        }
    }

    static func bubble(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat, u: CGFloat) {
        let c = Toon.circle(x, y, r)
        Toon.fill(c, UIColor.white.withAlphaComponent(0.25))
        Toon.stroke(c, width: 3 * u, color: UIColor(hex: 0xE6F6FF))
        Toon.fill(Toon.circle(x - r * 0.35, y - r * 0.35, r * 0.22), .white)
    }

    static func kelp(_ x: CGFloat, _ y: CGFloat, _ h: CGFloat, u: CGFloat) {
        let d = "M\(x) \(y) C\(x - 18) \(y - h * 0.3) \(x + 18) \(y - h * 0.6) \(x) \(y - h)"
        Toon.stroke(Toon.path(d), width: 9 * u, color: Toon.ink)
        Toon.stroke(Toon.path(d), width: 5 * u, color: UIColor(hex: 0x3FAE6A))
    }

    static func tree(_ x: CGFloat, _ y: CGFloat, _ k: CGFloat, u: CGFloat) {
        Toon.shape(Toon.path("M\(x - 10 * k) \(y) L\(x - 8 * k) \(y - 60 * k) L\(x + 8 * k) \(y - 60 * k) L\(x + 10 * k) \(y) Z"),
                   fill: UIColor(hex: 0x8A5A33), lineWidth: Toon.medium, unit: u)
        Toon.shape(Toon.circle(x, y - 90 * k, 44 * k), fill: UIColor(hex: 0x3FAE5A), lineWidth: Toon.medium, unit: u)
    }

    static func kite(_ x: CGFloat, _ y: CGFloat, _ k: CGFloat, u: CGFloat) {
        Toon.shape(Toon.path("M\(x) \(y - 30 * k) L\(x + 20 * k) \(y) L\(x) \(y + 34 * k) L\(x - 20 * k) \(y) Z"),
                   fill: UIColor(hex: 0xFFCF3A), lineWidth: Toon.fine, unit: u)
        Toon.stroke(Toon.path("M\(x) \(y + 34 * k) C\(x - 20) \(y + 70 * k) \(x + 20) \(y + 90 * k) \(x - 10) \(y + 130 * k)"), width: 2 * u)
    }

    private static let rainbowColors: [UInt32] = [0xFF7AA8, 0xFFCF5A, 0x7ED98A, 0x7AB8FF, 0xB78CFF]

    static func rainbow(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat, u: CGFloat) {
        for (i, hex) in rainbowColors.enumerated() {
            let rr = r - CGFloat(i) * 10
            Toon.stroke(Toon.path("M\(x - r + CGFloat(i) * 10) \(y) A\(rr) \(rr) 0 0 1 \(x + r - CGFloat(i) * 10) \(y)"),
                       width: 10 * u, color: UIColor(hex: hex))
        }
        Toon.stroke(Toon.path("M\(x - r - 5) \(y) A\(r + 5) \(r + 5) 0 0 1 \(x + r + 5) \(y)"), width: 3 * u)
        Toon.stroke(Toon.path("M\(x - r + 45) \(y) A\(r - 45) \(r - 45) 0 0 1 \(x + r - 45) \(y)"), width: 3 * u)
    }

    static func fence(_ x0: CGFloat, _ x1: CGFloat, _ y: CGFloat, u: CGFloat) {
        Toon.shape(Toon.rect(x0, y - 34, x1 - x0, 9), fill: UIColor(hex: 0xF1E3C6), lineWidth: Toon.fine, shaded: false, unit: u)
        var x = x0 + 10
        while x < x1 {
            Toon.shape(Toon.rect(x, y - 50, 12, 50), fill: UIColor(hex: 0xF1E3C6), lineWidth: Toon.fine, shaded: false, unit: u)
            x += 34
        }
    }

    static func barn(_ x: CGFloat, _ y: CGFloat, _ k: CGFloat, u: CGFloat) {
        Toon.shape(Toon.path("M\(x - 50 * k) \(y) L\(x - 50 * k) \(y - 60 * k) L\(x) \(y - 95 * k) L\(x + 50 * k) \(y - 60 * k) L\(x + 50 * k) \(y) Z"),
                   fill: UIColor(hex: 0xD6453A), lineWidth: Toon.medium, unit: u)
        Toon.shape(Toon.rect(x - 18 * k, y - 44 * k, 36 * k, 44 * k), fill: UIColor(hex: 0xF6EFE0), lineWidth: Toon.fine, shaded: false, unit: u)
    }

    static func bricks(_ W: CGFloat, _ gy: CGFloat, u: CGFloat) {
        var y: CGFloat = 14
        var r = 0
        while y < gy {
            Toon.stroke(Toon.path("M0 \(y) L\(W) \(y)"), width: 3 * u, color: UIColor(hex: 0x8A3B2A))
            var x = CGFloat(r % 2) * 30
            while x < W {
                Toon.stroke(Toon.path("M\(x) \(y) L\(x) \(y + 26)"), width: 3 * u, color: UIColor(hex: 0x8A3B2A))
                x += 60
            }
            y += 26
            r += 1
        }
    }

    static func hydrant(_ x: CGFloat, _ y: CGFloat, _ k: CGFloat, u: CGFloat) {
        Toon.shape(Toon.path("M\(x - 14 * k) \(y) L\(x - 14 * k) \(y - 46 * k) C\(x - 14 * k) \(y - 66 * k) \(x + 14 * k) \(y - 66 * k) \(x + 14 * k) \(y - 46 * k) L\(x + 14 * k) \(y) Z"),
                   fill: UIColor(hex: 0xE2433A), lineWidth: Toon.medium, unit: u)
        Toon.shape(Toon.rect(x - 22 * k, y - 40 * k, 44 * k, 10 * k), fill: UIColor(hex: 0xC9302A), lineWidth: Toon.fine, shaded: false, unit: u)
    }

    static func amp(_ x: CGFloat, _ y: CGFloat, _ k: CGFloat, u: CGFloat) {
        Toon.shape(Toon.rect(x - 34 * k, y - 70 * k, 68 * k, 70 * k), fill: UIColor(hex: 0x1E1C22), lineWidth: Toon.medium, unit: u)
        Toon.fill(Toon.rect(x - 26 * k, y - 62 * k, 52 * k, 54 * k), UIColor(hex: 0x3A3640))
        Toon.fill(Toon.circle(x, y - 35 * k, 18 * k), UIColor(hex: 0x222222))
        Toon.stroke(Toon.circle(x, y - 35 * k, 18 * k), width: 3 * u, color: UIColor(hex: 0x555555))
        Toon.shape(Toon.rect(x - 34 * k, y - 96 * k, 68 * k, 26 * k), fill: UIColor(hex: 0x1E1C22), lineWidth: Toon.medium, unit: u)
        Toon.fill(Toon.circle(x - 20 * k, y - 83 * k, 4 * k), UIColor(hex: 0x7DFF3A))
    }

    static func spot(_ x: CGFloat, _ H: CGFloat, color: UIColor) {
        Toon.fill(Toon.path("M\(x - 14) 0 L\(x + 14) 0 L\(x + 120) \(H) L\(x - 120) \(H) Z"), color.withAlphaComponent(0.18))
    }

    static func doghouse(_ x: CGFloat, _ y: CGFloat, _ k: CGFloat, u: CGFloat) {
        Toon.shape(Toon.path("M\(x - 46 * k) \(y) L\(x - 46 * k) \(y - 50 * k) L\(x) \(y - 88 * k) L\(x + 46 * k) \(y - 50 * k) L\(x + 46 * k) \(y) Z"),
                   fill: UIColor(hex: 0x5AA0D8), lineWidth: Toon.medium, unit: u)
        Toon.shape(Toon.path("M\(x - 16 * k) \(y) L\(x - 16 * k) \(y - 26 * k) C\(x - 16 * k) \(y - 44 * k) \(x + 16 * k) \(y - 44 * k) \(x + 16 * k) \(y - 26 * k) L\(x + 16 * k) \(y) Z"),
                   fill: Toon.ink, lineWidth: Toon.fine, shaded: false, unit: u)
        Toon.shape(Toon.path("M\(x - 56 * k) \(y - 46 * k) L\(x) \(y - 96 * k) L\(x + 56 * k) \(y - 46 * k) L\(x + 46 * k) \(y - 40 * k) L\(x) \(y - 82 * k) L\(x - 46 * k) \(y - 40 * k) Z"),
                   fill: UIColor(hex: 0xD6453A), lineWidth: Toon.fine, unit: u)
    }

    static func bone(_ x: CGFloat, _ y: CGFloat, _ k: CGFloat, u: CGFloat) {
        let d = "M\(x - 22 * k) \(y - 4 * k) L\(x + 22 * k) \(y - 4 * k) " +
            "C\(x + 26 * k) \(y - 16 * k) \(x + 38 * k) \(y - 10 * k) \(x + 32 * k) \(y) " +
            "C\(x + 38 * k) \(y + 10 * k) \(x + 26 * k) \(y + 16 * k) \(x + 22 * k) \(y + 4 * k) L\(x - 22 * k) \(y + 4 * k) " +
            "C\(x - 26 * k) \(y + 16 * k) \(x - 38 * k) \(y + 10 * k) \(x - 32 * k) \(y) " +
            "C\(x - 38 * k) \(y - 10 * k) \(x - 26 * k) \(y - 16 * k) \(x - 22 * k) \(y - 4 * k) Z"
        Toon.shape(Toon.path(d), fill: UIColor(hex: 0xFBF3E0), lineWidth: Toon.fine, shaded: false, unit: u)
    }

    static func checker(_ W: CGFloat, _ H: CGFloat, _ gy: CGFloat, u: CGFloat) {
        Toon.fill(Toon.rect(0, gy, W, H - gy), .white)
        let sz: CGFloat = 30
        var y = gy
        var r = 0
        while y < H {
            var x = CGFloat(r % 2) * sz
            while x < W {
                Toon.fill(Toon.rect(x, y, sz, sz), UIColor(hex: 0xE04B3C))
                x += sz * 2
            }
            y += sz
            r += 1
        }
        Toon.stroke(Toon.path("M0 \(gy) L\(W) \(gy)"), width: Toon.medium * u)
    }

    static func candle(_ x: CGFloat, _ y: CGFloat, _ k: CGFloat, u: CGFloat) {
        Toon.shape(Toon.path("M\(x - 16 * k) \(y) L\(x - 16 * k) \(y - 40 * k) C\(x - 16 * k) \(y - 54 * k) \(x - 6 * k) \(y - 56 * k) \(x - 6 * k) \(y - 70 * k) L\(x + 6 * k) \(y - 70 * k) C\(x + 6 * k) \(y - 56 * k) \(x + 16 * k) \(y - 54 * k) \(x + 16 * k) \(y - 40 * k) L\(x + 16 * k) \(y) Z"),
                   fill: UIColor(hex: 0x3B7A4A), lineWidth: Toon.medium, unit: u)
        Toon.shape(Toon.rect(x - 5 * k, y - 100 * k, 10 * k, 32 * k), fill: UIColor(hex: 0xFFF6E0), lineWidth: Toon.fine, shaded: false, unit: u)
        Toon.shape(Toon.path("M\(x) \(y - 124 * k) C\(x + 9 * k) \(y - 112 * k) \(x + 7 * k) \(y - 102 * k) \(x) \(y - 102 * k) C\(x - 7 * k) \(y - 102 * k) \(x - 9 * k) \(y - 112 * k) \(x) \(y - 124 * k) Z"),
                   fill: UIColor(hex: 0xFFCF3A), lineWidth: Toon.fine, shaded: false, unit: u)
    }

    /// No cross — the mockup's current `tomb` draws only the stone.
    static func tomb(_ x: CGFloat, _ y: CGFloat, _ k: CGFloat, u: CGFloat) {
        Toon.shape(Toon.path("M\(x - 22 * k) \(y) L\(x - 22 * k) \(y - 40 * k) C\(x - 22 * k) \(y - 66 * k) \(x + 22 * k) \(y - 66 * k) \(x + 22 * k) \(y - 40 * k) L\(x + 22 * k) \(y) Z"),
                   fill: UIColor(hex: 0x8F97B8), lineWidth: Toon.medium, unit: u)
    }

    static func star(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat, u: CGFloat) {
        let d = "M\(x) \(y - r) L\(x + r * 0.3) \(y - r * 0.3) L\(x + r) \(y) L\(x + r * 0.3) \(y + r * 0.3) L\(x) \(y + r) L\(x - r * 0.3) \(y + r * 0.3) L\(x - r) \(y) L\(x - r * 0.3) \(y - r * 0.3) Z"
        Toon.fill(Toon.path(d), UIColor(hex: 0xFFF3C4))
    }

    static func window(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, u: CGFloat) {
        let rect = Toon.rect(x - w / 2, y - h, w, h)
        Toon.shape(rect, fill: UIColor(hex: 0x26315E), lineWidth: Toon.bold, shaded: false, unit: u)
        moon(x + w * 0.2, y - h * 0.68, min(w, h) * 0.13, u: u)
        star(x - w * 0.25, y - h * 0.75, 6, u: u)
        star(x - w * 0.1, y - h * 0.4, 4, u: u)
        Toon.stroke(Toon.path("M\(x) \(y - h) L\(x) \(y) M\(x - w / 2) \(y - h / 2) L\(x + w / 2) \(y - h / 2)"),
                   width: Toon.medium * u, color: UIColor(hex: 0xC79A6A))
        Toon.stroke(rect, width: Toon.bold * u)
    }

    static func lamp(_ x: CGFloat, _ y: CGFloat, _ k: CGFloat, u: CGFloat) {
        Toon.stroke(Toon.path("M\(x) \(y) L\(x) \(y - 120 * k)"), width: 6 * u)
        Toon.shape(Toon.path("M\(x - 30 * k) \(y - 120 * k) L\(x - 20 * k) \(y - 160 * k) L\(x + 20 * k) \(y - 160 * k) L\(x + 30 * k) \(y - 120 * k) Z"),
                   fill: UIColor(hex: 0xF6D27A), lineWidth: Toon.medium, unit: u)
        Toon.shape(Toon.ellipse(x, y, 26 * k, 7 * k), fill: UIColor(hex: 0x6B4A33), lineWidth: Toon.fine, shaded: false, unit: u)
    }

    static func stripes(_ W: CGFloat, _ gy: CGFloat, u: CGFloat) {
        var x: CGFloat = 0
        while x < W {
            Toon.fill(Toon.rect(x, 0, 14, gy), UIColor(hex: 0xDFC58F))
            x += 36
        }
    }
}
