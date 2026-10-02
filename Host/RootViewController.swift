import UIKit
import CoreAudioKit

/// Standalone counterpart to `AU/AudioUnitViewController.swift`: the exact
/// same `PluginView` UI, but bound to a `LocalEngine` (its own
/// `AVAudioEngine` + `RenderContext`) instead of an `AUParameterTree` —
/// there is no host here to record automation to, so UI writes go straight
/// into the engine's parameter shadow, and there is no observer-token
/// dance to avoid a write bouncing back into the control that made it.
final class RootViewController: UIViewController {

    private let audio = LocalEngine()
    private let midi = MIDIInput()

    private var uiLink: CADisplayLink?

    /// Last vowel/amplitude actually pushed into the character view.
    /// `RenderContext` publishes these on every render callback — including
    /// silent ones — so most display-link ticks see no real change;
    /// skipping the write when nothing moved avoids re-triggering
    /// `CharacterView`'s unconditional `setNeedsDisplay()` for no reason, up
    /// to 120 times a second on ProMotion. Mirrors
    /// `AudioUnitViewController.lastPulledVowel/Amplitude`.
    private var lastPulledVowel: Float?
    private var lastPulledAmplitude: Float?

    /// The standalone app has no AU/host `fullState` to ride along with, so
    /// the character selection persists here instead — the AUv3 editor's
    /// counterpart to `MonkSynthAU.fullState["characterID"]`.
    private static let characterIDDefaultsKey = "characterID"

    /// The standalone side of the canonical, App-Group-shared preset store
    /// — see `SharedPresetStore`'s own doc comment for why this now backs
    /// both the standalone app and the AUv3 extension's presets instead of
    /// each keeping its own. `currentSnapshot` mirrors what
    /// `MonkSynthAU.saveCurrentAsUserPreset` reads from its own live
    /// `fullState`: whatever `audio` currently holds plus whatever character
    /// `pluginView.stage` is currently showing. `lazy`, not built in `init`,
    /// because it captures `self` and both `audio`/`pluginView` need to
    /// already exist — by the time anything actually calls into this (from
    /// `bind()`, in `viewDidLoad`), they do.
    ///
    /// On first access this also migrates whatever this app already had
    /// saved in `StandalonePresetStore`'s old `UserDefaults`-backed storage
    /// (pre-App-Group builds) into the shared store — see
    /// `migrateLegacyStandalonePresetsIfNeeded` below — so nobody's existing
    /// presets vanish when this ships.
    private lazy var presetStore: SharedPresetStore = {
        let store = SharedPresetStore(currentSnapshot: { [weak self] in
            guard let self else {
                return PresetSnapshot(params: Param.allCases.map(\.defaultValue),
                                       characterID: CharacterRegistry.defaultCharacter.id)
            }
            // `.faceID`, not `.id`: when the currently-showing character is
            // itself a saved user entry (`UserCharacter`), its own `id` is
            // a namespaced, non-built-in string ("user:My Patch") that
            // `CharacterRegistry` could never resolve back — `.faceID` is
            // always the real built-in face it should be saved under,
            // exactly `PresetSnapshot.characterID`'s contract. For a
            // built-in character `.faceID` is just its own `.id`, so this
            // is unchanged from before this task for that case.
            return PresetSnapshot(params: Param.allCases.map { self.audio.value(of: $0) },
                                   characterID: self.pluginView.stage.character.faceID)
        })
        Self.migrateLegacyStandalonePresetsIfNeeded(into: store)
        return store
    }()

    private static let migratedLegacyStandalonePresetsDefaultsKey = "monksynth.migratedStandaloneUserPresetsToSharedStore"

    /// "Existing presets must survive": anyone already running a build has
    /// presets in `StandalonePresetStore`'s `UserDefaults` key
    /// (`"userPresets"`, the same key that type's own `defaultsKey` uses).
    /// Reads that raw JSON directly rather than instantiating a
    /// `StandalonePresetStore` (whose stored-preset shape is private, and
    /// identical to `SharedPresetStore.StoredPreset`'s own — same field
    /// names, so `JSONDecoder` reads one straight into the other) and folds
    /// it into `store` once; `SharedPresetStore` itself tracks the "once"
    /// via `markerKey`, so this is a cheap no-op on every launch after the
    /// first successful migration.
    private static func migrateLegacyStandalonePresetsIfNeeded(into store: SharedPresetStore) {
        let legacy: [SharedPresetStore.StoredPreset]
        if let data = UserDefaults.standard.data(forKey: "userPresets"),
           let decoded = try? JSONDecoder().decode([SharedPresetStore.StoredPreset].self, from: data) {
            legacy = decoded
        } else {
            legacy = []
        }
        store.migrateLegacyPresetsIfNeeded(legacy, markerKey: migratedLegacyStandalonePresetsDefaultsKey)
    }

    private var pluginView: PluginView { view as! PluginView }

