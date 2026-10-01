# UI Stage Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers-extended-cc:subagent-driven-development (recommended) or superpowers-extended-cc:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the generic dark UI with the approved sticker-cartoon design: twelve redrawn characters with a shared expressive mouth, a per-character scene that is itself the XY pad, and restyled controls that recolour per character.

**Architecture:** A small drawing kit (`Toon`) draws SVG-style path data in a 300-unit stage space mapped onto the existing square stage, so the approved mockup paths in `docs/mockups/stage-redesign/gen.mjs` port number-for-number. A `ToonCharacter` protocol refines the existing `Character` protocol and supplies the shared mouth (`ToonMouth`). A new `SceneView` holds a backdrop, the existing `CharacterView` (still `PluginView.stage`) and the existing `XYPadView` (still `PluginView.pad`) stretched over the whole scene. `Theme` gains a live per-character accent that the chrome reads.

**Tech Stack:** Swift 5, UIKit + Core Graphics, XCTest, xcodegen (`scripts/test.sh` regenerates the project).

**User decisions (already made):**
- "Stage/scene (Recommended)": each character performs in its own scene and the scene is the XY pad.
- "Full redesign" of all twelve characters.
- Art style: bold sticker cartoon ("what do you think you can most accurately achieve" → sticker).
- Design approved as specced; mockups approved after review ("build it.") with these fixes applied: monk neck under robe and beads draped; fish fin attached; unicorn mane attached; dog and cat have necks; pizza cheese edge follows the crust arc; cat bib removed; ghost tombstones blank; fire fighter band clipped to the coat; sun has rays; touch marker is ripple rings.
- Schwung back-ports (stuck bend, pressure routing) are out of scope for this plan.

**Spec:** `docs/superpowers/specs/2026-10-01-ui-stage-redesign-design.md` (read the "Amendments from the mockup review" section — it overrides earlier numbers).

**Art source of truth:** `docs/mockups/stage-redesign/gen.mjs`. Every character is an entry `CH.<id>` with `body()`, `face(blink)`, `mouth: {x, y, scale, variant, lip}` and optional `over()`; scenes are in `scene(id, W, H)` and the `prop` table. `docs/mockups/stage-redesign/characters.png` and `mouths.png` show what the port must look like.

**Running tests:** `scripts/test.sh` (whole suite) or `scripts/test.sh MonkSynthTests/<ClassName>` (one class). It runs `xcodegen generate` first, so new files under `AU/UI` and `Tests/MonkSynthTests` are picked up automatically. Render harnesses write PNGs to `/tmp` (which is `/private/tmp` on the host); look at them with the Read tool.

---

## File structure

| File | Responsibility |
|---|---|
| `AU/UI/Toon.swift` (new) | Drawing kit: SVG path parser, stage mapping, shape/stroke/eye helpers, `UIColor(hex:)`, `Palette`, `Expression`. |
| `AU/UI/ToonMouth.swift` (new) | The shared five-anchor mouth: parameters, path, drawing. |
| `AU/UI/ToonCharacter.swift` (new) | `ToonCharacter` protocol + defaults bridging to `Character`. |
| `AU/UI/Backdrop.swift` (new) | Scene primitives (sky, ground, props) drawn in point space. |
| `AU/UI/SceneView.swift` (new) | Container: `BackdropView` + `CharacterView` + `XYPadView`; character-rect maths. |
| `AU/UI/CharacterThumbnail.swift` (new) | Renders a character in its scene into a small `UIImage` for the dropdown. |
| `AU/UI/Character.swift` | Protocol additions (`palette`, `drawFace`, `drawOverMouth`, `drawBackdrop`) with defaults. |
| `AU/UI/CharacterView.swift` | Calls `drawFace` / `drawOverMouth`. |
| `AU/UI/UserCharacter.swift` | Forwards the new requirements to its face. |
| `AU/UI/{Monk,Fish,Unicorn,Girl,OldMan,Cow,FireFighter,Punk,Dog,Pizza,Ghost,Cat}Character.swift` | Rewritten as `ToonCharacter`s, each with its scene. |
| `AU/UI/XYPadView.swift` | New drawing only (ticks, vowel scale, ripple marker, first-touch hint). Touch logic untouched. |
| `AU/UI/PluginView.swift` | One `scene` zone instead of stage + pad; palette application; restyled handle/info. |
| `AU/UI/Theme.swift` | New tokens, rounded fonts, live `accent`, two strip heights. |
| `AU/UI/KnobView.swift`, `ControlPages.swift`, `CharacterSelector.swift` | Restyle. |
| `AU/UI/CharacterDropdownView.swift`, `AboutView.swift`, `MoreAppsView.swift` | Restyle via tokens; dropdown thumbnails. |
| Tests: `ToonTests`, `ToonMouthTests`, `CharacterArtTests`, `BackdropTests`, `SceneViewTests` (new); `LayoutTests`, `CharacterTests`, `IdleAnimatorTests`, `ControlPagesTests` (updated). |

---

### Task 1: Toon drawing kit

**Goal:** A tested drawing kit that parses gen.mjs-style SVG path strings and draws sticker shapes in a 300-unit stage space.

**Files:**
- Create: `AU/UI/Toon.swift`
- Test: `Tests/MonkSynthTests/ToonTests.swift`

**Acceptance Criteria:**
- [ ] `Toon.path("M0 0 L10 0 L10 10 Z").bounds == CGRect(x: 0, y: 0, width: 10, height: 10)`.
- [ ] `Toon.path("M0 0 C0 -10 20 -10 20 0")` bounds have `minY < -5` (cubic parsed).
- [ ] `Toon.path("M0 0 A10 10 0 0 1 20 0")` bounds `minY` ≈ −10 and `maxX` ≈ 20 (circular arc, sweep over the top).
- [ ] Numbers with signs, decimals and no separators (`"M-2.5-3L4 5"`) parse.
- [ ] `UIColor(hex: 0x2B1D1A)` has RGB (43, 29, 26)/255.
- [ ] `Toon.inStage` maps (300, 300) to the stage's max corner.

**Verify:** `scripts/test.sh MonkSynthTests/ToonTests` → `** TEST SUCCEEDED **`

**Steps:**

- [ ] **Step 1: Write the failing tests**

```swift
// Tests/MonkSynthTests/ToonTests.swift
import UIKit
import XCTest
@testable import MonkSynth

final class ToonTests: XCTestCase {
    func testLinesAndClose() {
        XCTAssertEqual(Toon.path("M0 0 L10 0 L10 10 Z").bounds, CGRect(x: 0, y: 0, width: 10, height: 10))
    }

    func testCubic() {
        XCTAssertLessThan(Toon.path("M0 0 C0 -10 20 -10 20 0").bounds.minY, -5)
    }

    func testQuadratic() {
        XCTAssertLessThan(Toon.path("M0 0 Q10 -20 20 0").bounds.minY, -5)
    }

    func testCircularArcSweepsOverTheTop() {
        let b = Toon.path("M0 0 A10 10 0 0 1 20 0").bounds
        XCTAssertEqual(b.minY, -10, accuracy: 0.01)
        XCTAssertEqual(b.minX, 0, accuracy: 0.01)
        XCTAssertEqual(b.maxX, 20, accuracy: 0.01)
    }

    func testCompactNumberSyntax() {
        let b = Toon.path("M-2.5-3L4 5").bounds
        XCTAssertEqual(b.minX, -2.5, accuracy: 1e-9)
        XCTAssertEqual(b.minY, -3, accuracy: 1e-9)
        XCTAssertEqual(b.maxY, 5, accuracy: 1e-9)
    }

    func testHexColour() {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(hex: 0x2B1D1A).getRed(&r, green: &g, blue: &b, alpha: &a)
        XCTAssertEqual(r * 255, 43, accuracy: 0.01)
        XCTAssertEqual(g * 255, 29, accuracy: 0.01)
        XCTAssertEqual(b * 255, 26, accuracy: 0.01)
        XCTAssertEqual(a, 1)
    }

    func testInStageMapsTheThreeHundredUnitSquareOntoTheStage() {
        let stage = CGRect(x: 10, y: 20, width: 150, height: 150)
        let r = UIGraphicsImageRenderer(size: CGSize(width: 200, height: 200))
        var mapped = CGPoint.zero
        _ = r.image { _ in
            Toon.inStage(stage) { ctx in
                mapped = CGPoint(x: 300, y: 300).applying(ctx.ctm)
            }
        }
        // ctm includes the renderer's own flip/scale; compare against the
        // same context's mapping of the stage corner instead.
        var expected = CGPoint.zero
        _ = r.image { ctx in expected = CGPoint(x: stage.maxX, y: stage.maxY).applying(ctx.cgContext.ctm) }
        XCTAssertEqual(mapped.x, expected.x, accuracy: 0.01)
        XCTAssertEqual(mapped.y, expected.y, accuracy: 0.01)
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `scripts/test.sh MonkSynthTests/ToonTests`
Expected: build failure, `cannot find 'Toon' in scope`.

- [ ] **Step 3: Implement `AU/UI/Toon.swift`**

```swift
import UIKit

/// The sticker-cartoon drawing kit every character and scene shares: bold
/// ink outlines, flat fills, one hard shadow tone offset up-left so the
/// shadow reads as a crescent on the lower right.
///
/// Characters draw in a 300×300 "stage unit" space (see `inStage`) — the
/// same space the approved mockups in `docs/mockups/stage-redesign/gen.mjs`
/// use — so their path data ports number-for-number. Backdrops draw in
/// point space and pass `unit` so their outlines match the character's.
enum Toon {
    static let ink = UIColor(hex: 0x2B1D1A)

    /// Outline widths in stage units.
    static let bold: CGFloat = 7
    static let medium: CGFloat = 5
    static let fine: CGFloat = 3.5

    static let stageUnits: CGFloat = 300
    /// The shaded copy of a shape is the shape moved up-left by this much
    /// (in stage units); what it uncovers is the shadow.
    static let shadowOffset = CGSize(width: -9, height: -8)

    // MARK: - Stage mapping

