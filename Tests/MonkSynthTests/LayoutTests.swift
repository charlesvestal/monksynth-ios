import XCTest
import UIKit
@testable import MonkSynth

/// Covers `PluginView.layout(in:drawerOpen:safeArea:)`, the pure static
/// layout math behind the three-zone container (Stage / Pad / Controls) and
/// its collapsible drawer handle. Deliberately exercises only the static
/// function, never a live `PluginView` instance — every geometric fact this
/// suite cares about, including the handle's, is reachable from `ZoneLayout`
/// alone.
///
/// The controls strip is a drawer, in both orientations, defaulting OPEN:
/// it gets `Theme.stripHeight` when there's room, and otherwise shrinks —
/// but not below `Theme.minUsableStripHeight` while there's still enough
/// available height to honour that floor. Closed, it drops to zero height.
/// The Stage yields space first (down to zero below
/// `Theme.stageCollapseBelowHeight`); the Pad takes whatever remains and
/// may land below `Theme.minPadHeight` at extreme sizes — that's an
/// accepted trade against ever hiding an OPEN strip.
final class LayoutTests: XCTestCase {

    // MARK: - Aspect-ratio breakpoint

    /// Portrait (aspect ratio < 1.0) stacks: monk on top, pad below, controls
    /// strip at the bottom, all spanning the full inner width.
    func testPortraitStacksVerticallyBelowUnityAspectRatio() {
        let l = PluginView.layout(in: CGRect(x: 0, y: 0, width: 390, height: 844))

        let expectedWidth = 390 - 2 * Theme.gutter
        XCTAssertEqual(l.stage.width, expectedWidth, accuracy: 0.5,
                        "stage must span the full inner width when stacked")
        XCTAssertEqual(l.pad.width, expectedWidth, accuracy: 0.5,
                        "pad must span the full inner width when stacked")
        XCTAssertEqual(l.controls.width, expectedWidth, accuracy: 0.5,
                        "controls must span the full inner width when stacked")
        XCTAssertGreaterThanOrEqual(l.pad.minY, l.stage.maxY - 0.5,
                                     "pad must sit below the stage, not overlapping it")
        XCTAssertGreaterThanOrEqual(l.controls.minY, l.pad.maxY - 0.5,
                                     "controls must sit below the pad, not overlapping it")
    }

    /// Landscape (aspect ratio >= 1.0, including the square case) splits:
    /// monk beside the pad, with the control strip laid out below both.
    func testLandscapeSplitsHorizontallyAtOrAboveUnityAspectRatio() {
        let l = PluginView.layout(in: CGRect(x: 0, y: 0, width: 844, height: 390))

        XCTAssertGreaterThan(l.controls.height, 0, "the control strip must be visible in landscape")
        XCTAssertGreaterThan(l.stage.width, 0, "at this height the stage should not have collapsed")
        XCTAssertGreaterThanOrEqual(l.pad.minX, l.stage.maxX - 0.5,
                                     "pad must sit beside the stage, not overlapping it")
    }

    // MARK: - Short host rect (AUM-style strip)

    /// The exact size AUM hands this view for a compact strip. The aspect
    /// ratio still routes it through the landscape split, and the available
    /// height (164pt after gutters) comfortably clears `Theme.stripHeight` +
    /// a gutter, so the strip gets its full preferred height rather than
    /// merely the floor. That leaves only 64pt for the stage/pad row, well
    /// under `Theme.stageCollapseBelowHeight`, so the stage yields entirely
    /// and the pad gets the whole (now-thinner) row — smaller than
    /// `Theme.minPadHeight`, which is accepted now that the alternative
    /// would be hiding the strip instead.
    func testAUMStripKeepsControlsAtFullHeightAndCollapsesTheStage() {
        let l = PluginView.layout(in: CGRect(x: 0, y: 0, width: 375, height: 180))

        XCTAssertEqual(l.controls.height, Theme.stripHeight, accuracy: 0.5,
                        "an AUM-strip host rect has room for the strip's full preferred height")
        XCTAssertEqual(l.stage.width, 0, accuracy: 0.5, "stage must collapse to zero width")
        XCTAssertEqual(l.stage.height, 0, accuracy: 0.5, "stage must collapse to zero height")
        XCTAssertGreaterThan(l.pad.height, 0, "the pad must still get whatever height remains")
    }

