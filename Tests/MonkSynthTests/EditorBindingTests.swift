import AVFoundation
import XCTest
@testable import MonkSynth

final class EditorBindingTests: XCTestCase {

    private func makeDescription() -> AudioComponentDescription {
        AudioComponentDescription(
            componentType: kAudioUnitType_MusicDevice,
            componentSubType: 0x4D6E6B73,          // 'Mnks'
            componentManufacturer: 0x5673746C,     // 'Vstl'
            componentFlags: 0, componentFlagsMask: 0)
    }

    /// `AUParameterTree`'s token-based observer notifications are delivered
    /// asynchronously on a background thread and coalesced (confirmed
    /// empirically: on the order of tens of milliseconds even for a single
    /// write, versus `implementorValueObserver`, which fires synchronously
    /// and is what `ShadowTests`/`PresetTests` rely on). Anything that
    /// asserts on an observer having fired must poll the run loop rather
    /// than check once immediately after the write.
    private func pollUntil(timeout: TimeInterval = 3.0, _ condition: () -> Bool) {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }
    }

    // MARK: - preferredContentSize / host-supplied rect

    func testPreferredContentSizeIs480x320() {
        let vc = AudioUnitViewController()
        vc.loadViewIfNeeded()
        XCTAssertEqual(vc.preferredContentSize, CGSize(width: 480, height: 320))
    }

    /// An AUv3 host can hand the view any rect at all (see `PluginView`'s
    /// own doc comment). This isn't a layout test — `LayoutTests` already
    /// covers the zone arithmetic — it's just confirming the view controller
    /// doesn't crash under an extreme host-supplied frame and doesn't let
    /// that frame leak into its own stated preference.
    func testViewSurvivesHostSuppliedRect() {
        let vc = AudioUnitViewController()
        vc.loadViewIfNeeded()
        vc.view.frame = CGRect(x: 0, y: 0, width: 40, height: 4000)
        vc.view.layoutIfNeeded()
        vc.view.frame = CGRect(x: 0, y: 0, width: 4000, height: 40)
        vc.view.layoutIfNeeded()
        XCTAssertEqual(vc.preferredContentSize, CGSize(width: 480, height: 320))
    }

    // MARK: - createAudioUnit

    func testCreateAudioUnitReturnsMonkSynthAUAndRetainsIt() throws {
        let vc = AudioUnitViewController()
        let unit = try vc.createAudioUnit(with: makeDescription())
        XCTAssertTrue(unit is MonkSynthAU)
        XCTAssertTrue(vc.au === (unit as! MonkSynthAU))
    }

    // MARK: - UI -> AU

    func testKnobWriteReachesParameterTree() throws {
        let vc = AudioUnitViewController()
        let unit = try vc.createAudioUnit(with: makeDescription()) as! MonkSynthAU
        vc.loadViewIfNeeded()   // drives viewDidLoad -> bind()

        let pluginView = vc.view as! PluginView
        pluginView.controls.onParameterChange?(.vowel, 0.73)

        let value = unit.parameterTree?.parameter(withAddress: Param.vowel.rawValue)?.value
        XCTAssertEqual(value ?? -1, 0.73, accuracy: 1e-6)
    }

    func testPadWriteReachesParameterTree() throws {
        let vc = AudioUnitViewController()
        let unit = try vc.createAudioUnit(with: makeDescription()) as! MonkSynthAU
        vc.loadViewIfNeeded()

        let pluginView = vc.view as! PluginView
        pluginView.pad.onParameterChange?(.xyPitchTarget, 0.2)
        pluginView.pad.onParameterChange?(.xyNoteOn, 1.0)

        let pitch = unit.parameterTree?.parameter(withAddress: Param.xyPitchTarget.rawValue)?.value
        let noteOn = unit.parameterTree?.parameter(withAddress: Param.xyNoteOn.rawValue)?.value
        XCTAssertEqual(pitch ?? -1, 0.2, accuracy: 1e-6)
        XCTAssertEqual(noteOn ?? -1, 1.0, accuracy: 1e-6)
    }

    // MARK: - Character selection

    /// `bind()` seeds the visible `CharacterView` from whatever the AU
    /// already holds — covers a session restored (`fullState` set) before
    /// the editor was ever bound.
    func testBindSeedsCharacterViewFromAUsCharacterID() throws {
        let vc = AudioUnitViewController()
        let unit = try vc.createAudioUnit(with: makeDescription()) as! MonkSynthAU
        unit.setCharacterID("fish")

        vc.loadViewIfNeeded()   // drives viewDidLoad -> bind()

        let pluginView = vc.view as! PluginView
        XCTAssertEqual(pluginView.stage.character.id, "fish")
    }

    /// UI -> AU: stepping the character forward (the "next character" arrow)
    /// must write the new selection back into the AU (so it round-trips via
    /// `fullState`).
    func testStepForwardWritesCharacterIDBackToAU() throws {
        let vc = AudioUnitViewController()
        let unit = try vc.createAudioUnit(with: makeDescription()) as! MonkSynthAU
        vc.loadViewIfNeeded()

        let pluginView = vc.view as! PluginView
        XCTAssertEqual(unit.characterID, "monk")

        pluginView.stage.stepForward()

        XCTAssertEqual(unit.characterID, "fish")
        XCTAssertEqual(pluginView.stage.character.id, "fish")
    }

    /// UI -> AU: a forward step changes the character AND loads its voice —
    /// the same single `onCharacterSelected` callback every change route
    /// fires now (see that property's doc comment: there is no longer a
    /// "character only" mode to distinguish).
    func testStepForwardAlsoLoadsItsVoiceIntoTheParameterTree() throws {
        let vc = AudioUnitViewController()
        let unit = try vc.createAudioUnit(with: makeDescription()) as! MonkSynthAU
        vc.loadViewIfNeeded()

        let pluginView = vc.view as! PluginView
        XCTAssertEqual(pluginView.stage.character.id, "monk")

        // Dial headSize somewhere fish's own voice does NOT use, so the
        // assertion below can only pass if the step actually rewrote it.
        unit.parameterTree?.parameter(withAddress: Param.headSize.rawValue)?
            .setValue(0.5, originator: nil)

        pluginView.stage.stepForward()   // monk -> fish

        XCTAssertEqual(pluginView.stage.character.id, "fish")
        for (param, value) in CharacterVoiceTable.fish {
            let treeValue = unit.parameterTree?.parameter(withAddress: param.rawValue)?.value
            XCTAssertEqual(treeValue ?? -1, value, accuracy: 1e-6,
                            "\(param.identifier) did not load fish's voice")
        }
        // Live performance/routing parameters must be left exactly alone.
        let routing = unit.parameterTree?.parameter(withAddress: Param.pitchBendRouting.rawValue)?.value
        XCTAssertEqual(routing ?? -1, Param.pitchBendRouting.defaultValue, accuracy: 1e-6)
    }

    /// Symmetric coverage for `stepBackward()` (the "previous character"
    /// arrow) — stepping backward from monk wraps straight to the last
    /// entry (cow), and that also loads cow's voice.
    func testStepBackwardAlsoLoadsItsVoiceIntoTheParameterTree() throws {
        let vc = AudioUnitViewController()
        let unit = try vc.createAudioUnit(with: makeDescription()) as! MonkSynthAU
        vc.loadViewIfNeeded()

        let pluginView = vc.view as! PluginView
        XCTAssertEqual(pluginView.stage.character.id, "monk")

        pluginView.stage.stepBackward()   // monk -> cow (wraps backward)

        XCTAssertEqual(pluginView.stage.character.id, "cow")
        XCTAssertEqual(unit.characterID, "cow")
        for (param, value) in CharacterVoiceTable.cow {
            let treeValue = unit.parameterTree?.parameter(withAddress: param.rawValue)?.value
            XCTAssertEqual(treeValue ?? -1, value, accuracy: 1e-6,
                            "\(param.identifier) did not load cow's voice")
        }
    }

    /// UI -> AU: the picker's route (`select(_:)`, jumping straight to a
    /// given character rather than the adjacent one) must load its voice
    /// exactly the same way the arrows do — "either route" per the task.
    func testSelectingCharacterViaPickerRouteAlsoLoadsItsVoiceIntoTheParameterTree() throws {
        let vc = AudioUnitViewController()
        let unit = try vc.createAudioUnit(with: makeDescription()) as! MonkSynthAU
        vc.loadViewIfNeeded()

        let pluginView = vc.view as! PluginView
        pluginView.stage.select(UnicornCharacter())

        XCTAssertEqual(pluginView.stage.character.id, "unicorn")
        XCTAssertEqual(unit.characterID, "unicorn")
        for (param, value) in CharacterVoiceTable.unicorn {
            let treeValue = unit.parameterTree?.parameter(withAddress: param.rawValue)?.value
            XCTAssertEqual(treeValue ?? -1, value, accuracy: 1e-6,
                            "\(param.identifier) did not load unicorn's voice")
        }
    }

    /// The task requires voice-load writes to go through the parameter tree
    /// — never straight into the shadow — specifically so a real host sees
    /// and can record/undo them. Proven the same way
    /// `testWriteWithMatchingOriginatorDoesNotBounceBackToThatObserver`
    /// proves the originator mechanism: an independent second observer
    /// registration, standing in for a real host's automation recorder,
    /// must see the change.
    func testCharacterVoiceChangeIsVisibleToAnIndependentHostObserver() throws {
        let vc = AudioUnitViewController()
        let unit = try vc.createAudioUnit(with: makeDescription()) as! MonkSynthAU
        vc.loadViewIfNeeded()
        let pluginView = vc.view as! PluginView
        let tree = try XCTUnwrap(unit.parameterTree)

        var hostObservedCount = 0
        let hostToken = tree.token(byAddingParameterObserver: { _, _ in hostObservedCount += 1 })
        defer { tree.removeParameterObserver(hostToken) }

        pluginView.stage.stepForward()   // monk -> fish

        pollUntil { hostObservedCount > 0 }
        XCTAssertGreaterThan(hostObservedCount, 0,
            "an independent host observer must see the parameter writes a step's voice load produces")
    }

    /// AU -> UI: a `fullState` load reaching in *after* the editor is
    /// already bound and showing (e.g. a host applying a saved session to
    /// an already-open editor) must still update the visible character.
    func testLaterFullStateLoadUpdatesTheVisibleCharacter() throws {
        let vc = AudioUnitViewController()
        let unit = try vc.createAudioUnit(with: makeDescription()) as! MonkSynthAU
        vc.loadViewIfNeeded()

        let pluginView = vc.view as! PluginView
        XCTAssertEqual(pluginView.stage.character.id, "monk")

        unit.fullState = ["characterID": "unicorn"]

        // `onCharacterIDChange`'s handler hops to main via `DispatchQueue.
        // main.async` (defensive: `fullState` isn't guaranteed to be set
        // from the main thread), so — like the AUParameter observer tests
        // above — poll rather than asserting immediately.
        pollUntil { pluginView.stage.character.id == "unicorn" }
        XCTAssertEqual(pluginView.stage.character.id, "unicorn")
    }

    // MARK: - AU -> UI

    /// Host automation (an observer-token-less write) must reach the
    /// matching on-screen knob. `.vowel` lives on the MAIN page, which is
    /// shown by default, so no page switch is needed to see it update.
    func testHostAutomationUpdatesMatchingKnob() throws {
        let vc = AudioUnitViewController()
        let unit = try vc.createAudioUnit(with: makeDescription()) as! MonkSynthAU
        vc.loadViewIfNeeded()

        let pluginView = vc.view as! PluginView
        XCTAssertNotNil(pluginView.controls.knob(for: .vowel))

        let param = unit.parameterTree!.parameter(withAddress: Param.vowel.rawValue)!
        param.setValue(0.11, originator: nil)   // simulate host-side automation

        // The observer fires on a background thread after a short coalescing
        // delay, then hops to main before touching the knob; poll for both.
        pollUntil { abs((pluginView.controls.knob(for: .vowel)?.value ?? -1) - 0.11) < 1e-6 }

        XCTAssertEqual(pluginView.controls.knob(for: .vowel)?.value ?? -1, 0.11, accuracy: 1e-6)
    }

    // MARK: - Originator-token self-filtering

    /// This is the mechanism `bind()` relies on to avoid a write this
    /// controller just made bouncing straight back into the knob that
    /// produced it: `AUParameterTree` skips re-delivering a change to the
    /// observer whose own token was passed as `originator`, while still
    /// notifying every other observer (a real host's automation recorder,
    /// or — here — a second, independent registration standing in for one).
    /// Verified empirically: the observer with a matching `originator`
    /// token never fires for that write, even after a generous poll; a
    /// differently-tokened (or nil-originator) write reaches every
    /// registered observer.
    func testWriteWithMatchingOriginatorDoesNotBounceBackToThatObserver() throws {
        let au = try MonkSynthAU(componentDescription: makeDescription())
        let tree = try XCTUnwrap(au.parameterTree)
        let param = try XCTUnwrap(tree.parameter(withAddress: Param.headSize.rawValue))

        var selfCallCount = 0
        let selfToken = tree.token(byAddingParameterObserver: { _, _ in selfCallCount += 1 })
        var otherCallCount = 0
        let otherToken = tree.token(byAddingParameterObserver: { _, _ in otherCallCount += 1 })
        defer {
            tree.removeParameterObserver(selfToken)
            tree.removeParameterObserver(otherToken)
        }

        param.setValue(0.42, originator: selfToken)
        pollUntil { otherCallCount > 0 }
        XCTAssertEqual(selfCallCount, 0,
                        "the observer whose own token originated the write must not be re-notified")
        XCTAssertEqual(otherCallCount, 1,
                        "a different observer (e.g. the host) must still see the change")

        param.setValue(0.77, originator: nil)
        pollUntil { selfCallCount > 0 }
        XCTAssertEqual(selfCallCount, 1, "a write with no originator must reach every observer")
        XCTAssertEqual(otherCallCount, 2)
    }

    // MARK: - Safe before allocateRenderResources

    func testUIAnimationAccessorsAreSafeBeforeAllocateRenderResources() throws {
        let au = try MonkSynthAU(componentDescription: makeDescription())
        XCTAssertEqual(au.uiVowel, 0.5, accuracy: 1e-6)
        XCTAssertEqual(au.uiAmplitude, 0, accuracy: 1e-6)
        XCTAssertFalse(au.uiNoteActive)
    }

    // MARK: - Teardown

    func testControllerDeallocatesWithoutCrashEvenIfNeverAppeared() throws {
        weak var weakVC: AudioUnitViewController?
        try autoreleasepool {
            let vc = AudioUnitViewController()
            _ = try vc.createAudioUnit(with: makeDescription())
            vc.loadViewIfNeeded()
            weakVC = vc
        }
        XCTAssertNil(weakVC, "nothing should be left holding the controller")
    }

    /// Regression test for the `CADisplayLink` retain-cycle fix: starting
    /// the UI link (via `viewDidAppear`) and then dropping the controller
    /// WITHOUT a matching `viewDidDisappear` — a host is not guaranteed to
    /// call it in every teardown path — must not leak the controller. With
    /// `CADisplayLink(target: self, ...)` instead of the weak-target proxy,
    /// this would fail: the link stays attached to the run loop and keeps
    /// the whole editor (including the `MonkSynthAU` it retains) alive.
    func testControllerDeallocatesEvenWithDisplayLinkRunningAndNoDisappear() throws {
        weak var weakVC: AudioUnitViewController?
        try autoreleasepool {
            let vc = AudioUnitViewController()
            _ = try vc.createAudioUnit(with: makeDescription())
            vc.loadViewIfNeeded()
            vc.viewDidAppear(false)   // starts the display link
            weakVC = vc
        }
        XCTAssertNil(weakVC, "a running CADisplayLink must not keep the view controller alive")
    }

    /// The observer token is meant to be removed in `deinit`. There's no
    /// public way to ask an `AUParameterTree` how many observers are
    /// registered, so this proves the cleanup path is safe the way it's
    /// actually exercised: the AU (and its tree) outlive the controller,
    /// and a later automation write against that tree — after the
    /// controller, and its token, are long gone — must not crash.
    func testObserverTokenCleanupDoesNotCrashLaterWrites() throws {
        var capturedUnit: MonkSynthAU!
        weak var weakVC: AudioUnitViewController?
        try autoreleasepool {
            let vc = AudioUnitViewController()
            let unit = try vc.createAudioUnit(with: makeDescription()) as! MonkSynthAU
            vc.loadViewIfNeeded()
            capturedUnit = unit
            weakVC = vc
        }
        XCTAssertNil(weakVC)

        let param = try XCTUnwrap(capturedUnit.parameterTree?.parameter(withAddress: Param.vowel.rawValue))
        param.setValue(0.5, originator: nil)   // must not crash
    }

    // MARK: - Presets / saved characters
    //
    // Upstream's six factory presets stay reachable through `MonkSynthAU.
    // factoryPresets`/`currentPreset` for a HOST's own preset UI (see
    // `PresetTests`), but this app's own UI no longer surfaces them at all
    // — the deleted `PresetsView` used to; now `CharacterDropdownView` is
    // the only in-app picker, and it lists only characters (built-in plus
    // the user's own saved entries), never the factory bank. See the task:
    // "I want only the characters as presets."

    /// `bind()` hands `MonkSynthAU` itself to `pluginView` as the character
    /// dropdown's `PresetStoring` — it already conforms (see `MonkSynthAU`'s
    /// "User presets" section).
    func testBindWiresTheAUAsThePresetStore() throws {
        let vc = AudioUnitViewController()
        let unit = try vc.createAudioUnit(with: makeDescription()) as! MonkSynthAU
        vc.loadViewIfNeeded()

        let pluginView = vc.view as! PluginView
        XCTAssertTrue(pluginView.presetStore === unit)
    }

    /// Selecting a saved user entry (a `UserCharacter`) through the same
    /// `stage.select(_:)` route the dropdown uses must apply ITS OWN saved
    /// parameters — never `CharacterVoiceTable`'s voice for the face it
    /// happens to be drawn with (see the task's decision 5: a saved entry
    /// whose face is "cow" must not get the cow voice stomped over it).
    func testSelectingAUserCharacterAppliesItsSavedParametersNotTheFacesVoice() throws {
        let vc = AudioUnitViewController()
        let unit = try vc.createAudioUnit(with: makeDescription()) as! MonkSynthAU
        vc.loadViewIfNeeded()
        let pluginView = vc.view as! PluginView

        var params = Param.allCases.map(\.defaultValue)
        params[Int(Param.headSize.rawValue)] = 0.66
        let saved = UserCharacter(name: "My Patch", faceID: "cow", params: params)

        pluginView.stage.select(saved)

        XCTAssertEqual(pluginView.stage.character.id, "user:My Patch")
        XCTAssertEqual(pluginView.stage.character.displayName, "My Patch")
        XCTAssertEqual(param_shadow_get(unit.shadow, kParamHeadSize), 0.66, accuracy: 1e-6)
        // Cow's own built-in voice sets headSize to 0.08 (see
        // `CharacterVoiceTable.cow`) — proving the tree holds 0.66, not
        // that, is what actually distinguishes "loaded the saved patch"
        // from "loaded the face's voice".
        let cowsOwnHeadSize = CharacterVoiceTable.cow[.headSize] ?? -1
        XCTAssertEqual(cowsOwnHeadSize, 0.08, accuracy: 1e-6, "test assumption about cow's own voice is stale")
        XCTAssertGreaterThan(abs(param_shadow_get(unit.shadow, kParamHeadSize) - cowsOwnHeadSize), 0.1)
    }

    /// `characterID` persists the saved entry's own built-in FACE id, never
    /// its namespaced `"user:…"` id — `MonkSynthAU.setCharacterID`'s own doc
    /// comment explains why: `CharacterRegistry` could never resolve a
    /// `"user:…"` id back into anything meaningful.
    func testSelectingAUserCharacterPersistsItsFaceIDNotItsOwnID() throws {
        let vc = AudioUnitViewController()
        let unit = try vc.createAudioUnit(with: makeDescription()) as! MonkSynthAU
        vc.loadViewIfNeeded()
        let pluginView = vc.view as! PluginView

        let saved = UserCharacter(name: "Ghost Voice", faceID: "unicorn", params: Param.allCases.map(\.defaultValue))
        pluginView.stage.select(saved)

        XCTAssertEqual(unit.characterID, "unicorn")
    }

    /// Regression coverage for the exact bug the task's decision 5 warns
    /// about: `onCharacterIDChange` fires asynchronously
    /// (`DispatchQueue.main.async`, see `bind()`), so if `setCharacterID`
    /// still notified it the way it used to, a saved entry's display would
    /// silently revert to its plain built-in face a moment after selection.
    /// Polling well past that async hop must show the selection is stable.
    func testSelectingAUserCharacterDoesNotRevertToItsFaceOnTheNextRunLoopTurn() throws {
        let vc = AudioUnitViewController()
        _ = try vc.createAudioUnit(with: makeDescription()) as! MonkSynthAU
        vc.loadViewIfNeeded()
        let pluginView = vc.view as! PluginView

        let saved = UserCharacter(name: "Sticky", faceID: "girl", params: Param.allCases.map(\.defaultValue))
        pluginView.stage.select(saved)
        XCTAssertEqual(pluginView.stage.character.id, "user:Sticky")

        // Drain the run loop the same way `pollUntil` does elsewhere in this
        // file, long enough for the async hop `onCharacterIDChange` would
        // have used to have definitely happened, then assert the selection
        // never moved.
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        XCTAssertEqual(pluginView.stage.character.id, "user:Sticky",
            "selecting a saved character must not silently revert to its built-in face")
    }
}