    /// Runs `body` with the current context mapped so (0,0)…(300,300) covers
    /// `stage`. Nothing drawn inside leaks its transform.
    static func inStage(_ stage: CGRect, _ body: (CGContext) -> Void) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        ctx.saveGState()
        ctx.translateBy(x: stage.minX, y: stage.minY)
        ctx.scaleBy(x: stage.width / stageUnits, y: stage.height / stageUnits)
        body(ctx)
        ctx.restoreGState()
    }

    // MARK: - Shapes

    static func circle(_ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat) -> UIBezierPath {
        UIBezierPath(ovalIn: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2))
    }

    static func ellipse(_ cx: CGFloat, _ cy: CGFloat, _ rx: CGFloat, _ ry: CGFloat) -> UIBezierPath {
        UIBezierPath(ovalIn: CGRect(x: cx - rx, y: cy - ry, width: rx * 2, height: ry * 2))
    }

    static func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> UIBezierPath {
        UIBezierPath(rect: CGRect(x: x, y: y, width: w, height: h))
    }

    /// `path` rotated by `degrees` about (cx, cy) — gen.mjs's `rotate(a cx cy)`.
    static func rotated(_ path: UIBezierPath, degrees: CGFloat, cx: CGFloat, cy: CGFloat) -> UIBezierPath {
        let p = path.copy() as! UIBezierPath
        p.apply(CGAffineTransform(translationX: -cx, y: -cy))
        p.apply(CGAffineTransform(rotationAngle: degrees * .pi / 180))
        p.apply(CGAffineTransform(translationX: cx, y: cy))
        return p
    }

    /// gen.mjs `toon(...)`: fill, hard shadow, ink outline.
    /// `shadow` defaults to the fill at 80% brightness (gen.mjs `shade(base, 0.8)`).
    static func shape(_ path: UIBezierPath, fill: UIColor, lineWidth: CGFloat = bold,
                      shaded: Bool = true, shadow: UIColor? = nil, unit: CGFloat = 1) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        if shaded {
            (shadow ?? fill.adjusted(brightnessScale: 0.8)).setFill()
            path.fill()
            ctx.saveGState()
            path.addClip()
            let lit = path.copy() as! UIBezierPath
            lit.apply(CGAffineTransform(translationX: shadowOffset.width * unit, y: shadowOffset.height * unit))
            fill.setFill()
            lit.fill()
            ctx.restoreGState()
        } else {
            fill.setFill()
            path.fill()
        }
        stroke(path, width: lineWidth * unit)
    }

    /// gen.mjs `line(...)`: a round-capped, round-joined stroke.
    static func stroke(_ path: UIBezierPath, width: CGFloat, color: UIColor = ink) {
        color.setStroke()
        path.lineWidth = width
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        path.stroke()
    }

    /// A plain fill, for gen.mjs raw `<ellipse fill=… opacity=…>` details.
    static func fill(_ path: UIBezierPath, _ color: UIColor) {
        color.setFill()
        path.fill()
    }

    /// Draws `body` clipped to `path` (gen.mjs `clip-path` groups).
    static func clipped(to path: UIBezierPath, _ body: () -> Void) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        ctx.saveGState()
        path.addClip()
        body()
        ctx.restoreGState()
    }

    // MARK: - Face parts (gen.mjs eyeOpen / eyeClosed / cheek / hl)

    static func highlight(_ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat) {
        fill(circle(cx, cy, r), .white)
    }

    static func eyeOpen(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat,
                        iris: UIColor = ink, look: CGPoint = CGPoint(x: 2, y: 1)) {
        shape(circle(x, y, r), fill: .white, lineWidth: medium, shaded: false)
        fill(circle(x + look.x, y + look.y, r * 0.55), iris)
        if iris != ink { fill(circle(x + look.x, y + look.y, r * 0.28), ink) }
        highlight(x + look.x - r * 0.2, y + look.y - r * 0.22, r * 0.18)
    }

    static func eyeClosed(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat) {
        stroke(path("M\(x - w) \(y) Q\(x) \(y + w * 0.75) \(x + w) \(y)"), width: medium)
    }

    static func cheek(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat = 11, color: UIColor = UIColor(hex: 0xF28B9B)) {
        fill(ellipse(x, y, r, r * 0.65), color.withAlphaComponent(0.75))
    }

    // MARK: - SVG path parsing

    /// Parses the absolute SVG path subset gen.mjs emits: M L H V C Q Z, and
    /// A for circular arcs (rx == ry, no rotation).
    static func path(_ d: String) -> UIBezierPath {
        var scanner = PathScanner(d)
        let p = UIBezierPath()
        var current = CGPoint.zero
        var start = CGPoint.zero
        var command: Character = "M"
        while let next = scanner.nextCommandOrNumber() {
            if case .command(let c) = next { command = c }
            else { scanner.pushBack(next) }
            switch command {
            case "M":
                current = scanner.point(); start = current; p.move(to: current)
                command = "L"   // subsequent pairs are implicit lineTos
            case "L":
                current = scanner.point(); p.addLine(to: current)
            case "H":
                current.x = scanner.number(); p.addLine(to: current)
            case "V":
                current.y = scanner.number(); p.addLine(to: current)
            case "C":
                let c1 = scanner.point(), c2 = scanner.point(); current = scanner.point()
                p.addCurve(to: current, controlPoint1: c1, controlPoint2: c2)
            case "Q":
                let c = scanner.point(); current = scanner.point()
                p.addQuadCurve(to: current, controlPoint: c)
            case "A":
                let r = scanner.number(); _ = scanner.number(); _ = scanner.number()
                let large = scanner.number() != 0, sweep = scanner.number() != 0
                let end = scanner.point()
                addArc(to: p, from: current, to: end, radius: r, largeArc: large, sweep: sweep)
                current = end
            case "Z", "z":
                p.close(); current = start
            default:
                return p
            }
        }
        return p
    }

    /// SVG arc (endpoint form, rx == ry, no rotation) → centre form.
    /// SVG spec F.6.5 with the rotation terms dropped.
    private static func addArc(to p: UIBezierPath, from p0: CGPoint, to p1: CGPoint,
                               radius: CGFloat, largeArc: Bool, sweep: Bool) {
        let x1p = (p0.x - p1.x) / 2, y1p = (p0.y - p1.y) / 2
        let d2 = x1p * x1p + y1p * y1p
        guard d2 > 0 else { return }
        var r = radius
        if d2 > r * r { r = sqrt(d2) }   // radius too small: SVG scales it up
        let coef = (largeArc != sweep ? 1 : -1) * sqrt(max(0, (r * r - d2) / d2))
        let cxp = coef * y1p, cyp = -coef * x1p
        let c = CGPoint(x: cxp + (p0.x + p1.x) / 2, y: cyp + (p0.y + p1.y) / 2)
        let a0 = atan2((y1p - cyp) / r, (x1p - cxp) / r)
        let a1 = atan2((-y1p - cyp) / r, (-x1p - cxp) / r)
        var delta = a1 - a0
        if sweep && delta < 0 { delta += 2 * .pi }
        if !sweep && delta > 0 { delta -= 2 * .pi }
        p.addArc(withCenter: c, radius: r, startAngle: a0, endAngle: a0 + delta, clockwise: sweep)
    }

    private struct PathScanner {
        enum Token { case command(Character), number(CGFloat) }
        private let chars: [Character]
        private var i = 0
        private var pending: Token?
        init(_ s: String) { chars = Array(s) }

        mutating func pushBack(_ t: Token) { pending = t }

        mutating func nextCommandOrNumber() -> Token? {
            if let t = pending { pending = nil; return t }
            while i < chars.count, chars[i] == " " || chars[i] == "," || chars[i] == "\n" { i += 1 }
            guard i < chars.count else { return nil }
            let c = chars[i]
            if c.isLetter { i += 1; return .command(c) }
            return .number(scanNumber())
        }

        mutating func number() -> CGFloat {
            if case .number(let n)? = nextCommandOrNumber() { return n }
            return 0
        }

        mutating func point() -> CGPoint { CGPoint(x: number(), y: number()) }

        private mutating func scanNumber() -> CGFloat {
            let startIndex = i
            if i < chars.count, chars[i] == "-" || chars[i] == "+" { i += 1 }
            var seenDot = false
            while i < chars.count {
                let c = chars[i]
                if c.isNumber { i += 1 }
                else if c == ".", !seenDot { seenDot = true; i += 1 }
                else if c == "e" || c == "E" {
                    i += 1
                    if i < chars.count, chars[i] == "-" || chars[i] == "+" { i += 1 }
                } else { break }
            }
            return CGFloat(Double(String(chars[startIndex..<i])) ?? 0)
        }
    }
}

extension UIColor {
    /// 0xRRGGBB.
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: alpha)
    }
}

/// A character's colours: the scene's sky and ground, and the accent the
/// chrome (active tab, knob arcs, touch marker, selector chevron) takes on
/// while that character is loaded.
struct Palette: Equatable {
    var accent: UIColor
    var skyTop: UIColor
    var skyBottom: UIColor
    var ground: UIColor

    static let neutral = Palette(accent: UIColor(hex: 0xF0A020),
                                 skyTop: UIColor(hex: 0x3A3040),
                                 skyBottom: UIColor(hex: 0x2A2230),
                                 ground: UIColor(hex: 0x4A3D41))
}

/// Everything a face reacts to, already stepped by `CharacterView` so it
/// moves in frames: blink state, loudness (0…1, four steps) and the
/// quantised vowel.
struct Expression: Equatable {
    var blinking: Bool
    var loudness: CGFloat
    var vowel: Float

    static let rest = Expression(blinking: false, loudness: 0, vowel: 0.5)
}
```

Note: `UIColor.adjusted(...)` already exists in `AU/UI/Theme.swift`. A brightness scale in HSB with hue and saturation unchanged multiplies all three RGB channels equally, which matches gen.mjs's `shade(hex, 0.8)`.

- [ ] **Step 4: Run to verify pass**

Run: `scripts/test.sh MonkSynthTests/ToonTests`
Expected: `** TEST SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
git add AU/UI/Toon.swift Tests/MonkSynthTests/ToonTests.swift
git commit -m "Toon: the sticker drawing kit, and an SVG path parser so the mockups port as numbers"
```

---

### Task 2: Shared mouth and the `ToonCharacter` protocol

**Goal:** The five-anchor `ToonMouth`, a `ToonCharacter` protocol that turns 300-unit drawing into `Character` conformance, and `Character` gaining `palette`, `drawFace`, `drawOverMouth`, `drawBackdrop` (with defaults), wired through `CharacterView` and `UserCharacter`.

**Files:**
- Create: `AU/UI/ToonMouth.swift`, `AU/UI/ToonCharacter.swift`
- Modify: `AU/UI/Character.swift` (protocol + default extension), `AU/UI/CharacterView.swift` (`draw(_:)`), `AU/UI/UserCharacter.swift`
- Test: `Tests/MonkSynthTests/ToonMouthTests.swift`

**Acceptance Criteria:**
- [ ] `ToonMouth.params(vowel:)` returns exactly the gen.mjs `ANCHORS` at vowel 0, 0.25, 0.5, 0.75, 1.
- [ ] `params` is continuous: no width/height step > 0.6 units between vowel samples 0.01 apart.
- [ ] EE's w/h ratio ≥ 3× OO's.
- [ ] A test `ToonCharacter` (in the test file) drawn through `CharacterView` renders non-blank pixels at its mouth centre.
- [ ] `UserCharacter` forwards `palette`, `drawFace`, `drawOverMouth`, `drawBackdrop` to its face.
- [ ] Whole suite still passes (old characters keep working through the defaults).

**Verify:** `scripts/test.sh` → `** TEST SUCCEEDED **`

**Steps:**

- [ ] **Step 1: Write the failing tests**

```swift
// Tests/MonkSynthTests/ToonMouthTests.swift
import UIKit
import XCTest
@testable import MonkSynth

private struct ProbeCharacter: ToonCharacter {
    let id = "probe"
    let displayName = "Probe"
    let palette = Palette.neutral
    let mouthStyle = ToonMouth.Style(x: 150, y: 150, scale: 1, variant: .bare)
    func drawToonBody() { Toon.shape(Toon.circle(150, 150, 120), fill: .white) }
    func drawToonFace(_ e: Expression) {}
}

final class ToonMouthTests: XCTestCase {
    func testAnchorsMatchTheMockup() {
        let expected: [(CGFloat, CGFloat)] = [(24, 26), (34, 40), (50, 56), (64, 34), (74, 18)]
        for (i, (w, h)) in expected.enumerated() {
            let p = ToonMouth.params(vowel: Float(i) / 4)
            XCTAssertEqual(p.w, w, accuracy: 1e-6)
            XCTAssertEqual(p.h, h, accuracy: 1e-6)
        }
    }

    func testContinuous() {
        var prev = ToonMouth.params(vowel: 0)
        for i in 1...100 {
            let p = ToonMouth.params(vowel: Float(i) / 100)
            XCTAssertLessThanOrEqual(abs(p.w - prev.w), 0.6)
            XCTAssertLessThanOrEqual(abs(p.h - prev.h), 0.9)
            prev = p
        }
    }

    func testEEIsMuchWiderForItsHeightThanOO() {
        let oo = ToonMouth.params(vowel: 0), ee = ToonMouth.params(vowel: 1)
        XCTAssertGreaterThanOrEqual((ee.w / ee.h) / (oo.w / oo.h), 3)
    }

    func testMouthShapeIsInStageFractions() {
        let c = ProbeCharacter()
        let ah = c.mouthShape(vowel: 0.5)
        XCTAssertEqual(ah.w, 50.0 / 300, accuracy: 1e-6)
        XCTAssertEqual(ah.h, 56.0 / 300, accuracy: 1e-6)
        XCTAssertEqual(c.mouthCentre.fx, 0.5, accuracy: 1e-6)
        XCTAssertEqual(c.mouthBoxFraction, 1)
    }

    func testDrawsAMouthThroughCharacterView() throws {
        let view = CharacterView(frame: CGRect(x: 0, y: 0, width: 300, height: 300))
        view.character = ProbeCharacter()
        view.noteActive = true
        view.vowel = 0.5
        let img = UIGraphicsImageRenderer(size: view.bounds.size).image { ctx in
            view.layer.render(in: ctx.cgContext)
        }
        // The cavity colour (#4A1622) must appear at the mouth centre.
        let px = try XCTUnwrap(img.cgImage?.dataProvider?.data as Data?)
        let w = Int(img.size.width * img.scale)
        let i = ((150 * Int(img.scale)) * w + 150 * Int(img.scale)) * 4
        let (b, g, r) = (px[i], px[i + 1], px[i + 2])   // BGRA
        XCTAssertLessThan(Int(r), 120); XCTAssertLessThan(Int(g), 60); XCTAssertLessThan(Int(b), 80)
    }
}
```

(If the pixel format is RGBA on this runtime, `testDrawsAMouthThroughCharacterView` checks the same thresholds against R/G/B — all three channels are dark for the cavity colour either way; the thresholds were chosen to pass under both orders.)

- [ ] **Step 2: Run to verify failure**

Run: `scripts/test.sh MonkSynthTests/ToonMouthTests` → build fails (`ToonCharacter` unknown).

- [ ] **Step 3: Implement `AU/UI/ToonMouth.swift`**

```swift
import UIKit

/// The one mouth every drawn character sings with: five anchors —
/// OO (small pucker), OH (round), AH (tall, tongue), EH (wide, top teeth),
/// EE (slit, both rows of teeth) — interpolated linearly. Ported from
/// gen.mjs `ANCHORS` / `mouthPath` / `mouth`. All sizes are stage units
/// (the 300-unit space of `Toon.inStage`) at scale 1.
enum ToonMouth {
    struct Params: Equatable {
        var w, h, round, tongue, top, bottom: CGFloat
    }

    enum Variant { case lips, muzzle, bare }

