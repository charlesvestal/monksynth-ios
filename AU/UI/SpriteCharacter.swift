import UIKit

/// A character's art, described as data rather than Swift code — what
/// `SpriteCharacter` renders from. See `docs/CHARACTER-ART.md` for the
/// artist-facing version of everything below.
///
/// `Codable` + `Equatable` so a character can be authored, stored, and
/// round-tripped as JSON (or any other `Codable` format) with no Swift
/// changes at all: adding a character becomes "add a manifest value plus
/// some images", not "write a new `Character` conformer". That is the
/// whole point of this type existing separately from `SpriteCharacter`
/// itself, which only knows how to *render* a manifest, not author one.
struct SpriteManifest: Codable, Equatable {

    /// Where the mouth sits within the body image, and how big it is —
    /// mirrors `Character.mouthCentre`/`mouthBoxFraction`, but expressed as
    /// fractions of the BODY IMAGE's own canvas (0...1 on both axes)
    /// instead of the stage, so it survives any render size and any body
    /// image resolution unchanged. `SpriteCharacter` converts this into
    /// stage coordinates at draw time using the body image's letterboxed
    /// placement (see `SpriteCharacter.letterboxRect`).
    struct MouthPlacement: Codable, Equatable {
        /// Centre of the mouth box, as a fraction of the body image's width
        /// (`centerX`) and height (`centerY`).
        var centerX: CGFloat
        var centerY: CGFloat
        /// Size of the mouth box, as a fraction of the body image's width
        /// (`width`) and height (`height`). A mouth frame is letterboxed
        /// (aspect-fit, never stretched) into this box, so the box need not
        /// share the frame's own aspect ratio.
        var width: CGFloat
        var height: CGFloat
    }

    /// Stable and persisted exactly like `Character.id` — see that
    /// property's doc comment in `Character.swift`; the same
    /// never-change-it-once-shipped rule applies here.
    var id: String
    var displayName: String

    /// Resolved by whatever `SpriteImageLoader` the character is
    /// constructed with — an asset-catalog name for shipping art
    /// (`BundleImageLoader`), or an arbitrary key into an in-memory image
    /// set for generated/test art (`DictionaryImageLoader`). The manifest
    /// itself doesn't know or care which.
    var bodyImageName: String

    /// Full-body-canvas overlays, composited on top of the body at the
    /// same placement, painting only the eye area (transparent everywhere
    /// else) — see `docs/CHARACTER-ART.md` for why eyes are a swap rather
    /// than a sub-rect like the mouth. Exactly one is drawn per frame,
    /// chosen by `CharacterView`'s blink state.
    var eyeOpenImageName: String
    var eyeClosedImageName: String

    var mouthPlacement: MouthPlacement

    /// Mouth frames, in vowel order (index 0 = vowel 0, last index = vowel
    /// 1). Populate this for the "N separate images" packaging.
    var mouthFrameNames: [String]? = nil

    /// Mouth frames as one grid/strip sheet instead, sliced left-to-right
    /// then top-to-bottom into `mouthStripColumns` × `mouthStripRows`
    /// cells, of which the first `mouthStripFrameCount` (in that same
    /// reading order) are used, in vowel order. Populate these four
    /// together for the "single strip" packaging; leave `mouthFrameNames`
    /// nil. If both are populated, `mouthFrameNames` wins (see
    /// `SpriteCharacter.resolveMouthFrames`).
    var mouthStripName: String? = nil
    var mouthStripColumns: Int? = nil
    var mouthStripRows: Int? = nil
    var mouthStripFrameCount: Int? = nil
}

/// Resolves a named image for a `SpriteCharacter`. Kept as a protocol
/// rather than hardcoding `UIImage(named:)` so the SAME `SpriteCharacter`
/// type can draw shipping art out of an asset catalog (`BundleImageLoader`)
/// and generated/in-memory art with no asset catalog at all
/// (`DictionaryImageLoader`, used by the test fixture in
/// `Tests/MonkSynthTests/SpriteCharacterFixture.swift`) — the rendering and
/// fallback logic below never needs to know which.
protocol SpriteImageLoader {
    func image(named name: String) -> UIImage?
}

/// The shipping loader: looks images up by name in a given bundle's asset
/// catalog. Takes the bundle explicitly rather than defaulting to
/// `Bundle.main` — `AU/UI` is compiled into both the host app and the
/// `MonkSynthAU` app extension (see `project.yml`), and `Bundle.main`
/// resolves differently inside each, so the caller constructing a
/// `SpriteCharacter` is the one who knows which bundle its art actually
/// lives in.
struct BundleImageLoader: SpriteImageLoader {
    let bundle: Bundle
    func image(named name: String) -> UIImage? {
        UIImage(named: name, in: bundle, compatibleWith: nil)
    }
}

/// An in-memory loader backed by a plain dictionary — no bundle, no disk.
/// Exists for art that's generated programmatically rather than
/// hand-authored (the fixture this task shipped to prove the sprite path
/// works), but is generic enough for any other in-memory use.
struct DictionaryImageLoader: SpriteImageLoader {
    let images: [String: UIImage]
    func image(named name: String) -> UIImage? { images[name] }
}

