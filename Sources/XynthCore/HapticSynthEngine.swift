import CoreAudio
import Foundation
import Darwin

/// Live voice snapshot rendered on the UI trackpad mirror and telemetry bar.
public struct ActiveVoiceSnapshot: Sendable, Equatable, Identifiable {
    public let id: Int32
    public let x: Double
    public let y: Double
    public let size: Double
    public let hz: Double
    public let note: NoteReadout
    public let volume: Double
    public let isHeld: Bool

    public init(
        id: Int32,
        x: Double,
        y: Double,
        size: Double,
        hz: Double,
        note: NoteReadout,
        volume: Double,
        isHeld: Bool
    ) {
        self.id = id
        self.x = x
        self.y = y
        self.size = size
        self.hz = hz
        self.note = note
        self.volume = volume
        self.isHeld = isHeld
    }
}

/// Complete immutable telemetry snapshot published from the real-time haptic synth loop.
public struct SynthSnapshot: Sendable, Equatable {
    public let isSounding: Bool
    public let hardwareStatus: HapticHardwareStatus
    public let rawTouches: [TouchContact]
    public let activeVoices: [ActiveVoiceSnapshot]
    public let outputTones: [HapticTone]
    public let primaryHz: Double
    public let primaryNote: NoteReadout
    public let effectiveLevel: Double
    public let sliceDurationMs: Double
    public let actuationCount: UInt64
    public let demoLabel: String?

    public static let idle = SynthSnapshot(
        isSounding: false,
        hardwareStatus: .frameworkUnavailable("Starting"),
        rawTouches: [],
        activeVoices: [],
        outputTones: [],
        primaryHz: 0,
        primaryNote: NoteReadout(name: "—", cents: 0, midi: 0),
        effectiveLevel: 0,
        sliceDurationMs: 0,
        actuationCount: 0,
        demoLabel: nil
    )
}

/// Output of one deterministic synthesis slice.
public struct SynthesizedSlice: Sendable, Equatable {
    public let tones: [HapticTone]
    public let durationMs: Double
    public let level: Float
    public let primaryHz: Double
}

/// Real-time Force Touch haptic synthesis engine.
///
/// Runs a `QOS_CLASS_USER_INTERACTIVE` timing loop driven by `mach_absolute_time()`,
/// translating multi-finger trackpad coordinates (X = pitch, Y = volume/expression, contact size = pressure)
/// into phase-coherent multi-partial sinusoidal actuations on the MacBook's Taptic Engine.
public final class HapticSynthEngine: @unchecked Sendable {
    let actuator: HapticActuatorOutput
    let audioMirror: AudioMirrorOutput?

    private var lock = os_unfair_lock()
    private var _parameters = SynthParameters()
    private var _virtualTouch: TouchContact? = nil
    private var _snapshot: SynthSnapshot = .idle
    private var _running = false
    private var _pendingDemo: DemoRequest? = nil
    private var _clearHeldRequested = false

    private var workerThread: Thread?

    private struct VoiceState {
        let id: Int32
        var x: Double
        var y: Double
        var size: Double
        var currentHz: Double
        var targetHz: Double
        var currentVolume: Double
        var targetVolume: Double
        var brightness: Double
        var vibratoDepth: Double
        var startedAt: Double
        var lastSeenAt: Double
        var isReleasing: Bool
        var isHeld: Bool
    }

    let ticksPerSecond: Double
    private let startTick: UInt64

    @inline(__always)
    private func withLock<T>(_ body: () -> T) -> T {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        return body()
    }

    public init(
        actuator: HapticActuatorOutput = MultitouchBridge(),
        audioMirror: AudioMirrorOutput? = AudioMirrorOutput()
    ) {
        self.actuator = actuator
        self.audioMirror = audioMirror
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        self.ticksPerSecond = 1e9 * Double(info.denom) / Double(info.numer)
        self.startTick = mach_absolute_time()
        self._snapshot = SynthSnapshot(
            isSounding: false,
            hardwareStatus: actuator.status,
            rawTouches: [],
            activeVoices: [],
            outputTones: [],
            primaryHz: 0,
            primaryNote: NoteReadout(name: "—", cents: 0, midi: 0),
            effectiveLevel: 0,
            sliceDurationMs: 0,
            actuationCount: 0,
            demoLabel: nil
        )
    }