    // MARK: - No negative or NaN frames, anywhere

    /// Sweeps a wide range of host-supplied sizes — from a full-screen
    /// iPad down to a degenerate 1x1 rect — and asserts every zone stays a
    /// well-formed, non-negative, finite rectangle. This is what actually
    /// exercises the clamping in `portraitLayout`/`landscapeLayout`.
    func testNoZoneIsEverNegativeOrNaNAtAnySize() {
        let sizes: [CGSize] = [
            CGSize(width: 320, height: 480),   // iPhone SE portrait
            CGSize(width: 390, height: 844),   // iPhone portrait
            CGSize(width: 844, height: 390),   // iPhone landscape
            CGSize(width: 1024, height: 1366), // iPad Pro portrait
            CGSize(width: 400, height: 120),   // AUM-style strip, even shorter
            CGSize(width: 375, height: 180),   // AUM strip
            CGSize(width: 100, height: 100),   // tiny square
            CGSize(width: 1, height: 1),       // degenerate
        ]

        for size in sizes {
            let l = PluginView.layout(in: CGRect(origin: .zero, size: size))
            for (name, rect) in [("stage", l.stage), ("pad", l.pad), ("controls", l.controls)] {
                XCTAssertTrue(rect.width.isFinite, "\(name).width not finite at \(size)")
                XCTAssertTrue(rect.height.isFinite, "\(name).height not finite at \(size)")
                XCTAssertGreaterThanOrEqual(rect.width, 0, "\(name).width negative at \(size)")
                XCTAssertGreaterThanOrEqual(rect.height, 0, "\(name).height negative at \(size)")
            }
        }
    }

    // MARK: - Controls are always present

    /// The whole point of removing the drawer: at every realistic host size,
    /// the control strip actually occupies space — never zero, even when
    /// the size is short enough to force the stage away entirely.
    func testControlStripIsAlwaysPresentAcrossRealisticHostSizes() {
        let sizes: [CGSize] = [
            CGSize(width: 320, height: 480),
            CGSize(width: 390, height: 844),
            CGSize(width: 844, height: 390),
            CGSize(width: 1024, height: 1366),
            CGSize(width: 400, height: 120),
            CGSize(width: 375, height: 180),
            CGSize(width: 480, height: 320),
            CGSize(width: 100, height: 100),
        ]
        for size in sizes {
            let l = PluginView.layout(in: CGRect(origin: .zero, size: size))
            XCTAssertGreaterThan(l.controls.height, 0, "controls must be visible at \(size)")
            XCTAssertGreaterThan(l.controls.width, 0, "controls must have width at \(size)")
        }
    }

    /// A strip with ample room around it gets its full preferred height —
    /// there's no drawer left to fall back to, so this is the only shape a
    /// roomy layout can take.
    func testAmpleRoomGivesTheStripItsFullPreferredHeight() {
        let l = PluginView.layout(in: CGRect(x: 0, y: 0, width: 844, height: 390))
        XCTAssertEqual(l.controls.height, Theme.stripHeight, accuracy: 0.5)
    }

    /// Whenever the host rect has at least `Theme.minUsableStripHeight` of
    /// vertical room to give the whole stage/pad/controls stack (i.e. it
    /// isn't smaller than the floor itself), the strip must not be shown
    /// any shorter than that floor — a knob has to stay drawable. Covers a
    /// spread of aspect ratios and both the "ample room" and "just enough
    /// room" ends of that range.
    func testControlStripNeverDropsBelowTheUsableFloorWhileShown() {
        let sizes: [CGSize] = [
            CGSize(width: 375, height: 180),  // AUM strip
            CGSize(width: 844, height: 390),  // iPhone landscape, plenty of room
            CGSize(width: 390, height: 844),  // iPhone portrait, plenty of room
            CGSize(width: 320, height: 480),  // iPhone SE portrait
            CGSize(width: 400, height: 120),  // AUM-style strip, even shorter
            CGSize(width: 300, height: 94),   // just above the floor after gutters
        ]
        for size in sizes {
            let l = PluginView.layout(in: CGRect(origin: .zero, size: size))
            XCTAssertGreaterThanOrEqual(l.controls.height, Theme.minUsableStripHeight - 0.5,
                "controls fell below the usable floor at \(size): \(l.controls.height)")
        }
    }

