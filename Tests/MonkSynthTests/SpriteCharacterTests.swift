import XCTest
import UIKit
@testable import MonkSynth

/// Covers `SpriteCharacter` — the image-backed `Character` conformance —
/// and `SpriteManifest`, the `Codable` data it renders. Uses
/// `SpriteCharacterFixture` (real art rendered from `MonkCharacter` at test
/// time, see that file) for the "does this genuinely work" tests, and small
/// synthetic manifests/images for the specific edge cases (fewer frames,
/// missing/corrupt art, the strip packaging) so each test's premise is
/// exact rather than incidental to whatever the fixture happens to look
/// like.
final class SpriteCharacterTests: XCTestCase {

    // MARK: - Helpers

    /// Renders one `Character` frame directly through the protocol
    /// (`drawBody`/`drawEyes`/`drawMouth`, the same three calls
    /// `CharacterView` itself makes), independent of `CharacterView`'s idle
    /// state machine — every test here that wants a specific, deterministic
    /// pose calls this instead of driving a live `CharacterView`, so
    /// nothing depends on `CADisplayLink` ticking or wall-clock time.
    private func renderFrame(_ character: Character, stage: CGSize = CGSize(width: 300, height: 300),
                              vowel: Float = 0.5, blinking: Bool = false,
                              amplitudeBoost: CGFloat = 1) -> UIImage {
        let rect = CGRect(origin: .zero, size: stage)
        let renderer = UIGraphicsImageRenderer(size: stage)
        return renderer.image { _ in
            character.drawBody(in: rect)
            character.drawEyes(in: rect, blinking: blinking)
            character.drawMouth(in: rect, vowel: vowel, amplitudeBoost: amplitudeBoost)
        }
    }

    private func solidImage(_ color: UIColor, size: CGSize) -> UIImage {
        UIGraphicsImageRenderer(size: size).image { ctx in
            color.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
        }
    }

    // MARK: - Renders without crashing, at several sizes and aspect ratios

    /// Direct-protocol version: every combination below must complete
    /// without throwing/crashing and produce real image bytes, including
    /// extreme aspect ratios (well past anything `CharacterView`'s own
    /// centred-square `stage` would ever actually hand a character, since
    /// it always squares its rect first — see `CharacterView.draw(_:)`) so
    /// this is a strictly harder test than what production ever exercises.
    func testRendersWithoutCrashingAtSeveralSizesAndAspectRatios() {
        let sprite = SpriteCharacterFixture.make()
        let sizes: [CGSize] = [
            CGSize(width: 120, height: 120),     // small end of the stated range
            CGSize(width: 1200, height: 1200),   // iPad-large end
            CGSize(width: 300, height: 300),
            CGSize(width: 480, height: 120),     // wide
            CGSize(width: 120, height: 480),     // tall
            CGSize(width: 1, height: 1),         // degenerate but non-zero
        ]
        for size in sizes {
            for vowel: Float in [0, 0.25, 0.5, 0.75, 1] {
                let image = renderFrame(sprite, stage: size, vowel: vowel)
                XCTAssertNotNil(image.pngData(), "sprite character failed to render at size \(size), vowel \(vowel)")
            }
        }
    }

    /// End-to-end version through the real `CharacterView` pipeline (idle
    /// pose, quantisation, amplitude swell) at a spread of frame sizes —
    /// the same rendering path `PluginView` actually uses in the app.
    func testRendersWithoutCrashingThroughCharacterViewAtSeveralSizes() {
        let sprite = SpriteCharacterFixture.make()
        let sizes: [CGSize] = [
            CGSize(width: 130, height: 150),
            CGSize(width: 1024, height: 900),
            CGSize(width: 480, height: 120),
            CGSize(width: 160, height: 420),
        ]
        for size in sizes {
            let view = CharacterView(frame: CGRect(origin: .zero, size: size))
            view.character = sprite
            view.vowel = 0.6
            view.amplitude = 0.7
            view.noteActive = true
            let renderer = UIGraphicsImageRenderer(size: size)
            let image = renderer.image { ctx in
                view.layer.render(in: ctx.cgContext)
            }
            XCTAssertNotNil(image.pngData(), "CharacterView with a sprite character failed to render at \(size)")
        }
    }

    // MARK: - Vowel changes select different mouth frames

