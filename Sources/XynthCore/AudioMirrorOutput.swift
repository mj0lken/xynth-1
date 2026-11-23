import AVFoundation
import AudioToolbox
import CoreAudio
import Foundation
import Darwin

/// Describes an available macOS CoreAudio output device (Built-in Speakers, Headphones, BlackHole, etc.).
public struct AudioOutputDeviceInfo: Sendable, Equatable, Identifiable {
    public let id: AudioDeviceID
    public let name: String
    public let uid: String
    public let isDefault: Bool

    public init(id: AudioDeviceID, name: String, uid: String, isDefault: Bool) {
        self.id = id
        self.name = name
        self.uid = uid
        self.isDefault = isDefault
    }
}

/// Real-time safe phase-continuous additive oscillator bank rendered on CoreAudio's render thread.
/// Mirrors the exact partial stack (`HapticTone`s) driving the trackpad actuator without clicks or allocations.
public final class AudioOscillatorBank: @unchecked Sendable {
    private static let slotCount = 12

    private struct Slot {
        var phase: Double = 0.0
        var currentHz: Double = 440.0
        var targetHz: Double = 440.0
        var currentAmp: Double = 0.0
        var targetAmp: Double = 0.0
        var inUse: Bool = false
    }

    private var lock = os_unfair_lock()
    private var slots: [Slot] = Array(repeating: Slot(), count: AudioOscillatorBank.slotCount)
    private var outputGain: Double = 0.78

    public init() {}

    public func setOutputGain(_ gain: Double) {
        os_unfair_lock_lock(&lock)
        outputGain = min(1.0, max(0.0, gain))
        os_unfair_lock_unlock(&lock)
    }

    /// Updates target partials from the haptic synth loop.
    /// Matches incoming frequencies to nearby active oscillator slots to preserve continuous phase.
    public func update(tones: [HapticTone], level: Float) {
        let clampedLevel = Double(min(1.0, max(0.0, level)))

        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }

        guard clampedLevel > 0.0005, !tones.isEmpty else {
            for i in 0..<Self.slotCount {
                slots[i].targetAmp = 0.0
            }
            return
        }

        var slotClaimed = [Bool](repeating: false, count: Self.slotCount)
        var unmatchedTones: [HapticTone] = []

        // Pass 1: match each incoming tone to the closest active slot (within ~25% pitch delta) for smooth glides
        for tone in tones.prefix(Self.slotCount) {
            let hz = max(30.0, min(8000.0, tone.hz))
            let amp = max(0.0, tone.amp) * clampedLevel
            guard amp > 0.0002 else { continue }

            var bestIdx: Int? = nil
            var bestRatioDist = Double.greatestFiniteMagnitude

            for i in 0..<Self.slotCount where !slotClaimed[i] && slots[i].inUse {
                let ratio = abs(log2(hz / max(20.0, slots[i].currentHz)))
                if ratio < 0.35 && ratio < bestRatioDist {
                    bestRatioDist = ratio
                    bestIdx = i
                }
            }

            if let idx = bestIdx {
                slotClaimed[idx] = true
                slots[idx].targetHz = hz
                slots[idx].targetAmp = amp
                slots[idx].inUse = true
            } else {
                unmatchedTones.append(HapticTone(hz: hz, amp: amp))
            }
        }

        // Pass 2: assign new tones to free or quietest unclaimed slots (starting from 0 amp for click-free onset)
        for tone in unmatchedTones {
            var chosenIdx: Int? = nil
            var lowestAmp = Double.greatestFiniteMagnitude
            for i in 0..<Self.slotCount where !slotClaimed[i] {
                if !slots[i].inUse {
                    chosenIdx = i
                    break
                }
                if slots[i].currentAmp < lowestAmp {
                    lowestAmp = slots[i].currentAmp
                    chosenIdx = i
                }
            }
            if let idx = chosenIdx {
                slotClaimed[idx] = true
                slots[idx].currentHz = tone.hz
                slots[idx].targetHz = tone.hz
                slots[idx].targetAmp = tone.amp
                if !slots[idx].inUse || slots[idx].currentAmp < 0.002 {
                    slots[idx].currentAmp = 0.0
                    slots[idx].phase = 0.0
                }
                slots[idx].inUse = true
            }
        }

