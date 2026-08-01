// Parameter-sweep tuning harness for character geometry. Not an assertion
// test — like `RenderCloseup`, it's a tool for a human to look at.
//
// Renders one named `Geometry` constant of `girl` or `oldman` across N
// values into a labelled contact sheet (with the same 10% grid overlay
// `RenderCloseup` uses) at /tmp/sweep.png. Configure it with a line-based
// `KEY=value` file at /tmp/sweep_config.txt:
//
//   cat > /tmp/sweep_config.txt <<EOF
//   SWEEP_CHARACTER=girl
//   SWEEP_CONSTANT=hairlineCenterDepth
//   SWEEP_MIN=0.15
//   SWEEP_MAX=0.50
//   SWEEP_COUNT=5
//   EOF
//   scripts/test.sh MonkSynthTests/RenderSweep && open /tmp/sweep.png
//
// (a plain file rather than environment variables: `xcodebuild test`
// launches the test bundle inside the iOS Simulator, which does not
// reliably forward the invoking shell's environment — even via the
// documented `TEST_RUNNER_`-prefix convention — into
// `ProcessInfo.processInfo.environment` on every toolchain, whereas a file
// both processes can see always works). Process environment variables of
// the same names are read too and take precedence over the file when
// present, for toolchains where they do get forwarded. Every setting is
// optional — a bare `scripts/test.sh MonkSynthTests/RenderSweep` sweeps
// the girl's hairline fix over a sensible default range, so there's always
// something to look at.
//
// The constant is selected by name, not by editing `GirlCharacter.swift`/
// `OldManCharacter.swift`: each character's `Geometry` is a `var` stored
// property (see those files' "Tunable geometry" doc comments), so this
// harness makes a copy of the base character, mutates exactly one field on
// it via `WritableKeyPath`, and renders that copy — the drawing code itself
// is never touched.
import UIKit
import XCTest
@testable import MonkSynth

final class RenderSweep: XCTestCase {
    private static let cell = CGSize(width: 440, height: 440)
    private static let labelH: CGFloat = 34

    /// `/tmp/sweep_config.txt`'s `KEY=value` lines, merged UNDER the process
    /// environment (env wins when both set the same key) — see this file's
    /// header comment for why a config file exists alongside env vars.
    private static let configFilePath = "/tmp/sweep_config.txt"

    private func resolvedConfig() -> [String: String] {
        var config: [String: String] = [:]
        if let text = try? String(contentsOfFile: Self.configFilePath, encoding: .utf8) {
            for line in text.split(separator: "\n") {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty, !trimmed.hasPrefix("#"),
                      let eq = trimmed.firstIndex(of: "=") else { continue }
                let key = String(trimmed[trimmed.startIndex..<eq]).trimmingCharacters(in: .whitespaces)
                let value = String(trimmed[trimmed.index(after: eq)...]).trimmingCharacters(in: .whitespaces)
                config[key] = value
            }
        }
        for (key, value) in ProcessInfo.processInfo.environment where key.hasPrefix("SWEEP_") {
            config[key] = value
        }
        return config
    }