    // MARK: - Pad never goes negative, even where it dips below minPadHeight

    /// At extreme sizes the pad can now legitimately end up shorter than
    /// `Theme.minPadHeight` (the strip takes priority over it), but it must
    /// never go negative or NaN — `testNoZoneIsEverNegativeOrNaNAtAnySize`
    /// already sweeps that broadly; this pins the specific AUM-strip case
    /// the task called out by name.
    func testPadStaysNonNegativeEvenWhenShorterThanMinPadHeight() {
        let l = PluginView.layout(in: CGRect(x: 0, y: 0, width: 375, height: 180))
        XCTAssertTrue(l.pad.height.isFinite)
        XCTAssertGreaterThanOrEqual(l.pad.height, 0)
    }

    // MARK: - Safe area

    /// Reported from a device, back when the strip lived in a pull-up
    /// drawer: "control drawer can't be reached in portrait because of the
    /// home indicator". The bottom ~34pt of a modern iPhone is a system
    /// gesture region — anything placed there is unreachable, because the
    /// system claims the touch before the app sees it. The layout must inset
    /// by `safeAreaInsets`, not just by the gutter — still true now that the
    /// controls are a permanent strip rather than a drawer.
    func testControlsClearTheHomeIndicatorGestureRegion() {
        let homeIndicator = UIEdgeInsets(top: 59, left: 0, bottom: 34, right: 0)
        let bounds = CGRect(x: 0, y: 0, width: 390, height: 844)

        let unsafe = PluginView.layout(in: bounds)
        let safe = PluginView.layout(in: bounds, safeArea: homeIndicator)

        XCTAssertGreaterThan(unsafe.controls.maxY, bounds.maxY - homeIndicator.bottom,
                             "precondition: without the inset the controls sit in the gesture strip")
        XCTAssertLessThanOrEqual(safe.controls.maxY, bounds.maxY - homeIndicator.bottom + 0.5,
                                 "the controls must sit entirely above the home indicator")
    }

    /// The whole visible layout must respect the safe area, not only the
    /// controls strip — a pad running under the indicator would swallow
    /// drags too.
    func testEveryZoneStaysInsideTheSafeArea() {
        let insets = UIEdgeInsets(top: 59, left: 0, bottom: 34, right: 0)
        for size in [CGSize(width: 390, height: 844), CGSize(width: 844, height: 390)] {
            let b = CGRect(origin: .zero, size: size)
            let l = PluginView.layout(in: b, safeArea: insets)
            for (name, r) in [("stage", l.stage), ("pad", l.pad), ("controls", l.controls)]
            where r.height > 0 {
                XCTAssertGreaterThanOrEqual(r.minY, insets.top - 0.5, "\(name) top at \(size)")
                XCTAssertLessThanOrEqual(r.maxY, b.maxY - insets.bottom + 0.5,
                                         "\(name) bottom at \(size)")
            }
        }
    }

    // MARK: - Drawer handle

