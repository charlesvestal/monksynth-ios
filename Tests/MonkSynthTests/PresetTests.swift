import AVFoundation
import XCTest
@testable import MonkSynth

final class PresetTests: XCTestCase {

    private func makeAU() throws -> MonkSynthAU {
        let desc = AudioComponentDescription(
            componentType: kAudioUnitType_MusicDevice,
            componentSubType: 0x4D6E6B73,          // 'Mnks'
            componentManufacturer: 0x5673746C,     // 'Vstl'
            componentFlags: 0, componentFlagsMask: 0)
        return try MonkSynthAU(componentDescription: desc)
    }

    func testFullStateRoundTrips() throws {
        let source = try makeAU()
        let attack = source.parameterTree!.parameter(withAddress: Param.attack.rawValue)!
        let level = source.parameterTree!.parameter(withAddress: Param.level.rawValue)!
        attack.value = 0.73
        level.value = 0.21

        let state = source.fullState

        let destination = try makeAU()
        destination.fullState = state

        XCTAssertEqual(param_shadow_get(destination.shadow, kParamAttack), 0.73, accuracy: 1e-5)
        XCTAssertEqual(param_shadow_get(destination.shadow, kParamLevel), 0.21, accuracy: 1e-5)

        // The whole table round-trips, not just the two params that changed.
        for p in Param.allCases {
            XCTAssertEqual(param_shadow_get(destination.shadow, p.address),
                           param_shadow_get(source.shadow, p.address),
                           accuracy: 1e-6, "\(p.name) did not round-trip")
        }
    }

    func testSixFactoryPresetsInOrder() throws {
        let au = try makeAU()
        let names = au.factoryPresets?.map { $0.name }
        XCTAssertEqual(names, ["Dorje", "Jamyang", "Monastary", "Ngawang", "Rabten", "Tinley"])
    }

    func testSelectingPresetUpdatesShadowAndTree() throws {
        let au = try makeAU()
        let preset = try XCTUnwrap(au.factoryPresets?[2])
        XCTAssertEqual(preset.name, "Monastary")

        au.currentPreset = preset

        let expected = kFactoryPresets[2].values
        for (i, want) in expected.enumerated() {
            let addr = Param.address(atIndex: i)
            XCTAssertEqual(param_shadow_get(au.shadow, addr), want, accuracy: 1e-5,
                           "shadow mismatch at index \(i)")
            let treeValue = au.parameterTree!.parameter(withAddress: UInt64(i))!.value
            XCTAssertEqual(treeValue, want, accuracy: 1e-5,
                           "parameter tree mismatch at index \(i)")
        }
    }

    func testShortStateLeavesRemainingParametersAtDefaults() throws {
        let au = try makeAU()
        let shortValues: [AUValue] = [0.11, 0.22, 0.33]
        let data = shortValues.withUnsafeBufferPointer { Data(buffer: $0) }
        au.fullState = ["monkParams": data]

        XCTAssertEqual(param_shadow_get(au.shadow, kParamPortTime), 0.11, accuracy: 1e-6)
        XCTAssertEqual(param_shadow_get(au.shadow, kParamVowel), 0.22, accuracy: 1e-6)
        XCTAssertEqual(param_shadow_get(au.shadow, kParamDelay), 0.33, accuracy: 1e-6)

        // Everything from index 3 onward was never in the blob — still default.
        XCTAssertEqual(param_shadow_get(au.shadow, kParamHeadSize), Param.headSize.defaultValue, accuracy: 1e-6)
        XCTAssertEqual(param_shadow_get(au.shadow, kParamSustain), Param.sustain.defaultValue, accuracy: 1e-6)
        XCTAssertEqual(param_shadow_get(au.shadow, kParamLevel), Param.level.defaultValue, accuracy: 1e-6)
        XCTAssertEqual(param_shadow_get(au.shadow, kParamPitchWheelRaw), Param.pitchWheelRaw.defaultValue, accuracy: 1e-6)
    }
}