    /// Set by `startAudio()` if `LocalEngine.start()` throws. Presenting the
    /// alert is deferred to `viewDidAppear` rather than done immediately in
    /// `viewDidLoad` (where `startAudio()` itself runs, so audio setup
    /// begins as early as possible) — at `viewDidLoad` time this controller
    /// is `window.rootViewController`, but `SceneDelegate` hasn't called
    /// `makeKeyAndVisible()` yet, so `view.window` is technically installed
    /// but not yet key; presenting there risks UIKit's
    /// "not in the window hierarchy" warning and a dropped/mistimed alert.
    private var pendingStartError: Error?

    override func loadView() {
        view = PluginView(frame: CGRect(x: 0, y: 0, width: 480, height: 320))
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        bind()
        wireMIDI()
        wireAboutScreen()
        startAudio()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        startUILink()
        if let error = pendingStartError {
            pendingStartError = nil
            presentStartError(error)
        }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        uiLink?.invalidate(); uiLink = nil
    }

    deinit { uiLink?.invalidate() }

    // MARK: - UI -> engine, engine -> UI

    private func bind() {
        pluginView.pad.onParameterChange = { [weak self] param, value in
            self?.audio.setParameter(param, value)
        }
        pluginView.controls.onParameterChange = { [weak self] param, value in
            self?.audio.setParameter(param, value)
        }
        // A page that has never been shown seeds its knobs from the
        // engine's live values instead of `Param.defaultValue`.
        pluginView.controls.valueProvider = { [weak self] param in
            self?.audio.value(of: param) ?? param.defaultValue
        }
        // The currently-visible page's knobs were already constructed
        // before `valueProvider` existed (in `ControlPages.init`), so push
        // the engine's current values into them explicitly, once.
        for p in Param.allCases where !p.isHiddenFromUI {
            pluginView.controls.setValue(audio.value(of: p), for: p)
        }

        // Character selection: no AU/host `fullState` here, so restore from
        // `UserDefaults` instead — `CharacterRegistry.character(withID:)`
        // falls back to the default (monk) on first launch (no stored key)
        // or if a character was ever renamed/removed.
        let storedID = UserDefaults.standard.string(forKey: Self.characterIDDefaultsKey)
        pluginView.stage.character = CharacterRegistry.character(withID: storedID)
        // The user changed the character — an arrow step, or a dropdown
        // selection of either a built-in or a saved user entry — so it both
        // persists AND loads its sound, always; see `CharacterView.
        // onCharacterSelected`'s doc comment for why there is only one
        // callback now. `character.faceID` (never `.id`) is what gets
        // persisted: a saved user entry's own `.id` is a namespaced,
        // non-built-in string `CharacterRegistry.character(withID:)` could
        // never resolve back on the next launch's seed below, so this keeps
        // the persisted value a real built-in face id in every case — the
        // same "always a real built-in id" invariant `MonkSynthAU.
        // setCharacterID` now documents on the AUv3 side. `character.
        // savedParameters` (non-nil only for a `UserCharacter`) is what
        // actually loads: the saved patch itself, never the face's built-in
        // voice — falling back to `CharacterVoiceTable.voice(for:)` for
        // every built-in exactly as before this task. There's no
        // `AUParameterTree`/host to record the change here — same as every
        // other UI write in the standalone app (see `pad`/`controls`'
        // `onParameterChange` just above), this goes straight into
        // `LocalEngine`'s shadow. It also has to explicitly push each value
        // into `pluginView.controls` afterward, mirroring `MIDIInput`'s CC
        // and pitch-bend handlers just below: unlike the AUv3 path, nothing
        // here observes the shadow and refreshes the knobs automatically.
        pluginView.stage.onCharacterSelected = { [weak self] character in
            guard let self else { return }
            UserDefaults.standard.set(character.faceID, forKey: Self.characterIDDefaultsKey)
            let values = character.savedParameters ?? CharacterVoiceTable.voice(for: character)
            for (param, value) in values {
                self.audio.setParameter(param, value)
                self.pluginView.controls.setValue(value, for: param)
            }
        }
    }

    private func startAudio() {
        do {
            try audio.start()
        } catch {
            pendingStartError = error
        }
    }

    private func presentStartError(_ error: Error) {
        let alert = UIAlertController(
            title: NSLocalizedString("audio.start.failed.title", comment: "Audio engine failed to start"),
            message: error.localizedDescription,
            preferredStyle: .alert)
        alert.addAction(UIAlertAction(
            title: NSLocalizedString("ok", comment: "Dismiss"), style: .default))
        present(alert, animated: true)
    }

    // MARK: - MIDI -> engine, MIDI -> UI

