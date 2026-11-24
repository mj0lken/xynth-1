import Darwin
import Foundation

// MARK: - Built-in Trackpad Demos (Sweep, Arpeggio, Heartbeat & 3-Finger Musical Demo)

extension HapticSynthEngine {
    enum DemoRequest: Sendable {
        case sweep
        case arpeggio
        case heartbeat
        case shortDemo
    }

    func runDemo(_ demo: DemoRequest, params: SynthParameters, actuationCount: inout UInt64) {
        let master = Float(max(0.25, min(1.0, params.masterVolume)))

        switch demo {
        case .sweep:
            runSweepDemo(params: params, master: master, actuationCount: &actuationCount)
        case .arpeggio:
            runArpeggioDemo(params: params, master: master, actuationCount: &actuationCount)
        case .heartbeat:
            runHeartbeatDemo(params: params, master: master, actuationCount: &actuationCount)
        case .shortDemo:
            runShortMusicalDemo(params: params, master: master, actuationCount: &actuationCount)
        }
        audioMirror?.update(tones: [], level: 0)
    }

    private func runSweepDemo(params: SynthParameters, master: Float, actuationCount: inout UInt64) {
        let totalDuration = 3.2
        let start = mach_absolute_time()
        var elapsed = 0.0

        while elapsed < totalDuration && isRunning() {
            if hasUserInterrupt() { break }
            let progress = elapsed / totalDuration
            let hz = 98.0 * pow(3600.0 / 98.0, progress)
            let seg = Self.phaseCoherentDurationSeconds(phaseReferenceHz: hz, targetSeconds: 0.020)
            let env: Double = progress < 0.05 ? progress / 0.05 : (progress > 0.94 ? (1.0 - progress) / 0.06 : 1.0)
            let level = Float(min(1.0, max(0.0, env * Double(master))))
            let tones = [HapticTone(hz: hz, amp: 1.0)]
            emit(tones: tones, durationMs: seg * 1000.0, level: level, hapticsEnabled: params.hapticsEnabled)
            actuationCount += 1

            let voice = ActiveVoiceSnapshot(
                id: -1,
                x: progress,
                y: Double(level),
                size: 0.8,
                hz: hz,
                note: MusicalTheory.noteReadout(forHz: hz),
                volume: Double(level),
                isHeld: false
            )
            publishSnapshot(
                SynthSnapshot(
                    isSounding: true,
                    hardwareStatus: actuator.status,
                    rawTouches: actuator.currentContacts(),
                    activeVoices: [voice],
                    outputTones: tones,
                    primaryHz: hz,
                    primaryNote: voice.note,
                    effectiveLevel: Double(level),
                    sliceDurationMs: seg * 1000.0,
                    actuationCount: actuationCount,
                    demoLabel: "SWEEP 98 Hz → 3.6 kHz"
                )
            )

            elapsed += seg
            waitUntilTick(start + UInt64(elapsed * ticksPerSecond))
        }
    }