    /// The regression that caused this task: a drawer shipped once before
    /// with its handle anchored to `controls.maxY`, which is pinned to the
    /// bottom of the view and identical whether the drawer is open or
    /// closed — so the handle never visibly moved and the drawer looked
    /// broken/unreachable. This is the test that would have caught it: the
    /// handle's frame in the open layout must differ from the closed layout
    /// by roughly `Theme.stripHeight`, the actual distance the strip's top
    /// edge (`controls.minY`) travels.
    func testHandleFrameDiffersMeaningfullyBetweenOpenAndClosed() {
        let bounds = CGRect(x: 0, y: 0, width: 390, height: 844)
        let open = PluginView.layout(in: bounds, drawerOpen: true)
        let closed = PluginView.layout(in: bounds, drawerOpen: false)

        XCTAssertNotEqual(open.handle, closed.handle,
                          "the handle must occupy a different frame when the drawer opens/closes")

        let travelled = closed.handle.minY - open.handle.minY
        XCTAssertEqual(travelled, Theme.stripHeight, accuracy: 0.5,
            "the handle should travel the full distance the strip's top edge does when it opens/closes, not sit still")

        // Belt-and-suspenders against a future regression that reintroduces
        // a near-zero, easy-to-miss movement (e.g. an off-by-a-few-points
        // fix that technically satisfies "not equal" but still looks
        // static to a person watching the animation).
        XCTAssertGreaterThan(travelled, 40,
            "the handle's movement must be large enough to actually read as motion")
    }

    /// Same assertion as above but at the exact size and inset the task
    /// report calls out by name — a concrete real-world sanity check
    /// alongside the generic sweep.
    func testHandleFrameDiffersMeaningfullyBetweenOpenAndClosedWithSafeArea() {
        let bounds = CGRect(x: 0, y: 0, width: 390, height: 844)
        let insets = UIEdgeInsets(top: 59, left: 0, bottom: 34, right: 0)
        let open = PluginView.layout(in: bounds, drawerOpen: true, safeArea: insets)
        let closed = PluginView.layout(in: bounds, drawerOpen: false, safeArea: insets)

        XCTAssertNotEqual(open.handle, closed.handle)
        XCTAssertEqual(closed.handle.minY - open.handle.minY, Theme.stripHeight, accuracy: 0.5)
    }

    /// However far the handle travels, it must never cross into the bottom
    /// safe-area inset (the home-indicator gesture strip) in either state —
    /// the same defect that made the very first drawer unreachable, just
    /// checked against the handle specifically rather than the whole
    /// controls zone.
    func testHandleClearsTheSafeAreaBottomInBothStates() {
        let insets = UIEdgeInsets(top: 59, left: 0, bottom: 34, right: 0)
        for size in [CGSize(width: 390, height: 844), CGSize(width: 844, height: 390)] {
            let bounds = CGRect(origin: .zero, size: size)
            for open in [true, false] {
                let l = PluginView.layout(in: bounds, drawerOpen: open, safeArea: insets)
                XCTAssertLessThanOrEqual(l.handle.maxY, bounds.maxY - insets.bottom + 0.5,
                    "handle intrudes into the bottom safe area at \(size), drawerOpen=\(open): \(l.handle)")
            }
        }
    }

    /// Apple's HIG minimum tap target (44pt in both dimensions) must hold
    /// for the handle's hit region regardless of whether the drawer is open
    /// or closed — the visible pill inside it stays small, but the
    /// invisible region a finger actually has to land in must not.
    func testHandleMeetsMinimumTapTargetInBothStates() {
        let bounds = CGRect(x: 0, y: 0, width: 390, height: 844)
        for open in [true, false] {
            let l = PluginView.layout(in: bounds, drawerOpen: open)
            XCTAssertGreaterThanOrEqual(l.handle.width, 44,
                "handle hit region narrower than the 44pt HIG minimum, drawerOpen=\(open)")
            XCTAssertGreaterThanOrEqual(l.handle.height, 44,
                "handle hit region shorter than the 44pt HIG minimum, drawerOpen=\(open)")
        }
    }

    // MARK: - Character selector

    /// The usual size sweep: a spread of realistic host-supplied rects,
    /// portrait and landscape, phone and tablet, plus the AUM strip where
    /// the stage is known to collapse. The same sweep the old edge-arrow
    /// tests used (and `CharacterTests`' stage/pad-overlap sweep still
    /// uses) — kept identical so this suite exercises exactly the sizes
    /// that mattered before, not a hand-picked new set.
    private static let usualSizeSweep: [CGSize] = [
        CGSize(width: 320, height: 480),
        CGSize(width: 390, height: 844),
        CGSize(width: 844, height: 390),
        CGSize(width: 1024, height: 768),
        CGSize(width: 1024, height: 1366),
        CGSize(width: 375, height: 180),   // AUM strip — stage collapses
        CGSize(width: 480, height: 320),
    ]

