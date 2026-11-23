import Foundation

/// Musical root note (pitch class 0 = C ... 11 = B).
public enum RootNote: Int, CaseIterable, Identifiable, Sendable, Codable {
    case c = 0, cSharp, d, dSharp, e, f, fSharp, g, gSharp, a, aSharp, b

    public var id: Int { rawValue }

    public var label: String {
        switch self {
        case .c: return "C"
        case .cSharp: return "C#"
        case .d: return "D"
        case .dSharp: return "D#"
        case .e: return "E"
        case .f: return "F"
        case .fSharp: return "F#"
        case .g: return "G"
        case .gSharp: return "G#"
        case .a: return "A"
        case .aSharp: return "A#"
        case .b: return "B"
        }
    }
}

/// Musical scales available for trackpad pitch mapping.
public enum MusicalScale: String, CaseIterable, Identifiable, Sendable, Codable {
    case free
    case pentatonicMinor
    case pentatonicMajor
    case chromatic
    case major
    case minor
    case dorian
    case lydian
    case hirajoshi

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .free: return "Free (Theremin)"
        case .pentatonicMinor: return "Min Pentatonic"
        case .pentatonicMajor: return "Maj Pentatonic"
        case .chromatic: return "Chromatic"
        case .major: return "Major"
        case .minor: return "Natural Minor"
        case .dorian: return "Dorian"
        case .lydian: return "Lydian"
        case .hirajoshi: return "Hirajoshi"
        }
    }

    /// Semitone intervals within an octave, or empty for continuous fretless pitch.
    public var intervals: [Int] {
        switch self {
        case .free: return []
        case .chromatic: return Array(0..<12)
        case .pentatonicMajor: return [0, 2, 4, 7, 9]
        case .pentatonicMinor: return [0, 3, 5, 7, 10]
        case .major: return [0, 2, 4, 5, 7, 9, 11]
        case .minor: return [0, 2, 3, 5, 7, 8, 10]
        case .dorian: return [0, 2, 3, 5, 7, 9, 10]
        case .lydian: return [0, 2, 4, 6, 7, 9, 11]
        case .hirajoshi: return [0, 2, 3, 7, 8]
        }
    }
}

/// Frequency ranges tuned to the physical acoustics and fingertip mechanoreceptor sweet spots
/// of the MacBook Force Touch Taptic Engine.
public enum FrequencyRangePreset: String, CaseIterable, Identifiable, Sendable, Codable {
    case subFeel
    case balanced
    case acoustic
    case fullSpectrum

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .subFeel: return "Sub Feel"
        case .balanced: return "Balanced"
        case .acoustic: return "Acoustic"
        case .fullSpectrum: return "Full"
        }
    }

    public var subtitle: String {
        switch self {
        case .subFeel: return "65–392 Hz · Max Finger Buzz"
        case .balanced: return "131–1047 Hz · Feel + Pitch"
        case .acoustic: return "523–2093 Hz · Loudest Singing"
        case .fullSpectrum: return "98–3951 Hz · Full Motor Span"
        }
    }

    /// Base MIDI note range `(low, high)` before applying user octave offset.
    public var baseMidiRange: (low: Int, high: Int) {
        switch self {
        case .subFeel: return (36, 67)       // C2 (65.4 Hz) -> G4 (392 Hz)
        case .balanced: return (48, 84)      // C3 (130.8 Hz) -> C6 (1046.5 Hz)
        case .acoustic: return (72, 96)      // C5 (523.3 Hz) -> C7 (2093 Hz)
        case .fullSpectrum: return (43, 107) // G2 (98.0 Hz) -> B7 (3951.1 Hz)
        }
    }
}

/// Visual guide marker for rendering pitch grid lines on the interactive trackpad surface.
public struct ScaleMarker: Sendable, Equatable, Identifiable {
    public let id: Int
    public let normalizedX: Double
    public let midiNote: Int
    public let hz: Double
    public let label: String
    public let isRoot: Bool
}

public struct NoteReadout: Sendable, Equatable {
    public let name: String
    public let cents: Int
    public let midi: Double
}