/// A `Character` conformance backed by images instead of drawing code, so
/// hand-made art can be dropped in without writing `UIBezierPath`s. Renders
/// a `SpriteManifest`'s body/eye/mouth images, letterboxed into the stage
/// exactly like the six drawn characters fill it (never stretched) — see
/// `letterboxRect`.
///
/// **Degradation.** If ANY required image fails to load or decode — missing
/// name, corrupt data, or a decoded image with zero size — the WHOLE
/// character (body, eyes, and mouth together, never just one of them)
/// falls back to drawing as `MonkCharacter` instead. A partially-loaded
/// sprite (a good body but missing eyes, say) is deliberately not
/// partially rendered: a real body with `MonkCharacter`'s drawn eyes
/// stitched on top would look broken in a more confusing way than a clean,
/// whole-character fallback. `isArtLoaded` reports which case a given
/// instance is in, for callers/tests that want to tell "drawing its own
/// art" from "silently drawing the monk fallback" without inspecting
/// pixels. See `docs/CHARACTER-ART.md` for the artist-facing version.
struct SpriteCharacter: Character {
    let manifest: SpriteManifest
    private let art: LoadedArt?

    /// What every sprite character falls back to, wholesale, when its own
    /// art can't be used. Monk specifically because it's the roster's
    /// default and always available — see the type doc comment.
    static let fallback: Character = MonkCharacter()

    init(manifest: SpriteManifest, loader: SpriteImageLoader) {
        self.manifest = manifest
        self.art = LoadedArt(manifest: manifest, loader: loader)
    }

    /// `true` once every required image loaded and decoded successfully —
    /// `false` means every draw call below is silently drawing the monk
    /// fallback instead. See the type doc comment.
    var isArtLoaded: Bool { art != nil }

    var id: String { manifest.id }
    var displayName: String { manifest.displayName }

    func drawBody(in stage: CGRect) {
        guard let art else { return Self.fallback.drawBody(in: stage) }
        Self.draw(art.body, letterboxedIn: stage)
    }

    func drawEyes(in stage: CGRect, blinking: Bool) {
        guard let art else { return Self.fallback.drawEyes(in: stage, blinking: blinking) }
        Self.draw(blinking ? art.eyeClosed : art.eyeOpen, letterboxedIn: stage)
    }

    func drawMouth(in stage: CGRect, vowel: Float, amplitudeBoost: CGFloat) {
        guard let art else {
            return Self.fallback.drawMouth(in: stage, vowel: vowel, amplitudeBoost: amplitudeBoost)
        }
        let index = Self.mouthFrameIndex(forVowel: vowel, frameCount: art.mouthFrames.count)
        let frame = art.mouthFrames[index]

        // The mouth placement is a fraction of the BODY IMAGE's own canvas
        // (see `SpriteManifest.MouthPlacement`), so it has to be mapped
        // through the body's own letterboxed rect, not the raw stage — a
        // non-square body image doesn't fill the square stage edge to
        // edge, and the mouth has to track the body's actual pixels, not
        // the stage's.
        let bodyRect = Self.letterboxRect(for: art.body.size, in: stage)
        let mp = manifest.mouthPlacement
        // `amplitudeBoost` scales both axes by the same factor — mirrors
        // the drawn characters' amplitude swell (see
        // `Character.drawMouth`'s default implementation) without
        // distorting the frame image's own aspect ratio, which scaling
        // only height would do here.
        let boxW = bodyRect.width * mp.width * amplitudeBoost
        let boxH = bodyRect.height * mp.height * amplitudeBoost
        let center = CGPoint(x: bodyRect.minX + mp.centerX * bodyRect.width,
                              y: bodyRect.minY + mp.centerY * bodyRect.height)
        let box = CGRect(x: center.x - boxW / 2, y: center.y - boxH / 2, width: boxW, height: boxH)
        Self.draw(frame, letterboxedIn: box)
    }

    // MARK: - `Character`'s drawn-character members
    //
    // Never actually consulted for a `SpriteCharacter` — `drawMouth` above
    // is overridden, so `Character`'s default implementation of it (the one
    // every drawn character relies on) never runs for this type. Still
    // given real, manifest-derived values rather than inert placeholders,
    // so a `SpriteCharacter` stays meaningful to any code that inspects a
    // `Character`'s mouth geometry generically without knowing whether
    // it's drawn or image-backed.
    func mouthShape(vowel: Float) -> (w: CGFloat, h: CGFloat) {
        (manifest.mouthPlacement.width, manifest.mouthPlacement.height)
    }
    var mouthCentre: (fx: CGFloat, fy: CGFloat) {
        (manifest.mouthPlacement.centerX, manifest.mouthPlacement.centerY)
    }
    var mouthBoxFraction: CGFloat {
        max(manifest.mouthPlacement.width, manifest.mouthPlacement.height)
    }

    // MARK: - Geometry
    //
    // `internal`, not `private`, so tests can verify the letterbox/frame
    // math directly (pure geometry, no rendering needed) rather than only
    // indirectly through rendered pixels.

