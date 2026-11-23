import Foundation
import Testing
@testable import XynthCore

final class MockActuator: HapticActuatorOutput, @unchecked Sendable {
    private var lock = os_unfair_lock()
    private var _contacts: [TouchContact] = []
    private var _playedCalls: [(tones: [HapticTone], durationMs: Double, level: Float)] = []

    let status: HapticHardwareStatus = .ready(
        TrackpadDeviceInfo(id: 1234, isBuiltIn: true, hasActuator: true)
    )
    let availableDevices: [TrackpadDeviceInfo] = [
        TrackpadDeviceInfo(id: 1234, isBuiltIn: true, hasActuator: true)
    ]

    func setContacts(_ contacts: [TouchContact]) {
        os_unfair_lock_lock(&lock)
        _contacts = contacts
        os_unfair_lock_unlock(&lock)
    }

    func currentContacts() -> [TouchContact] {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        return _contacts
    }

    func play(tones: [HapticTone], durationMs: Double, level: Float) {
        os_unfair_lock_lock(&lock)
        _playedCalls.append((tones, durationMs, level))
        os_unfair_lock_unlock(&lock)
    }

    func recordedCalls() -> [(tones: [HapticTone], durationMs: Double, level: Float)] {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        return _playedCalls
    }

    func startTouchCapture() -> Bool { true }
    func stopTouchCapture() {}
    func reconnect(deviceID: UInt64?) -> HapticHardwareStatus { status }
    func shutdown() {}
}

@Suite("XYNTH-1 Core DSP & Haptic Safety")
struct XynthCoreTests {

    @Test("A4 tuning and note readout accuracy")
    func noteReadoutAccuracy() {
        let a4 = MusicalTheory.hz(forMidi: 69)
        #expect(abs(a4 - 440.0) < 0.001)

        let readout = MusicalTheory.noteReadout(forHz: 440.0)
        #expect(readout.name == "A4")
        #expect(readout.cents == 0)

        let c6 = MusicalTheory.noteReadout(forHz: 1046.502)
        #expect(c6.name == "C6")
        #expect(abs(c6.cents) <= 1)
    }

    @Test("Free scale is monotonic across normalized X")
    func freeScaleMonotonic() {
        var prev = 0.0
        for step in 0...20 {
            let x = Double(step) / 20.0
            let f = MusicalTheory.frequency(
                forNormalizedX: x,
                scale: .free,
                root: .c,
                preset: .balanced,
                octaveShift: 0
            )
            #expect(f > prev)
            prev = f
        }
    }

    @Test("Pentatonic minor quantization produces only valid scale pitch classes")
    func pentatonicQuantization() {
        let allowed = Set([0, 3, 5, 7, 10].map { ($0 + RootNote.a.rawValue) % 12 })
        for step in 0...50 {
            let x = Double(step) / 50.0
            let hz = MusicalTheory.frequency(
                forNormalizedX: x,
                scale: .pentatonicMinor,
                root: .a,
                preset: .balanced,
                octaveShift: 0
            )
            let midi = Int(MusicalTheory.midi(forHz: hz).rounded())
            let pc = ((midi % 12) + 12) % 12
            #expect(allowed.contains(pc))
        }
    }

    @Test("Tactile sub-feel maps high notes into fingertip mechanoreceptor sweet spot")
    func tactileSubFeelRange() {
        #expect(HapticSynthEngine.tactileSubFrequency(forFundamental: 180.0) == nil)
        let sub880 = HapticSynthEngine.tactileSubFrequency(forFundamental: 880.0)
        #expect(sub880 != nil)
        #expect(abs(sub880! - 220.0) < 0.01)

        let sub1760 = HapticSynthEngine.tactileSubFrequency(forFundamental: 1760.0)
        #expect(sub1760 != nil)
        #expect(sub1760! >= 110.0 && sub1760! <= 245.0)
    }

    @Test("Phase-coherent slice duration finishes on integer wave cycles")
    func phaseCoherentDuration() {
        for hz in [110.0, 220.0, 440.0, 1046.5, 2200.0] {
            let sec = HapticSynthEngine.phaseCoherentDurationSeconds(phaseReferenceHz: hz, targetSeconds: 0.020)
            #expect(sec >= 0.011 && sec <= 0.036)
            let cycles = sec * hz
            let frac = abs(cycles - cycles.rounded())
            #expect(frac < 0.001, "Expected integer cycles for \(hz) Hz, got \(cycles)")
        }
    }