    deinit {
        stop()
        audioMirror?.shutdown()
        actuator.shutdown()
    }

    // MARK: - Public API

    public var parameters: SynthParameters {
        get { withLock { _parameters } }
        set { withLock { _parameters = newValue } }
    }

    public func updateParameters(_ mutate: (inout SynthParameters) -> Void) {
        withLock { mutate(&_parameters) }
    }

    public var hardwareStatus: HapticHardwareStatus {
        actuator.status
    }

    public var availableDevices: [TrackpadDeviceInfo] {
        actuator.availableDevices
    }

    public func snapshot() -> SynthSnapshot {
        withLock { _snapshot }
    }

    /// Sets or clears a virtual finger from clicking/dragging directly on the on-screen XY pad.
    public func setVirtualTouch(x: Double, y: Double, down: Bool, size: Double = 0.72) {
        withLock {
            _virtualTouch = down
                ? TouchContact(id: 9001, fingerID: 9001, state: 4, x: x, y: y, size: size)
                : nil
        }
    }

    /// Triggers a 3.2-second acoustic & tactile frequency sweep (98 Hz → 3.6 kHz) directly on the trackpad.
    public func triggerSweepDemo() {
        withLock { _pendingDemo = .sweep }
    }

    /// Plays a short luminous chord arpeggio directly on the trackpad as a quick check.
    public func triggerArpeggioDemo() {
        withLock { _pendingDemo = .arpeggio }
    }

    /// Plays two felt-and-heard low tactile heartbeat thumps.
    public func triggerHeartbeatDemo() {
        withLock { _pendingDemo = .heartbeat }
    }

    /// Plays a 4.6-second expressive multi-finger musical demo (melodic hook + shimmering 3-finger chord + glide).
    public func triggerShortDemo() {
        withLock { _pendingDemo = .shortDemo }
    }

    public func cancelDemo() {
        withLock { _pendingDemo = nil }
    }

    /// Clears any frozen multi-touch chord in Hold mode so manual pitch/volume faders take over immediately.
    public func clearHeldContacts() {
        withLock { _clearHeldRequested = true }
    }

    @discardableResult
    public func reconnectHardware(deviceID: UInt64? = nil) -> HapticHardwareStatus {
        let st = actuator.reconnect(deviceID: deviceID)
        if st.isReady {
            _ = actuator.startTouchCapture()
        }
        return st
    }

    // MARK: - Audio Mirror Output (Speakers / Virtual Recording Bus)

    public var isAudioMirrorEnabled: Bool {
        audioMirror?.isEnabled ?? false
    }

    public var audioMirrorError: String? {
        audioMirror?.lastError
    }

    public var selectedAudioOutputDeviceID: AudioDeviceID? {
        audioMirror?.selectedDeviceID
    }

    public func availableAudioOutputDevices() -> [AudioOutputDeviceInfo] {
        AudioMirrorOutput.availableOutputDevices()
    }

    @discardableResult
    public func setAudioMirrorEnabled(_ enabled: Bool) -> Bool {
        audioMirror?.setEnabled(enabled) ?? false
    }

    @discardableResult
    public func selectAudioOutputDevice(_ deviceID: AudioDeviceID?) -> Bool {
        audioMirror?.selectDevice(deviceID) ?? false
    }

    public func setAudioOutputGain(_ gain: Double) {
        audioMirror?.setOutputGain(gain)
    }

    public func start() {
        let alreadyRunning = withLock {
            if _running { return true }
            _running = true
            return false
        }
        guard !alreadyRunning else { return }

        if actuator.status.isReady {
            _ = actuator.startTouchCapture()
        }

        let thread = Thread { [weak self] in
            self?.runLoop()
        }
        thread.name = "com.xynth1.haptic-synth-loop"
        thread.qualityOfService = .userInteractive
        self.workerThread = thread
        thread.start()
    }

    public func stop() {
        withLock {
            _running = false
            _pendingDemo = nil
        }
        audioMirror?.update(tones: [], level: 0)
        audioMirror?.shutdown()
        actuator.stopTouchCapture()
    }

    // MARK: - Pure Deterministic Synthesis Helpers (Unit-Testable)