    /// The centred, aspect-preserving rect `imageSize` occupies when
    /// letterboxed into `stage` — the same idea as
    /// `AVLayerVideoGravity.resizeAspect`, done by hand so it works
    /// identically in a plain geometry test and in the live view (no
    /// `CALayer`/`AVPlayerLayer` needed). Falls back to `stage` itself for
    /// a degenerate size, so a caller never has to guard division by zero.
    static func letterboxRect(for imageSize: CGSize, in stage: CGRect) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0, stage.width > 0, stage.height > 0 else {
            return stage
        }
        let scale = min(stage.width / imageSize.width, stage.height / imageSize.height)
        let w = imageSize.width * scale
        let h = imageSize.height * scale
        return CGRect(x: stage.midX - w / 2, y: stage.midY - h / 2, width: w, height: h)
    }

    /// Nearest-frame mapping from a (already quantised) vowel position to
    /// an index into a `frameCount`-length mouth frame array. Uses the same
    /// "scale onto the step count, then round" shape as
    /// `CharacterView.quantisedVowel` itself, so it lands exactly on frame
    /// 0 at vowel 0 and `frameCount - 1` at vowel 1 — including when
    /// `frameCount` is `CharacterView.vowelFrameCount` (24) itself, where
    /// this becomes a 1:1 identity mapping, and when it's smaller, where
    /// several adjacent quantised vowel steps land on the same nearest
    /// frame rather than reading out of bounds.
    static func mouthFrameIndex(forVowel vowel: Float, frameCount: Int) -> Int {
        guard frameCount > 1 else { return 0 }
        let clamped = min(max(vowel, 0), 1)
        let steps = Float(frameCount - 1)
        let idx = Int((clamped * steps).rounded())
        return min(max(idx, 0), frameCount - 1)
    }

    private static func draw(_ image: UIImage, letterboxedIn rect: CGRect) {
        image.draw(in: letterboxRect(for: image.size, in: rect))
    }

    /// Slices `manifest`'s mouth frames into an ordered `[UIImage]` via
    /// whichever of the two packagings (`mouthFrameNames` vs the
    /// `mouthStrip*` quartet) is populated — see `SpriteManifest`'s doc
    /// comment. Returns `nil` (triggering the whole-character fallback,
    /// same as any other missing/corrupt image — see the type doc comment)
    /// if neither is usably populated, if any named frame fails to load,
    /// or if the strip's own geometry doesn't check out.
    static func resolveMouthFrames(manifest: SpriteManifest, loader: SpriteImageLoader) -> [UIImage]? {
        if let names = manifest.mouthFrameNames, !names.isEmpty {
            var frames: [UIImage] = []
            frames.reserveCapacity(names.count)
            for name in names {
                guard let image = loader.image(named: name), image.size.width > 0, image.size.height > 0 else {
                    return nil
                }
                frames.append(image)
            }
            return frames
        }

        guard let stripName = manifest.mouthStripName,
              let columns = manifest.mouthStripColumns, columns > 0,
              let rows = manifest.mouthStripRows, rows > 0,
              let frameCount = manifest.mouthStripFrameCount, frameCount > 0,
              frameCount <= columns * rows,
              let strip = loader.image(named: stripName), strip.size.width > 0, strip.size.height > 0,
              let cgStrip = strip.cgImage
        else { return nil }

        let cellW = cgStrip.width / columns
        let cellH = cgStrip.height / rows
        guard cellW > 0, cellH > 0 else { return nil }

        var frames: [UIImage] = []
        frames.reserveCapacity(frameCount)
        for i in 0..<frameCount {
            let col = i % columns
            let row = i / columns
            let rect = CGRect(x: col * cellW, y: row * cellH, width: cellW, height: cellH)
            guard let cropped = cgStrip.cropping(to: rect) else { return nil }
            frames.append(UIImage(cgImage: cropped, scale: strip.scale, orientation: strip.imageOrientation))
        }
        return frames
    }

    /// Everything needed to draw a `SpriteCharacter`, only constructed once
    /// every required image has loaded and decoded successfully — its mere
    /// existence (vs `SpriteCharacter.art` being `nil`) IS the
    /// loaded/fallback distinction.
    private struct LoadedArt {
        let body: UIImage
        let eyeOpen: UIImage
        let eyeClosed: UIImage
        let mouthFrames: [UIImage]

        init?(manifest: SpriteManifest, loader: SpriteImageLoader) {
            func load(_ name: String) -> UIImage? {
                guard let image = loader.image(named: name), image.size.width > 0, image.size.height > 0 else {
                    return nil
                }
                return image
            }
            guard let body = load(manifest.bodyImageName),
                  let eyeOpen = load(manifest.eyeOpenImageName),
                  let eyeClosed = load(manifest.eyeClosedImageName),
                  let mouthFrames = SpriteCharacter.resolveMouthFrames(manifest: manifest, loader: loader),
                  !mouthFrames.isEmpty
            else { return nil }
            self.body = body
            self.eyeOpen = eyeOpen
            self.eyeClosed = eyeClosed
            self.mouthFrames = mouthFrames
        }
    }
}