    @Test("Anti-stall safety invariants: <= 6 tones, sum == 1.0, safe Hz and level")
    func antiStallInvariants() {
        var params = SynthParameters()
        params.timbre = .brassSaw
        params.subFeelAmount = 0.40
        params.masterVolume = 1.0

        let voices: [(hz: Double, volume: Double, brightness: Double)] = [
            (440.0, 0.9, 1.0),
            (554.37, 0.85, 1.0),
            (659.25, 0.8, 1.0),
            (880.0, 0.75, 1.0)
        ]

        let slice = HapticSynthEngine.buildSlice(voices: voices, params: params)
        #expect(slice != nil)
        guard let slice else { return }

        #expect(slice.tones.count <= MultitouchBridge.maxSimultaneousTones)
        #expect(slice.tones.count >= 1)

        let ampSum = slice.tones.reduce(0.0) { $0 + $1.amp }
        #expect(abs(ampSum - 1.0) < 0.001)
        #expect(slice.level > 0.0 && slice.level <= 1.0)

        for tone in slice.tones {
            #expect(tone.hz >= MultitouchBridge.minSafeFrequencyHz)
            #expect(tone.hz <= MultitouchBridge.maxSafeFrequencyHz)
            #expect(tone.amp > 0.0 && tone.amp <= 1.0)
        }
    }

    @Test("Axis mapping modes map Y and contact size as expected")
    func axisMappingModes() {
        var params = SynthParameters()
        let lowLight = TouchContact(id: 1, x: 0.5, y: 0.1, size: 0.25)
        let highFirm = TouchContact(id: 1, x: 0.5, y: 0.9, size: 1.1)

        params.mappingMode = .xyPitchVolume
        let xyLow = HapticSynthEngine.evaluateAxisMapping(contact: lowLight, params: params)
        let xyHigh = HapticSynthEngine.evaluateAxisMapping(contact: highFirm, params: params)
        #expect(xyHigh.volume > xyLow.volume + 0.5)

        params.mappingMode = .pressureVolumeYTimbre
        let ptLow = HapticSynthEngine.evaluateAxisMapping(contact: lowLight, params: params)
        let ptHigh = HapticSynthEngine.evaluateAxisMapping(contact: highFirm, params: params)
        #expect(ptHigh.volume > ptLow.volume + 0.4)
        #expect(ptHigh.brightness > ptLow.brightness + 0.6)

        params.mappingMode = .pressureVolumeYVibrato
        let pvLow = HapticSynthEngine.evaluateAxisMapping(contact: lowLight, params: params)
        let pvHigh = HapticSynthEngine.evaluateAxisMapping(contact: highFirm, params: params)
        #expect(pvHigh.vibratoDepth > pvLow.vibratoDepth + 0.4)
    }

    @Test("Engine real-time loop synthesizes from virtual touch and releases cleanly")
    func engineVirtualTouchLifecycle() async throws {
        let mock = MockActuator()
        let engine = HapticSynthEngine(actuator: mock, audioMirror: nil)
        engine.start()
        defer { engine.stop() }

        engine.setVirtualTouch(x: 0.6, y: 0.8, down: true)
        try await Task.sleep(for: .milliseconds(90))

        let activeSnap = engine.snapshot()
        #expect(activeSnap.isSounding == true)
        #expect(activeSnap.activeVoices.count == 1)
        #expect(activeSnap.primaryHz > 100.0)
        #expect(!mock.recordedCalls().isEmpty)

        engine.setVirtualTouch(x: 0.6, y: 0.8, down: false)
        try await Task.sleep(for: .milliseconds(160))

        let releasedSnap = engine.snapshot()
        #expect(releasedSnap.isSounding == false)
        #expect(releasedSnap.activeVoices.isEmpty)
    }

    @Test("Audio oscillator bank renders bounded smooth audio and decays cleanly to silence")
    func audioOscillatorBankRenderAndRelease() {
        let bank = AudioOscillatorBank()
        bank.setOutputGain(0.85)
        bank.update(
            tones: [
                HapticTone(hz: 440.0, amp: 0.7),
                HapticTone(hz: 880.0, amp: 0.3)
            ],
            level: 0.9
        )

        let sr = 48_000.0
        var buf = [Float](repeating: 0, count: 1024)
        buf.withUnsafeMutableBufferPointer { ptr in
            bank.render(into: ptr.baseAddress!, frameCount: ptr.count, sampleRate: sr)
        }

        let peakActive = buf.map { abs($0) }.max() ?? 0
        let allFinite = buf.allSatisfy(\.isFinite)
        #expect(peakActive > 0.05)
        #expect(peakActive <= 1.0)
        #expect(allFinite)

        // Clear tones and render ~100 ms to confirm clean fade to silence
        bank.update(tones: [], level: 0)
        for _ in 0..<5 {
            buf.withUnsafeMutableBufferPointer { ptr in
                bank.render(into: ptr.baseAddress!, frameCount: ptr.count, sampleRate: sr)
            }
        }
        let tailPeak = buf.suffix(128).map { abs($0) }.max() ?? 1.0
        #expect(tailPeak < 0.005)
    }