    /// `SpriteCharacter.mouthFrameIndex` in isolation: exact, not
    /// pixel-diffed. 24 frames is the fixture's own count and
    /// `CharacterView.vowelFrameCount`, so this is the identity-mapping
    /// case — every quantised vowel step should land on its own index.
    func testMouthFrameIndexCoversZeroToOneAndHitsExtremesAt24Frames() {
        XCTAssertEqual(SpriteCharacter.mouthFrameIndex(forVowel: 0, frameCount: 24), 0)
        XCTAssertEqual(SpriteCharacter.mouthFrameIndex(forVowel: 1, frameCount: 24), 23)

        var seen = Set<Int>()
        for step in 0..<24 {
            let vowel = CharacterView.quantisedVowel(Float(step) / 23)
            let index = SpriteCharacter.mouthFrameIndex(forVowel: vowel, frameCount: 24)
            XCTAssertGreaterThanOrEqual(index, 0)
            XCTAssertLessThan(index, 24)
            seen.insert(index)
        }
        XCTAssertEqual(seen.count, 24, "24 frames against 24 quantised steps should be a 1:1 mapping, got \(seen.count) distinct indices")
    }

    /// End-to-end: rendering the (real, 24-frame) fixture at vowel 0 vs
    /// vowel 1 through the actual `Character.drawMouth` path must produce
    /// visibly different pixels — proof the frame selection isn't a no-op
    /// wired to a single always-drawn image.
    func testDifferentVowelsProduceDifferentRenderedMouthFrames() {
        let sprite = SpriteCharacterFixture.make()
        let atZero = renderFrame(sprite, vowel: 0).pngData()
        let atHalf = renderFrame(sprite, vowel: 0.5).pngData()
        let atOne = renderFrame(sprite, vowel: 1).pngData()

        XCTAssertNotEqual(atZero, atHalf, "vowel 0 and vowel 0.5 rendered identically")
        XCTAssertNotEqual(atHalf, atOne, "vowel 0.5 and vowel 1 rendered identically")
        XCTAssertNotEqual(atZero, atOne, "vowel 0 and vowel 1 rendered identically")
    }

    // MARK: - Fewer than 24 frames maps to nearest, no crash / no OOB

    /// Pure-function sweep across every one of the 24 canonical quantised
    /// vowel steps against several frame counts smaller than 24 (including
    /// 1, the extreme case): the index must always land in bounds, and the
    /// extremes must still resolve to the first/last frame.
    func testFewerThanTwentyFourFramesMapsToNearestWithoutGoingOutOfBounds() {
        for frameCount in [1, 2, 5, 6, 12, 23] {
            XCTAssertEqual(SpriteCharacter.mouthFrameIndex(forVowel: 0, frameCount: frameCount), 0,
                            "frameCount \(frameCount): vowel 0 should land on frame 0")
            XCTAssertEqual(SpriteCharacter.mouthFrameIndex(forVowel: 1, frameCount: frameCount), frameCount - 1,
                            "frameCount \(frameCount): vowel 1 should land on the last frame")
            for step in 0..<24 {
                let vowel = CharacterView.quantisedVowel(Float(step) / 23)
                let index = SpriteCharacter.mouthFrameIndex(forVowel: vowel, frameCount: frameCount)
                XCTAssertGreaterThanOrEqual(index, 0, "frameCount \(frameCount), step \(step): index below zero")
                XCTAssertLessThan(index, frameCount, "frameCount \(frameCount), step \(step): index out of bounds")
            }
        }
    }

    /// The same sweep again, but through the REAL `drawMouth` — which
    /// actually indexes into the loaded `mouthFrames` array — using a
    /// 6-frame fixture (fewer than `CharacterView.vowelFrameCount`). This
    /// is the test that would catch an off-by-one causing an actual
    /// out-of-bounds array read, which the pure-function test above can't:
    /// it proves the array access itself, not just the arithmetic.
    func testRenderingEveryQuantisedStepWithFewerThanTwentyFourFramesNeverCrashes() {
        let sprite = SpriteCharacterFixture.make(frameCount: 6)
        XCTAssertTrue(sprite.isArtLoaded, "fixture with 6 frames should still load cleanly")
        for step in 0..<24 {
            let vowel = CharacterView.quantisedVowel(Float(step) / 23)
            let image = renderFrame(sprite, vowel: vowel)
            XCTAssertNotNil(image.pngData(), "rendering step \(step) (vowel \(vowel)) with a 6-frame sprite failed")
        }
    }