    private func runArpeggioDemo(params: SynthParameters, master: Float, actuationCount: inout UInt64) {
        // Ascending A-minor 9 arpeggio across the trackpad's sweet spot
        let notes: [(midi: Double, dur: Double)] = [
            (57, 0.16), // A3
            (64, 0.16), // E4
            (69, 0.16), // A4
            (71, 0.16), // B4
            (72, 0.18), // C5
            (76, 0.18), // E5
            (81, 0.42)  // A5
        ]

        for (idx, item) in notes.enumerated() where isRunning() {
            if hasUserInterrupt() { break }
            let hz = MusicalTheory.hz(forMidi: item.midi)
            let sub = Self.tactileSubFrequency(forFundamental: hz)
            let noteStart = mach_absolute_time()
            var t = 0.0

            while t < item.dur && isRunning() {
                if hasUserInterrupt() { break }
                let env = min(1.0, t / 0.015) * (idx == notes.count - 1 ? max(0.0, 1.0 - t / item.dur) : 0.85 + 0.15 * (1.0 - t / item.dur))
                var tones = [HapticTone(hz: hz, amp: 0.72), HapticTone(hz: min(4000, hz * 2.0), amp: 0.28)]
                if let sub {
                    tones.append(HapticTone(hz: sub, amp: 0.22))
                }
                let sum = tones.reduce(0.0) { $0 + $1.amp }
                let norm = tones.map { HapticTone(hz: $0.hz, amp: $0.amp / sum) }
                let refHz = sub ?? hz
                let seg = Self.phaseCoherentDurationSeconds(phaseReferenceHz: refHz, targetSeconds: 0.020)
                let level = Float(min(1.0, max(0.0, env * Double(master))))
                emit(tones: norm, durationMs: seg * 1000.0, level: level, hapticsEnabled: params.hapticsEnabled)
                actuationCount += 1

                let normX = Double(idx) / Double(max(1, notes.count - 1))
                let voice = ActiveVoiceSnapshot(
                    id: -2,
                    x: normX,
                    y: Double(level),
                    size: 0.85,
                    hz: hz,
                    note: MusicalTheory.noteReadout(forHz: hz),
                    volume: Double(level),
                    isHeld: false
                )
                publishSnapshot(
                    SynthSnapshot(
                        isSounding: true,
                        hardwareStatus: actuator.status,
                        rawTouches: actuator.currentContacts(),
                        activeVoices: [voice],
                        outputTones: norm,
                        primaryHz: hz,
                        primaryNote: voice.note,
                        effectiveLevel: Double(level),
                        sliceDurationMs: seg * 1000.0,
                        actuationCount: actuationCount,
                        demoLabel: "TRACKPAD CHORD CHECK"
                    )
                )

                t += seg
                waitUntilTick(noteStart + UInt64(t * ticksPerSecond))
            }
        }
    }

    private func runHeartbeatDemo(params: SynthParameters, master: Float, actuationCount: inout UInt64) {
        for (beatIdx, amp) in [1.0, 0.72].enumerated() where isRunning() {
            if hasUserInterrupt() { break }
            let start = mach_absolute_time()
            var t = 0.0

            while t < 0.12 && isRunning() {
                let hz = 115.0 + 740.0 * exp(-t / 0.020)
                let seg = max(0.004, 1.0 / hz)
                let level = Float(min(1.0, amp * exp(-t / 0.052) * Double(master)))
                let tones = [HapticTone(hz: hz, amp: 1.0)]
                emit(tones: tones, durationMs: seg * 1000.0, level: level, hapticsEnabled: params.hapticsEnabled)
                actuationCount += 1
                publishSnapshot(
                    SynthSnapshot(
                        isSounding: true,
                        hardwareStatus: actuator.status,
                        rawTouches: actuator.currentContacts(),
                        activeVoices: [],
                        outputTones: tones,
                        primaryHz: hz,
                        primaryNote: MusicalTheory.noteReadout(forHz: hz),
                        effectiveLevel: Double(level),
                        sliceDurationMs: seg * 1000.0,
                        actuationCount: actuationCount,
                        demoLabel: "TACTILE PULSE"
                    )
                )
                t += seg
                waitUntilTick(start + UInt64(t * ticksPerSecond))
            }
            audioMirror?.update(tones: [], level: 0)
            if beatIdx == 0 {
                usleep(165_000)
            }
        }
    }