    @Test("5-finger chord preserves all 5 fundamentals within the 6-tone actuator cap")
    func fiveFingerChordGuaranteesAllFundamentals() {
        var params = SynthParameters()
        params.timbre = .brassSaw
        params.subFeelAmount = 0.25
        params.maxVoices = 5
        params.masterVolume = 1.0

        let fiveHz = [220.0, 261.63, 329.63, 392.0, 493.88] // A minor 9 five-finger chord
        let voices = fiveHz.map { (hz: $0, volume: 0.8, brightness: 0.7) }

        let slice = HapticSynthEngine.buildSlice(voices: voices, params: params)
        #expect(slice != nil)
        guard let slice else { return }

        #expect(slice.tones.count <= MultitouchBridge.maxSimultaneousTones)
        #expect(slice.tones.count >= 5)

        let ampSum = slice.tones.reduce(0.0) { $0 + $1.amp }
        #expect(abs(ampSum - 1.0) < 0.001)

        for expectedHz in fiveHz {
            let found = slice.tones.contains { abs($0.hz - expectedHz) < 0.5 }
            #expect(found, "Expected fundamental \(expectedHz) Hz to be preserved in 5-finger chord")
        }
    }

    @Test("Engine tracks 5 simultaneous hardware fingers without dropping the 5th finger")
    func engineTracksFiveHardwareFingers() async throws {
        let mock = MockActuator()
        let engine = HapticSynthEngine(actuator: mock, audioMirror: nil)
        engine.updateParameters {
            $0.hardwareTouchArmed = true
            $0.maxVoices = 5
            $0.scale = .pentatonicMinor
        }
        engine.start()
        defer { engine.stop() }

        let fiveContacts: [TouchContact] = (1...5).map { idx in
            TouchContact(
                id: Int32(idx),
                fingerID: Int32(idx),
                state: 4,
                x: Double(idx) / 6.0,
                y: 0.75,
                size: 0.7
            )
        }
        mock.setContacts(fiveContacts)
        try await Task.sleep(for: .milliseconds(90))

        let snap = engine.snapshot()
        #expect(snap.isSounding == true)
        #expect(snap.activeVoices.count == 5)

        // Simulate a brief 15 ms capacitive flicker dropping finger 5; 32 ms grace window should hold all 5 steady
        mock.setContacts(Array(fiveContacts.prefix(4)))
        try await Task.sleep(for: .milliseconds(15))
        mock.setContacts(fiveContacts)
        try await Task.sleep(for: .milliseconds(45))

        let steadySnap = engine.snapshot()
        #expect(steadySnap.activeVoices.count == 5)
    }

    @Test("AppVersion SemVer parsing and comparison works with v-prefixes")
    func appVersionParsingAndComparison() {
        let v1 = AppVersion(parsing: "v0.2.0")
        let v2 = AppVersion(parsing: "0.2.1")
        let v3 = AppVersion(parsing: "v1.0.0-beta.1")
        #expect(v1 != nil && v2 != nil && v3 != nil)
        #expect(v1! < v2!)
        #expect(v2! < v3!)
        #expect(AppVersion(parsing: "0.2.0") == v1)
    }

    @Test("GitHub release JSON parser extracts latest macOS zip asset")
    func gitHubReleaseParsing() {
        let json = """
        {
          "tag_name": "v0.3.0",
          "name": "XYNTH-1 v0.3.0",
          "body": "Improved 5-finger response and auto-updates.",
          "html_url": "https://github.com/mj0lken/xynth-1/releases/tag/v0.3.0",
          "published_at": "2026-11-23T22:00:00Z",
          "assets": [
            {
              "name": "XYNTH-1-v0.3.0-macos.zip",
              "browser_download_url": "https://github.com/mj0lken/xynth-1/releases/download/v0.3.0/XYNTH-1-v0.3.0-macos.zip"
            }
          ]
        }
        """.data(using: .utf8)!

        let info = AppUpdateService.parseGitHubReleaseJSON(json)
        #expect(info != nil)
        #expect(info?.version == AppVersion(major: 0, minor: 3, patch: 0))
        #expect(info?.zipAssetURL?.lastPathComponent == "XYNTH-1-v0.3.0-macos.zip")
    }
}