    // MARK: - Blink is a no-op for the monk's meditating eyes

    /// The fixture (and the fallback below) render through `MonkCharacter`,
    /// whose eyes are drawn closed in meditation regardless of `blinking` —
    /// see `MonkCharacter.drawToonFace`. So, unlike a sprite with real open/
    /// closed art, `blinking` must NOT change the rendered pixels here.
    func testBlinkingDoesNotChangeTheMonksClosedEyes() {
        let sprite = SpriteCharacterFixture.make()
        XCTAssertTrue(sprite.isArtLoaded)

        let stage = CGRect(origin: .zero, size: CGSize(width: 300, height: 300))
        let renderer = UIGraphicsImageRenderer(size: stage.size)

        let open = renderer.image { _ in sprite.drawEyes(in: stage, blinking: false) }
        let closed = renderer.image { _ in sprite.drawEyes(in: stage, blinking: true) }

        XCTAssertEqual(open.pngData(), closed.pngData(),
                        "the monk's eyes are closed in meditation, blink or not")
    }

    /// The fallback path behaves the same way — `SpriteCharacter` with
    /// unusable art delegates `blinking` through to `MonkCharacter.drawEyes`,
    /// which is likewise unaffected by it.
    func testBlinkingDoesNotChangeTheFallbacksClosedEyes() {
        let manifest = SpriteManifest(id: "broken", displayName: "Broken",
                                       bodyImageName: "missing-body",
                                       eyeOpenImageName: "missing-eye-open",
                                       eyeClosedImageName: "missing-eye-closed",
                                       mouthPlacement: .init(centerX: 0.5, centerY: 0.5, width: 0.2, height: 0.2),
                                       mouthFrameNames: ["missing-mouth"])
        let sprite = SpriteCharacter(manifest: manifest, loader: DictionaryImageLoader(images: [:]))
        XCTAssertFalse(sprite.isArtLoaded)

        let stage = CGRect(origin: .zero, size: CGSize(width: 300, height: 300))
        let renderer = UIGraphicsImageRenderer(size: stage.size)
        let open = renderer.image { _ in sprite.drawEyes(in: stage, blinking: false) }
        let closed = renderer.image { _ in sprite.drawEyes(in: stage, blinking: true) }
        XCTAssertEqual(open.pngData(), closed.pngData())
    }

    // MARK: - Missing/corrupt art degrades gracefully

    private func brokenManifest(mouthFrameNames: [String]? = ["mouth"]) -> SpriteManifest {
        SpriteManifest(id: "broken", displayName: "Broken",
                        bodyImageName: "body", eyeOpenImageName: "eyeOpen", eyeClosedImageName: "eyeClosed",
                        mouthPlacement: .init(centerX: 0.5, centerY: 0.394, width: 0.27, height: 0.27),
                        mouthFrameNames: mouthFrameNames)
    }

    /// Every required name unresolved: no crash, `isArtLoaded` reports the
    /// degraded state, and — because the fallback calls straight through to
    /// `MonkCharacter`'s own methods with the same parameters — rendering
    /// is BYTE-IDENTICAL to rendering `MonkCharacter` directly, not merely
    /// "some image, not blank".
    func testEntirelyMissingArtFallsBackToMonkExactly() {
        let sprite = SpriteCharacter(manifest: brokenManifest(), loader: DictionaryImageLoader(images: [:]))
        XCTAssertFalse(sprite.isArtLoaded)

        for vowel: Float in [0, 0.4, 1] {
            for blinking in [false, true] {
                let spriteImage = renderFrame(sprite, vowel: vowel, blinking: blinking).pngData()
                let monkImage = renderFrame(MonkCharacter(), vowel: vowel, blinking: blinking).pngData()
                XCTAssertEqual(spriteImage, monkImage,
                                "fallback render should be byte-identical to MonkCharacter at vowel \(vowel), blinking \(blinking)")
            }
        }
    }

