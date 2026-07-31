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

    /// Renders a `PluginView` with the drawer forced open or closed, with a
    /// device-like safe area applied — same injection trick as
    /// `renderWithInsets` (`safeAreaInsets` is read-only), plus a tap on the
    /// handle to actually drive `PluginView`'s own toggle, not a test-only
    /// backdoor. `UIView.animate` inside `toggleDrawer` runs synchronously
    /// to its final state when there's no active run loop driving it here,
    /// so the layout is already settled by the time this returns.
    private func renderDrawerState(_ size: CGSize, _ insets: UIEdgeInsets, open: Bool) -> UIImage {
        let vc = UIViewController()
        let view = PluginView(frame: CGRect(origin: .zero, size: size))
        vc.view = view
        vc.additionalSafeAreaInsets = insets
        let window = UIWindow(frame: CGRect(origin: .zero, size: size))
        window.rootViewController = vc
        window.isHidden = false
        view.setNeedsLayout()
        view.layoutIfNeeded()

        if !open {
            // PluginView defaults to open; closing it exercises the exact
            // gesture-driven path a finger would (the private
            // `drawerHandle`/`toggleDrawer`), not a reach-around. Mirrors
            // how `ControlPagesTests` exercises `showPage` directly rather
            // than synthesizing a UIButton tap: the target under test is
            // internal to this file's module, so a direct call is honest,
            // not a shortcut.
            view.perform(Selector(("toggleDrawer")))
            view.setNeedsLayout()
            view.layoutIfNeeded()
        }

        return UIGraphicsImageRenderer(size: size).image { c in
            view.layer.render(in: c.cgContext)
        }
    }

    /// Required visual check for the collapsible control drawer: open and
    /// closed states side by side, at a portrait and a landscape size, with
    /// the bottom safe-area (home indicator) strip marked in red so it's
    /// obvious at a glance whether the handle ever dips into it. The whole
    /// point is eyeballing whether the handle visibly moves between the two
    /// columns of each pair — a numeric assertion of that already lives in
    /// `LayoutTests.testHandleFrameDiffersMeaningfullyBetweenOpenAndClosed`,
    /// but only a human looking at pixels can confirm it actually *reads*
    /// as movement, and that the little chevron indeed flips direction.
    func testWriteDrawerOpenClosedSheet() throws {
        let insets = UIEdgeInsets(top: 59, left: 0, bottom: 34, right: 0)
        let sizes: [(String, CGSize)] = [
            ("portrait 390x844", CGSize(width: 390, height: 844)),
            ("landscape 844x390", CGSize(width: 844, height: 390)),
        ]
        let gap: CGFloat = 20
        let label: CGFloat = 18
        let colGap: CGFloat = 10

        let rowHeight = (sizes.map(\.1.height).max() ?? 0) + gap + label
        let sheet = CGSize(
            width: sizes.reduce(0) { $0 + $1.1.width * 2 + colGap } + gap * CGFloat(sizes.count + 1),
            height: rowHeight * CGFloat(sizes.count) + gap)

        let image = UIGraphicsImageRenderer(size: sheet).image { ctx in
            UIColor(white: 0.06, alpha: 1).setFill()
            ctx.fill(CGRect(origin: .zero, size: sheet))

            var y = gap
            for (name, size) in sizes {
                var x = gap
                for (stateName, open) in [("OPEN", true), ("CLOSED", false)] {
                    renderDrawerState(size, insets, open: open).draw(at: CGPoint(x: x, y: y + label))
                    // Mark the home indicator strip the system reserves —
                    // the handle must never sit inside this band.
                    UIColor.systemRed.withAlphaComponent(0.28).setFill()
                    ctx.fill(CGRect(x: x, y: y + label + size.height - insets.bottom,
                                    width: size.width, height: insets.bottom))
                    ("\(name) — \(stateName)" as NSString).draw(
                        at: CGPoint(x: x, y: y),
                        withAttributes: [.font: UIFont.systemFont(ofSize: 12, weight: .semibold),
                                         .foregroundColor: UIColor(white: 0.75, alpha: 1)])
                    x += size.width + colGap
                }
                y += rowHeight
            }
        }
        let data = try XCTUnwrap(image.pngData())
        try data.write(to: URL(fileURLWithPath: "/tmp/ui_drawer.png"))
        print("SNAPSHOT_WRITTEN /tmp/ui_drawer.png bytes=\(data.count)")
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

    /// Renders only `rect` (in `view`'s own coordinate space) of a laid-out
    /// view, at 1x scale so the crop math stays simple. Used below to zoom
    /// in on the stage zone — at full-UI scale the step arrows are too
    /// small in a screenshot to actually judge their look.
    private func crop(_ view: UIView, to rect: CGRect) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: rect.size, format: format).image { ctx in
            ctx.cgContext.translateBy(x: -rect.origin.x, y: -rect.origin.y)
            view.layer.render(in: ctx.cgContext)
        }
    }

    /// Close-up of the header row (character selector + info button) at a
    /// spread of sizes, including 375×180 — the AUM strip, the specific
    /// size the task calls out by name as the one the old edge arrows
    /// failed at (they vanished entirely once the stage collapsed there).
    /// Rendered at full-UI scale the header is too small in a screenshot to
    /// judge legibility/collision, so this crops in. Required visual check:
    /// confirm the name is legible, the ‹/⌄/› glyphs are unambiguous, and
    /// nothing collides with the info button — at every size, not just the
    /// roomy ones.
    func testWriteCharacterSelectorCloseup() throws {
        let sizes: [(String, CGSize)] = [
            ("AUM strip 375x180", CGSize(width: 375, height: 180)),
            ("AUM tall 375x320", CGSize(width: 375, height: 320)),
            ("portrait 390x844", CGSize(width: 390, height: 844)),
            ("landscape 844x390", CGSize(width: 844, height: 390)),
            ("iPad 1024x768", CGSize(width: 1024, height: 768)),
        ]
        let gap: CGFloat = 16
        let label: CGFloat = 18
        let margin: CGFloat = 12

        var crops: [(String, UIImage)] = []
        for (name, size) in sizes {
            let view = PluginView(frame: CGRect(origin: .zero, size: size))
            view.setNeedsLayout(); view.layoutIfNeeded()
            let l = PluginView.layout(in: CGRect(origin: .zero, size: size))
            // The whole header band, not just the selector's own rect —
            // showing `infoButton` alongside it is what makes "nothing
            // collides" actually checkable by eye.
            let bandHeight = max(l.characterSelector.maxY, l.infoButton.maxY) + margin
            let cropRect = CGRect(x: 0, y: 0, width: size.width, height: min(size.height, bandHeight))
            crops.append((name, crop(view, to: cropRect)))
        }

        let sheetW = (crops.map(\.1.size.width).max() ?? 0) + gap * 2
        let sheetH = crops.reduce(0) { $0 + $1.1.size.height + gap + label } + gap
        let sheet = CGSize(width: sheetW, height: sheetH)
        let renderer = UIGraphicsImageRenderer(size: sheet)
        let image = renderer.image { ctx in
            UIColor(white: 0.06, alpha: 1).setFill()
            ctx.fill(CGRect(origin: .zero, size: sheet))
            var y = gap
            for (name, img) in crops {
                img.draw(at: CGPoint(x: gap, y: y + label))
                (name as NSString).draw(
                    at: CGPoint(x: gap, y: y),
                    withAttributes: [.font: UIFont.systemFont(ofSize: 12, weight: .semibold),
                                     .foregroundColor: UIColor(white: 0.75, alpha: 1)])
                y += img.size.height + gap + label
            }
        }
        let data = try XCTUnwrap(image.pngData())
        try data.write(to: URL(fileURLWithPath: "/tmp/ui_characterselector.png"))
        print("SNAPSHOT_WRITTEN /tmp/ui_characterselector.png bytes=\(data.count)")
    }

    /// The character dropdown overlay (opened from the selector's `⌄`): a
    /// normal-height standalone render, the same overlay embedded in a full
    /// `PluginView` (so the scrim/panel read correctly against the rest of
    /// the UI), and — the specific failure mode the old character-art grid
    /// had — the exact AUM-strip size (375×180) to confirm a plain list of
    /// names actually scrolls and stays usable there, unlike the grid it
    /// replaced ("a clipped sliver of one row plus a Close button filling
    /// the panel"). Required visual check.
    func testWriteCharacterDropdownSheet() throws {
        let gap: CGFloat = 20
        let label: CGFloat = 18

        func snapshot(_ view: UIView, size: CGSize) -> UIImage {
            view.frame = CGRect(origin: .zero, size: size)
            view.setNeedsLayout(); view.layoutIfNeeded()
            return UIGraphicsImageRenderer(size: size).image { c in view.layer.render(in: c.cgContext) }
        }

        let standaloneSize = CGSize(width: 390, height: 700)
        let standalone = CharacterDropdownView(frame: .zero, current: CharacterRegistry.all[2])

        let inContextSize = CGSize(width: 390, height: 844)
        let inContext = PluginView(frame: CGRect(origin: .zero, size: inContextSize))
        inContext.setNeedsLayout(); inContext.layoutIfNeeded()
        inContext.characterSelector.onOpenDropdown?()

        let shortSize = CGSize(width: 375, height: 180)
        // The dropdown open AT the AUM strip's own PluginView, not just the
        // standalone overlay at that size — proves the whole stack (scrim
        // over the real header/pad/controls) still works at strip height,
        // not only the overlay in isolation.
        let shortInContext = PluginView(frame: CGRect(origin: .zero, size: shortSize))
        shortInContext.setNeedsLayout(); shortInContext.layoutIfNeeded()
        shortInContext.characterSelector.onOpenDropdown?()

        let columns: [(String, UIView, CGSize)] = [
            ("standalone 390x700", standalone, standaloneSize),
            ("in PluginView 390x844", inContext, inContextSize),
            ("AUM strip 375x180 (must scroll)", shortInContext, shortSize),
        ]

        let sheet = CGSize(width: columns.reduce(0) { $0 + $1.2.width + gap } + gap,
                           height: (columns.map(\.2.height).max() ?? 0) + gap * 2 + label)
        let renderer = UIGraphicsImageRenderer(size: sheet)
        let image = renderer.image { ctx in
            UIColor(white: 0.06, alpha: 1).setFill()
            ctx.fill(CGRect(origin: .zero, size: sheet))
            var x = gap
            for (name, view, size) in columns {
                snapshot(view, size: size).draw(at: CGPoint(x: x, y: gap + label))
                (name as NSString).draw(
                    at: CGPoint(x: x, y: gap),
                    withAttributes: [.font: UIFont.systemFont(ofSize: 12, weight: .semibold),
                                     .foregroundColor: UIColor(white: 0.75, alpha: 1)])
                x += size.width + gap
            }
        }
        let data = try XCTUnwrap(image.pngData())
        try data.write(to: URL(fileURLWithPath: "/tmp/ui_characterdropdown.png"))
        print("SNAPSHOT_WRITTEN /tmp/ui_characterdropdown.png bytes=\(data.count)")
    }
}
