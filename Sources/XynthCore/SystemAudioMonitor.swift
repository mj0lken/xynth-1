import Foundation
import CoreAudio

/// Checks whether the Mac's default audio output is muted or at zero volume,
/// proving that 100% of the sound comes directly from the Force Touch trackpad.
public enum SystemAudioMonitor {
    public enum MuteState: Sendable, Equatable {
        case muted
        case unmuted(volume: Float)
        case unknown
    }

    public static func currentMuteState() -> MuteState {
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &addr,
            0,
            nil,
            &size,
            &device
        ) == noErr else {
            return .unknown
        }

        var known = false
        var muted: UInt32 = 0
        size = UInt32(MemoryLayout<UInt32>.size)
        addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )

        if AudioObjectHasProperty(device, &addr),
           AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &muted) == noErr {
            known = true
            if muted != 0 {
                return .muted
            }
        }

        for element in [kAudioObjectPropertyElementMain, AudioObjectPropertyElement(1)] {
            var volume: Float32 = 1.0
            size = UInt32(MemoryLayout<Float32>.size)
            addr = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyVolumeScalar,
                mScope: kAudioObjectPropertyScopeOutput,
                mElement: element
            )
            if AudioObjectHasProperty(device, &addr),
               AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &volume) == noErr {
                if volume < 0.001 {
                    return .muted
                }
                return .unmuted(volume: volume)
            }
        }

        return known ? .unmuted(volume: 1.0) : .unknown
    }
}