    /// "Corrupt" (decoded but degenerate — zero-size) is treated exactly
    /// like "missing": a loader that resolves the body name to a
    /// zero-size `UIImage` still triggers the whole-character fallback,
    /// not a crash or a blank/invisibly-tiny body.
    func testZeroSizeDecodedImageIsTreatedAsCorruptAndFallsBack() {
        let images: [String: UIImage] = [
            "body": UIImage(),   // valid UIImage, .size == .zero — stands in for "corrupt"
            "eyeOpen": solidImage(.white, size: CGSize(width: 400, height: 400)),
            "eyeClosed": solidImage(.black, size: CGSize(width: 400, height: 400)),
            "mouth": solidImage(.gray, size: CGSize(width: 100, height: 100)),
        ]
        let sprite = SpriteCharacter(manifest: brokenManifest(), loader: DictionaryImageLoader(images: images))
        XCTAssertFalse(sprite.isArtLoaded, "a zero-size decoded image must not count as successfully loaded")
        XCTAssertNotNil(renderFrame(sprite).pngData(), "fallback render must still succeed, not crash")
    }

    /// Partial art (body fine, eyes missing) does NOT partially render —
    /// per the documented "all or nothing" rule, the whole character
    /// (including the body, which WAS available) falls back to Monk, so a
    /// sprite body is never seen stitched to Monk's drawn eyes.
    func testPartiallyMissingArtFallsBackEntirelyNotJustTheMissingPiece() {
        let images: [String: UIImage] = [
            "body": solidImage(.orange, size: CGSize(width: 400, height: 400)),
            "eyeOpen": solidImage(.white, size: CGSize(width: 400, height: 400)),
            // eyeClosed deliberately missing
            "mouth": solidImage(.gray, size: CGSize(width: 100, height: 100)),
        ]
        let sprite = SpriteCharacter(manifest: brokenManifest(), loader: DictionaryImageLoader(images: images))
        XCTAssertFalse(sprite.isArtLoaded)

        let stage = CGRect(origin: .zero, size: CGSize(width: 300, height: 300))
        let spriteBody = UIGraphicsImageRenderer(size: stage.size).image { _ in sprite.drawBody(in: stage) }
        let monkBody = UIGraphicsImageRenderer(size: stage.size).image { _ in MonkCharacter().drawBody(in: stage) }
        XCTAssertEqual(spriteBody.pngData(), monkBody.pngData(),
                        "an available body image must not be drawn once ANY other required image is missing")
    }

    /// No mouth frames at all (empty array) degrades the same way as any
    /// other missing asset, rather than crashing on an empty-array index.
    func testEmptyMouthFrameListFallsBack() {
        let sprite = SpriteCharacter(manifest: brokenManifest(mouthFrameNames: []),
                                      loader: DictionaryImageLoader(images: [
                                        "body": solidImage(.orange, size: CGSize(width: 400, height: 400)),
                                        "eyeOpen": solidImage(.white, size: CGSize(width: 400, height: 400)),
                                        "eyeClosed": solidImage(.black, size: CGSize(width: 400, height: 400)),
                                      ]))
        XCTAssertFalse(sprite.isArtLoaded)
        XCTAssertNotNil(renderFrame(sprite).pngData())
    }

    // MARK: - The grid/strip mouth-frame packaging

    /// Slices a synthetic 3×2 strip (6 cells, distinct greys) into frames
    /// and confirms the resulting character loads and renders distinctly
    /// across the vowel range — the "one horizontal/grid strip" packaging
    /// the task calls out as an alternative to N separate images.
    func testMouthFrameStripPackagingSlicesAndRendersDistinctFrames() {
        let columns = 3, rows = 2, frameCount = 6
        let cell = CGSize(width: 40, height: 40)
        let strip = UIGraphicsImageRenderer(size: CGSize(width: cell.width * CGFloat(columns),
                                                           height: cell.height * CGFloat(rows))).image { ctx in
            for i in 0..<frameCount {
                let col = i % columns, row = i / columns
                UIColor(white: CGFloat(i) / CGFloat(frameCount - 1), alpha: 1).setFill()
                ctx.fill(CGRect(x: CGFloat(col) * cell.width, y: CGFloat(row) * cell.height,
                                 width: cell.width, height: cell.height))
            }
        }
        var manifest = brokenManifest(mouthFrameNames: nil)
        manifest.mouthFrameNames = nil
        manifest.mouthStripName = "strip"
        manifest.mouthStripColumns = columns
        manifest.mouthStripRows = rows
        manifest.mouthStripFrameCount = frameCount

        let images: [String: UIImage] = [
            "body": solidImage(.orange, size: CGSize(width: 400, height: 400)),
            "eyeOpen": solidImage(.white, size: CGSize(width: 400, height: 400)),
            "eyeClosed": solidImage(.black, size: CGSize(width: 400, height: 400)),
            "strip": strip,
        ]
        let sprite = SpriteCharacter(manifest: manifest, loader: DictionaryImageLoader(images: images))
        XCTAssertTrue(sprite.isArtLoaded, "a well-formed strip manifest should load successfully")

        let atZero = renderFrame(sprite, vowel: 0).pngData()
        let atOne = renderFrame(sprite, vowel: 1).pngData()
        XCTAssertNotEqual(atZero, atOne, "the strip's first and last cells should render differently")
    }