    /// Unlike the old edge arrows (only shown beside a non-collapsed
    /// stage), `characterSelector` lives in the header row and is computed
    /// independently of `stage` — so it must meet the 44pt HIG minimum tap
    /// target in both dimensions at EVERY size in the sweep, no "not shown
    /// here" exception.
    func testCharacterSelectorMeetsMinimumTapTargetAcrossTheSizeSweep() {
        for size in Self.usualSizeSweep {
            let l = PluginView.layout(in: CGRect(origin: .zero, size: size))
            XCTAssertGreaterThanOrEqual(l.characterSelector.height, 44,
                "character selector shorter than the 44pt HIG minimum at \(size): \(l.characterSelector)")
            XCTAssertGreaterThanOrEqual(l.characterSelector.width, 44,
                "character selector narrower than the 44pt HIG minimum at \(size): \(l.characterSelector)")
        }
    }

    /// Across the whole sweep, the selector may not intersect the pad, the
    /// controls strip, the drawer handle, or the info button — the four
    /// things the task explicitly calls out as off-limits (stricter than
    /// the old arrows, which were allowed to sit over `stage` itself; the
    /// selector isn't drawn over any zone, it lives in its own header row).
    func testCharacterSelectorDoesNotIntersectPadControlsHandleOrInfoButton() {
        for size in Self.usualSizeSweep {
            let l = PluginView.layout(in: CGRect(origin: .zero, size: size))
            let selector = l.characterSelector
            XCTAssertFalse(selector.intersects(l.pad),
                "selector \(selector) overlaps pad \(l.pad) at \(size)")
            XCTAssertFalse(selector.intersects(l.controls),
                "selector \(selector) overlaps controls \(l.controls) at \(size)")
            XCTAssertFalse(selector.intersects(l.handle),
                "selector \(selector) overlaps handle \(l.handle) at \(size)")
            XCTAssertFalse(selector.intersects(l.infoButton),
                "selector \(selector) overlaps infoButton \(l.infoButton) at \(size)")
        }
    }

    /// The specific gain of this design over the old edge arrows, called
    /// out by name in the task: at the exact AUM-strip size where the stage
    /// collapses entirely (see
    /// `testAUMStripKeepsControlsAtFullHeightAndCollapsesTheStage`, and
    /// where the old arrows used to vanish along with it), the selector
    /// must still be there, and still meet its own 44pt tap target.
    func testCharacterSelectorIsPresentEvenWhenStageCollapses() {
        let l = PluginView.layout(in: CGRect(x: 0, y: 0, width: 375, height: 180))
        XCTAssertEqual(l.stage, .zero, "precondition: stage collapses at this size")
        XCTAssertGreaterThanOrEqual(l.characterSelector.width, 44,
            "the character selector must remain usable even when the stage collapses")
        XCTAssertGreaterThanOrEqual(l.characterSelector.height, 44)
    }

    /// A degenerate host rect (smaller than the gutters themselves) must
    /// still produce a well-formed selector frame — i.e. it degrades to a
    /// small-but-finite, non-negative rect rather than NaN or negative,
    /// mirroring `testNoZoneIsEverNegativeOrNaNAtAnySize`'s guarantee for
    /// the other zones.
    func testCharacterSelectorFrameIsNeverNaNOrNegativeEvenAtDegenerateSizes() {
        let sizes: [CGSize] = [CGSize(width: 1, height: 1), CGSize(width: 100, height: 100)]
        for size in sizes {
            let l = PluginView.layout(in: CGRect(origin: .zero, size: size))
            XCTAssertTrue(l.characterSelector.width.isFinite, "selector width not finite at \(size)")
            XCTAssertTrue(l.characterSelector.height.isFinite, "selector height not finite at \(size)")
            XCTAssertGreaterThanOrEqual(l.characterSelector.width, 0, "selector width negative at \(size)")
            XCTAssertGreaterThanOrEqual(l.characterSelector.height, 0, "selector height negative at \(size)")
        }
    }
}
