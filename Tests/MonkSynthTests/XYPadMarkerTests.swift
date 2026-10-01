import XCTest
import UIKit
@testable import MonkSynth

/// The pad covers the whole scene, so repainting it on every touch move
/// redraws a full-scene bitmap at touch rate. The touch marker therefore
/// lives on its own small layer that only moves; the pad's `draw(_:)`
/// (ticks, vowel pills, hint) reruns only when that content changes.
///
/// `layer.needsDisplay()` is CALayer's own "setNeedsDisplay was called and
/// no display has happened since" flag, so these tests need no hook in the
/// view: flush with `displayIfNeeded()`, act, then read the flag.
final class XYPadMarkerTests: XCTestCase {

    private var savedHintFlag: Any?

    override func setUp() {
        super.setUp()
        savedHintFlag = UserDefaults.standard.object(forKey: XYPadView.hintDismissedKey)
    }

    override func tearDown() {
        UserDefaults.standard.set(savedHintFlag, forKey: XYPadView.hintDismissedKey)
        super.tearDown()
    }

    private func makePad(hintDismissed: Bool) -> XYPadView {
        UserDefaults.standard.set(hintDismissed, forKey: XYPadView.hintDismissedKey)
        let pad = XYPadView(frame: CGRect(x: 0, y: 0, width: 200, height: 100))
        pad.layer.displayIfNeeded()
        XCTAssertFalse(pad.layer.needsDisplay(), "precondition: nothing pending after a flush")
        return pad
    }

    func testTouchesMoveTheMarkerWithoutRepaintingThePad() {
        let pad = makePad(hintDismissed: true)
        XCTAssertTrue(pad.touchMarker.isHidden, "no marker before a touch")

        pad.beginTouch(at: CGPoint(x: 50, y: 25), in: pad.bounds.size)
        XCTAssertFalse(pad.layer.needsDisplay(), "touch-down must not repaint the whole pad")
        XCTAssertFalse(pad.touchMarker.isHidden)
        XCTAssertEqual(pad.touchMarker.position.x, 50, accuracy: 1e-4)
        XCTAssertEqual(pad.touchMarker.position.y, 25, accuracy: 1e-4)

        pad.moveTouch(at: CGPoint(x: 150, y: 80), in: pad.bounds.size)
        XCTAssertFalse(pad.layer.needsDisplay(), "touch-move must not repaint the whole pad")
        XCTAssertEqual(pad.touchMarker.position.x, 150, accuracy: 1e-4)
        XCTAssertEqual(pad.touchMarker.position.y, 80, accuracy: 1e-4)

        pad.endTouch()
        XCTAssertFalse(pad.layer.needsDisplay(), "touch-up must not repaint the whole pad")
        XCTAssertTrue(pad.touchMarker.isHidden, "marker hides when the note ends")
    }

    /// A drag past the edge clamps the parameters; the marker clamps with
    /// them, so it never sits somewhere the sound isn't.
    func testMarkerClampsToThePadLikeTheParameters() {
        let pad = makePad(hintDismissed: true)
        pad.beginTouch(at: CGPoint(x: 260, y: -40), in: pad.bounds.size)
        XCTAssertEqual(pad.touchMarker.position.x, 200, accuracy: 1e-4)
        XCTAssertEqual(pad.touchMarker.position.y, 0, accuracy: 1e-4)
    }

    /// Dismissing the first-touch hint is a real content change, so the
    /// first touch on a fresh install still repaints once.
    func testFirstTouchRepaintsOnceToDismissTheHint() {
        let pad = makePad(hintDismissed: false)
        pad.beginTouch(at: CGPoint(x: 50, y: 25), in: pad.bounds.size)
        XCTAssertTrue(pad.layer.needsDisplay(), "hint dismissal must repaint")
        pad.layer.displayIfNeeded()
        pad.moveTouch(at: CGPoint(x: 60, y: 30), in: pad.bounds.size)
        XCTAssertFalse(pad.layer.needsDisplay())
    }

    /// The marker's dot takes the character's accent without repainting.
    func testAccentRecoloursTheMarkerDot() {
        let pad = makePad(hintDismissed: true)
        pad.accent = .red
        XCTAssertFalse(pad.layer.needsDisplay())
        let fills = (pad.touchMarker.sublayers ?? []).compactMap { ($0 as? CAShapeLayer)?.fillColor }
        XCTAssertTrue(fills.contains(UIColor.red.cgColor), "expected the accent dot among \(fills)")
    }
}