        // Pass 3: gracefully fade out any unclaimed slots
        for i in 0..<Self.slotCount where !slotClaimed[i] {
            slots[i].targetAmp = 0.0
        }
    }

    public func silenceImmediately() {
        os_unfair_lock_lock(&lock)
        for i in 0..<Self.slotCount {
            slots[i].targetAmp = 0.0
            slots[i].currentAmp = 0.0
            slots[i].inUse = false
        }
        os_unfair_lock_unlock(&lock)
    }

    /// Renders `frameCount` mono samples into `outBuffer` at `sampleRate`.
    /// Designed to be allocation-free and safe on CoreAudio's real-time render thread.
    public func render(into outBuffer: UnsafeMutablePointer<Float>, frameCount: Int, sampleRate: Double) {
        let sr = max(8000.0, sampleRate)
        let twoPiOverSR = (2.0 * Double.pi) / sr
        // ~4.5 ms attack / ~14 ms release & ~6 ms frequency smoothing for zero clicks
        let attackCoeff = 1.0 - exp(-1.0 / (0.0045 * sr))
        let releaseCoeff = 1.0 - exp(-1.0 / (0.014 * sr))
        let hzCoeff = 1.0 - exp(-1.0 / (0.006 * sr))

        os_unfair_lock_lock(&lock)
        let gain = outputGain * 0.55

        for frame in 0..<frameCount {
            var mix = 0.0
            for i in 0..<Self.slotCount {
                guard slots[i].inUse || slots[i].targetAmp > 0.0001 else { continue }
                let targetAmp = slots[i].targetAmp
                let coeff = targetAmp >= slots[i].currentAmp ? attackCoeff : releaseCoeff
                slots[i].currentAmp += (targetAmp - slots[i].currentAmp) * coeff
                slots[i].currentHz += (slots[i].targetHz - slots[i].currentHz) * hzCoeff

                let amp = slots[i].currentAmp
                if amp < 0.00008 && targetAmp == 0.0 {
                    slots[i].currentAmp = 0.0
                    slots[i].inUse = false
                    continue
                }

                mix += sin(slots[i].phase) * amp
                var nextPhase = slots[i].phase + slots[i].currentHz * twoPiOverSR
                if nextPhase >= 2.0 * Double.pi {
                    nextPhase -= 2.0 * Double.pi
                }
                slots[i].phase = nextPhase
            }

            // Soft tanh limiter keeps screen recordings clean with zero digital clipping
            let sample = tanh(mix * gain)
            outBuffer[frame] = Float(sample)
        }
        os_unfair_lock_unlock(&lock)
    }
}

/// Optional real-time CoreAudio / AVAudioEngine mirror that routes the trackpad synthesizer
/// to MacBook speakers, headphones, or virtual recording buses (e.g. BlackHole / Screen Recording).
public final class AudioMirrorOutput: @unchecked Sendable {
    private let bank = AudioOscillatorBank()
    private var lock = os_unfair_lock()

    private var engine: AVAudioEngine?
    private var sourceNode: AVAudioSourceNode?
    private var _isEnabled = false
    private var _selectedDeviceID: AudioDeviceID? = nil
    private var _lastError: String? = nil

    public init() {}

    deinit {
        shutdown()
    }

    public var isEnabled: Bool {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        return _isEnabled
    }

    public var selectedDeviceID: AudioDeviceID? {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        return _selectedDeviceID
    }

    public var lastError: String? {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        return _lastError
    }

    public func setOutputGain(_ gain: Double) {
        bank.setOutputGain(gain)
    }

    public func update(tones: [HapticTone], level: Float) {
        os_unfair_lock_lock(&lock)
        let enabled = _isEnabled
        os_unfair_lock_unlock(&lock)
        guard enabled else { return }
        bank.update(tones: tones, level: level)
    }

    @discardableResult
    public func setEnabled(_ enabled: Bool) -> Bool {
        os_unfair_lock_lock(&lock)
        let currentlyEnabled = _isEnabled
        let devID = _selectedDeviceID
        os_unfair_lock_unlock(&lock)

        if enabled == currentlyEnabled { return true }
        if enabled {
            return startEngine(deviceID: devID)
        } else {
            stopEngine()
            return true
        }
    }

    @discardableResult
    public func selectDevice(_ deviceID: AudioDeviceID?) -> Bool {
        os_unfair_lock_lock(&lock)
        _selectedDeviceID = deviceID
        let shouldRestart = _isEnabled
        os_unfair_lock_unlock(&lock)

        if shouldRestart {
            stopEngine()
            return startEngine(deviceID: deviceID)
        }
        return true
    }

    public func shutdown() {
        stopEngine()
    }

    // MARK: - CoreAudio Device Enumeration

