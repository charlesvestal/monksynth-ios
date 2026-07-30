import AVFoundation

public final class MonkSynthAU: AUAudioUnit {
    public override init(componentDescription: AudioComponentDescription,
                         options: AudioComponentInstantiationOptions = []) throws {
        try super.init(componentDescription: componentDescription, options: options)
    }
}
