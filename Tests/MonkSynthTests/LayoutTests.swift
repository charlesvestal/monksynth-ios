import XCTest
import UIKit
@testable import MonkSynth

/// Covers `PluginView.layout(in:drawerOpen:)`, the pure static layout math
/// behind the three-zone container (Stage / Pad / Controls). Deliberately
/// exercises only the static function, never a live `PluginView` instance,
/// except in the tap-target test where the actual hit-region geometry lives
/// on the instance rather than in `ZoneLayout`.
final class LayoutTests: XCTestCase {

    // MARK: - Aspect-ratio breakpoint

    /// Portrait (aspect ratio < 1.0) stacks: monk on top, pad below, and the
    /// control strip lives in a drawer that spans the full inner width.
    func testPortraitStacksVerticallyBelowUnityAspectRatio() {
        let l = PluginView.layout(in: CGRect(x: 0, y: 0, width: 390, height: 844), drawerOpen: false)

        XCTAssertTrue(l.isDrawer, "aspect ratio < 1.0 must put the controls in a drawer")

        let expectedWidth = 390 - 2 * Theme.gutter
        XCTAssertEqual(l.stage.width, expectedWidth, accuracy: 0.5,
                        "stage must span the full inner width when stacked")
        XCTAssertEqual(l.pad.width, expectedWidth, accuracy: 0.5,
                        "pad must span the full inner width when stacked")
        XCTAssertGreaterThanOrEqual(l.pad.minY, l.stage.maxY - 0.5,
                                     "pad must sit below the stage, not overlapping it")
    }

    /// Landscape (aspect ratio >= 1.0, including the square case) splits:
    /// monk beside the pad, with the control strip always laid out (never a
    /// drawer).
    func testLandscapeSplitsHorizontallyAtOrAboveUnityAspectRatio() {
        let l = PluginView.layout(in: CGRect(x: 0, y: 0, width: 844, height: 390), drawerOpen: false)

        XCTAssertFalse(l.isDrawer, "aspect ratio >= 1.0 must lay the control strip out directly")
        XCTAssertGreaterThan(l.controls.height, 0, "the control strip must be visible in landscape")
        XCTAssertGreaterThan(l.stage.width, 0, "at this height the stage should not have collapsed")
        XCTAssertGreaterThanOrEqual(l.pad.minX, l.stage.maxX - 0.5,
                                     "pad must sit beside the stage, not overlapping it")
    }

    // MARK: - Short host rect (AUM-style strip)

    /// A wide, short rect like AUM can hand this view: the aspect ratio
    /// still routes it through the landscape split, but the available
    /// height (204pt after gutters) is below `Theme.stageCollapseBelowHeight`
    /// (260), so the stage yields entirely and the pad keeps the whole row
    /// at exactly `Theme.minPadHeight`.
    func testShortHostRectKeepsThePadPlayable() {
        let l = PluginView.layout(in: CGRect(x: 0, y: 0, width: 390, height: 220), drawerOpen: false)

        XCTAssertGreaterThanOrEqual(l.pad.height, Theme.minPadHeight - 0.5,
                                     "pad must keep at least minPadHeight even in a short strip")
        XCTAssertEqual(l.stage.width, 0, accuracy: 0.5, "stage must collapse to zero width")
        XCTAssertEqual(l.stage.height, 0, accuracy: 0.5, "stage must collapse to zero height")
    }

    // MARK: - No negative or NaN frames, anywhere

    /// Sweeps a wide range of host-supplied sizes — from a full-screen
    /// iPad down to a degenerate 1x1 rect — with the drawer both open and
    /// closed, and asserts every zone stays a well-formed, non-negative,
    /// finite rectangle. This is what actually exercises the clamping in
    /// `portraitLayout`/`landscapeLayout`.
    func testNoZoneIsEverNegativeOrNaNAtAnySize() {
        let sizes: [CGSize] = [
            CGSize(width: 320, height: 480),   // iPhone SE portrait
            CGSize(width: 390, height: 844),   // iPhone portrait
            CGSize(width: 844, height: 390),   // iPhone landscape
            CGSize(width: 1024, height: 1366), // iPad Pro portrait
            CGSize(width: 400, height: 120),   // AUM-style strip, even shorter
            CGSize(width: 100, height: 100),   // tiny square
            CGSize(width: 1, height: 1),       // degenerate
        ]

        for size in sizes {
            for drawerOpen in [false, true] {
                let l = PluginView.layout(in: CGRect(origin: .zero, size: size), drawerOpen: drawerOpen)
                for (name, rect) in [("stage", l.stage), ("pad", l.pad), ("controls", l.controls)] {
                    XCTAssertTrue(rect.width.isFinite,
                                  "\(name).width not finite at \(size), drawerOpen=\(drawerOpen)")
                    XCTAssertTrue(rect.height.isFinite,
                                  "\(name).height not finite at \(size), drawerOpen=\(drawerOpen)")
                    XCTAssertGreaterThanOrEqual(rect.width, 0,
                                                 "\(name).width negative at \(size), drawerOpen=\(drawerOpen)")
                    XCTAssertGreaterThanOrEqual(rect.height, 0,
                                                 "\(name).height negative at \(size), drawerOpen=\(drawerOpen)")
                }
            }
        }
    }

    // MARK: - Drawer handle tap target

    /// The visible drawer handle is a deliberately tiny 34x4 pill, but the
    /// actual hit region around it (`PluginView.drawerHitFrame`, driven by
    /// the gesture recognizer on `drawerHandle`) must meet Apple's 44pt HIG
    /// minimum in both dimensions — a 4pt-tall tap target is effectively
    /// unhittable.
    func testDrawerHandleHitRegionMeetsMinimumTapTarget() {
        let view = PluginView(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        view.layoutIfNeeded()

        XCTAssertGreaterThanOrEqual(view.drawerHitFrame.height, 44,
                                     "drawer handle tap target must be at least 44pt tall")
        XCTAssertGreaterThanOrEqual(view.drawerHitFrame.width, 44,
                                     "drawer handle tap target must be at least 44pt wide")
    }
}