    private func wireMIDI() {
        // Note on/off: straight through. `LocalEngine.noteOn`/`noteOff`
        // only ever queue (see `NoteEventQueue`), so this is safe to call
        // from CoreMIDI's own thread, which is what actually calls this
        // closure.
        midi.onNoteOn = { [weak self] note, velocity in
            self?.audio.noteOn(note, velocity: velocity)
        }
        midi.onNoteOff = { [weak self] note in
            self?.audio.noteOff(note)
        }
        // CC: map to the matching Param (upstream controller.cpp:454-458,
        // the same table `MonkSynthAU.internalRenderBlock`'s `0xB0` case
        // uses), write it into the engine, and mirror it onto the matching
        // on-screen knob. `setParameter` is shadow-safe from any thread;
        // touching `pluginView` is not, so that part hops to main.
        midi.onControlChange = { [weak self] cc, value in
            guard let self else { return }
            if cc == 120 || cc == 123 { self.audio.allNotesOff(); return }   // All Sound/Notes Off
            guard let addr = RenderContext.parameter(forCC: cc),
                  let param = Param(rawValue: UInt64(addr.rawValue))
            else { return }
            self.audio.setParameter(param, value)
            DispatchQueue.main.async {
                self.pluginView.controls.setValue(value, for: param)
            }
        }
        // Pitch wheel: bends pitch ±2 st on top of Tune. It springs back, so
        // it has no knob of its own and moves none.
        midi.onPitchBend = { [weak self] normalized in
            self?.audio.applyPitchBend(normalized)
        }
    }

    // MARK: - Monk animation

    private func startUILink() {
        guard uiLink == nil else { return }
        // CADisplayLink retains its target for as long as it stays added to
        // a run loop. Pointing it straight at `self` would leak this
        // controller (and the `LocalEngine`/`MIDIInput` it owns) if
        // viewDidDisappear is ever skipped. Routing through a weak-target
        // proxy — mirroring `AudioUnitViewController`'s own
        // `DisplayLinkProxy` (private to that file, so duplicated here
        // rather than reused across the AU/Host boundary) — means the link
        // can only keep the tiny proxy alive, never `self`.
        let proxy = DisplayLinkProxy(self)
        let link = CADisplayLink(target: proxy, selector: #selector(DisplayLinkProxy.tick))
        link.add(to: .main, forMode: .common)
        uiLink = link
    }

    /// Reads the render thread's published animation state. Never touches
    /// the engine or `dsp/` — plain main-thread loads of values
    /// `RenderContext.render` already wrote after the last block.
    fileprivate func pullAnimationState() {
        let vowel = audio.uiVowel
        let amplitude = audio.uiAmplitude
        if vowel != lastPulledVowel {
            pluginView.stage.vowel = vowel
            lastPulledVowel = vowel
        }
        if amplitude != lastPulledAmplitude {
            pluginView.stage.amplitude = amplitude
            lastPulledAmplitude = amplitude
        }
        // CharacterView's own `noteActive` didSet already guards on change,
        // so no need to duplicate that check here.
        pluginView.stage.noteActive = audio.uiNoteActive
    }

    // MARK: - About screen / Bluetooth MIDI

    /// The standalone app is the real entry point for the about screen's
    /// "Source code" link and its Bluetooth MIDI shortcut — unlike the AUv3
    /// extension (`AudioUnitViewController.bind()`), this app has an actual
    /// `UIApplication` to hand a URL to, and it owns the Bluetooth MIDI
    /// picker outright rather than borrowing a host's. `showsBluetoothOption`
    /// is what makes `PluginView`'s about screen show that button at all —
    /// it defaults to false so the AUv3 editor never offers it when embedded
    /// in someone else's host. This replaces the small temporary corner
    /// button that used to be the only way to reach Bluetooth MIDI; the
    /// about screen's ⓘ button is the real, permanent entry point now.
    private func wireAboutScreen() {
        pluginView.showsBluetoothOption = true
        pluginView.onOpenURL = { url in UIApplication.shared.open(url) }
        pluginView.onBluetoothMIDI = { [weak self] in self?.presentBluetoothMIDI() }
        // User presets: `presetStore` (this app's own App-Group-backed
        // storage — see that property's doc comment) is handed straight to
        // `pluginView`, exactly like `AudioUnitViewController.bind()` hands
        // over its `MonkSynthAU`. `CharacterDropdownView` is the only place
        // that lists, saves, and deletes saved entries now — selecting one
        // is handled uniformly with a built-in character by `bind()`'s own
        // `onCharacterSelected` closure above (via `Character.
        // savedParameters`), so there is nothing else to wire here.
        pluginView.presetStore = presetStore
    }

    func presentBluetoothMIDI() {
        let central = CABTMIDICentralViewController()
        central.navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .done, target: self, action: #selector(dismissBluetoothMIDI))
        let nav = UINavigationController(rootViewController: central)
        present(nav, animated: true)
    }

    @objc private func dismissBluetoothMIDI() {
        dismiss(animated: true)
    }
}

/// Breaks the strong retain `CADisplayLink(target:selector:)` would
/// otherwise put on the view controller. See `startUILink`.
private final class DisplayLinkProxy: NSObject {
    private weak var owner: RootViewController?
    init(_ owner: RootViewController) { self.owner = owner }
    @objc func tick() { owner?.pullAnimationState() }
}
