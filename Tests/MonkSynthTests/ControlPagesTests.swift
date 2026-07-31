import XCTest
import UIKit
@testable import MonkSynth

final class ControlPagesTests: XCTestCase {

    // MARK: - Page coverage

    /// Derives the expected set from `Param.isHiddenFromUI` rather than
    /// hardcoding 18 names, so this test fails loudly if `Params.swift`
    /// grows a new parameter that nobody added to a page.
    func testAllNonHiddenParametersAppearExactlyOnceAcrossPages() {
        let expected = Set(Param.allCases.filter { !$0.isHiddenFromUI })
        XCTAssertEqual(expected.count, 18, "expected 18 non-hidden parameters, got \(expected.count)")

        let flattened = ControlPages.pages.flatMap { $0.params }
        XCTAssertEqual(flattened.count, 18,
                        "expected 18 total param slots across all pages, got \(flattened.count)")

        let flattenedSet = Set(flattened)
        XCTAssertEqual(flattenedSet.count, flattened.count,
                        "a parameter is listed on more than one page")
        XCTAssertEqual(flattenedSet, expected,
                        "pages must cover exactly the non-hidden parameter set, no more, no less")
    }

    // MARK: - KnobView.value(from:dragDelta:fine:)

    func testFullTravelSpansEntireRangeUpAndDown() {
        // Dragging UP is negative dy in view coordinates and must increase
        // the value; dragging DOWN (positive dy) must decrease it.
        let up = KnobView.value(from: 0, dragDelta: -KnobView.fullTravel, fine: false)
        XCTAssertEqual(up, 1.0, accuracy: 1e-6)

        let down = KnobView.value(from: 1, dragDelta: KnobView.fullTravel, fine: false)
        XCTAssertEqual(down, 0.0, accuracy: 1e-6)
    }

    func testPartialTravelIsProportional() {
        let quarter = KnobView.value(from: 0, dragDelta: -KnobView.fullTravel / 4, fine: false)
        XCTAssertEqual(quarter, 0.25, accuracy: 1e-6)
    }

    func testFineModeIsOneEighthSensitivity() {
        let delta: CGFloat = -20
        let coarseChange = KnobView.value(from: 0.5, dragDelta: delta, fine: false) - 0.5
        let fineChange = KnobView.value(from: 0.5, dragDelta: delta, fine: true) - 0.5

        XCTAssertGreaterThan(coarseChange, 0)
        XCTAssertEqual(fineChange, coarseChange * Float(KnobView.fineFactor), accuracy: 1e-6,
                        "fine mode must move the value at exactly 1/8 the coarse rate for the same drag delta")
    }

    func testValueClampsAtBothEnds() {
        let clampedHigh = KnobView.value(from: 0.9, dragDelta: -10_000, fine: false)
        XCTAssertEqual(clampedHigh, 1.0, accuracy: 1e-6)

        let clampedLow = KnobView.value(from: 0.1, dragDelta: 10_000, fine: false)
        XCTAssertEqual(clampedLow, 0.0, accuracy: 1e-6)
    }

    // MARK: - Page switching does not leak arranged subviews

    /// Guards the bug called out in the task: `showPage` used to only
    /// `removeFromSuperview()` the tracked `knobs` array. `knobRow`'s
    /// `arrangedSubviews` is checked directly (not just `knobs.count`,
    /// which is always freshly reassigned regardless) so a real leak in the
    /// UIStackView's own bookkeeping would show up here.
    func testSwitchingPagesDoesNotAccumulateStaleArrangedSubviews() {
        let pages = ControlPages(frame: CGRect(x: 0, y: 0, width: 400, height: 120))
        let order = [0, 1, 2, 3, 4, 0, 2, 4, 1, 3, 0]

        for index in order {
            pages.showPage(index)
            let expectedCount = ControlPages.pages[index].params.count
            XCTAssertEqual(pages.visibleKnobViews.count, expectedCount,
                            "page \(index) should show exactly \(expectedCount) knobs, found \(pages.visibleKnobViews.count)")
            XCTAssertEqual(pages.knobs.count, expectedCount)
        }
    }

    // MARK: - valueProvider seeds newly-shown pages

    /// Without a `valueProvider`, a page not yet visible when the host
    /// automates one of its parameters would show `Param.defaultValue`
    /// instead of the real current value once the user switches to it.
    /// `ControlPages.valueProvider` lets the owner (Task 12) close over the
    /// AU's live parameter tree to fix this without `ControlPages` itself
    /// depending on the AU.
    func testValueProviderSeedsNewlyShownPageInsteadOfDefault() {
        let pages = ControlPages(frame: CGRect(x: 0, y: 0, width: 400, height: 120))
        let seeded: [Param: Float] = [.attack: 0.9]
        pages.valueProvider = { seeded[$0] ?? $0.defaultValue }

        // ENV (index 1) isn't the initially-shown page (MAIN, index 0 is).
        pages.showPage(1)

        XCTAssertEqual(pages.knob(for: .attack)?.value ?? -1, 0.9, accuracy: 1e-6)
        // A sibling on the same page with no seeded value still falls back
        // to its normal default.
        XCTAssertEqual(pages.knob(for: .decay)?.value ?? -1, Param.decay.defaultValue, accuracy: 1e-6)
    }

    func testWithoutValueProviderNewPageFallsBackToParamDefaults() {
        let pages = ControlPages(frame: CGRect(x: 0, y: 0, width: 400, height: 120))
        pages.showPage(2)
        XCTAssertEqual(pages.knob(for: .unison)?.value ?? -1, Param.unison.defaultValue, accuracy: 1e-6)
    }
}