    /// Computes tactile sub-octave frequency in the fingertip mechanoreceptor sweet spot (115...245 Hz).
    public static func tactileSubFrequency(forFundamental hz: Double) -> Double? {
        guard hz > 310.0 else { return nil }
        var sub = hz * 0.5
        while sub > 245.0 && sub * 0.5 >= 110.0 {
            sub *= 0.5
        }
        guard sub >= 100.0 && sub <= 260.0 else { return nil }
        return sub
    }

    /// Computes phase-coherent segment duration in seconds (~16...28 ms), snapping to an integer
    /// number of wave cycles of `phaseReferenceHz` so consecutive sine actuations stitch seamlessly at phase 0.
    public static func phaseCoherentDurationSeconds(
        phaseReferenceHz: Double,
        targetSeconds: Double = 0.020
    ) -> Double {
        let f = max(MultitouchBridge.minSafeFrequencyHz, min(MultitouchBridge.maxSafeFrequencyHz, phaseReferenceHz))
        let cycles = max(1.0, (targetSeconds * f).rounded())
        let seg = cycles / f
        return min(0.036, max(0.011, seg))
    }

    /// Computes per-voice `(targetVolume, brightness, vibratoDepth)` for a contact under the selected mapping mode.
    public static func evaluateAxisMapping(
        contact: TouchContact,
        params: SynthParameters
    ) -> (volume: Double, brightness: Double, vibratoDepth: Double) {
        let clampedY = min(1.0, max(0.0, contact.y))
        let normalizedPressure = min(1.0, max(0.0, (contact.size - 0.14) / 1.05))

        switch params.mappingMode {
        case .xyPitchVolume:
            // Smooth perceptual loudness ramp from bottom (quiet whisper) to top (full intensity).
            let vol: Double
            if clampedY < 0.02 {
                vol = (clampedY / 0.02) * 0.06
            } else {
                vol = 0.06 + 0.94 * pow((clampedY - 0.02) / 0.98, 0.78)
            }
            // Finger flatness subtly opens harmonic brightness for organic tactile response.
            let bright = min(1.0, max(0.0, params.brightness * 0.7 + normalizedPressure * 0.35))
            return (vol, bright, params.vibratoDepth)

        case .pressureVolumeYTimbre:
            let vol = min(1.0, max(0.14, 0.14 + normalizedPressure * 0.86))
            return (vol, clampedY, params.vibratoDepth)

        case .pressureVolumeYVibrato:
            let vol = min(1.0, max(0.14, 0.14 + normalizedPressure * 0.86))
            let vib = 0.03 + clampedY * 0.65
            return (vol, params.brightness, vib)
        }
    }