    public static func defaultOutputDeviceID() -> AudioDeviceID? {
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
        ) == noErr, device != 0 else {
            return nil
        }
        return device
    }

    public static func availableOutputDevices() -> [AudioOutputDeviceInfo] {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &addr,
            0,
            nil,
            &dataSize
        ) == noErr, dataSize > 0 else {
            return []
        }

        let count = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &addr,
            0,
            nil,
            &dataSize,
            &deviceIDs
        ) == noErr else {
            return []
        }

        let defaultID = defaultOutputDeviceID()
        var results: [AudioOutputDeviceInfo] = []

        for id in deviceIDs {
            guard outputChannelCount(for: id) > 0 else { continue }
            let name = stringProperty(kAudioObjectPropertyName, for: id) ?? "Output Device \(id)"
            let uid = stringProperty(kAudioDevicePropertyDeviceUID, for: id) ?? "\(id)"
            results.append(AudioOutputDeviceInfo(id: id, name: name, uid: uid, isDefault: id == defaultID))
        }

        return results.sorted { lhs, rhs in
            if lhs.isDefault != rhs.isDefault { return lhs.isDefault }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    // MARK: - Private AVAudioEngine Lifecycle

    private func startEngine(deviceID: AudioDeviceID?) -> Bool {
        stopEngine()

        let newEngine = AVAudioEngine()
        let outputNode = newEngine.outputNode

        // Route to a specific CoreAudio device if the user picked one (e.g. BlackHole or Speakers)
        if let targetID = deviceID, let audioUnit = outputNode.audioUnit {
            var devID = targetID
            let status = AudioUnitSetProperty(
                audioUnit,
                kAudioOutputUnitProperty_CurrentDevice,
                kAudioUnitScope_Global,
                0,
                &devID,
                UInt32(MemoryLayout<AudioDeviceID>.size)
            )
            if status != noErr {
                os_unfair_lock_lock(&lock)
                _lastError = "Could not select audio output device (OSStatus \(status))."
                os_unfair_lock_unlock(&lock)
                return false
            }
        }

        let outputFormat = outputNode.outputFormat(forBus: 0)
        let sampleRate = outputFormat.sampleRate > 0 ? outputFormat.sampleRate : 48_000.0
        let channelCount = max(1, min(2, outputFormat.channelCount))
        guard let renderFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: channelCount,
            interleaved: false
        ) else {
            return false
        }

        let oscBank = self.bank
        let node = AVAudioSourceNode(format: renderFormat) { _, _, frameCount, audioBufferList -> OSStatus in
            let frames = Int(frameCount)
            let abl = UnsafeMutableAudioBufferListPointer(audioBufferList)
            guard let firstData = abl.first?.mData?.assumingMemoryBound(to: Float.self) else {
                return noErr
            }

            oscBank.render(into: firstData, frameCount: frames, sampleRate: sampleRate)

            // Copy mono synth signal cleanly into remaining channels (e.g. stereo R)
            if abl.count > 1 {
                for ch in 1..<abl.count {
                    if let dst = abl[ch].mData?.assumingMemoryBound(to: Float.self) {
                        memcpy(dst, firstData, frames * MemoryLayout<Float>.size)
                    }
                }
            }
            return noErr
        }

        newEngine.attach(node)
        newEngine.connect(node, to: newEngine.mainMixerNode, format: renderFormat)
        newEngine.connect(newEngine.mainMixerNode, to: outputNode, format: renderFormat)
        newEngine.prepare()

        do {
            try newEngine.start()
            os_unfair_lock_lock(&lock)
            self.engine = newEngine
            self.sourceNode = node
            self._isEnabled = true
            self._lastError = nil
            os_unfair_lock_unlock(&lock)
            return true
        } catch {
            os_unfair_lock_lock(&lock)
            self._isEnabled = false
            self._lastError = error.localizedDescription
            os_unfair_lock_unlock(&lock)
            return false
        }
    }

    private func stopEngine() {
        bank.silenceImmediately()

        os_unfair_lock_lock(&lock)
        let oldEngine = engine
        engine = nil
        sourceNode = nil
        _isEnabled = false
        os_unfair_lock_unlock(&lock)

        if let oldEngine {
            oldEngine.stop()
            oldEngine.reset()
        }
    }

    private static func outputChannelCount(for deviceID: AudioDeviceID) -> Int {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(deviceID, &addr, 0, nil, &size) == noErr, size > 0 else {
            return 0
        }
        let rawPtr = UnsafeMutableRawPointer.allocate(
            byteCount: Int(size),
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { rawPtr.deallocate() }

        guard AudioObjectGetPropertyData(deviceID, &addr, 0, nil, &size, rawPtr) == noErr else {
            return 0
        }

        let bufferList = UnsafeMutableAudioBufferListPointer(rawPtr.assumingMemoryBound(to: AudioBufferList.self))
        return bufferList.reduce(0) { $0 + Int($1.mNumberChannels) }
    }

    private static func stringProperty(_ selector: AudioObjectPropertySelector, for deviceID: AudioDeviceID) -> String? {
        var addr = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var cfStr: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(deviceID, &addr, 0, nil, &size, &cfStr) == noErr,
              let value = cfStr?.takeRetainedValue() else {
            return nil
        }
        return value as String
    }
}
