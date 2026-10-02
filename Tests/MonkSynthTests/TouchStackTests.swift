import XCTest
@testable import MonkSynth

/// The scene plays like a mono keyboard: the newest finger sings; lift it and
/// the one still down takes over from where it is; the note ends with the
/// last finger.
final class TouchStackTests: XCTestCase {
    private let a = CGPoint(x: 10, y: 10), b = CGPoint(x: 200, y: 50)

    func testTheFirstFingerStartsTheNote() {
        var s = TouchStack<Int>()
        XCTAssertEqual(s.press(1, at: a), .begin(a))
    }

    func testASecondFingerTakesOver() {
        var s = TouchStack<Int>()
        _ = s.press(1, at: a)
        XCTAssertEqual(s.press(2, at: b), .move(b))
    }

    func testLiftingTheSecondFingerGoesBackToTheFirst() {
        var s = TouchStack<Int>()
        _ = s.press(1, at: a)
        _ = s.press(2, at: b)
        XCTAssertEqual(s.lift(2), .move(a))
        XCTAssertEqual(s.lift(1), .end)
    }

    func testItGoesBackToWhereTheFirstFingerIsNowNotWhereItStarted() {
        var s = TouchStack<Int>()
        _ = s.press(1, at: a)
        _ = s.press(2, at: b)
        let moved = CGPoint(x: 40, y: 90)
        XCTAssertNil(s.move(1, to: moved), "a finger underneath must not play while another is on top")
        XCTAssertEqual(s.lift(2), .move(moved))
    }

    func testLiftingAnOlderFingerChangesNothing() {
        var s = TouchStack<Int>()
        _ = s.press(1, at: a)
        _ = s.press(2, at: b)
        XCTAssertNil(s.lift(1))
        XCTAssertEqual(s.move(2, to: a), .move(a))
        XCTAssertEqual(s.lift(2), .end)
    }

    func testThreeFingersFallBackInOrder() {
        var s = TouchStack<Int>()
        let c = CGPoint(x: 300, y: 300)
        _ = s.press(1, at: a); _ = s.press(2, at: b); _ = s.press(3, at: c)
        XCTAssertEqual(s.lift(3), .move(b))
        XCTAssertEqual(s.lift(2), .move(a))
        XCTAssertEqual(s.lift(1), .end)
    }

    func testUnknownTouchesAreIgnored() {
        var s = TouchStack<Int>()
        XCTAssertNil(s.move(9, to: a))
        XCTAssertNil(s.lift(9))
        XCTAssertTrue(s.isEmpty)
    }
}