    /// Mixes up to 5 active voices into a single actuator-safe slice (≤ 6 tones, normalized amplitudes, phase-locked window).
    /// Guarantees every active finger's fundamental frequency is preserved before allocating remaining slots to harmonics/sub-feel.
    public static func buildSlice(
        voices: [(hz: Double, volume: Double, brightness: Double)],
        params: SynthParameters
    ) -> SynthesizedSlice? {
        let active = voices.filter { $0.volume > 0.012 && $0.hz.isFinite }
        guard !active.isEmpty else { return nil }

        let voiceCount = active.count
        let partialsPerVoice: Int
        switch voiceCount {
        case 1: partialsPerVoice = 5
        case 2: partialsPerVoice = 3
        case 3: partialsPerVoice = 2
        default: partialsPerVoice = 2 // 4-5 fingers: guarantee all fundamentals first, fill spare slot with strongest overtone/sub
        }

        var guaranteedFundamentals: [HapticTone] = []
        guaranteedFundamentals.reserveCapacity(voiceCount)
        var extraPartials: [HapticTone] = []
        extraPartials.reserveCapacity(10)

        var lowestPhaseRef = Double.greatestFiniteMagnitude
        var maxVoiceVol = 0.0

        for v in active {
            maxVoiceVol = max(maxVoiceVol, v.volume)
            let harmonics = params.timbre.partials(
                baseHz: v.hz,
                brightness: v.brightness,
                maxPartials: partialsPerVoice
            )
            let harmonicSum = max(0.0001, harmonics.reduce(0.0) { $0 + $1.amp })
            for (idx, h) in harmonics.enumerated() {
                let weighted = HapticTone(hz: h.hz, amp: (h.amp / harmonicSum) * v.volume)
                if idx == 0 {
                    guaranteedFundamentals.append(weighted)
                } else {
                    extraPartials.append(weighted)
                }
            }
            lowestPhaseRef = min(lowestPhaseRef, v.hz)

            // Inject tactile sub-octave feel for high notes whenever enabled (strongest bass anchor wins spare slot in 5-finger chords)
            if params.subFeelAmount > 0.01,
               let subHz = tactileSubFrequency(forFundamental: v.hz) {
                let subWeight = voiceCount <= 2 ? 0.72 : 0.55
                let subAmp = v.volume * params.subFeelAmount * subWeight
                extraPartials.append(HapticTone(hz: subHz, amp: subAmp))
                if voiceCount <= 3 {
                    lowestPhaseRef = min(lowestPhaseRef, subHz)
                }
            }
        }

        // 1. Always preserve every active finger's fundamental (up to 5 fingers)
        var selected: [HapticTone] = Array(
            guaranteedFundamentals
                .sorted { $0.amp > $1.amp }
                .prefix(MultitouchBridge.maxSimultaneousTones)
        )

        // 2. Fill remaining tone slots (up to 6 total) with strongest harmonics / tactile sub-feel
        let remainingSlots = max(0, MultitouchBridge.maxSimultaneousTones - selected.count)
        if remainingSlots > 0 && !extraPartials.isEmpty {
            selected.append(contentsOf: extraPartials.sorted { $0.amp > $1.amp }.prefix(remainingSlots))
        }

        let prioritized = selected.map {
            HapticTone(
                hz: min(MultitouchBridge.maxSafeFrequencyHz, max(MultitouchBridge.minSafeFrequencyHz, $0.hz)),
                amp: $0.amp
            )
        }

        guard !prioritized.isEmpty else { return nil }

        // Normalize tones so sum == 1.0 (anti-stall invariant)
        let toneSum = max(0.0001, prioritized.reduce(0.0) { $0 + $1.amp })
        let normalizedTones = prioritized.map { HapticTone(hz: $0.hz, amp: $0.amp / toneSum) }

        // Overall actuator level reflects peak voice volume with gentle polyphonic bloom, capped by masterVolume
        let polyScale = voiceCount > 1 ? min(1.0, maxVoiceVol + 0.10 * Double(voiceCount - 1)) : maxVoiceVol
        let finalLevel = Float(min(1.0, max(0.0, polyScale * params.masterVolume)))
        guard finalLevel > 0.004 else { return nil }

        let phaseHz = lowestPhaseRef.isFinite ? lowestPhaseRef : active[0].hz
        let durationSec = phaseCoherentDurationSeconds(phaseReferenceHz: phaseHz, targetSeconds: 0.020)

        // Primary displayed frequency is the highest-volume active fundamental
        let primaryHz = active.max(by: { $0.volume < $1.volume })?.hz ?? active[0].hz

        return SynthesizedSlice(
            tones: normalizedTones,
            durationMs: durationSec * 1000.0,
            level: finalLevel,
            primaryHz: primaryHz
        )
    }

    // MARK: - Real-time Synthesis Loop

    private func nowSeconds() -> Double {
        Double(mach_absolute_time() - startTick) / ticksPerSecond
    }

    func waitUntilTick(_ target: UInt64) {
        let spinMargin = UInt64(0.0014 * ticksPerSecond)
        while isRunning() {
            let current = mach_absolute_time()
            if current >= target { return }
            let remaining = target - current
            if remaining > spinMargin {
                let sleepUs = useconds_t(Double(remaining - spinMargin) / ticksPerSecond * 1_000_000.0)
                if sleepUs > 0 { usleep(sleepUs) }
            }
        }
    }

    func isRunning() -> Bool {
        withLock { _running }
    }

