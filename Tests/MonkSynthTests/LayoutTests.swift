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

    /// Found by rendering the UI at real host sizes: at an AUM-strip height the
    /// control strip was tall enough to draw its tab bar but too short to fit a
    /// knob, so the user got five tabs controlling invisible dials. Below
    /// `Theme.minUsableStripHeight` the controls must collapse to a drawer.
    func testTooShortAControlStripCollapsesToADrawerRatherThanShowingEmptyTabs() {
        let l = PluginView.layout(in: CGRect(x: 0, y: 0, width: 375, height: 180),
                                  drawerOpen: false)
        XCTAssertTrue(l.isDrawer,
                      "a strip too short for a knob must become a drawer")
        XCTAssertEqual(l.controls.height, Theme.drawerHandleHeight, accuracy: 0.5)
        XCTAssertGreaterThanOrEqual(l.pad.height, Theme.minPadHeight - 0.5,
                                    "collapsing the strip must give the height to the pad")
    }

    /// A strip with room for a knob stays a strip.
    func testATallEnoughControlStripStaysVisible() {
        let l = PluginView.layout(in: CGRect(x: 0, y: 0, width: 844, height: 390),
                                  drawerOpen: false)
        XCTAssertFalse(l.isDrawer)
        XCTAssertGreaterThanOrEqual(l.controls.height, Theme.minUsableStripHeight - 0.5)
    }

    /// Reported from a device: "control drawer can't be reached in portrait
    /// because of the home indicator". The bottom ~34pt of a modern iPhone is
    /// a system gesture region — anything placed there is unreachable, because
    /// the system claims the touch before the app sees it. The layout must
    /// inset by `safeAreaInsets`, not just by the gutter.
    func testDrawerClearsTheHomeIndicatorGestureRegion() {
        let homeIndicator = UIEdgeInsets(top: 59, left: 0, bottom: 34, right: 0)
        let bounds = CGRect(x: 0, y: 0, width: 390, height: 844)

        let unsafe = PluginView.layout(in: bounds, drawerOpen: false)
        let safe = PluginView.layout(in: bounds, drawerOpen: false, safeArea: homeIndicator)

        XCTAssertGreaterThan(unsafe.controls.maxY, bounds.maxY - homeIndicator.bottom,
                             "precondition: without the inset the drawer sits in the gesture strip")
        XCTAssertLessThanOrEqual(safe.controls.maxY, bounds.maxY - homeIndicator.bottom + 0.5,
                                 "the drawer must sit entirely above the home indicator")
    }

    /// The whole visible layout must respect the safe area, not only the
    /// drawer — a pad running under the indicator would swallow drags too.
    func testEveryZoneStaysInsideTheSafeArea() {
        let insets = UIEdgeInsets(top: 59, left: 0, bottom: 34, right: 0)
        for size in [CGSize(width: 390, height: 844), CGSize(width: 844, height: 390)] {
            let b = CGRect(origin: .zero, size: size)
            let l = PluginView.layout(in: b, drawerOpen: true, safeArea: insets)
            for (name, r) in [("stage", l.stage), ("pad", l.pad), ("controls", l.controls)]
            where r.height > 0 {
                XCTAssertGreaterThanOrEqual(r.minY, insets.top - 0.5, "\(name) top at \(size)")
                XCTAssertLessThanOrEqual(r.maxY, b.maxY - insets.bottom + 0.5,
                                         "\(name) bottom at \(size)")
            }
        }
    }
}