    struct Style {
        var x: CGFloat
        var y: CGFloat
        var scale: CGFloat
        var variant: Variant
        var lip: UIColor = .clear
    }

    static let anchors: [Params] = [
        Params(w: 24, h: 26, round: 1.0, tongue: 0.0, top: 0, bottom: 0),   // OO
        Params(w: 34, h: 40, round: 1.0, tongue: 0.3, top: 0, bottom: 0),   // OH
        Params(w: 50, h: 56, round: 0.9, tongue: 1.0, top: 0, bottom: 0),   // AH
        Params(w: 64, h: 34, round: 0.45, tongue: 0.8, top: 1, bottom: 0),  // EH
        Params(w: 74, h: 18, round: 0.12, tongue: 0.0, top: 1, bottom: 1),  // EE
    ]

    static let cavity = UIColor(hex: 0x4A1622)
    static let tongue = UIColor(hex: 0xE8607A)
    static let teeth = UIColor(hex: 0xFFFAF0)

    static func params(vowel: Float) -> Params {
        let t = CGFloat(min(max(vowel, 0), 1)) * 4
        let i = min(3, Int(t))
        let f = t - CGFloat(i)
        let a = anchors[i], b = anchors[i + 1]
        func mix(_ x: CGFloat, _ y: CGFloat) -> CGFloat { x + (y - x) * f }
        return Params(w: mix(a.w, b.w), h: mix(a.h, b.h), round: mix(a.round, b.round),
                      tongue: mix(a.tongue, b.tongue), top: mix(a.top, b.top), bottom: mix(a.bottom, b.bottom))
    }

    /// The aperture: four cubics, the bottom dropping further than the top.
    /// `round` 1 is an ellipse; toward 0 the corners pinch to points.
    static func path(cx: CGFloat, cy: CGFloat, w: CGFloat, h: CGFloat, round: CGFloat) -> UIBezierPath {
        let l = cx - w / 2, r = cx + w / 2
        let t = cy - h * 0.42, b = cy + h * 0.58
        let kx = (w / 2) * 0.552, kyT = h * 0.42 * 0.552 * round, kyB = h * 0.58 * 0.552 * round
        let p = UIBezierPath()
        p.move(to: CGPoint(x: l, y: cy))
        p.addCurve(to: CGPoint(x: cx, y: t), controlPoint1: CGPoint(x: l, y: cy - kyT), controlPoint2: CGPoint(x: cx - kx, y: t))
        p.addCurve(to: CGPoint(x: r, y: cy), controlPoint1: CGPoint(x: cx + kx, y: t), controlPoint2: CGPoint(x: r, y: cy - kyT))
        p.addCurve(to: CGPoint(x: cx, y: b), controlPoint1: CGPoint(x: r, y: cy + kyB), controlPoint2: CGPoint(x: cx + kx, y: b))
        p.addCurve(to: CGPoint(x: l, y: cy), controlPoint1: CGPoint(x: cx - kx, y: b), controlPoint2: CGPoint(x: l, y: cy + kyB))
        p.close()
        return p
    }

    /// Draws in stage units; call inside `Toon.inStage`.
    /// `boost` is `CharacterView`'s stepped amplitude swell (≥ 1), applied to height.
    static func draw(_ s: Style, vowel: Float, boost: CGFloat) {
        let p = params(vowel: vowel)
        let w = p.w * s.scale, h = p.h * s.scale * boost
        let path = path(cx: s.x, cy: s.y, w: w, h: h, round: p.round)
        if s.variant == .lips {
            Toon.stroke(path, width: 17 * s.scale)
            Toon.stroke(path, width: 10 * s.scale, color: s.lip)
        }
        Toon.fill(path, cavity)
        Toon.clipped(to: path) {
            if p.tongue > 0.02 {
                Toon.fill(Toon.ellipse(s.x + w * 0.08, s.y + h * 0.58, w * 0.38, h * 0.42 * p.tongue), tongue)
            }
            if p.top > 0.02 {
                Toon.fill(Toon.rect(s.x - w, s.y - h, w * 2, h * 0.42 + h * 0.3 * p.top - h * 0.12), teeth)
            }
            if p.bottom > 0.02 {
                Toon.fill(Toon.rect(s.x - w, s.y + h * 0.58 - h * 0.28 * p.bottom, w * 2, h), teeth)
            }
        }
        Toon.stroke(path, width: (s.variant == .lips ? Toon.fine : Toon.medium) * max(0.8, s.scale))
    }
}
```

- [ ] **Step 4: Add the protocol requirements to `AU/UI/Character.swift`**

Add to `protocol Character` (after `drawEyes`):

```swift
    /// The character's colours — its scene and the chrome's accent.
    var palette: Palette { get }

    /// Eyes, brows, cheeks — everything that reacts to `expression`. Drawn
    /// after `drawBody`, before the mouth. The default calls `drawEyes`, so
    /// image-backed characters keep working unchanged.
    func drawFace(in stage: CGRect, expression: Expression)

    /// Anything that must sit ON the mouth (a moustache, whiskers). Default: nothing.
    func drawOverMouth(in stage: CGRect)

    /// The scene behind the character. `rect` is the whole (non-square)
    /// scene; `stage` is where the character's square sits inside it.
    func drawBackdrop(in rect: CGRect, stage: CGRect)
```

Add to the existing `extension Character` (the one with `faceID`):

```swift
    var palette: Palette { .neutral }
    func drawFace(in stage: CGRect, expression: Expression) {
        drawEyes(in: stage, blinking: expression.blinking)
    }
    func drawOverMouth(in stage: CGRect) {}
    func drawBackdrop(in rect: CGRect, stage: CGRect) {
        Backdrop.plain(in: rect, stage: stage, palette: palette)
    }
```

`Backdrop.plain` is created in Task 5; until then add a minimal `AU/UI/Backdrop.swift` now containing only:

```swift
import UIKit

/// Scene primitives. Everything draws in point space; `u` is the
/// character's stage-unit scale (stage width / 300) so outlines match.
enum Backdrop {
    /// Sky gradient over a ground band — the fallback scene.
    static func plain(in rect: CGRect, stage: CGRect, palette: Palette) {
        sky(rect, top: palette.skyTop, bottom: palette.skyBottom)
        let u = max(stage.width, 1) / Toon.stageUnits
        ground(rect, y: rect.minY + rect.height * 0.72, color: palette.ground, u: u)
    }

    static func sky(_ rect: CGRect, top: UIColor, bottom: UIColor) {
        guard let ctx = UIGraphicsGetCurrentContext(),
              let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                 colors: [top.cgColor, bottom.cgColor] as CFArray,
                                 locations: [0, 1]) else { return }
        ctx.saveGState()
        ctx.clip(to: rect)
        ctx.drawLinearGradient(g, start: CGPoint(x: rect.midX, y: rect.minY),
                               end: CGPoint(x: rect.midX, y: rect.maxY), options: [])
        ctx.restoreGState()
    }

    /// gen.mjs `ground(W, H, gy, col)`: a band from `y` to the bottom with an ink top edge.
    static func ground(_ rect: CGRect, y: CGFloat, color: UIColor, u: CGFloat) {
        let band = Toon.rect(rect.minX - 10, y, rect.width + 20, rect.maxY - y + 10)
        Toon.fill(band, color)
        Toon.stroke(band, width: Toon.medium * u)
    }
}
```

- [ ] **Step 5: Create `AU/UI/ToonCharacter.swift`**

```swift
import UIKit

/// A character drawn with the `Toon` kit in 300-unit stage space, singing
/// with the shared `ToonMouth`. Conformers implement only the `drawToon…`
/// methods and `mouthStyle`; every `Character` requirement that involves a
/// stage rect is supplied here by mapping into stage units.
///
/// Implement `drawToonFace` (never `drawEyes`): the default `drawEyes`
/// below routes through it.
protocol ToonCharacter: Character {
    var mouthStyle: ToonMouth.Style { get }
    func drawToonBody()
    func drawToonFace(_ e: Expression)
    func drawToonOverMouth()
}

extension ToonCharacter {
    func drawToonOverMouth() {}

    func drawBody(in stage: CGRect) { Toon.inStage(stage) { _ in drawToonBody() } }

    func drawFace(in stage: CGRect, expression: Expression) {
        Toon.inStage(stage) { _ in drawToonFace(expression) }
    }

    func drawEyes(in stage: CGRect, blinking: Bool) {
        var e = Expression.rest
        e.blinking = blinking
        drawFace(in: stage, expression: e)
    }

    func drawOverMouth(in stage: CGRect) { Toon.inStage(stage) { _ in drawToonOverMouth() } }

    /// Stage fractions, already scaled by `mouthStyle.scale` — so
    /// `mouthBoxFraction` is 1.
    func mouthShape(vowel: Float) -> (w: CGFloat, h: CGFloat) {
        let p = ToonMouth.params(vowel: vowel)
        return (p.w * mouthStyle.scale / Toon.stageUnits, p.h * mouthStyle.scale / Toon.stageUnits)
    }

    var mouthCentre: (fx: CGFloat, fy: CGFloat) {
        (mouthStyle.x / Toon.stageUnits, mouthStyle.y / Toon.stageUnits)
    }

    var mouthBoxFraction: CGFloat { 1 }

    func drawMouth(in stage: CGRect, vowel: Float, amplitudeBoost: CGFloat) {
        Toon.inStage(stage) { _ in ToonMouth.draw(mouthStyle, vowel: vowel, boost: amplitudeBoost) }
    }
}
```

- [ ] **Step 6: `CharacterView.draw(_:)` uses the face and over-mouth layers**

Replace the body of `draw(_:)` after `character.drawBody(in: stage)` with:

```swift
        let pose = currentPose
        let vowel = Self.quantisedVowel(pose.vowel)
        character.drawFace(in: stage, expression: Expression(blinking: pose.blinking,
                                                             loudness: steppedLoudness,
                                                             vowel: vowel))
        drawMouth(in: stage, vowel: vowel)
        character.drawOverMouth(in: stage)
```

and factor the stepping out of `drawMouth(in:vowel:)` into a property both use:

```swift
    /// Loudness in four steps — the mouth swell and the brows move in
    /// frames, never glide (see `quantisedVowel`).
    private var steppedLoudness: CGFloat {
        let ampSteps: Float = 4
        return CGFloat((min(max(amplitude, 0), 1) * ampSteps).rounded() / ampSteps)
    }

    private func drawMouth(in stage: CGRect, vowel: Float) {
        character.drawMouth(in: stage, vowel: vowel, amplitudeBoost: 1 + steppedLoudness * 0.35)
    }
```

- [ ] **Step 7: `UserCharacter` forwards the new requirements**

Add beside the existing forwards in `AU/UI/UserCharacter.swift`:

```swift
    var palette: Palette { face.palette }
    func drawFace(in stage: CGRect, expression: Expression) { face.drawFace(in: stage, expression: expression) }
    func drawOverMouth(in stage: CGRect) { face.drawOverMouth(in: stage) }
    func drawBackdrop(in rect: CGRect, stage: CGRect) { face.drawBackdrop(in: rect, stage: stage) }