    private func runLoop() {
        pthread_set_qos_class_self_np(QOS_CLASS_USER_INTERACTIVE, 0)

        var voices: [Int32: VoiceState] = [:]
        var heldContacts: [TouchContact] = []
        var actuationCount: UInt64 = 0

        while isRunning() {
            let sliceStartTick = mach_absolute_time()
            let t = nowSeconds()

            // Pull parameters, virtual touch, and demo request in one quick lock
            let (params, virtualTouch, demo, shouldClearHeld) = withLock { () -> (SynthParameters, TouchContact?, DemoRequest?, Bool) in
                let nextDemo = _pendingDemo
                _pendingDemo = nil
                let clearHeld = _clearHeldRequested
                _clearHeldRequested = false
                return (_parameters, _virtualTouch, nextDemo, clearHeld)
            }

            if shouldClearHeld {
                heldContacts.removeAll(keepingCapacity: true)
            }

            // Handle one-shot demos (sweep / arpeggio / heartbeat)
            if let demo {
                runDemo(demo, params: params, actuationCount: &actuationCount)
                voices.removeAll()
                continue
            }

            let rawContacts = actuator.currentContacts()

            // Determine active driving contacts for synthesis (up to full 5-finger trackpad polyphony!)
            var drivingContacts: [TouchContact] = []
            if params.hardwareTouchArmed && !rawContacts.isEmpty {
                drivingContacts = Array(rawContacts.sorted { $0.id < $1.id }.prefix(max(1, min(5, params.maxVoices))))
            } else if let virtualTouch {
                drivingContacts = [virtualTouch]
            }

            // Hold / Drone mode management
            var usingHeld = false
            if params.holdDrone {
                if !drivingContacts.isEmpty {
                    heldContacts = drivingContacts
                } else if !heldContacts.isEmpty {
                    drivingContacts = heldContacts
                    usingHeld = true
                } else {
                    // Drone active with no prior finger: synthesize from manual X/Y sliders
                    drivingContacts = [
                        TouchContact(
                            id: 9900,
                            fingerID: 9900,
                            state: 4,
                            x: params.manualPitchX,
                            y: params.manualVolumeY,
                            size: 0.85
                        )
                    ]
                    usingHeld = true
                }
            } else {
                heldContacts.removeAll(keepingCapacity: true)
                if drivingContacts.isEmpty && params.manualSynthActive {
                    drivingContacts = [
                        TouchContact(
                            id: 9900,
                            fingerID: 9900,
                            state: 4,
                            x: params.manualPitchX,
                            y: params.manualVolumeY,
                            size: 0.85
                        )
                    ]
                    usingHeld = true
                }
            }

            // Reconcile voice table (attack / glide / release)
            let activeIDs = Set(drivingContacts.map(\.id))
            let glideAlpha = max(0.08, 1.0 - params.glideAmount * 0.86)

            for contact in drivingContacts {
                let targetHz = MusicalTheory.frequency(
                    forNormalizedX: contact.x,
                    scale: params.scale,
                    root: params.root,
                    preset: params.rangePreset,
                    octaveShift: params.octaveShift
                )
                let mapped = Self.evaluateAxisMapping(contact: contact, params: params)

                if var existing = voices[contact.id] {
                    existing.x = contact.x
                    existing.y = contact.y
                    existing.size = contact.size
                    existing.targetHz = targetHz
                    existing.currentHz *= pow(targetHz / max(20.0, existing.currentHz), glideAlpha)
                    existing.targetVolume = mapped.volume
                    existing.currentVolume += (mapped.volume - existing.currentVolume) * 0.55
                    existing.brightness = mapped.brightness
                    existing.vibratoDepth = mapped.vibratoDepth
                    existing.lastSeenAt = t
                    existing.isReleasing = false
                    existing.isHeld = usingHeld
                    voices[contact.id] = existing
                } else {
                    voices[contact.id] = VoiceState(
                        id: contact.id,
                        x: contact.x,
                        y: contact.y,
                        size: contact.size,
                        currentHz: targetHz,
                        targetHz: targetHz,
                        currentVolume: mapped.volume * 0.70, // Soft click-free onset
                        targetVolume: mapped.volume,
                        brightness: mapped.brightness,
                        vibratoDepth: mapped.vibratoDepth,
                        startedAt: t,
                        lastSeenAt: t,
                        isReleasing: false,
                        isHeld: usingHeld
                    )
                }
            }

            // Smooth release tail for lifted fingers with a 32 ms anti-flicker grace window
            // so brief capacitive dips on a 4th/5th finger never cut out mid-chord.
            let contactGraceSeconds = 0.032
            for id in Array(voices.keys) where !activeIDs.contains(id) {
                if var v = voices[id] {
                    if t - v.lastSeenAt < contactGraceSeconds && !v.isReleasing {
                        // Hold steady across a single-frame multitouch flicker
                        voices[id] = v
                    } else {
                        v.isReleasing = true
                        v.isHeld = false
                        v.currentVolume *= 0.42
                        if v.currentVolume < 0.025 {
                            voices.removeValue(forKey: id)
                        } else {
                            voices[id] = v
                        }
                    }
                }
            }

            // Apply per-voice vibrato LFO and prepare voice mix
            var voiceInputs: [(hz: Double, volume: Double, brightness: Double)] = []
            var voiceSnapshots: [ActiveVoiceSnapshot] = []
            let sortedVoices = voices.values.sorted { $0.id < $1.id }

            for v in sortedVoices {
                let age = max(0.0, t - v.startedAt)
                // Gentle vibrato fade-in over first 140 ms so attacks stay pitch-true
                let vibEnv = min(1.0, age / 0.14)
                let vibSemitones = v.vibratoDepth * vibEnv * sin(2.0 * .pi * params.vibratoRateHz * age)
                let modulatedHz = v.currentHz * pow(2.0, vibSemitones / 12.0)

                voiceInputs.append((hz: modulatedHz, volume: v.currentVolume, brightness: v.brightness))
                if !v.isReleasing {
                    voiceSnapshots.append(
                        ActiveVoiceSnapshot(
                            id: v.id,
                            x: v.x,
                            y: v.y,
                            size: v.size,
                            hz: modulatedHz,
                            note: MusicalTheory.noteReadout(forHz: modulatedHz),
                            volume: min(1.0, v.currentVolume * params.masterVolume),
                            isHeld: v.isHeld
                        )
                    )
                }
            }

            if let slice = Self.buildSlice(voices: voiceInputs, params: params) {
                emit(tones: slice.tones, durationMs: slice.durationMs, level: slice.level, hapticsEnabled: params.hapticsEnabled)
                actuationCount += 1

                let snap = SynthSnapshot(
                    isSounding: true,
                    hardwareStatus: actuator.status,
                    rawTouches: rawContacts,
                    activeVoices: voiceSnapshots,
                    outputTones: slice.tones,
                    primaryHz: slice.primaryHz,
                    primaryNote: MusicalTheory.noteReadout(forHz: slice.primaryHz),
                    effectiveLevel: Double(slice.level),
                    sliceDurationMs: slice.durationMs,
                    actuationCount: actuationCount,
                    demoLabel: nil
                )
                publishSnapshot(snap)

                let nextTick = sliceStartTick + UInt64((slice.durationMs / 1000.0) * ticksPerSecond)
                waitUntilTick(nextTick)
            } else {
                audioMirror?.update(tones: [], level: 0)
                let snap = SynthSnapshot(
                    isSounding: false,
                    hardwareStatus: actuator.status,
                    rawTouches: rawContacts,
                    activeVoices: [],
                    outputTones: [],
                    primaryHz: 0,
                    primaryNote: NoteReadout(name: "—", cents: 0, midi: 0),
                    effectiveLevel: 0,
                    sliceDurationMs: 0,
                    actuationCount: actuationCount,
                    demoLabel: nil
                )
                publishSnapshot(snap)
                usleep(6_000) // ~166 Hz idle responsiveness with <0.1% CPU usage
            }
        }
    }

    func emit(tones: [HapticTone], durationMs: Double, level: Float, hapticsEnabled: Bool) {
        if hapticsEnabled {
            actuator.play(tones: tones, durationMs: durationMs, level: level)
        }
        audioMirror?.update(tones: tones, level: level)
    }

    func hasUserInterrupt() -> Bool {
        let (hasVirtualTouch, armed) = withLock { (_virtualTouch != nil, _parameters.hardwareTouchArmed) }
        if hasVirtualTouch { return true }
        if armed && !actuator.currentContacts().isEmpty { return true }
        return false
    }

    func publishSnapshot(_ snap: SynthSnapshot) {
        withLock { _snapshot = snap }
    }
}