    func testWriteSweep() throws {
        let env = resolvedConfig()
        let characterID = env["SWEEP_CHARACTER"] ?? "girl"
        let constant = env["SWEEP_CONSTANT"] ?? "hairlineCenterDepth"
        let count = max(2, Int(env["SWEEP_COUNT"] ?? "5") ?? 5)
        let outputPath = env["SWEEP_OUTPUT"] ?? "/tmp/sweep.png"

        switch characterID {
        case "girl":
            let (keyPath, defaultRange) = try XCTUnwrap(Self.girlConstants[constant],
                "unknown SWEEP_CONSTANT '\(constant)' for girl — known: \(Self.girlConstants.keys.sorted())")
            let values = sweepValues(env: env, defaultRange: defaultRange, count: count)
            try renderSweep(base: GirlCharacter(), keyPath: keyPath, values: values,
                             label: constant, outputPath: outputPath)
        case "oldman":
            let (keyPath, defaultRange) = try XCTUnwrap(Self.oldManConstants[constant],
                "unknown SWEEP_CONSTANT '\(constant)' for oldman — known: \(Self.oldManConstants.keys.sorted())")
            let values = sweepValues(env: env, defaultRange: defaultRange, count: count)
            try renderSweep(base: OldManCharacter(), keyPath: keyPath, values: values,
                             label: constant, outputPath: outputPath)
        case "firefighter":
            let (keyPath, defaultRange) = try XCTUnwrap(Self.fireFighterConstants[constant],
                "unknown SWEEP_CONSTANT '\(constant)' for firefighter — known: \(Self.fireFighterConstants.keys.sorted())")
            let values = sweepValues(env: env, defaultRange: defaultRange, count: count)
            try renderSweep(base: FireFighterCharacter(), keyPath: keyPath, values: values,
                             label: constant, outputPath: outputPath)
        case "cat":
            let (keyPath, defaultRange) = try XCTUnwrap(Self.catConstants[constant],
                "unknown SWEEP_CONSTANT '\(constant)' for cat — known: \(Self.catConstants.keys.sorted())")
            let values = sweepValues(env: env, defaultRange: defaultRange, count: count)
            try renderSweep(base: CatCharacter(), keyPath: keyPath, values: values,
                             label: constant, outputPath: outputPath)
        case "punk":
            let (keyPath, defaultRange) = try XCTUnwrap(Self.punkConstants[constant],
                "unknown SWEEP_CONSTANT '\(constant)' for punk — known: \(Self.punkConstants.keys.sorted())")
            let values = sweepValues(env: env, defaultRange: defaultRange, count: count)
            try renderSweep(base: PunkCharacter(), keyPath: keyPath, values: values,
                             label: constant, outputPath: outputPath)
        default:
            XCTFail("unknown SWEEP_CHARACTER '\(characterID)' — expected 'girl', 'oldman', 'firefighter', 'cat', or 'punk'")
        }
    }

    // MARK: - Known sweepable constants

    /// Every `GirlCharacter.Geometry` field worth sweeping, with a sensible
    /// default (min, max) range — named explicitly (no reflection) so a
    /// typo in `SWEEP_CONSTANT` fails loudly via `XCTUnwrap` instead of
    /// silently sweeping the wrong field.
    private static let girlConstants: [String: (WritableKeyPath<GirlCharacter, CGFloat>, ClosedRange<CGFloat>)] = [
        "hairlineCenterDepth":     (\GirlCharacter.geometry.hairlineCenterDepth, 0.10...0.55),
        "hairlineSideAngleDeg":    (\GirlCharacter.geometry.hairlineSideAngleDeg, 35...85),
        "hairlinePeakDepth":       (\GirlCharacter.geometry.hairlinePeakDepth, 0.95...1.40),
        "hairlineTopControlDepth": (\GirlCharacter.geometry.hairlineTopControlDepth, 1.10...1.70),
        "armLineWidthFraction":    (\GirlCharacter.geometry.armLineWidthFraction, 0.015...0.075),
        "handRadiusFraction":      (\GirlCharacter.geometry.handRadiusFraction, 0.03...0.08),
        "neckWidth":               (\GirlCharacter.geometry.neckWidth, 0.020...0.075),
    ]

    /// Same, for `OldManCharacter.Geometry`.
    private static let oldManConstants: [String: (WritableKeyPath<OldManCharacter, CGFloat>, ClosedRange<CGFloat>)] = [
        "sideHairOuterRadius":      (\OldManCharacter.geometry.sideHairOuterRadius, 0.95...1.60),
        "sideHairInnerTaperRadius": (\OldManCharacter.geometry.sideHairInnerTaperRadius, 0.45...0.95),
        "sideHairTopAttachRadius":  (\OldManCharacter.geometry.sideHairTopAttachRadius, 0.70...1.00),
        "sideHairTopLift":          (\OldManCharacter.geometry.sideHairTopLift, 0.10...0.60),
        "sideHairBulgeLift":        (\OldManCharacter.geometry.sideHairBulgeLift, -0.10...0.30),
        "wrinkleAlpha":             (\OldManCharacter.geometry.wrinkleAlpha, 0.10...0.65),
    ]

    /// Same, for `FireFighterCharacter.Geometry`'s neck-column fields (the
    /// cone-vs-neck defect fix).
    private static let fireFighterConstants: [String: (WritableKeyPath<FireFighterCharacter, CGFloat>, ClosedRange<CGFloat>)] = [
        "neckWidth":                (\FireFighterCharacter.geometry.neckWidth, 0.030...0.140),
        "shoulderNeckControlInset": (\FireFighterCharacter.geometry.shoulderNeckControlInset, 0.02...0.30),
    ]

