import XCTest
import UIKit
@testable import MonkSynth

/// `CharacterView.draw(_:)` renders the body's shaded primitives (see the
/// style spec's "Performance" section) into a cached `UIImage` keyed by
/// character id, view size, and screen scale, then composites that same
/// bitmap every frame — only the eyes and mouth are drawn fresh. This is the
/// proof: a fake `Character` that counts every `drawBody` call must see
/// exactly one call across several redraws that only touch `vowel`/
/// `amplitude`/blinking, and a fresh call only when the cache key actually
/// changes (character swap, bounds resize, scale change).
final class CharacterBodyCacheTests: XCTestCase {

    /// Shared mutable counter a `CountingCharacter` increments from
    /// `drawBody`. A class (not a struct field) so multiple `Character`
    /// value-type instances sharing one `id` can still report into the same
    /// counter across the `character =` reassignments these tests do.
    private final class DrawCounter { var count = 0 }

    private struct CountingCharacter: Character {
        let id: String
        let counter: DrawCounter

        let displayName = "Counting"
        func drawBody(in stage: CGRect) { counter.count += 1 }
        func drawEyes(in stage: CGRect, blinking: Bool) {}
        func mouthShape(vowel: Float) -> (w: CGFloat, h: CGFloat) { (0.2, 0.2) }
        let mouthCentre: (fx: CGFloat, fy: CGFloat) = (0.5, 0.5)
        let mouthBoxFraction: CGFloat = 0.2
    }

    /// Calls the view's own `draw(_:)` inside a real graphics context —
    /// the same requirement `Shading`'s `UIGraphicsGetCurrentContext()`
    /// calls have — without relying on `CALayer.render(in:)`'s own content-
    /// caching semantics, which would make "did drawBody get skipped"
    /// ambiguous with "did the layer just reuse its backing store".
    private func renderOnce(_ view: CharacterView) {
        let renderer = UIGraphicsImageRenderer(size: view.bounds.size)
        _ = renderer.image { _ in view.draw(view.bounds) }
    }

    func testBodyIsRenderedOnceThenReusedAcrossMouthOnlyChanges() {
        let counter = DrawCounter()
        let view = CharacterView(frame: CGRect(x: 0, y: 0, width: 200, height: 200))
        view.character = CountingCharacter(id: "counting-a", counter: counter)

        renderOnce(view)
        XCTAssertEqual(counter.count, 1, "the first draw must render the body")

        // Mouth/eyes-only changes: amplitude, vowel, and note state (which
        // drives the mouth's live pose) must all reuse the cached image.
        view.vowel = 0.15
        renderOnce(view)
        view.vowel = 0.9
        renderOnce(view)
        view.amplitude = 0.6
        renderOnce(view)
        view.noteActive = true
        renderOnce(view)
        view.noteActive = false
        renderOnce(view)

        XCTAssertEqual(counter.count, 1,
                       "mouth/eyes-only changes must reuse the cached body image, not call drawBody again")
    }

    func testBodyReRendersWhenCharacterChanges() {
        let counterA = DrawCounter()
        let counterB = DrawCounter()
        let view = CharacterView(frame: CGRect(x: 0, y: 0, width: 200, height: 200))
        view.character = CountingCharacter(id: "counting-a", counter: counterA)
        renderOnce(view)
        XCTAssertEqual(counterA.count, 1)

        view.character = CountingCharacter(id: "counting-b", counter: counterB)
        renderOnce(view)
        XCTAssertEqual(counterB.count, 1, "a different character id must invalidate the cache and redraw")
        XCTAssertEqual(counterA.count, 1, "switching away must not re-render the old character")
    }

    func testBodyReRendersWhenBoundsSizeChanges() {
        let counter = DrawCounter()
        let view = CharacterView(frame: CGRect(x: 0, y: 0, width: 200, height: 200))
        view.character = CountingCharacter(id: "counting-resize", counter: counter)
        renderOnce(view)
        XCTAssertEqual(counter.count, 1)

        view.frame = CGRect(x: 0, y: 0, width: 260, height: 260)
        renderOnce(view)
        XCTAssertEqual(counter.count, 2, "a bounds size change must invalidate the cache and redraw")

        // Redrawing again at the SAME new size must not re-render a third
        // time — proves the cache key, not just "something changed once",
        // is what's gating this.
        renderOnce(view)
        XCTAssertEqual(counter.count, 2)
    }
}
