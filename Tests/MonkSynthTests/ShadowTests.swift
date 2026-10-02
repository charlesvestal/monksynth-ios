import AVFoundation
import XCTest
@testable import MonkSynth

final class ShadowTests: XCTestCase {

    private func makeAU() throws -> MonkSynthAU {
        let desc = AudioComponentDescription(
            componentType: kAudioUnitType_MusicDevice,
            componentSubType: 0x4D6E6B73,          // 'Mnks'
            componentManufacturer: 0x5673746C,     // 'Vstl'
            componentFlags: 0, componentFlagsMask: 0)
        return try MonkSynthAU(componentDescription: desc)
    }

    func testTreeHasEveryParameter() throws {
        let au = try makeAU()
        XCTAssertEqual(au.parameterTree?.allParameters.count, Int(kParamCount.rawValue))
    }

    func testSettingParameterUpdatesShadow() throws {
        let au = try makeAU()
        let attack = au.parameterTree!.parameter(withAddress: Param.attack.rawValue)!
        attack.value = 0.4
        XCTAssertEqual(param_shadow_get(au.shadow, kParamAttack), 0.4, accuracy: 1e-6)
    }

    func testDefaultsSeededIntoShadow() throws {
        let au = try makeAU()
        XCTAssertEqual(param_shadow_get(au.shadow, kParamDelay), 0.8, accuracy: 1e-6)
        XCTAssertEqual(param_shadow_get(au.shadow, kParamSustain), 1.0, accuracy: 1e-6)
        XCTAssertEqual(param_shadow_get(au.shadow, kParamVibrato), 0.0, accuracy: 1e-6)
    }
}
