import XCTest
import AVFoundation
@testable import MonkSynth

/// Covers `RootViewController`'s presets wiring — the standalone
/// counterpart to `EditorBindingTests`'s "Presets" section. `RootViewController`,
/// `LocalEngine`, and its `presetStore` are all private, so these tests only
/// reach in through `PluginView`'s own public surface (`view as!
/// MonkSynth.PluginView`), checking that applying a preset lands on the
/// visible knobs/character exactly the way a real tap on a `PresetsView` row
/// would.
///
/// `RootViewController.viewDidLoad()` unconditionally starts a real
/// `LocalEngine` (see `LocalEngineTests`, which already proves that works in
/// this environment) — irrelevant here, since `LocalEngine.setParameter`/
/// `value(of:)` work through the lock-free parameter shadow regardless of
/// whether the underlying `AVAudioEngine` actually started.
///
/// Every type this file touches that crosses from `RootViewController`
/// (Host-only, reachable only via `@testable import MonkSynth`) is
/// explicitly qualified `MonkSynth.X` — `PluginView` and `PresetSnapshot`
/// are BOTH also directly compiled a second time straight into this test
/// target (see `project.yml`'s `MonkSynthTests` sources), so an unqualified
/// `PluginView`/`PresetSnapshot` here would resolve to that other,
/// locally-compiled type rather than the one `RootViewController` actually
/// hands out/expects — `LocalEngineTests`'s own doc comment documents the
/// exact same duplication for `Param`/`XYPadView`.
final class RootViewControllerPresetsTests: XCTestCase {

    func testApplyingFactoryPresetUpdatesOnScreenKnobs() {
        let vc = RootViewController()
        vc.loadViewIfNeeded()
        let pluginView = vc.view as! MonkSynth.PluginView

        pluginView.onApplyFactoryPreset?(0)   // Dorje

        let expected = kFactoryPresets[0].values[Int(Param.headSize.rawValue)]
        XCTAssertEqual(pluginView.controls.knob(for: .headSize)?.value ?? -1, expected, accuracy: 1e-5)
    }

    func testApplyingOutOfRangeFactoryPresetIndexDoesNotCrash() {
        let vc = RootViewController()
        vc.loadViewIfNeeded()
        let pluginView = vc.view as! MonkSynth.PluginView

        pluginView.onApplyFactoryPreset?(999)
        pluginView.onApplyFactoryPreset?(-1)
    }

    /// "Loading restores both" — applying a resolved user-preset snapshot
    /// updates both the on-screen knobs AND the visible character,
    /// synchronously (no host/observer round trip to wait on, unlike the
    /// AUv3 path).
    func testApplyingUserPresetSnapshotUpdatesKnobsAndCharacter() {
        let vc = RootViewController()
        vc.loadViewIfNeeded()
        let pluginView = vc.view as! MonkSynth.PluginView

        var params = Param.allCases.map(\.defaultValue)
        params[Int(Param.headSize.rawValue)] = 0.66
        let snapshot = MonkSynth.PresetSnapshot(params: params, characterID: "fish")

        pluginView.onApplyUserPreset?(snapshot)

        XCTAssertEqual(pluginView.controls.knob(for: .headSize)?.value ?? -1, 0.66, accuracy: 1e-6)
        XCTAssertEqual(pluginView.stage.character.id, "fish")
    }

    /// An unknown characterID falls back to monk on the standalone path too.
    func testApplyingUserPresetWithUnknownCharacterIDFallsBackToMonk() {
        let vc = RootViewController()
        vc.loadViewIfNeeded()
        let pluginView = vc.view as! MonkSynth.PluginView

        let snapshot = MonkSynth.PresetSnapshot(params: Param.allCases.map(\.defaultValue),
                                                 characterID: "some-character-that-was-removed")
        pluginView.onApplyUserPreset?(snapshot)

        XCTAssertEqual(pluginView.stage.character.id, CharacterRegistry.defaultCharacter.id)
    }

    /// `RootViewController` hands `pluginView` its own `StandalonePresetStore`
    /// (not nil, and always reporting `supportsUserPresets == true` — see
    /// that type's doc comment).
    func testPresetStoreIsWiredAndSupportsUserPresets() {
        let vc = RootViewController()
        vc.loadViewIfNeeded()
        let pluginView = vc.view as! MonkSynth.PluginView

        XCTAssertNotNil(pluginView.presetStore)
        XCTAssertEqual(pluginView.presetStore?.supportsUserPresets, true)
    }
}
