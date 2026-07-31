import XCTest
import AVFoundation
@testable import MonkSynth

/// Covers `RootViewController`'s character/preset-store wiring — the
/// standalone counterpart to `EditorBindingTests`'s "Presets / saved
/// characters" section. `RootViewController`, `LocalEngine`, and its
/// `presetStore` are all private, so these tests only reach in through
/// `PluginView`'s own public surface (`view as! MonkSynth.PluginView`),
/// checking that selecting a saved character lands on the visible
/// knobs/character exactly the way a real tap on a `CharacterDropdownView`
/// row would. Upstream's six factory presets stay reachable through
/// `MonkSynthAU.factoryPresets`/`currentPreset` for hosts (`PresetTests`),
/// but the deleted `PresetsView` was this app's only in-app UI for them —
/// there is no standalone-side equivalent to cover any more.
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

    /// Selecting a saved user entry updates both the on-screen knobs AND the
    /// visible character, synchronously (no host/observer round trip to
    /// wait on, unlike the AUv3 path) — using its OWN saved parameters, not
    /// `CharacterVoiceTable`'s voice for the face it happens to be drawn
    /// with (see the task's decision 5).
    func testSelectingAUserCharacterUpdatesKnobsAndCharacterUsingItsSavedParameters() {
        let vc = RootViewController()
        vc.loadViewIfNeeded()
        let pluginView = vc.view as! MonkSynth.PluginView

        var params = Param.allCases.map(\.defaultValue)
        params[Int(Param.headSize.rawValue)] = 0.66
        let saved = MonkSynth.UserCharacter(name: "My Patch", faceID: "fish", params: params)

        pluginView.stage.select(saved)

        XCTAssertEqual(pluginView.controls.knob(for: .headSize)?.value ?? -1, 0.66, accuracy: 1e-6)
        XCTAssertEqual(pluginView.stage.character.id, "user:My Patch")
        XCTAssertEqual(pluginView.stage.character.displayName, "My Patch")
    }

    /// `RootViewController` hands `pluginView` its own App-Group-backed
    /// `presetStore` (not nil, and always reporting `supportsUserPresets ==
    /// true` — see `SharedPresetStore`'s doc comment).
    func testPresetStoreIsWiredAndSupportsUserPresets() {
        let vc = RootViewController()
        vc.loadViewIfNeeded()
        let pluginView = vc.view as! MonkSynth.PluginView

        XCTAssertNotNil(pluginView.presetStore)
        XCTAssertEqual(pluginView.presetStore?.supportsUserPresets, true)
    }
}