    /// Malformed strip geometry (more frames requested than the grid has
    /// cells) degrades like any other unusable art, rather than cropping
    /// out of bounds or crashing.
    func testMalformedStripGeometryFallsBackRatherThanCrashing() {
        var manifest = brokenManifest(mouthFrameNames: nil)
        manifest.mouthFrameNames = nil
        manifest.mouthStripName = "strip"
        manifest.mouthStripColumns = 2
        manifest.mouthStripRows = 1
        manifest.mouthStripFrameCount = 10   // more than 2×1 = 2 cells

        let images: [String: UIImage] = [
            "body": solidImage(.orange, size: CGSize(width: 400, height: 400)),
            "eyeOpen": solidImage(.white, size: CGSize(width: 400, height: 400)),
            "eyeClosed": solidImage(.black, size: CGSize(width: 400, height: 400)),
            "strip": solidImage(.gray, size: CGSize(width: 80, height: 40)),
        ]
        let sprite = SpriteCharacter(manifest: manifest, loader: DictionaryImageLoader(images: images))
        XCTAssertFalse(sprite.isArtLoaded)
        XCTAssertNotNil(renderFrame(sprite).pngData())
    }

    /// When a manifest populates both packagings, `mouthFrameNames` wins —
    /// documented on `SpriteManifest`; locked in here so the precedence
    /// can't drift silently.
    func testMouthFrameNamesWinsWhenBothPackagingsArePopulated() {
        var manifest = brokenManifest(mouthFrameNames: ["mouth"])
        manifest.mouthStripName = "strip"
        manifest.mouthStripColumns = 1
        manifest.mouthStripRows = 1
        manifest.mouthStripFrameCount = 1

        let images: [String: UIImage] = [
            "body": solidImage(.orange, size: CGSize(width: 400, height: 400)),
            "eyeOpen": solidImage(.white, size: CGSize(width: 400, height: 400)),
            "eyeClosed": solidImage(.black, size: CGSize(width: 400, height: 400)),
            "mouth": solidImage(.blue, size: CGSize(width: 100, height: 100)),
            // deliberately no "strip" entry — if the strip path were taken
            // instead, loading would fail and isArtLoaded would be false.
        ]
        let sprite = SpriteCharacter(manifest: manifest, loader: DictionaryImageLoader(images: images))
        XCTAssertTrue(sprite.isArtLoaded, "mouthFrameNames should be used even though strip fields are also set")
    }

    // MARK: - Letterbox geometry never distorts

    func testLetterboxRectPreservesAspectRatioAndCentres() {
        let stage = CGRect(x: 10, y: 20, width: 200, height: 200)

        // A 2:1 image in a square stage must letterbox top/bottom, never
        // stretch to fill the square.
        let wide = SpriteCharacter.letterboxRect(for: CGSize(width: 400, height: 200), in: stage)
        XCTAssertEqual(wide.width, 200, accuracy: 0.001)
        XCTAssertEqual(wide.height, 100, accuracy: 0.001)
        XCTAssertEqual(wide.midX, stage.midX, accuracy: 0.001)
        XCTAssertEqual(wide.midY, stage.midY, accuracy: 0.001)

        // A 1:2 image must letterbox left/right.
        let tall = SpriteCharacter.letterboxRect(for: CGSize(width: 200, height: 400), in: stage)
        XCTAssertEqual(tall.width, 100, accuracy: 0.001)
        XCTAssertEqual(tall.height, 200, accuracy: 0.001)

        // A square image in a square stage fills it exactly (no bars) —
        // matches how a drawn character's stage-fraction geometry already
        // fills the square stage with no letterboxing needed.
        let square = SpriteCharacter.letterboxRect(for: CGSize(width: 200, height: 200), in: stage)
        XCTAssertEqual(square, stage)
    }