    private func runShortMusicalDemo(params: SynthParameters, master: Float, actuationCount: inout UInt64) {
        // 4.6-second expressive musical showcase: melodic glass riff -> glowing 3-finger Am9 chord -> silky octave bloom
        struct DemoStep {
            let midis: [Double]
            let xs: [Double]
            let ys: [Double]
            let duration: Double
            let glideToMidis: [Double]?
        }

        let phrase: [DemoStep] = [
            DemoStep(midis: [69], xs: [0.36], ys: [0.76], duration: 0.24, glideToMidis: nil),         // A4
            DemoStep(midis: [72], xs: [0.48], ys: [0.82], duration: 0.24, glideToMidis: nil),         // C5
            DemoStep(midis: [76], xs: [0.62], ys: [0.88], duration: 0.30, glideToMidis: nil),         // E5
            DemoStep(midis: [74], xs: [0.55], ys: [0.78], duration: 0.22, glideToMidis: [76]),        // D5 -> E5 glide
            DemoStep(midis: [79], xs: [0.74], ys: [0.90], duration: 0.36, glideToMidis: nil),         // G5
            DemoStep(midis: [76], xs: [0.62], ys: [0.80], duration: 0.26, glideToMidis: nil),         // E5
            // 3-finger Am9 shimmering chord (A3 + E4 + B4)
            DemoStep(midis: [57, 64, 71], xs: [0.22, 0.44, 0.66], ys: [0.76, 0.84, 0.80], duration: 0.95, glideToMidis: nil),
            // Resolve into bright 3-finger Cmaj7 -> A5 bloom (C4 + G4 + E5 -> A4 + E5 + A5)
            DemoStep(midis: [60, 67, 76], xs: [0.28, 0.52, 0.76], ys: [0.80, 0.86, 0.90], duration: 0.80, glideToMidis: [69, 76, 81]),
            DemoStep(midis: [69, 76, 81], xs: [0.40, 0.64, 0.86], ys: [0.84, 0.88, 0.92], duration: 1.05, glideToMidis: nil)
        ]

        for (stepIdx, step) in phrase.enumerated() where isRunning() {
            if hasUserInterrupt() { break }
            let stepStart = mach_absolute_time()
            var t = 0.0
            let isFinal = (stepIdx == phrase.count - 1)

            while t < step.duration && isRunning() {
                if hasUserInterrupt() { break }
                let u = min(1.0, max(0.0, t / step.duration))
                let attack = min(1.0, t / 0.022)
                let release = isFinal ? max(0.0, 1.0 - max(0.0, (u - 0.55) / 0.45)) : (u > 0.88 ? max(0.25, (1.0 - u) / 0.12) : 1.0)
                let env = attack * release

                var voiceInputs: [(hz: Double, volume: Double, brightness: Double)] = []
                var activeVoiceSnaps: [ActiveVoiceSnapshot] = []
                for i in 0..<step.midis.count {
                    let baseMidi = step.midis[i]
                    let targetMidi = step.glideToMidis?[safe: i] ?? baseMidi
                    let smoothU = u * u * (3.0 - 2.0 * u)
                    let currentMidi = baseMidi + (targetMidi - baseMidi) * smoothU
                    let vib = sin(2.0 * .pi * 5.2 * t + Double(i) * 0.9) * (u > 0.25 ? 0.10 : 0.0)
                    let hz = MusicalTheory.hz(forMidi: currentMidi + vib)
                    let yVal = step.ys[safe: i] ?? 0.82
                    let xVal = min(0.96, max(0.04, (step.xs[safe: i] ?? 0.5) + (targetMidi - baseMidi) * 0.015 * smoothU))
                    let vol = min(1.0, max(0.0, yVal * env))
                    voiceInputs.append((hz: hz, volume: vol, brightness: 0.62))
                    activeVoiceSnaps.append(
                        ActiveVoiceSnapshot(
                            id: Int32(-10 - i),
                            x: xVal,
                            y: yVal * (0.7 + 0.3 * env),
                            size: 0.85,
                            hz: hz,
                            note: MusicalTheory.noteReadout(forHz: hz),
                            volume: vol * Double(master),
                            isHeld: false
                        )
                    )
                }

                var demoParams = params
                demoParams.masterVolume = Double(master)
                demoParams.subFeelAmount = max(0.24, params.subFeelAmount)

                if let slice = Self.buildSlice(voices: voiceInputs, params: demoParams) {
                    emit(tones: slice.tones, durationMs: slice.durationMs, level: slice.level, hapticsEnabled: params.hapticsEnabled)
                    actuationCount += 1
                    publishSnapshot(
                        SynthSnapshot(
                            isSounding: true,
                            hardwareStatus: actuator.status,
                            rawTouches: actuator.currentContacts(),
                            activeVoices: activeVoiceSnaps,
                            outputTones: slice.tones,
                            primaryHz: slice.primaryHz,
                            primaryNote: MusicalTheory.noteReadout(forHz: slice.primaryHz),
                            effectiveLevel: Double(slice.level),
                            sliceDurationMs: slice.durationMs,
                            actuationCount: actuationCount,
                            demoLabel: "DEMO · 3-FINGER GLASS RIFF"
                        )
                    )
                    t += slice.durationMs / 1000.0
                } else {
                    t += 0.016
                }
                waitUntilTick(stepStart + UInt64(t * ticksPerSecond))
            }
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
