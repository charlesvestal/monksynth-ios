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

    /// Renders a PluginView reporting a device-like safe area. `safeAreaInsets`
    /// is read-only and `PluginView` is `final`, so the insets are injected the
    /// way the system does it — via a hosting view controller's
    /// `additionalSafeAreaInsets`, which propagates down to `view.safeAreaInsets`.
    private func renderWithInsets(_ size: CGSize, _ insets: UIEdgeInsets) -> UIImage {
        let vc = UIViewController()
        vc.view = PluginView(frame: CGRect(origin: .zero, size: size))
        vc.additionalSafeAreaInsets = insets
        let window = UIWindow(frame: CGRect(origin: .zero, size: size))
        window.rootViewController = vc
        window.isHidden = false
        vc.view.setNeedsLayout()
        vc.view.layoutIfNeeded()
        return UIGraphicsImageRenderer(size: size).image { c in
            vc.view.layer.render(in: c.cgContext)
        }
    }

    /// Portrait on an iPhone with a home indicator: the control strip must sit
    /// clear of the bottom gesture strip, drawn here as a red band.
    func testWriteSafeAreaSheet() throws {
        let insets = UIEdgeInsets(top: 59, left: 0, bottom: 34, right: 0)
        let sizes: [(String, CGSize)] = [
            ("portrait 390x844", CGSize(width: 390, height: 844)),
            ("landscape 844x390", CGSize(width: 844, height: 390)),
        ]
        let gap: CGFloat = 20
        let sheet = CGSize(width: sizes.reduce(0) { $0 + $1.1.width + gap } + gap,
                           height: (sizes.map(\.1.height).max() ?? 0) + gap * 2 + 18)
        let image = UIGraphicsImageRenderer(size: sheet).image { ctx in
            UIColor(white: 0.06, alpha: 1).setFill()
            ctx.fill(CGRect(origin: .zero, size: sheet))
            var x = gap
            for (name, size) in sizes {
                renderWithInsets(size, insets).draw(at: CGPoint(x: x, y: gap + 18))
                // Mark the home indicator strip the system reserves.
                UIColor.systemRed.withAlphaComponent(0.28).setFill()
                ctx.fill(CGRect(x: x, y: gap + 18 + size.height - insets.bottom,
                                width: size.width, height: insets.bottom))
                (name as NSString).draw(
                    at: CGPoint(x: x, y: gap),
                    withAttributes: [.font: UIFont.systemFont(ofSize: 12, weight: .semibold),
                                     .foregroundColor: UIColor(white: 0.75, alpha: 1)])
                x += size.width + gap
            }
        }
        let data = try XCTUnwrap(image.pngData())
        try data.write(to: URL(fileURLWithPath: "/tmp/ui_safearea.png"))
        print("SNAPSHOT_WRITTEN /tmp/ui_safearea.png bytes=\(data.count)")
    }

    /// The about screen (with its new "More Apps" link) plus the More Apps
    /// sheet in its three reachable states — loading, populated, and the
    /// honest failure message — rendered directly rather than through a
    /// real network fetch (`MoreAppsView.debugSetEntries`) so this stays
    /// deterministic and safe to run offline/in CI.
    func testWriteAboutAndMoreAppsSheet() throws {
        let size = CGSize(width: 390, height: 700)
        let gap: CGFloat = 20
        let label: CGFloat = 18

        func snapshot(_ view: UIView) -> UIImage {
            view.setNeedsLayout(); view.layoutIfNeeded()
            return UIGraphicsImageRenderer(size: size).image { c in view.layer.render(in: c.cgContext) }
        }

        let about = AboutView(frame: CGRect(origin: .zero, size: size))
        about.showsBluetoothButton = true

        let loading = MoreAppsView(frame: CGRect(origin: .zero, size: size))

        let populated = MoreAppsView(frame: CGRect(origin: .zero, size: size))
        populated.debugSetEntries([
            MoreAppsCatalog.Entry(name: "Qwertet", blurb: "Free  \u{00B7}  Music",
                                   url: "https://apps.apple.com/app/id0"),
            MoreAppsCatalog.Entry(name: "Qwerty Keys", blurb: "$4.99  \u{00B7}  Music",
                                   url: "https://apps.apple.com/app/id1"),
        ])

        let empty = MoreAppsView(frame: CGRect(origin: .zero, size: size))
        empty.debugSetEntries([])

        let columns: [(String, UIView)] = [
            ("AboutView", about),
            ("MoreAppsView (loading)", loading),
            ("MoreAppsView (populated)", populated),
            ("MoreAppsView (no network, no cache)", empty),
        ]

        let sheet = CGSize(width: size.width * CGFloat(columns.count) + gap * CGFloat(columns.count + 1),
                           height: size.height + gap * 2 + label)
        let renderer = UIGraphicsImageRenderer(size: sheet)
        let image = renderer.image { ctx in
            UIColor(white: 0.06, alpha: 1).setFill()
            ctx.fill(CGRect(origin: .zero, size: sheet))

            var x = gap
            for (name, view) in columns {
                snapshot(view).draw(at: CGPoint(x: x, y: gap + label))
                (name as NSString).draw(
                    at: CGPoint(x: x, y: gap),
                    withAttributes: [.font: UIFont.systemFont(ofSize: 12, weight: .semibold),
                                     .foregroundColor: UIColor(white: 0.75, alpha: 1)])
                x += size.width + gap
            }
        }
        let data = try XCTUnwrap(image.pngData())
        try data.write(to: URL(fileURLWithPath: "/tmp/ui_moreapps.png"))
        print("SNAPSHOT_WRITTEN /tmp/ui_moreapps.png bytes=\(data.count)")
    }
}