```

- [ ] **Step 8: Run the whole suite**

Run: `scripts/test.sh` → `** TEST SUCCEEDED **` (old characters still conform via defaults).

- [ ] **Step 9: Commit**

```bash
git add AU/UI/ToonMouth.swift AU/UI/ToonCharacter.swift AU/UI/Backdrop.swift AU/UI/Character.swift AU/UI/CharacterView.swift AU/UI/UserCharacter.swift Tests/MonkSynthTests/ToonMouthTests.swift
git commit -m "One mouth for everyone: ToonMouth, ToonCharacter, and faces that see loudness"
```

---

### Porting rules (used by Tasks 3 and 4)

Each character file is rewritten as a `struct <Name>Character: ToonCharacter` with the same `id` and `displayName` as today. Port `CH.<id>` from `docs/mockups/stage-redesign/gen.mjs` literally:

| gen.mjs | Swift |
|---|---|
| `toon(P('d'), '#rrggbb')` | `Toon.shape(Toon.path("d"), fill: UIColor(hex: 0xRRGGBB))` |
| `toon(C(x, y, r), …)` / `toon(E(x, y, rx, ry), …)` | `Toon.shape(Toon.circle(x, y, r), …)` / `Toon.shape(Toon.ellipse(x, y, rx, ry), …)` |
| `{ sw: W_MED }` / `W_FINE` / `3` | `lineWidth: Toon.medium` / `Toon.fine` / `3` |
| `{ noShadow: true }` | `shaded: false` |
| `{ shadow: '#…' }` | `shadow: UIColor(hex: 0x…)` |
| `` toon(`rect x=.. y=.. width=.. height=..`, …) `` | `Toon.shape(Toon.rect(x, y, w, h), …)` |
| `line('d', w, col)` | `Toon.stroke(Toon.path("d"), width: w, color: UIColor(hex: …))` (colour omitted → ink) |
| `eyeOpen(x, y, r, iris, [lx, ly])` | `Toon.eyeOpen(x, y, r, iris: …, look: CGPoint(x: lx, y: ly))` |
| `eyeClosed(x, y, w)` / `cheek(x, y, r, col)` / `hl(x, y, r)` | `Toon.eyeClosed` / `Toon.cheek` / `Toon.highlight` |
| raw `<ellipse … fill="#fff" opacity="0.45"/>` | `Toon.fill(Toon.ellipse(…), UIColor.white.withAlphaComponent(0.45))` |
| raw `<circle … fill=A stroke=INK stroke-width=w/>` | `Toon.shape(Toon.circle(…), fill: A, lineWidth: w, shaded: false)` |
| `transform="rotate(a cx cy)"` | `Toon.rotated(path, degrees: a, cx: cx, cy: cy)` |
| `<clipPath>` + `<g clip-path>` | `Toon.clipped(to: path) { … }` |
| `.map(...).join('')` loops | Swift `for` loops with the same arithmetic |
| `face: (blink) => blink ? A : B` | `if e.blinking { A } else { B }` inside `drawToonFace` |
| `over: () => …` | `drawToonOverMouth()` |
| `mouth: { x, y, scale, variant, lip }` | `let mouthStyle = ToonMouth.Style(x:, y:, scale:, variant: .lips/.muzzle/.bare, lip: UIColor(hex:))` |
| `palette: { accent, skyTop, skyBot, ground }` | `let palette = Palette(accent:, skyTop:, skyBottom:, ground:)` |

Additions beyond the mockup (the spec's "faces react"): in `drawToonFace`, raise each brow by `e.loudness * 6` stage units (translate the brow path's y by `-e.loudness * 6`); where a character has no brows, nothing changes. Do not otherwise change the art.

One fix beyond the mockup: **Punk's mohawk** tips move down 6 units (every `y` in that one path +6) so the outline does not clip at the stage top (the framing test enforces this).

Delete the old files' private helpers, derived-colour constants and doc comments that describe the old art; keep a short type doc comment naming the character and its scene.

Worked example — `AU/UI/MonkCharacter.swift` in full (the scene is added in Task 5):

```swift
import UIKit

/// The monk: shaved head, maroon robe with a saffron sash, prayer beads
/// draped on the robe below the neckline. Sings on a Himalayan terrace.
struct MonkCharacter: ToonCharacter {
    let id = "monk"
    let displayName = "Monk"
    let palette = Palette(accent: UIColor(hex: 0xF0A020), skyTop: UIColor(hex: 0xF7B57A),
                          skyBottom: UIColor(hex: 0xFBE6C4), ground: UIColor(hex: 0xB98A55))
    let mouthStyle = ToonMouth.Style(x: 150, y: 165, scale: 0.8, variant: .lips, lip: UIColor(hex: 0xC8735F))

    private static let skin = UIColor(hex: 0xE4B085)

    func drawToonBody() {
        Toon.shape(Toon.path("M126 168 L174 168 L176 234 L124 234 Z"), fill: Self.skin, lineWidth: Toon.medium)
        Toon.shape(Toon.path("M30 300 C40 246 78 214 116 209 C128 230 172 230 184 209 C222 214 260 246 270 300 Z"),
                   fill: UIColor(hex: 0xA8322A))
        Toon.shape(Toon.path("M98 216 C104 212 110 210 116 209 C150 238 204 266 232 300 L188 300 C166 272 134 248 98 216 Z"),
                   fill: UIColor(hex: 0xF2A51F), lineWidth: Toon.medium)
        for i in 0..<9 {
            let t = CGFloat(i) / 8
            let x = (1 - t) * (1 - t) * 104 + 2 * t * (1 - t) * 150 + t * t * 196
            let y = (1 - t) * (1 - t) * 214 + 2 * t * (1 - t) * 268 + t * t * 214
            Toon.shape(Toon.circle(x, y, 6), fill: UIColor(hex: 0x6E3F22), lineWidth: 3)
        }
        Toon.shape(Toon.circle(84, 128, 15), fill: Self.skin, lineWidth: Toon.medium)
        Toon.shape(Toon.circle(216, 128, 15), fill: Self.skin, lineWidth: Toon.medium)
        Toon.shape(Toon.ellipse(150, 118, 68, 72), fill: UIColor(hex: 0xE9BB8F))
        Toon.fill(Toon.ellipse(128, 70, 16, 9), UIColor.white.withAlphaComponent(0.45))
    }

    func drawToonFace(_ e: Expression) {
        let lift = -e.loudness * 6
        Toon.stroke(Toon.path("M112 \(102 + lift) Q124 \(96 + lift) 136 \(101 + lift)"), width: Toon.fine)
        Toon.stroke(Toon.path("M164 \(101 + lift) Q176 \(96 + lift) 188 \(102 + lift)"), width: Toon.fine)
        // The monk's eyes are closed in meditation, blink or not.
        Toon.eyeClosed(124, 120, 13)
        Toon.eyeClosed(176, 120, 13)
        Toon.stroke(Toon.path("M148 128 Q144 142 152 146"), width: Toon.fine)
        Toon.cheek(108, 146)
        Toon.cheek(192, 146)
    }
}
```

---

### Task 3: Characters A — Monk, Fish, Unicorn, Little Girl, Old Man, Cow

**Goal:** The first six characters ported to `ToonCharacter`, with art tests that enforce framing, attachment and mouth size.

**Files:**
- Modify (rewrite): `AU/UI/MonkCharacter.swift`, `AU/UI/FishCharacter.swift`, `AU/UI/UnicornCharacter.swift`, `AU/UI/GirlCharacter.swift`, `AU/UI/OldManCharacter.swift`, `AU/UI/CowCharacter.swift`
- Create: `Tests/MonkSynthTests/CharacterArtTests.swift`
- Modify: `Tests/MonkSynthTests/CharacterTests.swift` (remove `testEachCharacterProducesADifferentMouthShapeSweep`), `Tests/MonkSynthTests/IdleAnimatorTests.swift` (`testMouthShapeIsContinuousAcrossVowelRange` endpoints)

**Acceptance Criteria:**
- [ ] Each of the six renders (alone, transparent background, 300×300 at scale 1) with every opaque pixel (alpha > 0.5) in ONE 4-connected region — no floating parts.
- [ ] No opaque pixel in row 0, column 0 or column 299 (nothing clips at the stage edge).
- [ ] At AH the mouth height ≥ 0.11 of the stage; at EE width ≥ 0.14.
- [ ] `IdleAnimatorTests` endpoints updated to Monk's new values: `mouthShape(vowel: 0)` = (24·0.8/300, 26·0.8/300), `mouthShape(vowel: 1)` = (74·0.8/300, 18·0.8/300).
- [ ] A rendered sheet of the six (via `RenderMonkSnapshot.testWriteAllCharactersSweep`) visually matches `docs/mockups/stage-redesign/characters.png` for these six — checked by reading `/tmp/characters.png`.

**Verify:** `scripts/test.sh` → `** TEST SUCCEEDED **`, then `scripts/test.sh MonkSynthTests/RenderMonkSnapshot` and Read `/private/tmp/characters.png`.

**Steps:**

- [ ] **Step 1: Write `CharacterArtTests` (fails for unported characters by design — it iterates only `ToonCharacter`s, and also fails now because none are ported yet)**

```swift
// Tests/MonkSynthTests/CharacterArtTests.swift
import UIKit
import XCTest
@testable import MonkSynth

/// Art guarantees every drawn character must keep: one connected figure
/// (no floating heads, collars or beads), nothing clipped at the stage edge,
/// and a mouth big enough to read.
final class CharacterArtTests: XCTestCase {

    static var toons: [ToonCharacter] { CharacterRegistry.all.compactMap { $0 as? ToonCharacter } }

    /// Task 3 expects these six; Task 4 changes this to all twelve.
    static let expectedToonIDs: Set<String> = ["monk", "fish", "unicorn", "girl", "oldman", "cow"]

    func testExpectedCharactersAreToons() {
        XCTAssertTrue(Self.expectedToonIDs.isSubset(of: Set(Self.toons.map(\.id))))
    }

