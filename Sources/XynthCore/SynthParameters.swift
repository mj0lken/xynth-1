import Foundation

/// Selectable harmonic timbres synthesized directly by stacking sine partials on the Taptic Engine.
public enum SynthTimbre: String, CaseIterable, Identifiable, Sendable, Codable {
    case pureSine
    case warmOctave
    case hollow
    case brassSaw
    case fifthOrgan
    case glassBell
    case vocalFormant

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .pureSine: return "Pure Sine"
        case .warmOctave: return "Warm"
        case .hollow: return "Hollow"
        case .brassSaw: return "Saw Buzz"
        case .fifthOrgan: return "Fifth Organ"
        case .glassBell: return "Glass Bell"
        case .vocalFormant: return "Formant"
        }
    }

    public var shortName: String {
        switch self {
        case .pureSine: return "SINE"
        case .warmOctave: return "WARM"
        case .hollow: return "HOLLOW"
        case .brassSaw: return "SAW"
        case .fifthOrgan: return "FIFTH"
        case .glassBell: return "BELL"
        case .vocalFormant: return "VOICE"
        }
    }

    public var shortcutIndex: Int {
        switch self {
        case .pureSine: return 1
        case .warmOctave: return 2
        case .hollow: return 3
        case .brassSaw: return 4
        case .fifthOrgan: return 5
        case .glassBell: return 6
        case .vocalFormant: return 7
        }
    }

    /// Generates harmonic partials for a voice at fundamental `baseHz`, scaled by `brightness` (`0...1`).
    public func partials(baseHz: Double, brightness: Double, maxPartials: Int) -> [HapticTone] {
        let b = min(1.0, max(0.0, brightness))
        let raw: [(Double, Double)]

        switch self {
        case .pureSine:
            raw = [(baseHz, 1.0)]

        case .warmOctave:
            raw = [
                (baseHz, 0.72),
                (baseHz * 2.0, 0.20 + 0.25 * b),
                (baseHz * 3.0, 0.08 * b)
            ]

        case .hollow:
            raw = [
                (baseHz, 0.65),
                (baseHz * 3.0, 0.22 + 0.18 * b),
                (baseHz * 5.0, 0.06 + 0.14 * b)
            ]

        case .brassSaw:
            raw = [
                (baseHz, 0.44),
                (baseHz * 2.0, 0.24 + 0.08 * b),
                (baseHz * 3.0, 0.14 + 0.10 * b),
                (baseHz * 4.0, 0.07 + 0.09 * b),
                (baseHz * 5.0, 0.04 + 0.08 * b)
            ]

        case .fifthOrgan:
            raw = [
                (baseHz, 0.52),
                (baseHz * 1.4983, 0.28 + 0.08 * b), // Perfect fifth (2^(7/12))
                (baseHz * 2.0, 0.20 + 0.12 * b),
                (baseHz * 3.0, 0.06 * b)
            ]

        case .glassBell:
            raw = [
                (baseHz, 0.56),
                (baseHz * 2.756, 0.28 + 0.12 * b),
                (baseHz * 5.404, 0.10 + 0.12 * b)
            ]

        case .vocalFormant:
            // Interpolate vowel formants across brightness (u -> o -> a -> e -> i)
            let vowels: [(f1: Double, f2: Double)] = [
                (300, 870),   // oo
                (500, 1000),  // oh
                (730, 1150),  // ah
                (530, 1840),  // eh
                (280, 2250)   // ee
            ]
            let pos = b * Double(vowels.count - 1)
            let lo = Int(pos.rounded(.down))
            let hi = min(vowels.count - 1, lo + 1)
            let frac = pos - Double(lo)
            let f1 = vowels[lo].f1 + (vowels[hi].f1 - vowels[lo].f1) * frac
            let f2 = vowels[lo].f2 + (vowels[hi].f2 - vowels[lo].f2) * frac
            raw = [
                (baseHz, 0.38),
                (f1, 0.34),
                (f2, 0.28)
            ]
        }

        let valid = raw
            .filter { $0.0 >= MultitouchBridge.minSafeFrequencyHz && $0.0 <= MultitouchBridge.maxSafeFrequencyHz && $0.1 > 0.005 }
            .prefix(max(1, maxPartials))
            .map { HapticTone(hz: $0.0, amp: $0.1) }

        return valid.isEmpty ? [HapticTone(hz: min(MultitouchBridge.maxSafeFrequencyHz, max(MultitouchBridge.minSafeFrequencyHz, baseHz)), amp: 1.0)] : valid
    }
}

