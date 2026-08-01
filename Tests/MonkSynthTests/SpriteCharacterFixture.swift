import UIKit
@testable import MonkSynth

/// Generates a real, working `SpriteCharacter` at test time by rendering
/// `MonkCharacter`'s own drawing code into a body image, two eye-state
/// overlays, and a set of mouth frame images — proof that the sprite path
/// is genuinely exercised, not theoretical, without needing any hand-drawn
/// art. Everything is built as in-memory `UIImage`s via
/// `DictionaryImageLoader`; nothing touches disk or an asset catalog.
///
/// Deliberately NOT added to `CharacterRegistry.all` (see that type's doc
/// comment in `Character.swift`, and `docs/CHARACTER-ART.md`) — this exists
/// for tests only, which is also why it lives under `Tests/MonkSynthTests`
/// rather than `AU/UI`: per `project.yml`, this directory is only compiled
/// into the `MonkSynthTests` target, never into `MonkSynth`/`MonkSynthAU`,
/// so there is no way for it to end up shipping by accident.
enum SpriteCharacterFixture {
    /// Canvas size for the body/eye images. Square, matching
    /// `MonkCharacter`'s own natural stage — `drawBody`/`drawEyes` are
    /// defined in stage-fraction terms assuming a square stage, so
    /// rendering them into a non-square canvas here would distort MONK'S
    /// OWN geometry, which isn't what this fixture is for. Dedicated,
    /// non-square-image coverage of `SpriteCharacter`'s own letterbox math
    /// lives in `SpriteCharacterTests` instead, using tiny synthetic
    /// images where the aspect ratio is exactly known.
    static let bodyCanvas = CGSize(width: 400, height: 400)

    /// Canvas size for each mouth frame — small and square, the way a real
    /// mouth-frame sprite cell would be, not a full body-sized canvas.
    static let mouthCanvas = CGSize(width: 160, height: 160)

    /// The character every other test builds on: 24 mouth frames, matching
    /// `CharacterView.vowelFrameCount` exactly, so `mouthFrameIndex`
    /// resolves to a 1:1 identity mapping — the "real" sprite character
    /// this task shipped to prove the path works.
    static func make() -> SpriteCharacter {
        make(frameCount: 24, id: "fixture.monk-sprite", displayName: "Monk (Sprite Fixture)")
    }

    /// Builds a fixture with an arbitrary mouth-frame count and image
    /// loader, so tests can exercise the nearest-frame mapping for counts
    /// other than 24, and the missing/corrupt-art fallback, while still
    /// going through the same real construction path as `make()` above.
    static func make(
        frameCount: Int,
        id: String = "fixture.monk-sprite",
        displayName: String = "Monk (Sprite Fixture)",
        loaderOverride: ((_ images: [String: UIImage]) -> SpriteImageLoader)? = nil
    ) -> SpriteCharacter {
        let monk = MonkCharacter()
        let manifest = SpriteManifest(
            id: id,
            displayName: displayName,
            bodyImageName: "body",
            eyeOpenImageName: "eyeOpen",
            eyeClosedImageName: "eyeClosed",
            mouthPlacement: SpriteManifest.MouthPlacement(
                centerX: monk.mouthCentre.fx,
                centerY: monk.mouthCentre.fy,
                width: monk.mouthBoxFraction,
                height: monk.mouthBoxFraction),
            mouthFrameNames: (0..<max(frameCount, 0)).map { "mouth\($0)" })

        var images: [String: UIImage] = [
            "body": renderBody(),
            "eyeOpen": renderEyes(blinking: false),
            "eyeClosed": renderEyes(blinking: true),
        ]
        for i in 0..<max(frameCount, 0) {
            let vowel = frameCount > 1 ? Float(i) / Float(frameCount - 1) : 0
            images["mouth\(i)"] = renderMouthFrame(vowel: vowel)
        }

        let loader = loaderOverride?(images) ?? DictionaryImageLoader(images: images)
        return SpriteCharacter(manifest: manifest, loader: loader)
    }

    // MARK: - Rendering MonkCharacter's own drawing code into images

    private static func renderBody() -> UIImage {
        let stage = CGRect(origin: .zero, size: bodyCanvas)
        let renderer = UIGraphicsImageRenderer(size: bodyCanvas)
        return renderer.image { _ in
            MonkCharacter().drawBody(in: stage)
        }
    }

    private static func renderEyes(blinking: Bool) -> UIImage {
        let stage = CGRect(origin: .zero, size: bodyCanvas)
        let renderer = UIGraphicsImageRenderer(size: bodyCanvas)
        return renderer.image { _ in
            MonkCharacter().drawEyes(in: stage, blinking: blinking)
        }
    }

    /// Renders a single mouth frame using `MonkCharacter`'s own
    /// `mouthShape(vowel:)` sweep, sized against the frame's own canvas
    /// width the same way `Character.drawMouth`'s default implementation
    /// sizes an oval against the stage's width — so frames genuinely differ
    /// across the vowel range, the way real per-vowel mouth art would.
    private static func renderMouthFrame(vowel: Float) -> UIImage {
        let shape = MonkCharacter().mouthShape(vowel: vowel)
        let renderer = UIGraphicsImageRenderer(size: mouthCanvas)
        return renderer.image { _ in
            let w = mouthCanvas.width * shape.w
            let h = mouthCanvas.width * shape.h
            let rect = CGRect(x: mouthCanvas.width / 2 - w / 2, y: mouthCanvas.height / 2 - h / 2,
                               width: w, height: h)
            UIColor.black.setFill()
            UIBezierPath(ovalIn: rect).fill()
        }
    }
}
