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
}