/// How the trackpad's X, Y, and Finger Contact Size (Pressure) axes map to synth parameters.
public enum ControlMappingMode: String, CaseIterable, Identifiable, Sendable, Codable {
    case xyPitchVolume
    case pressureVolumeYTimbre
    case pressureVolumeYVibrato

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .xyPitchVolume: return "XY: Pitch + Vol"
        case .pressureVolumeYTimbre: return "Press: Vol · Y: Timbre"
        case .pressureVolumeYVibrato: return "Press: Vol · Y: Vibrato"
        }
    }

    public var yAxisLabel: String {
        switch self {
        case .xyPitchVolume: return "VOLUME"
        case .pressureVolumeYTimbre: return "TIMBRE"
        case .pressureVolumeYVibrato: return "VIBRATO"
        }
    }

    public var hintText: String {
        switch self {
        case .xyPitchVolume:
            return "Slide X for Pitch · Slide Y for Volume · Multi-finger for Chords"
        case .pressureVolumeYTimbre:
            return "Slide X for Pitch · Press flatter for Volume · Slide Y for Harmonics"
        case .pressureVolumeYVibrato:
            return "Slide X for Pitch · Press flatter for Volume · Slide Y for Vibrato"
        }
    }
}

/// Complete real-time synthesis configuration copied lock-safely into the audio/haptic thread.
public struct SynthParameters: Sendable, Equatable {
    public var scale: MusicalScale = .pentatonicMinor
    public var root: RootNote = .a
    public var rangePreset: FrequencyRangePreset = .balanced
    public var octaveShift: Int = 0
    public var timbre: SynthTimbre = .warmOctave
    public var mappingMode: ControlMappingMode = .xyPitchVolume

    /// Master output ceiling (`0.0 ... 1.0`).
    public var masterVolume: Double = 0.90
    /// Blends a tactile sub-octave in the fingertip mechanoreceptor sweet spot (110–250 Hz) when playing higher pitches.
    public var subFeelAmount: Double = 0.24
    /// Portamento / pitch smoothing (`0.0` = instant crisp snap, `1.0` = slow liquid theremin glide).
    public var glideAmount: Double = 0.28
    /// Base harmonic brightness (`0.0 ... 1.0`).
    public var brightness: Double = 0.55
    /// Pitch LFO vibrato depth in semitones (`0.0 ... 0.8`).
    public var vibratoDepth: Double = 0.14
    /// Pitch LFO vibrato rate in Hz (`2.0 ... 10.0`).
    public var vibratoRateHz: Double = 5.4
    /// Maximum simultaneous multi-touch voices (`1 ... 5`, maxing out MacBook 5-finger trackpad sensing).
    public var maxVoices: Int = 5

    /// When true, freezes the active voices so the trackpad sustains continuously without holding fingers down
    /// (allowing you to rest your hand on the glass to feel it, or sculpt pitch/volume with sliders).
    public var holdDrone: Bool = false
    /// Manual pitch control (`0.0 ... 1.0`) used when Hold/Drone is active with no fingers or in Direct Slider mode.
    public var manualPitchX: Double = 0.50
    /// Manual volume control (`0.0 ... 1.0`) used when Hold/Drone is active with no fingers or in Direct Slider mode.
    public var manualVolumeY: Double = 0.72
    /// Enables direct manual slider synthesis even when no fingers are touching.
    public var manualSynthActive: Bool = false

    /// Whether raw hardware trackpad contacts from MultitouchSupport should drive the synth right now.
    /// Typically true when Play Mode (cursor lock) is active, Option is held, or Always-Live is toggled on.
    public var hardwareTouchArmed: Bool = false

    /// Whether the physical Force Touch trackpad actuator is driven (keep ON to feel & hear the glass).
    public var hapticsEnabled: Bool = true

    public init() {}
}