    /// Renders the figure alone and returns an alpha mask (true = opaque).
    static func mask(_ c: Character, vowel: Float = 0.5) -> (w: Int, h: Int, opaque: [Bool]) {
        let side = 300
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let img = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { _ in
            let stage = CGRect(x: 0, y: 0, width: side, height: side)
            c.drawBody(in: stage)
            c.drawFace(in: stage, expression: Expression(blinking: false, loudness: 0, vowel: vowel))
            c.drawMouth(in: stage, vowel: vowel, amplitudeBoost: 1)
            c.drawOverMouth(in: stage)
        }
        let cg = img.cgImage!
        var data = [UInt8](repeating: 0, count: side * side * 4)
        let ctx = CGContext(data: &data, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: side, height: side))
        // CGContext rows run bottom-up; flip so index 0 is the top row.
        var opaque = [Bool](repeating: false, count: side * side)
        for y in 0..<side { for x in 0..<side {
            opaque[(side - 1 - y) * side + x] = data[(y * side + x) * 4 + 3] > 127
        } }
        return (side, side, opaque)
    }

    func testEveryFigureIsOneConnectedPiece() {
        for c in Self.toons {
            let m = Self.mask(c)
            var seen = [Bool](repeating: false, count: m.opaque.count)
            var regions: [Int] = []
            for start in 0..<m.opaque.count where m.opaque[start] && !seen[start] {
                var stack = [start]; seen[start] = true; var size = 0
                while let i = stack.popLast() {
                    size += 1
                    let x = i % m.w, y = i / m.w
                    for (nx, ny) in [(x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)]
                    where nx >= 0 && ny >= 0 && nx < m.w && ny < m.h {
                        let j = ny * m.w + nx
                        if m.opaque[j] && !seen[j] { seen[j] = true; stack.append(j) }
                    }
                }
                regions.append(size)
            }
            regions.sort(by: >)
            let stray = regions.dropFirst().reduce(0, +)
            XCTAssertLessThanOrEqual(stray, 12,
                "\(c.id) has \(regions.count) separate pieces (largest \(regions.prefix(4))) — something is floating")
        }
    }

    func testNothingClipsAtTheTopOrSides() {
        for c in Self.toons {
            let m = Self.mask(c)
            for x in 0..<m.w { XCTAssertFalse(m.opaque[x], "\(c.id) touches the top edge at x=\(x)"); if m.opaque[x] { break } }
            for y in 0..<m.h {
                XCTAssertFalse(m.opaque[y * m.w], "\(c.id) touches the left edge at y=\(y)")
                XCTAssertFalse(m.opaque[y * m.w + m.w - 1], "\(c.id) touches the right edge at y=\(y)")
                if m.opaque[y * m.w] || m.opaque[y * m.w + m.w - 1] { break }
            }
        }
    }

    func testMouthsAreBigEnoughToRead() {
        for c in Self.toons {
            XCTAssertGreaterThanOrEqual(c.mouthShape(vowel: 0.5).h * c.mouthBoxFraction, 0.11, "\(c.id) AH too short")
            XCTAssertGreaterThanOrEqual(c.mouthShape(vowel: 1).w * c.mouthBoxFraction, 0.14, "\(c.id) EE too narrow")
        }
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `scripts/test.sh MonkSynthTests/CharacterArtTests`
Expected: `testExpectedCharactersAreToons` fails (no character conforms yet).

- [ ] **Step 3: Port the six characters**

Rewrite each file per the Porting rules. `MonkCharacter.swift` is the worked example above, verbatim. For the other five, port `CH.fish`, `CH.unicorn`, `CH.girl`, `CH.oldman`, `CH.cow` from gen.mjs. Struct names stay `FishCharacter`, `UnicornCharacter`, `GirlCharacter`, `OldManCharacter`, `CowCharacter`; ids stay `fish`, `unicorn`, `girl`, `oldman`, `cow`; display names stay as today.

- [ ] **Step 4: Update the tests that encoded the old rigs**

In `Tests/MonkSynthTests/CharacterTests.swift` delete `testEachCharacterProducesADifferentMouthShapeSweep` (the spec replaces per-character mouth sweeps with one shared mouth; `CharacterArtTests.testMouthsAreBigEnoughToRead` and `ToonMouthTests` cover the mouth now). Keep `testNotEveryCharacterSharesTheSameMouthPlacement`.

In `Tests/MonkSynthTests/IdleAnimatorTests.swift`, `testMouthShapeIsContinuousAcrossVowelRange`, change the endpoint assertions to:

```swift
        XCTAssertEqual(first.w, 24 * 0.8 / 300, accuracy: 1e-9)
        XCTAssertEqual(first.h, 26 * 0.8 / 300, accuracy: 1e-9)
        XCTAssertEqual(last.w, 74 * 0.8 / 300, accuracy: 1e-9)
        XCTAssertEqual(last.h, 18 * 0.8 / 300, accuracy: 1e-9)
```

and update the doc comment above it to say the anchors come from `ToonMouth.anchors` scaled by the monk's `mouthStyle.scale`.

- [ ] **Step 5: Run the suite**

Run: `scripts/test.sh` → `** TEST SUCCEEDED **`. If `testEveryFigureIsOneConnectedPiece` fails for a character, the message names it: compare its render to the mockup — a mistyped coordinate is the usual cause. Do not loosen the test.

- [ ] **Step 6: Look at the render**

Run: `scripts/test.sh MonkSynthTests/RenderMonkSnapshot`, then Read `/private/tmp/characters.png`. The six rows must match the mockup figures in `docs/mockups/stage-redesign/characters.png` (no backdrop yet — that's Task 5). Mouths must step OO→EE across the five columns.

- [ ] **Step 7: Commit**

```bash
git add AU/UI/MonkCharacter.swift AU/UI/FishCharacter.swift AU/UI/UnicornCharacter.swift AU/UI/GirlCharacter.swift AU/UI/OldManCharacter.swift AU/UI/CowCharacter.swift Tests/MonkSynthTests/CharacterArtTests.swift Tests/MonkSynthTests/CharacterTests.swift Tests/MonkSynthTests/IdleAnimatorTests.swift
git commit -m "Redraw Monk, Fish, Unicorn, Little Girl, Old Man and Cow as sticker characters"
```

---

### Task 4: Characters B — Fire Fighter, Punk, Dog, Pizza, Ghost, Cat

**Goal:** The remaining six ported; all twelve pass the art tests.

**Files:**
- Modify (rewrite): `AU/UI/FireFighterCharacter.swift`, `AU/UI/PunkCharacter.swift`, `AU/UI/DogCharacter.swift`, `AU/UI/PizzaCharacter.swift`, `AU/UI/GhostCharacter.swift`, `AU/UI/CatCharacter.swift`
- Modify: `Tests/MonkSynthTests/CharacterArtTests.swift` (`expectedToonIDs`)

**Acceptance Criteria:**
- [ ] `CharacterArtTests.expectedToonIDs` is all twelve ids and every test in the class passes.
- [ ] Punk's mohawk tips are 6 units lower than in gen.mjs and nothing touches the top edge.
- [ ] Fire Fighter's reflective band is clipped to the coat (uses `Toon.clipped`); the coat outline is stroked after the band.
- [ ] `/private/tmp/characters.png` shows all twelve matching the mockup.

**Verify:** `scripts/test.sh` → `** TEST SUCCEEDED **`; Read `/private/tmp/characters.png` after `scripts/test.sh MonkSynthTests/RenderMonkSnapshot`.

**Steps:**

- [ ] **Step 1: Widen the test's expectations (red)**

```swift
    static let expectedToonIDs: Set<String> = ["monk", "fish", "unicorn", "girl", "oldman", "cow",
                                               "firefighter", "punk", "dog", "pizza", "ghost", "cat"]
```

Also add, in `CharacterArtTests`:

```swift
    func testEveryRegisteredCharacterIsAToon() {
        XCTAssertEqual(Self.toons.count, CharacterRegistry.all.count)
    }
```

Run `scripts/test.sh MonkSynthTests/CharacterArtTests` → fails.

- [ ] **Step 2: Port `CH.firefighter`, `CH.punk`, `CH.dog`, `CH.pizza`, `CH.ghost`, `CH.cat`** per the Porting rules. Struct names and ids unchanged. Fire Fighter's band in Swift:

```swift
        let coat = Toon.path("M30 300 C38 246 80 218 150 216 C220 218 262 246 270 300 Z")
        Toon.shape(coat, fill: UIColor(hex: 0xF2B33A))
        Toon.clipped(to: coat) {
            let band = Toon.rect(0, 258, 300, 18)
            Toon.fill(band, UIColor(hex: 0xE9EEF2))
            Toon.stroke(band, width: 3.5)
            Toon.fill(Toon.rect(0, 265, 300, 4), UIColor(hex: 0xC9D1D8))
        }
        Toon.stroke(coat, width: Toon.bold)
```

The pizza's cheese and crust use the `A` arc command — `Toon.path` handles it; draw the crust as two strokes of the arc path (`width: 34` ink, then `width: 25` crust colour) plus the highlight arc, as gen.mjs does.

- [ ] **Step 3: Run the suite** → `** TEST SUCCEEDED **`.

- [ ] **Step 4: Look at the render** — `scripts/test.sh MonkSynthTests/RenderMonkSnapshot`, Read `/private/tmp/characters.png`, compare all twelve to the mockup.

- [ ] **Step 5: Commit**

```bash
git add AU/UI/FireFighterCharacter.swift AU/UI/PunkCharacter.swift AU/UI/DogCharacter.swift AU/UI/PizzaCharacter.swift AU/UI/GhostCharacter.swift AU/UI/CatCharacter.swift Tests/MonkSynthTests/CharacterArtTests.swift
git commit -m "Redraw Fire Fighter, Punk, Dog, Pizza, Ghost and Cat; all twelve are sticker characters"
```

---

### Task 5: Scenes

**Goal:** Every character draws its own scene (sky, ground, props) in any rect, ported from gen.mjs `scene()` and `prop`.

**Files:**
- Modify: `AU/UI/Backdrop.swift` (add every prop)
- Modify: all twelve `AU/UI/*Character.swift` (add `drawBackdrop(in:stage:)`)
- Create: `Tests/MonkSynthTests/BackdropTests.swift`

**Acceptance Criteria:**
- [ ] Each character's backdrop renders at 300×300, 812×226 and 359×104 without leaving any fully transparent pixel inside `rect`.
- [ ] The twelve backdrops' top-centre pixels are not all the same colour (each scene is its own).
- [ ] Props scale with the scene: a backdrop drawn at 812×226 has no prop wider than the rect (spot-checked by rendering and asserting no crash and full coverage).

**Verify:** `scripts/test.sh MonkSynthTests/BackdropTests` → `** TEST SUCCEEDED **`

**Steps:**

- [ ] **Step 1: Failing tests**

```swift
// Tests/MonkSynthTests/BackdropTests.swift
import UIKit
import XCTest
@testable import MonkSynth

final class BackdropTests: XCTestCase {
    private func render(_ c: Character, _ size: CGSize) -> UIImage {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = false
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            let rect = CGRect(origin: .zero, size: size)
            let side = min(size.height * 0.94, size.width * 0.8)
            let stage = CGRect(x: rect.midX - side / 2, y: rect.maxY - side, width: side, height: side)
            c.drawBackdrop(in: rect, stage: stage)
        }
    }

    private func alpha(_ img: UIImage, _ x: Int, _ y: Int) -> UInt8 {
        let cg = img.cgImage!
        var px = [UInt8](repeating: 0, count: 4)
        let ctx = CGContext(data: &px, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(cg, in: CGRect(x: -x, y: -(cg.height - 1 - y), width: cg.width, height: cg.height))
        return px[3]
    }

    func testEveryBackdropCoversItsRectAtEverySize() {
        for c in CharacterRegistry.all {
            for size in [CGSize(width: 300, height: 300), CGSize(width: 812, height: 226), CGSize(width: 359, height: 104)] {
                let img = render(c, size)
                for (x, y) in [(1, 1), (Int(size.width) - 2, 1), (1, Int(size.height) - 2),
                               (Int(size.width) - 2, Int(size.height) - 2), (Int(size.width) / 2, Int(size.height) / 2)] {
                    XCTAssertEqual(alpha(img, x, y), 255, "\(c.id) leaves a hole at \(x),\(y) in \(size)")
                }
            }
        }
    }

    func testScenesDiffer() {
        let tops = CharacterRegistry.all.map { c -> UIColor in c.palette.skyTop }
        XCTAssertGreaterThan(Set(tops.map { $0.description }).count, 6)
    }
}
```

Run → `testScenesDiffer` passes already (palettes exist); `testEveryBackdropCoversItsRectAtEverySize` passes with the plain fallback. Both are guards; the real check of this task is the render review in Step 4. Proceed.

- [ ] **Step 2: Port the props into `AU/UI/Backdrop.swift`**

Port each entry of gen.mjs `prop` as a `static func` on `Backdrop` with the same name and parameters plus a trailing `u: CGFloat` (outline scale): `mountain`, `sun`, `moon`, `cloud`, `flags`, `bubble`, `kelp`, `tree`, `kite`, `rainbow`, `fence`, `barn`, `bricks`, `hydrant`, `amp`, `spot`, `doghouse`, `bone`, `checker`, `candle`, `tomb` (no cross — the mockup's final `tomb` draws only the stone), `star`, `window`, `lamp`, `stripes`. Inside them, `toon(...)` becomes `Toon.shape(..., lineWidth: <w> , unit: u)` and `line(..., w)` becomes `Toon.stroke(..., width: w * u)`. Coordinates stay as gen.mjs computes them from `x, y, k` (point space). Example:

```swift
    static func sun(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat, u: CGFloat) {
        for i in 0..<12 {
            let a = CGFloat(i) * .pi / 6
            let p = UIBezierPath()
            p.move(to: CGPoint(x: x + cos(a) * r * 1.3, y: y + sin(a) * r * 1.3))
            p.addLine(to: CGPoint(x: x + cos(a) * r * 1.7, y: y + sin(a) * r * 1.7))
            Toon.stroke(p, width: 9 * u)
            Toon.stroke(p, width: 4.5 * u, color: UIColor(hex: 0xFFD35A))
        }
        Toon.shape(Toon.circle(x, y, r), fill: UIColor(hex: 0xFFD35A), lineWidth: Toon.medium, shaded: false, unit: u)
    }

    static func mountain(_ x: CGFloat, _ y: CGFloat, _ k: CGFloat, u: CGFloat) {
        Toon.shape(Toon.path("M\(x - 90 * k) \(y) L\(x) \(y - 110 * k) L\(x + 90 * k) \(y) Z"),
                   fill: UIColor(hex: 0x8C8FB8), lineWidth: Toon.medium, unit: u)
        Toon.shape(Toon.path("M\(x - 30 * k) \(y - 73 * k) L\(x) \(y - 110 * k) L\(x + 30 * k) \(y - 73 * k) L\(x + 14 * k) \(y - 80 * k) L\(x) \(y - 70 * k) L\(x - 14 * k) \(y - 80 * k) Z"),
                   fill: .white, lineWidth: Toon.fine, shaded: false, unit: u)
    }
```

All prop coordinates are relative to `rect.origin` = (0,0) in gen.mjs; in Swift translate by `rect.minX/minY` once at the start of each character's `drawBackdrop` (`ctx.translateBy`) so the ported arithmetic stays identical.

- [ ] **Step 3: Add `drawBackdrop` to each character**

Port the matching `case` of gen.mjs `scene(id, W, H)`:

```swift
    // MonkCharacter
    func drawBackdrop(in rect: CGRect, stage: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        ctx.saveGState(); ctx.clip(to: rect); ctx.translateBy(x: rect.minX, y: rect.minY)
        let W = rect.width, H = rect.height, u = stage.width / Toon.stageUnits
        let gy = (H * 0.72).rounded(), R = W * 0.88, L = W * 0.12, cx = W / 2
        Backdrop.sky(CGRect(x: 0, y: 0, width: W, height: H), top: palette.skyTop, bottom: palette.skyBottom)
        Backdrop.sun(R - W * 0.06, gy - H * 0.3, min(30, H * 0.08), u: u)
        Backdrop.mountain(L + 20, gy, H / 300, u: u)
        Backdrop.mountain(R, gy, H / 380, u: u)
        Backdrop.mountain(cx + W * 0.3, gy, H / 460, u: u)
        Backdrop.ground(CGRect(x: 0, y: 0, width: W, height: H), y: gy, color: palette.ground, u: u)
        Backdrop.flags(-10, W + 10, H * 0.08, u: u)
        ctx.restoreGState()
    }
```

Do the same for the other eleven from their `case`. The Fish's ground uses `H * 0.86`; Pizza has no `ground` call (the checker cloth is its ground); Old Man and Fire Fighter draw wallpaper/bricks before the ground.

- [ ] **Step 4: Render and look**

Temporarily point `RenderMonkSnapshot.testWriteAllCharactersSweep` at backdrops by drawing `character.drawBackdrop(in: cellRect, stage: stageRect)` before rendering each `CharacterView` (this change is kept — Task 9 relies on it). Run it, Read `/private/tmp/characters.png`, and compare each cell to `docs/mockups/stage-redesign/characters.png`.

- [ ] **Step 5: Run suite** → `** TEST SUCCEEDED **`

- [ ] **Step 6: Commit**

```bash
git add AU/UI/Backdrop.swift AU/UI/*Character.swift Tests/MonkSynthTests/BackdropTests.swift Tests/MonkSynthTests/RenderMonkSnapshot.swift
git commit -m "Every character gets its own scene"
```

---

### Task 6: The scene is the pad — `SceneView`, layout, `XYPadView` restyle

**Goal:** Replace the separate stage and pad zones with one scene: backdrop + character + full-size transparent pad, with ticks, vowel scale, ripple touch marker and a first-touch hint.

**Files:**
- Create: `AU/UI/SceneView.swift`, `Tests/MonkSynthTests/SceneViewTests.swift`
- Modify: `AU/UI/PluginView.swift` (`ZoneLayout`, `layout(...)`, `landscapeLayout`/`portraitLayout` → one `sceneLayout`, `layoutSubviews`, init wiring), `AU/UI/XYPadView.swift` (`draw(_:)`, `accent`, hint), `AU/UI/Theme.swift` (strip heights)
- Modify tests: `Tests/MonkSynthTests/LayoutTests.swift`, `Tests/MonkSynthTests/CharacterTests.swift` (the two stage/pad overlap tests), `Tests/MonkSynthTests/ControlPagesTests.swift` (strip-height references), `Tests/MonkSynthTests/RenderUISnapshot.swift` (compiles against new names)

**Acceptance Criteria:**
- [ ] `ZoneLayout` has `scene`, `controls`, `handle`, `infoButton`, `characterSelector` (no `stage`/`pad`).
- [ ] `scene` spans the full inner width from below the header to above the strip in both orientations.
- [ ] `SceneView.characterRect(in:)` is bottom-centred, square, side = `min(h·0.94, w·0.8)` floored, and `.zero` below 72pt.
- [ ] `pluginView.pad.frame == sceneView.bounds`; `pluginView.stage` is detached from the hierarchy when `characterRect` is `.zero`.
- [ ] Strip preferred height: `Theme.stripHeight` (132) when `inner.height > inner.width`, `Theme.stripHeightWide` (96) otherwise; floor `Theme.minUsableStripHeight` unchanged.
- [ ] Every existing `LayoutTests` invariant (no NaN/negative, inside safe area, handle travels, selector never hits info/handle, strip floor) still holds against `scene` in place of `pad`.
- [ ] `XYPadView` touch/parameter behaviour unchanged (`XYPadTests` pass untouched).

**Verify:** `scripts/test.sh` → `** TEST SUCCEEDED **`; `scripts/test.sh MonkSynthTests/RenderUISnapshot` then Read `/private/tmp/ui_sizes.png`.

**Steps:**

- [ ] **Step 1: Failing `SceneViewTests`**

```swift
// Tests/MonkSynthTests/SceneViewTests.swift
import UIKit
import XCTest
@testable import MonkSynth

final class SceneViewTests: XCTestCase {
    func testCharacterRectIsBottomCentredSquare() {
        let r = SceneView.characterRect(in: CGRect(x: 0, y: 0, width: 812, height: 226))
        XCTAssertEqual(r.width, r.height)
        XCTAssertEqual(r.width, floor(226 * 0.94))
        XCTAssertEqual(r.maxY, 226)
        XCTAssertEqual(r.midX, 406, accuracy: 0.5)
    }

    func testNarrowSceneIsLimitedByWidth() {
        let r = SceneView.characterRect(in: CGRect(x: 0, y: 0, width: 374, height: 600))
        XCTAssertEqual(r.width, floor(374 * 0.8))
    }

    func testTinySceneHidesTheCharacter() {
        XCTAssertEqual(SceneView.characterRect(in: CGRect(x: 0, y: 0, width: 359, height: 60)), .zero)
    }

    func testPadCoversTheWholeSceneAndStageDetachesWhenHidden() {
        let stage = CharacterView(), pad = XYPadView()
        let scene = SceneView(stage: stage, pad: pad)
        scene.frame = CGRect(x: 0, y: 0, width: 374, height: 400)
        scene.layoutIfNeeded()
        XCTAssertEqual(pad.frame, scene.bounds)
        XCTAssertNotNil(stage.superview)
        scene.frame = CGRect(x: 0, y: 0, width: 359, height: 40)
        scene.layoutIfNeeded()
        XCTAssertNil(stage.superview)
    }
}
```

Run → build fails (`SceneView` unknown).

- [ ] **Step 2: `AU/UI/SceneView.swift`**

```swift
import UIKit

/// The playable stage: the character's scene, the character standing in it,
/// and the XY pad stretched transparently over all of it — touch anywhere
/// in the scene and it sings (X pitch, Y vowel, exactly as the pad always
/// has). The character itself never takes touches.
final class SceneView: UIView {
    let backdrop = BackdropView()
    let stage: CharacterView
    let pad: XYPadView

    /// Below this the figure is too small to read; the scene stays playable.
    static let minCharacterSide: CGFloat = 72

    init(stage: CharacterView, pad: XYPadView) {
        self.stage = stage
        self.pad = pad
        super.init(frame: .zero)
        clipsToBounds = true
        layer.borderColor = Toon.ink.cgColor
        layer.borderWidth = 3
        addSubview(backdrop)
        addSubview(stage)
        addSubview(pad)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    /// Bottom-centred square; the figure stands on the scene's bottom edge.
    static func characterRect(in bounds: CGRect) -> CGRect {
        let side = floor(min(bounds.height * 0.94, bounds.width * 0.8))
        guard side >= minCharacterSide else { return .zero }
        return CGRect(x: bounds.midX - side / 2, y: bounds.maxY - side, width: side, height: side)
    }

    var character: Character = MonkCharacter() {
        didSet { backdrop.character = character; pad.accent = character.palette.accent }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = min(18, bounds.height * 0.14)
        backdrop.frame = bounds
        pad.frame = bounds
        let r = Self.characterRect(in: bounds)
        backdrop.characterRect = r
        // Detach, don't hide: CharacterView's display link only stops once
        // its window goes nil (see CharacterView.updateDisplayLink).
        if r == .zero {
            if stage.superview != nil { stage.removeFromSuperview() }
        } else {
            if stage.superview == nil { insertSubview(stage, aboveSubview: backdrop) }
            stage.frame = r
        }
    }
}

/// Draws `character.drawBackdrop`. Redraws only when the character or the
/// size changes — never per animation frame.
final class BackdropView: UIView {
    var character: Character = MonkCharacter() { didSet { setNeedsDisplay() } }
    var characterRect: CGRect = .zero { didSet { if characterRect != oldValue { setNeedsDisplay() } } }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        contentMode = .redraw
        isOpaque = true
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func draw(_ rect: CGRect) {
        // A hidden figure still sets the scene's scale: use the square it would have had.
        let side = min(bounds.height * 0.94, bounds.width * 0.8)
        let stage = characterRect == .zero
            ? CGRect(x: bounds.midX - side / 2, y: bounds.maxY - side, width: side, height: side)
            : characterRect
        character.drawBackdrop(in: bounds, stage: stage)
    }
}
```

- [ ] **Step 3: Strip heights in `AU/UI/Theme.swift`**

Replace `static let stripHeight: CGFloat = 92` with:

```swift
    /// Preferred control-strip heights: taller in portrait (two rows: tabs
    /// over full-size knobs), shorter when wide (tabs become a side column).
    static let stripHeight: CGFloat = 132
    static let stripHeightWide: CGFloat = 96
```

Delete `minPadHeight` and `stageCollapseBelowHeight` once nothing references them (Step 4 removes the uses).

- [ ] **Step 4: `PluginView` — one scene zone**

`ZoneLayout` becomes:

```swift
struct ZoneLayout: Equatable {
    /// The playable scene: everything between the header row and the strip.
    var scene: CGRect
    var controls: CGRect
    var handle: CGRect
    var infoButton: CGRect = .zero
    var characterSelector: CGRect = .zero
}
```

Replace `landscapeLayout` and `portraitLayout` with:

```swift
    /// The scene takes the full inner width from below the header row to
    /// the strip's top gutter, in both orientations; only the strip's
    /// preferred height differs (see `Theme.stripHeight`/`stripHeightWide`).
    private static func sceneLayout(inner: CGRect, gutter g: CGFloat, drawerOpen: Bool) -> ZoneLayout {
        let isWide = inner.width >= inner.height
        let stripH = drawerOpen
            ? controlStripHeight(available: inner.height, gutter: g,
                                 preferred: isWide ? Theme.stripHeightWide : Theme.stripHeight)
            : 0
        let headerReserve = headerHeight + g
        let sceneH = max(0, inner.height - stripH - (stripH > 0 ? g : 0) - headerReserve)
        let controls = CGRect(x: inner.minX, y: inner.maxY - stripH, width: inner.width, height: stripH)
        return ZoneLayout(scene: CGRect(x: inner.minX, y: inner.minY + headerReserve, width: inner.width, height: sceneH),
                          controls: controls, handle: handleFrame(for: controls))
    }
```

`controlStripHeight(available:gutter:)` gains a `preferred:` parameter used in place of `Theme.stripHeight`; `stripHeight(available:gutter:drawerOpen:)` is deleted (folded in above). In `layout(...)`, call `sceneLayout` for every size and return `ZoneLayout(scene: .zero, controls: .zero, handle: .zero, ...)` in the degenerate guard.

In `init`, replace adding `stage` and `pad` as direct subviews (and the `pad.layer`/`pad.backgroundColor` styling) with:

```swift
    lazy var sceneView = SceneView(stage: stage, pad: pad)
    // in init:
        addSubview(sceneView)
```

In the existing `stage.onCharacterChanged` closure (around `PluginView.swift:287`), add `self.sceneView.character = character`; also set `sceneView.character = stage.character` once at the end of `init`.

In `layoutSubviews`, replace `pad.frame = l.pad` and the whole stage collapse/insert block with `sceneView.frame = l.scene`. Update every doc comment in `PluginView.swift` that describes stage/pad/landscape split/portrait stack to describe the single scene. Keep `stage`/`pad` as `let` properties (controllers use them).

- [ ] **Step 5: `XYPadView` drawing**

Add `var accent: UIColor = Theme.accent { didSet { setNeedsDisplay() } }` and replace `draw(_:)`:

```swift
    /// UserDefaults key: set once the scene has been touched; until then a
    /// small "touch to sing" hint shows (the scene no longer looks like a pad).
    static let hintDismissedKey = "scene.hintDismissed"
    private var showsHint = !UserDefaults.standard.bool(forKey: XYPadView.hintDismissedKey)

    override func draw(_ rect: CGRect) {
        guard rect.width > 0, rect.height > 0 else { return }
        let ink = Toon.ink
        // Pitch ticks along the bottom: 25 marks, octaves tallest.
        for i in 0...24 {
            let x = 12 + (rect.width - 24) * CGFloat(i) / 24
            let h: CGFloat = i % 12 == 0 ? 16 : (i % 2 == 1 ? 7 : 11)
            let p = UIBezierPath()
            p.move(to: CGPoint(x: x, y: rect.maxY - 4)); p.addLine(to: CGPoint(x: x, y: rect.maxY - h))
            Toon.stroke(p, width: 2, color: UIColor.white.withAlphaComponent(0.75))
        }
        // Vowel scale up the right edge, OO at the bottom.
        if rect.height >= 90 {
            let font = Theme.display(11)
            for (i, v) in ["OO", "OH", "AH", "EH", "EE"].enumerated() {
                let y = 14 + (rect.height - 50) * (1 - CGFloat(i) / 4)
                let s = NSAttributedString(string: v, attributes: [
                    .font: font, .foregroundColor: UIColor.white.withAlphaComponent(0.85),
                    .strokeColor: ink, .strokeWidth: -3])
                let size = s.size()
                s.draw(at: CGPoint(x: rect.maxX - 8 - size.width, y: y))
            }
        }
        if showsHint && !isPlaying && rect.height >= 90 {
            let s = NSAttributedString(string: NSLocalizedString("pad.hint", comment: "first-touch hint"),
                                       attributes: [.font: Theme.display(15), .foregroundColor: UIColor.white,
                                                    .strokeColor: ink, .strokeWidth: -4])
            let size = s.size()
            s.draw(at: CGPoint(x: rect.midX - size.width / 2, y: rect.minY + 12))
        }
        guard isPlaying else { return }
        let c = CGPoint(x: rect.minX + CGFloat(pitch) * rect.width, y: rect.minY + CGFloat(1 - vowel) * rect.height)
        Toon.stroke(Toon.circle(c.x, c.y, 30), width: 3, color: UIColor.white.withAlphaComponent(0.45))
        Toon.stroke(Toon.circle(c.x, c.y, 20), width: 3, color: UIColor.white.withAlphaComponent(0.8))
        Toon.shape(Toon.circle(c.x, c.y, 10), fill: accent, lineWidth: 4, shaded: false)
    }
```

In `beginTouch`, after setting `isPlaying = true`, add:

```swift
            if showsHint {
                showsHint = false
                UserDefaults.standard.set(true, forKey: Self.hintDismissedKey)
            }
```

Set `isOpaque = false` and `backgroundColor = .clear` in `init`. Add `"pad.hint" = "touch to sing";` to `AU/Resources/en.lproj/Localizable.strings`, `"pad.hint" = "触れて歌おう";` to `ja.lproj`, `"pad.hint" = "터치해서 노래하기";` to `ko.lproj` (`LocalizationTests` checks keys match across languages).

`Theme.display(_:)` is added in Task 7; add it now in `Theme.swift` so this compiles:

```swift
    /// SF Rounded heavy — names, tabs, scene labels.
    static func display(_ size: CGFloat) -> UIFont {
        let base = UIFont.systemFont(ofSize: size, weight: .heavy)
        guard let d = base.fontDescriptor.withDesign(.rounded) else { return base }
        return UIFont(descriptor: d, size: size)
    }
```

- [ ] **Step 6: Update the layout tests**

In `LayoutTests.swift`:
- Replace `testPortraitStacksVerticallyBelowUnityAspectRatio` and `testLandscapeSplitsHorizontallyAtOrAboveUnityAspectRatio` with:

```swift
    func testSceneSpansTheFullWidthBetweenHeaderAndStripInBothOrientations() {
        for size in [CGSize(width: 390, height: 844), CGSize(width: 844, height: 390), CGSize(width: 1024, height: 768)] {
            let l = PluginView.layout(in: CGRect(origin: .zero, size: size))
            XCTAssertEqual(l.scene.width, size.width - 2 * Theme.gutter, accuracy: 0.5, "\(size)")
            XCTAssertGreaterThanOrEqual(l.scene.minY, l.infoButton.maxY, "\(size)")
            XCTAssertLessThanOrEqual(l.scene.maxY, l.controls.minY - Theme.gutter + 0.5, "\(size)")
        }
    }
```

- `testAUMStripKeepsControlsAtFullHeightAndCollapsesTheStage` → rename `testAUMStripKeepsControlsAtFullHeight`; assert `l.controls.height == Theme.stripHeightWide` (accuracy 0.5) and `l.scene.height >= 0`; drop the stage assertions (whether the figure shows is `SceneView`'s call, tested there).
- `testAmpleRoomGivesTheStripItsFullPreferredHeight`: expect `Theme.stripHeight` for a portrait size and `Theme.stripHeightWide` for a landscape size (assert both).
- In every loop over `[("stage", l.stage), ("pad", l.pad), ("controls", l.controls)]`, use `[("scene", l.scene), ("controls", l.controls)]`.
- `testPadStaysNonNegativeEvenWhenShorterThanMinPadHeight` → `testSceneStaysNonNegativeAtTinySizes` asserting `l.scene.height` finite and ≥ 0.
- `testCharacterSelectorDoesNotIntersectPadControlsHandleOrInfoButton`: `l.pad` → `l.scene`.
- `testCharacterSelectorIsPresentEvenWhenStageCollapses`: drop the `l.stage == .zero` precondition; keep the selector assertions at 375×180.
- Update the file's header doc comment to describe scene + strip.

In `CharacterTests.swift` delete `testStageAndPadNeverOverlapAcrossLayoutSizes` and `testHitTestInsidePadFrameNeverResolvesToStage` (stage and pad are now intentionally layered; `SceneViewTests` covers the new arrangement and `CharacterView` remains non-interactive, still asserted by `testCharacterViewIsNotAnAccessibilityElement`), and replace them with:

```swift
    func testTouchesInTheSceneReachThePadNotTheCharacter() {
        let view = PluginView(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        view.layoutIfNeeded()
        let p = view.sceneView.convert(CGPoint(x: view.sceneView.bounds.midX, y: view.sceneView.bounds.maxY - 20), to: view)
        XCTAssertTrue(view.hitTest(p, with: nil) === view.pad)
    }
```

In `ControlPagesTests.swift`, the two `Theme.stripHeight` references stay valid (portrait value); re-run and adjust only if an assertion's arithmetic assumed 92.

Fix any remaining compile errors in `RenderUISnapshot.swift` (it only builds `PluginView`s; no zone names expected).

- [ ] **Step 7: Run suite and look**

`scripts/test.sh` → `** TEST SUCCEEDED **`. Then `scripts/test.sh MonkSynthTests/RenderUISnapshot`, Read `/private/tmp/ui_sizes.png`: every size shows the scene filling the band between header and strip, the monk standing on its bottom edge, no empty pad box.

- [ ] **Step 8: Commit**

```bash
git add AU/UI/SceneView.swift AU/UI/PluginView.swift AU/UI/XYPadView.swift AU/UI/Theme.swift AU/Resources Tests/MonkSynthTests
git commit -m "The scene is the pad: one playable stage instead of a character beside an empty box"
```

---

### Task 7: Chrome — tokens, knobs, segmented tabs, header, handle, live accent

**Goal:** The control strip, header and drawer handle drawn in the sticker style, recoloured from the current character's accent.

**Files:**
- Modify: `AU/UI/Theme.swift`, `AU/UI/KnobView.swift` (`draw(_:)` only), `AU/UI/ControlPages.swift`, `AU/UI/CharacterSelector.swift`, `AU/UI/PluginView.swift` (handle, info button, `applyPalette`)
- Test: `Tests/MonkSynthTests/ControlPagesTests.swift` (add), `Tests/MonkSynthTests/ThemeTests.swift` (new)

**Acceptance Criteria:**
- [ ] `Theme` tokens: `background` 0x1D1719, `panel` 0x2A2225, `panelDeep` 0x1B1416, `cream` 0xFFF1D6, `textPrimary` 0xFFF4E6, `textDim` 0xC2B1A8, `track` 0x4A3D41, `ink` = `Toon.ink`; `accent` is a `static var` defaulting to the monk accent.
- [ ] `Theme.label(_:weight:)` and `Theme.display(_:)` return rounded-design fonts (`fontDescriptor.symbolicTraits`/`design` check: descriptor's `.design` attribute is `.rounded` where available).
- [ ] Selecting a character sets `Theme.accent` to its palette accent and redraws knobs, tabs, selector chevron and pad marker (test: after `pluginView.stage.select(PunkCharacter())`, `Theme.accent == PunkCharacter().palette.accent` and the selected tab button's background equals it).
- [ ] `ControlPages` uses a side tab column when `bounds.width >= bounds.height * 5`, otherwise a top row (test both via `tabBarFrame`).
- [ ] Knob interaction and accessibility unchanged (existing `ControlPagesTests` and knob tests pass).

**Verify:** `scripts/test.sh` → `** TEST SUCCEEDED **`; `scripts/test.sh MonkSynthTests/RenderUISnapshot`, Read `/private/tmp/ui_knobs.png`, `/private/tmp/ui_sizes.png`, `/private/tmp/ui_characterselector.png`.

**Steps:**

- [ ] **Step 1: Failing tests**

```swift
// Tests/MonkSynthTests/ThemeTests.swift
import UIKit
import XCTest
@testable import MonkSynth

final class ThemeTests: XCTestCase {
    override func tearDown() { Theme.accent = MonkCharacter().palette.accent }

    func testFontsAreRounded() {
        XCTAssertTrue(Theme.display(14).fontName.lowercased().contains("rounded"))
        XCTAssertTrue(Theme.label(10).fontName.lowercased().contains("rounded"))
    }

    func testSelectingACharacterRecoloursTheChrome() {
        let view = PluginView(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        view.layoutIfNeeded()
        view.stage.select(PunkCharacter())
        XCTAssertEqual(Theme.accent, PunkCharacter().palette.accent)
        XCTAssertEqual(view.controls.selectedTabButton?.backgroundColor, PunkCharacter().palette.accent)
        XCTAssertEqual(view.pad.accent, PunkCharacter().palette.accent)
    }
}
```

Add to `ControlPagesTests`:

```swift
    func testTabsSitInAColumnWhenTheStripIsWideAndShort() {
        let pages = ControlPages(frame: CGRect(x: 0, y: 0, width: 812, height: 96))
        pages.layoutIfNeeded()
        XCTAssertGreaterThan(pages.tabBarFrame.height, pages.tabBarFrame.width)
        let tall = ControlPages(frame: CGRect(x: 0, y: 0, width: 374, height: 132))
        tall.layoutIfNeeded()
        XCTAssertGreaterThan(tall.tabBarFrame.width, tall.tabBarFrame.height)
    }
```

(`PluginView.controls` is the existing `ControlPages` property; check its name in `PluginView.swift` and use it.)

Run → fails.

- [ ] **Step 2: `Theme.swift` tokens and fonts**

```swift
enum Theme {
    static let background  = UIColor(hex: 0x1D1719)
    static let panel       = UIColor(hex: 0x2A2225)
    static let panelDeep   = UIColor(hex: 0x1B1416)
    static let panelBorder = Toon.ink
    static let cream       = UIColor(hex: 0xFFF1D6)
    static let track       = UIColor(hex: 0x4A3D41)
    static let ink         = Toon.ink
    static let textPrimary = UIColor(hex: 0xFFF4E6)
    static let textDim     = UIColor(hex: 0xC2B1A8)
    /// The loaded character's accent; set by `PluginView.applyPalette`.
    static var accent = UIColor(hex: 0xF0A020)
    // skin / robe / robeShadow: keep only if still referenced after Tasks 3–4; otherwise delete.
    ...
    static func label(_ size: CGFloat, weight: UIFont.Weight = .semibold) -> UIFont { rounded(size, weight) }
    static func display(_ size: CGFloat) -> UIFont { rounded(size, .heavy) }
    private static func rounded(_ size: CGFloat, _ weight: UIFont.Weight) -> UIFont {
        let base = UIFont.systemFont(ofSize: size, weight: weight)
        guard let d = base.fontDescriptor.withDesign(.rounded) else { return base }
        return UIFont(descriptor: d, size: size)
    }
}
```

(Remove the temporary `display` added in Task 6 — it is now this one.)

- [ ] **Step 3: `KnobView.draw(_:)`** — keep `captionHeight`, `dialSide` and caption code; replace the dial drawing:

```swift
        let side = min(rect.width, rect.height - Self.captionHeight)
        guard side > 4 else { return }
        let dial = CGRect(x: rect.midX - side / 2, y: rect.minY + 1, width: side, height: side - 3)
            .insetBy(dx: 1.5, dy: 0)
        let s = min(dial.width, dial.height)
        let c = CGPoint(x: dial.midX, y: dial.minY + s / 2)
        let border: CGFloat = s >= 90 ? 4 : (s >= 40 ? 3 : 2)
        let ringW = max(4, s * 0.15)
        let start = CGFloat(135) * .pi / 180            // 7:30 position
        let end = start + CGFloat(270) * .pi / 180
        // Hard drop shadow, then the ring body.
        Toon.fill(Toon.circle(c.x, c.y + border, s / 2), Theme.ink)
        Toon.fill(Toon.circle(c.x, c.y, s / 2), Theme.panel)
        let arcR = s / 2 - ringW / 2 - border / 2
        let track = UIBezierPath(arcCenter: c, radius: arcR, startAngle: start, endAngle: end, clockwise: true)
        track.lineWidth = ringW; Theme.track.setStroke(); track.stroke()
        let lit = UIBezierPath(arcCenter: c, radius: arcR, startAngle: start,
                               endAngle: start + CGFloat(270 * Double(value)) * .pi / 180, clockwise: true)
        lit.lineWidth = ringW; Theme.accent.setStroke(); if value > 0.001 { lit.stroke() }
        Toon.stroke(Toon.circle(c.x, c.y, s / 2 - border / 2), width: border)
        // Cream face with ink edge and an ink pointer.
        let faceR = s / 2 - ringW - border / 2
        Toon.shape(Toon.circle(c.x, c.y, faceR), fill: Theme.cream, lineWidth: border, shaded: false)
        let angle = start + CGFloat(270 * Double(value)) * .pi / 180
        let p = UIBezierPath()
        p.move(to: CGPoint(x: c.x + cos(angle) * faceR * 0.25, y: c.y + sin(angle) * faceR * 0.25))
        p.addLine(to: CGPoint(x: c.x + cos(angle) * faceR * 0.8, y: c.y + sin(angle) * faceR * 0.8))
        Toon.stroke(p, width: max(2.5, s * 0.08))
```

Captions: name in `Theme.label(Self.nameFontSize, weight: .heavy)` colour `Theme.textDim`, value in `Theme.display(Self.valueFontSize + 2)` colour `Theme.textPrimary`; raise `captionHeight` by 2 if the larger value font no longer fits (the existing caption-fit test will say).

- [ ] **Step 4: `ControlPages` segmented bar**

- Replace `tabBar` (a `UIStackView`) with a container `UIView` `tabTrack` (background `Theme.panelDeep`, ink border 3, corner radius = half its short side) holding the `UIStackView` of buttons and a `selector` `UIView` behind them (background `Theme.accent`, ink border 3, same corner rounding) that moves under the selected button.
- Buttons: title font `Theme.display(11)`, uppercase titles as today, title colour `Theme.ink` when selected, `Theme.textDim` otherwise, background clear.
- `var tabBarFrame: CGRect { tabTrack.frame }` and `var selectedTabButton: UIButton?` (for tests). `selectedTabButton?.backgroundColor` must equal `Theme.accent`: set the selected button's `backgroundColor = Theme.accent` and make `selector` purely the ink outline + shadow behind it, OR drop `selector` and colour the button directly — choose the latter (simpler; the "sliding" animation becomes a 0.18 s `UIView.animate` crossfade of background colours, skipped under Reduce Motion).
- `layoutSubviews`: if `bounds.width >= bounds.height * 5`, tabs are a vertical column on the left (`width 92`, full height minus 8, stack axis `.vertical`) and the knob row fills the rest; otherwise a top row of height 30 (stack axis `.horizontal`) with knobs below, as today.
- `func applyPalette()`: re-run the button colouring in `showPage` and `knobs.forEach { $0.setNeedsDisplay() }`.

- [ ] **Step 5: `CharacterSelector` and `PluginView` chrome**

- `CharacterSelector`: the two arrow buttons become 36pt circles (`Theme.cream` background, ink border 3, `layer.shadowColor = ink`, `shadowOffset (0, 3)`, `shadowOpacity 1`, `shadowRadius 0`) with an ink chevron (`UIImage(systemName: "chevron.left"/"chevron.right")` tinted `Theme.ink`, bold). The name label uses `Theme.display(20)`, colour `Theme.textPrimary`, and gains a trailing `chevron.down` image tinted `Theme.accent`. Keep all frame/truncation/accessibility logic exactly as is.
- `PluginView`: drawer handle bar → `Theme.cream` capsule, ink border 3, chevron tint `Theme.ink`. Info button → 36pt circle, `Theme.panel` fill, ink border 3, `info` glyph tinted `Theme.textDim`. `backgroundColor = Theme.background`.
- `PluginView.applyPalette(_ p: Palette)`: `Theme.accent = p.accent; controls.applyPalette(); characterSelector.applyPalette(); pad.accent = p.accent`. Call it from the `stage.onCharacterChanged` closure (next to `sceneView.character = character`) and once at the end of `init`.
- `CharacterSelector.applyPalette()`: re-tint the chevron-down with `Theme.accent`.

- [ ] **Step 6: Run and look**

`scripts/test.sh` → `** TEST SUCCEEDED **`. `scripts/test.sh MonkSynthTests/RenderUISnapshot`; Read `/private/tmp/ui_knobs.png`, `/private/tmp/ui_sizes.png`, `/private/tmp/ui_characterselector.png`. Compare with the mockup's Controls close-up (knob, segmented tabs, header) — open https://claude.ai/artifact/WjsXjs35ABk6J91EPadANX if unsure.

- [ ] **Step 7: Commit**

```bash
git add AU/UI/Theme.swift AU/UI/KnobView.swift AU/UI/ControlPages.swift AU/UI/CharacterSelector.swift AU/UI/PluginView.swift Tests/MonkSynthTests
git commit -m "Sticker chrome: cream dials, a segmented tab bar, round header buttons, and every accent follows the character"
```

---

### Task 8: Overlays — dropdown thumbnails, About, More Apps

**Goal:** The picker shows each character's face in its scene; About and More Apps read as the same app.

**Files:**
- Create: `AU/UI/CharacterThumbnail.swift`
- Modify: `AU/UI/CharacterDropdownView.swift` (row view), `AU/UI/AboutView.swift`, `AU/UI/MoreAppsView.swift`
- Test: `Tests/MonkSynthTests/CharacterDropdownViewTests.swift` (add)

**Acceptance Criteria:**
- [ ] `CharacterThumbnail.image(for:side:)` returns a `side × side` image with opaque corners (scene drawn) for every registered character, and for a `UserCharacter` (its face's scene).
- [ ] Every dropdown row shows a 40pt thumbnail with an ink border and 10pt corner radius to the left of the name.
- [ ] Panels in all three overlays use `Theme.panel` with a 3pt ink border; titles use `Theme.display`; the current-row highlight uses `Theme.accent`.
- [ ] Existing `CharacterDropdownViewTests`, `AboutViewTests`, `MoreAppsCatalogTests` pass.

**Verify:** `scripts/test.sh` → `** TEST SUCCEEDED **`; `scripts/test.sh MonkSynthTests/RenderUISnapshot`, Read `/private/tmp/ui_characterdropdown.png`, `/private/tmp/ui_moreapps.png`, `/private/tmp/ui_about_donation.png`.

**Steps:**

- [ ] **Step 1: Failing test** (add to `CharacterDropdownViewTests`)

```swift
    func testThumbnailsDrawTheSceneForEveryCharacter() {
        for c in CharacterRegistry.all + [UserCharacter(name: "Mine", faceID: "cat", params: [])] {
            let img = CharacterThumbnail.image(for: c, side: 40)
            XCTAssertEqual(img.size, CGSize(width: 40, height: 40))
            let cg = img.cgImage!
            var px = [UInt8](repeating: 0, count: 4)
            let ctx = CGContext(data: &px, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))   // samples bottom-left
            XCTAssertEqual(px[3], 255, "\(c.id) thumbnail corner is transparent")
        }
    }
```

- [ ] **Step 2: `AU/UI/CharacterThumbnail.swift`**

```swift
import UIKit

/// A small picture of a character singing AH in its own scene, for lists.
enum CharacterThumbnail {
    static func image(for character: Character, side: CGFloat) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.opaque = true
        return UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { _ in
            let rect = CGRect(x: 0, y: 0, width: side, height: side)
            // Crop to head and shoulders: draw the figure larger than the tile.
            let figure = side * 1.5
            let stage = CGRect(x: (side - figure) / 2, y: side - figure * 0.88, width: figure, height: figure)
            character.drawBackdrop(in: rect, stage: stage)
            character.drawBody(in: stage)
            character.drawFace(in: stage, expression: .rest)
            character.drawMouth(in: stage, vowel: 0.5, amplitudeBoost: 1)
            character.drawOverMouth(in: stage)
        }
    }
}
```

- [ ] **Step 3: Dropdown row** — in the row view class in `CharacterDropdownView.swift` (the one setting `nameLabel`, `badge`, `checkmark` around lines 370–415), add a `UIImageView` `thumb` (40×40, `layer.cornerRadius = 10`, `clipsToBounds`, `layer.borderWidth = 3`, `layer.borderColor = Theme.ink.cgColor`) as the leading element, set from `CharacterThumbnail.image(for: character, side: 40)` when the row is configured. Generate thumbnails lazily per row (they are cheap; no cache needed for 12–40 rows). Row background: `Theme.panel`; current row border `Theme.accent`, 3pt.

- [ ] **Step 4: About / More Apps / dropdown panels** — wherever these views set `panel.backgroundColor`, `layer.borderColor`, `layer.borderWidth`, title fonts: use `Theme.panel`, `Theme.ink`, `3`, `Theme.display(<same size>)`. Buttons that use `UIButton.Configuration` take `baseBackgroundColor = Theme.cream`, `baseForegroundColor = Theme.ink`, plus a 3pt ink border via `background.strokeColor/strokeWidth`. Do not change copy, layout maths or behaviour.

- [ ] **Step 5: Run and look** — suite passes; Read the three overlay PNGs.

- [ ] **Step 6: Commit**

```bash
git add AU/UI/CharacterThumbnail.swift AU/UI/CharacterDropdownView.swift AU/UI/AboutView.swift AU/UI/MoreAppsView.swift Tests/MonkSynthTests/CharacterDropdownViewTests.swift
git commit -m "The picker shows faces, and the overlays match the stage"
```

---

### Task 9: Render review, app icon, docs

**Goal:** Every surface reviewed against the mockups at every host size, the app icon regenerated from the new monk, and the character-art guide updated.

**Files:**
- Modify: `Tests/MonkSynthTests/RenderMonkSnapshot.swift` (sweep includes a loud column and a blink column), `Tests/MonkSynthTests/RenderUISnapshot.swift` (size sheet for monk, fish, punk), `Tests/MonkSynthTests/RenderAppIcon.swift`
- Modify: `Host/Assets.xcassets/AppIcon.appiconset/*` (the 1024 image), `docs/CHARACTER-ART.md`

**Acceptance Criteria:**
- [ ] `/tmp/characters.png`: 12 rows × 7 columns (5 vowels, loud AH, blink) in scenes; every row reviewed against the mockup; findings fixed.
- [ ] `/tmp/ui_sizes.png` rendered for monk, fish and punk at the six host sizes; nothing overlaps, every scene is playable, the strip never hides.
- [ ] App icon: the new monk in his scene, 1024×1024 opaque, copied into `AppIcon.appiconset` replacing the old file of the same name.
- [ ] `docs/CHARACTER-ART.md` has a section "Drawn characters" explaining `ToonCharacter`, the 300-unit stage, `gen.mjs` as the design tool, and the art tests.
- [ ] Full suite passes.

**Verify:** `scripts/test.sh` → `** TEST SUCCEEDED **`; Read each PNG listed.

**Steps:**

- [ ] **Step 1: Sweep columns** — in `testWriteAllCharactersSweep`, change `vowels` to `[0.0, 0.25, 0.5, 0.75, 1.0]` plus two extra cells per row: `(vowel 0.5, amplitude 1.0)` labelled `loud`, and a blink cell rendered by calling `character.drawBackdrop`, `drawBody`, `drawFace(expression: Expression(blinking: true, loudness: 0, vowel: 0.5))`, `drawMouth`, `drawOverMouth` directly (CharacterView's idle animator controls blinking, so draw the blink cell without it).

- [ ] **Step 2: Size sheet per character** — in `RenderUISnapshot.testWriteSizeSheet`, render each size three times (selecting `MonkCharacter`, `FishCharacter`, `PunkCharacter` via `view.stage.character = …` before layout), three columns per size, write `/tmp/ui_sizes.png`.

- [ ] **Step 3: Icon** — in `RenderAppIcon`, before rendering the `CharacterView`, draw `MonkCharacter().drawBackdrop(in: CGRect(x: 0, y: 0, width: side, height: side), stage: <the same stage rect the CharacterView will use, mapped into icon space>)`. Run `scripts/test.sh MonkSynthTests/RenderAppIcon`, Read `/private/tmp/monk_icon.png`, then copy it over the 1024 image in `Host/Assets.xcassets/AppIcon.appiconset/` (check `Contents.json` for the filename).

- [ ] **Step 4: Review** — run `scripts/test.sh MonkSynthTests/RenderMonkSnapshot` and `scripts/test.sh MonkSynthTests/RenderUISnapshot`; Read every PNG they write. For each character check: head attached, nothing floating, mouth steps OO→EE clearly, blink closes the eyes, loud lifts brows and opens the mouth further, scene props don't collide with the figure. Fix anything wrong in the character/scene file and re-render.

- [ ] **Step 5: Docs** — add to `docs/CHARACTER-ART.md` (before "A concrete example"):

```markdown
## Drawn characters

The twelve built-in characters are drawn in code, not images. Each is a
`ToonCharacter` (`AU/UI/ToonCharacter.swift`): it draws its body and face
with the `Toon` kit (`AU/UI/Toon.swift`) in a 300×300 "stage unit" space,
names where its mouth sits (`mouthStyle`), and draws its own scene
(`drawBackdrop`). The mouth itself is shared (`AU/UI/ToonMouth.swift`).

The shapes were designed in `docs/mockups/stage-redesign/gen.mjs`, which
renders the same path data as SVG — edit a character there first
(`node gen.mjs` writes `out/`), then copy the numbers across; `Toon.path`
reads the same path syntax.

`CharacterArtTests` keeps every drawn character honest: one connected figure
(nothing floating), nothing clipped at the stage edge, and a mouth at least
0.11 of the stage tall at AH and 0.14 wide at EE.
```

- [ ] **Step 6: Suite + commit**

```bash
scripts/test.sh
git add Tests/MonkSynthTests/RenderMonkSnapshot.swift Tests/MonkSynthTests/RenderUISnapshot.swift Tests/MonkSynthTests/RenderAppIcon.swift Host/Assets.xcassets docs/CHARACTER-ART.md
git commit -m "Review renders for every character and size, a new icon, and the drawn-character guide"
```

---

## Self-review notes

- Spec §1 (kit, framing, mouth, faces react) → Tasks 1–4; §2 (twelve) → Tasks 3–4; §3 (palette, backdrop, SceneView, pad drawing, hint, accessibility unchanged) → Tasks 5–6; §4 (chrome, typography, knobs, tabs, header, handle, overlays, thumbnails) → Tasks 7–8; Verification → Task 9 and per-task render reviews; mockup amendments → Porting rules + Tasks 3–6.
- Names used across tasks: `Toon.shape/stroke/fill/path/inStage/clipped/rotated/circle/ellipse/rect/eyeOpen/eyeClosed/cheek/highlight`, `Palette`, `Expression(.rest)`, `ToonMouth.Style/params/draw/anchors`, `ToonCharacter.drawToonBody/drawToonFace/drawToonOverMouth/mouthStyle`, `Backdrop.plain/sky/ground/<props>`, `SceneView(stage:pad:)/.characterRect(in:)/.character`, `BackdropView.character/.characterRect`, `XYPadView.accent/hintDismissedKey`, `Theme.stripHeight/stripHeightWide/display/label/accent`, `ControlPages.tabBarFrame/selectedTabButton/applyPalette`, `PluginView.sceneView/applyPalette`, `CharacterThumbnail.image(for:side:)`.
