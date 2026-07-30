import CoreAudioKit

public final class AudioUnitViewController: AUViewController, AUAudioUnitFactory {
    var audioUnit: MonkSynthAU?

    public func createAudioUnit(with desc: AudioComponentDescription) throws -> AUAudioUnit {
        let au = try MonkSynthAU(componentDescription: desc)
        audioUnit = au
        return au
    }
}
