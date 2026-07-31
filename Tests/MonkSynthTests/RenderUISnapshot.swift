// Visual-check harness for the whole plugin UI at realistic host sizes.
// Not an assertion test. Run:
//
//   scripts/test.sh MonkSynthTests/RenderUISnapshot && open /tmp/ui_sizes.png
//
// AUv3 hosts hand the plugin arbitrary rects — AUM gives short wide strips,
// GarageBand gives something taller, the standalone gets the full screen. Each
// of those has to look right, and only looking at them proves it.
import UIKit
import XCTest
@testable import MonkSynth

final class RenderUISnapshot: XCTestCase {

    /// Sizes a real host actually hands an AUv3, plus the standalone.
    private static let sizes: [(String, CGSize)] = [
        ("AUM strip 375x180",      CGSize(width: 375, height: 180)),
        ("AUM tall 375x320",       CGSize(width: 375, height: 320)),
        ("AUv3 default 480x320",   CGSize(width: 480, height: 320)),
        ("iPhone landscape 844x390", CGSize(width: 844, height: 390)),
        ("iPhone portrait 390x844",  CGSize(width: 390, height: 844)),
        ("iPad 1024x768",          CGSize(width: 1024, height: 768)),
    ]

    private func render(_ size: CGSize) -> UIImage {
        let view = PluginView(frame: CGRect(origin: .zero, size: size))
        // Force a full layout+display pass, as a real host would.
        view.setNeedsLayout()
        view.layoutIfNeeded()
        let r = UIGraphicsImageRenderer(size: size)
        return r.image { ctx in view.layer.render(in: ctx.cgContext) }
    }

    func testWriteSizeSheet() throws {
        let pad: CGFloat = 16
        let label: CGFloat = 18
        let cols = 2
        let rows = (Self.sizes.count + cols - 1) / cols
        let colW = Self.sizes.map(\.1.width).max()! + pad
        let rowH = Self.sizes.map(\.1.height).max()! + pad + label

        let sheet = CGSize(width: colW * CGFloat(cols) + pad,
                           height: rowH * CGFloat(rows) + pad)
        let renderer = UIGraphicsImageRenderer(size: sheet)
        let image = renderer.image { ctx in
            UIColor(white: 0.06, alpha: 1).setFill()
            ctx.fill(CGRect(origin: .zero, size: sheet))
            for (i, entry) in Self.sizes.enumerated() {
                let (name, size) = entry
                let x = pad + CGFloat(i % cols) * colW
                let y = pad + CGFloat(i / cols) * rowH
                render(size).draw(at: CGPoint(x: x, y: y + label))
                (name as NSString).draw(
                    at: CGPoint(x: x, y: y),
                    withAttributes: [.font: UIFont.systemFont(ofSize: 12, weight: .semibold),
                                     .foregroundColor: UIColor(white: 0.75, alpha: 1)])
            }
        }
        let data = try XCTUnwrap(image.pngData())
        try data.write(to: URL(fileURLWithPath: "/tmp/ui_sizes.png"))
        print("SNAPSHOT_WRITTEN /tmp/ui_sizes.png bytes=\(data.count)")
    }

    /// Close-up of one control page so knob rendering and labelling can be
    /// judged at the size a finger actually meets them.
    func testWriteKnobCloseup() throws {
        let sizes: [(String, CGSize)] = [
            ("strip row 375x92",  CGSize(width: 375, height: 92)),
            ("wide row 844x92",   CGSize(width: 844, height: 92)),
            ("narrow row 320x92", CGSize(width: 320, height: 92)),
        ]
        let gap: CGFloat = 14
        let sheet = CGSize(width: sizes.map(\.1.width).max()! + gap * 2,
                           height: sizes.reduce(0) { $0 + $1.1.height + gap + 16 } + gap)
        let renderer = UIGraphicsImageRenderer(size: sheet)
        let image = renderer.image { ctx in
            Theme.background.setFill()
            ctx.fill(CGRect(origin: .zero, size: sheet))
            var y: CGFloat = gap
            for (name, size) in sizes {
                (name as NSString).draw(
                    at: CGPoint(x: gap, y: y),
                    withAttributes: [.font: UIFont.systemFont(ofSize: 11),
                                     .foregroundColor: Theme.textDim])
                y += 16
                let pages = ControlPages(frame: CGRect(origin: .zero, size: size))
                pages.setNeedsLayout(); pages.layoutIfNeeded()
                let img = UIGraphicsImageRenderer(size: size).image { c in
                    pages.layer.render(in: c.cgContext)
                }
                img.draw(at: CGPoint(x: gap, y: y))
                y += size.height + gap
            }
        }
        let data = try XCTUnwrap(image.pngData())
        try data.write(to: URL(fileURLWithPath: "/tmp/ui_knobs.png"))
        print("SNAPSHOT_WRITTEN /tmp/ui_knobs.png bytes=\(data.count)")
    }
}