    /// Degenerate/zero image size falls back to the stage itself rather
    /// than dividing by zero or producing a NaN rect.
    func testLetterboxRectHandlesZeroSizeWithoutDivideByZero() {
        let stage = CGRect(x: 0, y: 0, width: 100, height: 100)
        let result = SpriteCharacter.letterboxRect(for: .zero, in: stage)
        XCTAssertEqual(result, stage)
        XCTAssertFalse(result.width.isNaN)
    }

    // MARK: - Manifest round-trips through Codable

    func testManifestWithSeparateMouthFramesRoundTripsThroughCodable() throws {
        let manifest = SpriteManifest(
            id: "roundtrip.images", displayName: "Round Trip",
            bodyImageName: "body", eyeOpenImageName: "eyeOpen", eyeClosedImageName: "eyeClosed",
            mouthPlacement: .init(centerX: 0.5, centerY: 0.4, width: 0.3, height: 0.25),
            mouthFrameNames: (0..<24).map { "mouth\($0)" })

        let data = try JSONEncoder().encode(manifest)
        let decoded = try JSONDecoder().decode(SpriteManifest.self, from: data)
        XCTAssertEqual(manifest, decoded)
    }

    func testManifestWithMouthStripRoundTripsThroughCodable() throws {
        var manifest = SpriteManifest(
            id: "roundtrip.strip", displayName: "Round Trip Strip",
            bodyImageName: "body", eyeOpenImageName: "eyeOpen", eyeClosedImageName: "eyeClosed",
            mouthPlacement: .init(centerX: 0.5, centerY: 0.4, width: 0.3, height: 0.25))
        manifest.mouthStripName = "strip"
        manifest.mouthStripColumns = 6
        manifest.mouthStripRows = 4
        manifest.mouthStripFrameCount = 24

        let data = try JSONEncoder().encode(manifest)
        let decoded = try JSONDecoder().decode(SpriteManifest.self, from: data)
        XCTAssertEqual(manifest, decoded)
        XCTAssertNil(decoded.mouthFrameNames)
    }

    // MARK: - BundleImageLoader (the shipping path — no shipping character
    // uses it yet, but it's the mechanism `docs/CHARACTER-ART.md` documents
    // for real art, so it gets its own direct coverage rather than only
    // being exercised indirectly through `DictionaryImageLoader`.)

    func testBundleImageLoaderReturnsNilForAnUnknownAssetName() {
        let loader = BundleImageLoader(bundle: Bundle(for: SpriteCharacterTests.self))
        XCTAssertNil(loader.image(named: "definitely-not-a-real-character-asset"))
    }

    /// A `SpriteCharacter` pointed at a real bundle that simply has no
    /// matching asset-catalog entries (this test bundle has no character
    /// art at all) must degrade exactly like the in-memory missing-art
    /// cases above — proving the fallback path works through the actual
    /// production loader, not only through the test double.
    func testSpriteCharacterWithBundleImageLoaderAndNoMatchingAssetsFallsBackGracefully() {
        let sprite = SpriteCharacter(manifest: brokenManifest(),
                                      loader: BundleImageLoader(bundle: Bundle(for: SpriteCharacterTests.self)))
        XCTAssertFalse(sprite.isArtLoaded)
        XCTAssertNotNil(renderFrame(sprite).pngData())
    }

    // MARK: - The six drawn characters still work unchanged

    /// Not a full regression sweep (that's `CharacterTests`,
    /// `IdleAnimatorTests`, `RenderMonkSnapshot`, etc., all untouched by
    /// this task) — just a direct proof that adding `drawMouth` to
    /// `Character` didn't quietly change what the default implementation
    /// draws for a real drawn character, since that default is now defined
    /// in an extension rather than inline in `CharacterView`.
    func testEveryRegisteredCharacterStillRendersThroughTheDefaultDrawMouth() {
        for character in CharacterRegistry.all {
            let image = renderFrame(character, vowel: 0.5, blinking: false)
            XCTAssertNotNil(image.pngData(), "\(character.id) failed to render")
        }
    }
}