    /// Same, for `CatCharacter.Geometry`'s neck-column fields.
    private static let catConstants: [String: (WritableKeyPath<CatCharacter, CGFloat>, ClosedRange<CGFloat>)] = [
        "neckWidth":                (\CatCharacter.geometry.neckWidth, 0.040...0.160),
        "shoulderNeckControlInset": (\CatCharacter.geometry.shoulderNeckControlInset, 0.02...0.30),
    ]

    /// Same, for `PunkCharacter.Geometry`'s neck-column fields.
    private static let punkConstants: [String: (WritableKeyPath<PunkCharacter, CGFloat>, ClosedRange<CGFloat>)] = [
        "neckWidth":                (\PunkCharacter.geometry.neckWidth, 0.030...0.130),
        "shoulderNeckControlInset": (\PunkCharacter.geometry.shoulderNeckControlInset, 0.02...0.30),
    ]

    // MARK: - Rendering

    /// Renders `base` across `values`, mutating a single field via
    /// `keyPath` on a fresh copy for each cell.
    private func renderSweep<C: Character>(
        base: C,
        keyPath: WritableKeyPath<C, CGFloat>,
        values: [CGFloat],
        label: String,
        outputPath: String
    ) throws {
        let cols = values.count
        let sheet = CGSize(width: Self.cell.width * CGFloat(cols), height: Self.cell.height + Self.labelH)
        let image = UIGraphicsImageRenderer(size: sheet).image { ctx in
            Theme.background.setFill()
            ctx.fill(CGRect(origin: .zero, size: sheet))

            for (i, value) in values.enumerated() {
                var character = base
                character[keyPath: keyPath] = value

                let x = Self.cell.width * CGFloat(i)
                let frame = CGRect(x: x, y: Self.labelH, width: Self.cell.width, height: Self.cell.height)

                let view = CharacterView(frame: CGRect(origin: .zero, size: Self.cell))
                view.backgroundColor = .clear
                view.character = character
                view.vowel = 0.5
                view.amplitude = 0.0
                view.noteActive = false
                ctx.cgContext.saveGState()
                ctx.cgContext.translateBy(x: x, y: Self.labelH)
                view.layer.render(in: ctx.cgContext)
                ctx.cgContext.restoreGState()

                drawGridOverlay(in: ctx.cgContext, frame: frame)

                ("\(label) = \(String(format: "%.3f", value))" as NSString).draw(
                    at: CGPoint(x: x + 6, y: 2),
                    withAttributes: [.font: UIFont.systemFont(ofSize: 13, weight: .semibold),
                                     .foregroundColor: Theme.textPrimary])
            }
        }
        let data = try XCTUnwrap(image.pngData())
        try data.write(to: URL(fileURLWithPath: outputPath))
        print("SNAPSHOT_WRITTEN \(outputPath) bytes=\(data.count)")
    }

    /// The same 10% grid overlay `RenderCloseup` draws, so alignment is
    /// measurable in every swept cell too, not just eyeballed.
    private func drawGridOverlay(in cgContext: CGContext, frame: CGRect) {
        let side = min(frame.width, frame.height)
        let stage = CGRect(x: frame.midX - side / 2, y: frame.midY - side / 2, width: side, height: side)
        cgContext.setLineWidth(0.5)
        for step in 1..<10 {
            let f = CGFloat(step) / 10.0
            let major = step == 5
            UIColor.systemTeal.withAlphaComponent(major ? 0.55 : 0.22).setStroke()
            cgContext.stroke(CGRect(x: stage.minX, y: stage.minY + stage.height * f,
                                     width: stage.width, height: 0))
            cgContext.stroke(CGRect(x: stage.minX + stage.width * f, y: stage.minY,
                                     width: 0, height: stage.height))
        }
    }

    /// Evenly spaced values across `env`'s `SWEEP_MIN`/`SWEEP_MAX` (falling
    /// back to `defaultRange`), `count` of them, inclusive of both ends.
    private func sweepValues(env: [String: String], defaultRange: ClosedRange<CGFloat>, count: Int) -> [CGFloat] {
        let lo = env["SWEEP_MIN"].flatMap { Double($0) }.map { CGFloat($0) } ?? defaultRange.lowerBound
        let hi = env["SWEEP_MAX"].flatMap { Double($0) }.map { CGFloat($0) } ?? defaultRange.upperBound
        guard count > 1 else { return [lo] }
        return (0..<count).map { i in lo + (hi - lo) * CGFloat(i) / CGFloat(count - 1) }
    }
}