public enum MusicalTheory {
    private static let noteNames = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]

    public static func hz(forMidi midi: Double) -> Double {
        440.0 * pow(2.0, (midi - 69.0) / 12.0)
    }

    public static func midi(forHz hz: Double) -> Double {
        69.0 + 12.0 * log2(max(20.0, hz) / 440.0)
    }

    public static func noteLabel(forMidiNote midi: Int) -> String {
        let pitchClass = ((midi % 12) + 12) % 12
        let octave = (midi / 12) - 1
        return "\(noteNames[pitchClass])\(octave)"
    }

    public static func noteReadout(forHz hz: Double) -> NoteReadout {
        guard hz > 20 else { return NoteReadout(name: "—", cents: 0, midi: 0) }
        let exactMidi = midi(forHz: hz)
        let nearest = Int(exactMidi.rounded())
        let cents = Int(((exactMidi - Double(nearest)) * 100.0).rounded())
        return NoteReadout(name: noteLabel(forMidiNote: nearest), cents: cents, midi: exactMidi)
    }

    /// Computes effective MIDI range `(low, high)` clamped safely inside the Taptic Engine's playable span.
    public static func effectiveMidiRange(
        preset: FrequencyRangePreset,
        octaveShift: Int
    ) -> (low: Double, high: Double) {
        let base = preset.baseMidiRange
        let shift = Double(octaveShift * 12)
        // Clamp between ~49 Hz (MIDI 31, G1) and ~3951 Hz (MIDI 107, B7)
        let minMidi = 31.0
        let maxMidi = 107.0
        let span = Double(base.high - base.low)
        let low = min(maxMidi - span, max(minMidi, Double(base.low) + shift))
        let high = min(maxMidi, low + span)
        return (low, high)
    }

    /// Generates all quantized MIDI notes inside the active range for a given scale & root.
    public static func scaleNotes(
        scale: MusicalScale,
        root: RootNote,
        preset: FrequencyRangePreset,
        octaveShift: Int
    ) -> [Int] {
        let range = effectiveMidiRange(preset: preset, octaveShift: octaveShift)
        let lo = Int(range.low.rounded(.down))
        let hi = Int(range.high.rounded(.up))
        let intervals = scale == .free ? [0, 7] : scale.intervals
        let allowed = Set(intervals.map { ($0 + root.rawValue) % 12 })
        return (lo...hi).filter { allowed.contains((($0 % 12) + 12) % 12) }
    }

    /// Maps normalized horizontal trackpad coordinate `x` (`0...1`) to target frequency in Hz.
    public static func frequency(
        forNormalizedX x: Double,
        scale: MusicalScale,
        root: RootNote,
        preset: FrequencyRangePreset,
        octaveShift: Int
    ) -> Double {
        let clampedX = min(1.0, max(0.0, x))
        let range = effectiveMidiRange(preset: preset, octaveShift: octaveShift)

        if scale == .free {
            let midiVal = range.low + clampedX * (range.high - range.low)
            return hz(forMidi: midiVal)
        }

        let notes = scaleNotes(scale: scale, root: root, preset: preset, octaveShift: octaveShift)
        guard !notes.isEmpty else {
            return hz(forMidi: range.low + clampedX * (range.high - range.low))
        }

        // Divide trackpad width into equal-width cells per scale note so every note has generous finger space.
        let index = min(notes.count - 1, max(0, Int((clampedX * Double(notes.count)).rounded(.down))))
        return hz(forMidi: Double(notes[index]))
    }

    /// Produces visual guide markers for the XY trackpad grid.
    public static func scaleMarkers(
        scale: MusicalScale,
        root: RootNote,
        preset: FrequencyRangePreset,
        octaveShift: Int
    ) -> [ScaleMarker] {
        let range = effectiveMidiRange(preset: preset, octaveShift: octaveShift)

        if scale == .free {
            // Show octave/root reference lines across the continuous pitch space
            let lo = Int(range.low.rounded(.up))
            let hi = Int(range.high.rounded(.down))
            var markers: [ScaleMarker] = []
            for note in lo...hi {
                let pc = ((note % 12) + 12) % 12
                let isRoot = pc == root.rawValue
                let isFifth = pc == (root.rawValue + 7) % 12
                guard isRoot || isFifth else { continue }
                let normX = (Double(note) - range.low) / max(1.0, range.high - range.low)
                markers.append(
                    ScaleMarker(
                        id: note,
                        normalizedX: normX,
                        midiNote: note,
                        hz: hz(forMidi: Double(note)),
                        label: noteLabel(forMidiNote: note),
                        isRoot: isRoot
                    )
                )
            }
            return markers
        }

        let notes = scaleNotes(scale: scale, root: root, preset: preset, octaveShift: octaveShift)
        guard !notes.isEmpty else { return [] }
        let count = Double(notes.count)
        return notes.enumerated().map { idx, note in
            let centerX = (Double(idx) + 0.5) / count
            let isRoot = (((note % 12) + 12) % 12) == root.rawValue
            return ScaleMarker(
                id: note,
                normalizedX: centerX,
                midiNote: note,
                hz: hz(forMidi: Double(note)),
                label: noteLabel(forMidiNote: note),
                isRoot: isRoot
            )
        }
    }
}
