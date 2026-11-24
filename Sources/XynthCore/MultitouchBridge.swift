import Foundation
import Darwin
import IOKit

/// Represents a single active finger contact read from the trackpad's MultitouchSupport hardware frame.
public struct TouchContact: Sendable, Equatable, Identifiable {
    public let id: Int32
    public let fingerID: Int32
    public let state: Int32
    /// Normalized horizontal position across the trackpad (`0.0` = left edge, `1.0` = right edge).
    public let x: Double
    /// Normalized vertical position across the trackpad (`0.0` = bottom edge, `1.0` = top edge).
    public let y: Double
    /// Normalized horizontal velocity.
    public let vx: Double
    /// Normalized vertical velocity.
    public let vy: Double
    /// Contact signal magnitude / area (`zTotal`), typically ~0.15 (feather light) to ~1.5+ (firm flat press).
    public let size: Double
    public let majorAxis: Double
    public let minorAxis: Double
    public let angle: Double

    public init(
        id: Int32,
        fingerID: Int32 = 0,
        state: Int32 = 4,
        x: Double,
        y: Double,
        vx: Double = 0,
        vy: Double = 0,
        size: Double = 0.6,
        majorAxis: Double = 0,
        minorAxis: Double = 0,
        angle: Double = 0
    ) {
        self.id = id
        self.fingerID = fingerID
        self.state = state
        self.x = min(1.0, max(0.0, x))
        self.y = min(1.0, max(0.0, y))
        self.vx = vx
        self.vy = vy
        self.size = max(0.0, size)
        self.majorAxis = majorAxis
        self.minorAxis = minorAxis
        self.angle = angle
    }
}

/// A single sinusoidal partial driven on the trackpad's Force Touch actuator.
public struct HapticTone: Sendable, Equatable {
    public let hz: Double
    public let amp: Double

    public init(hz: Double, amp: Double) {
        self.hz = hz
        self.amp = amp
    }
}

/// Hardware Force Touch trackpad descriptor.
public struct TrackpadDeviceInfo: Sendable, Equatable, Identifiable {
    public let id: UInt64
    public let isBuiltIn: Bool
    public let hasActuator: Bool

    public var displayName: String {
        isBuiltIn ? "Built-in Force Touch Trackpad" : "Magic Trackpad (\(String(id, radix: 16).suffix(4).uppercased()))"
    }
}

/// Connection/availability status of the private MultitouchSupport haptic motor.
public enum HapticHardwareStatus: Sendable, Equatable {
    case ready(TrackpadDeviceInfo)
    case frameworkUnavailable(String)
    case noTrackpadFound(isLaptop: Bool)
    case noForceTouchActuator
    case actuatorOpenFailed(Int32)

    public var isReady: Bool {
        if case .ready = self { return true }
        return false
    }

    public var shortLabel: String {
        switch self {
        case .ready(let info):
            return info.isBuiltIn ? "Built-in Force Touch" : "Magic Trackpad"
        case .frameworkUnavailable:
            return "API Unavailable"
        case .noTrackpadFound:
            return "No Trackpad Found"
        case .noForceTouchActuator:
            return "No Force Touch Motor"
        case .actuatorOpenFailed:
            return "Motor Busy"
        }
    }

    public var detailMessage: String {
        switch self {
        case .ready(let info):
            return "Connected directly to \(info.displayName) via MultitouchSupport."
        case .frameworkUnavailable(let reason):
            return "MultitouchSupport private framework unavailable: \(reason)"
        case .noTrackpadFound(let isLaptop):
            if isLaptop {
                return "No trackpad was detected. Ensure your trackpad is active and relaunch XYNTH-1."
            } else {
                return "No Force Touch trackpad found. Connect a Magic Trackpad 2 or newer and reconnect."
            }
        case .noForceTouchActuator:
            return "A trackpad was found, but it lacks a Force Touch haptic actuator (requires a 2015+ MacBook or Magic Trackpad 2+)."
        case .actuatorOpenFailed(let code):
            return "Could not open the trackpad haptic actuator (error \(code))."
        }
    }
}

/// Abstract output interface so the synth engine can drive real hardware or be unit-tested cleanly.
public protocol HapticActuatorOutput: AnyObject, Sendable {
    var status: HapticHardwareStatus { get }
    var availableDevices: [TrackpadDeviceInfo] { get }
    func currentContacts() -> [TouchContact]
    func play(tones: [HapticTone], durationMs: Double, level: Float)
    func startTouchCapture() -> Bool
    func stopTouchCapture()
    func reconnect(deviceID: UInt64?) -> HapticHardwareStatus
    func shutdown()
}

// MARK: - Module-level C callback state

private final class TouchFrameStore: @unchecked Sendable {
    static let shared = TouchFrameStore()
    private var lock = os_unfair_lock()
    private var contacts: [TouchContact] = []

    func update(_ newContacts: [TouchContact]) {
        os_unfair_lock_lock(&lock)
        contacts = newContacts
        os_unfair_lock_unlock(&lock)
    }

    func read() -> [TouchContact] {
        os_unfair_lock_lock(&lock)
        let copy = contacts
        os_unfair_lock_unlock(&lock)
        return copy
    }

    func clear() {
        os_unfair_lock_lock(&lock)
        contacts.removeAll(keepingCapacity: true)
        os_unfair_lock_unlock(&lock)
    }
}

private typealias MTCreateListFn = @convention(c) () -> Unmanaged<CFArray>?
private typealias MTGetIDFn = @convention(c) (UnsafeMutableRawPointer, UnsafeMutablePointer<UInt64>) -> Int32
private typealias MTIsBuiltInFn = @convention(c) (UnsafeMutableRawPointer) -> Bool
private typealias MTActuatorCreateFn = @convention(c) (UInt64) -> Unmanaged<CFTypeRef>?
private typealias MTActuatorOpenFn = @convention(c) (CFTypeRef) -> Int32
private typealias MTActuatorCloseFn = @convention(c) (CFTypeRef) -> Int32
private typealias MTActuationCreateFn = @convention(c) (CFDictionary, Int32) -> UnsafeMutableRawPointer?
private typealias MTActuationPlayFn = @convention(c) (UnsafeMutableRawPointer, UnsafeMutableRawPointer, UInt32, Float, Float) -> Int32
private typealias MTFrameCallbackFn = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, Int32, Double, Int32) -> Int32
private typealias MTRegisterCallbackFn = @convention(c) (UnsafeMutableRawPointer, MTFrameCallbackFn) -> Void
private typealias MTDeviceStartFn = @convention(c) (UnsafeMutableRawPointer, Int32) -> Void
private typealias MTDeviceStopFn = @convention(c) (UnsafeMutableRawPointer) -> Void

private let mtContactCallback: MTFrameCallbackFn = { _, data, count, _, _ in
    var parsed: [TouchContact] = []
    var seenIDs = Set<Int32>()
    if let data, count > 0 {
        let clampedCount = min(Int(count), 16)
        parsed.reserveCapacity(clampedCount)
        for i in 0..<clampedCount {
            let rec = data.advanced(by: i * 96)
            let state = rec.load(fromByteOffset: 20, as: Int32.self)
            let size = Double(rec.load(fromByteOffset: 48, as: Float.self))
            // States 3 (hover/near), 4 (touching), 5 (breaking touch) are standard active touch states.
            // Also include state 2 (makeTouch onset) when contact area is present so light 4th/5th fingers
            // (pinky/thumb) never drop out mid-chord.
            let isActive = (3...5).contains(state) || (state == 2 && size > 0.06)
            guard isActive else { continue }
            let pathID = rec.load(fromByteOffset: 16, as: Int32.self)
            let fingerID = rec.load(fromByteOffset: 24, as: Int32.self)
            let stableID: Int32 = pathID != 0 ? pathID : (fingerID != 0 ? fingerID : Int32(i + 1))
            guard seenIDs.insert(stableID).inserted else { continue }
            let x = Double(rec.load(fromByteOffset: 32, as: Float.self))
            let y = Double(rec.load(fromByteOffset: 36, as: Float.self))
            let vx = Double(rec.load(fromByteOffset: 40, as: Float.self))
            let vy = Double(rec.load(fromByteOffset: 44, as: Float.self))
            let angle = Double(rec.load(fromByteOffset: 56, as: Float.self))
            let major = Double(rec.load(fromByteOffset: 60, as: Float.self))
            let minor = Double(rec.load(fromByteOffset: 64, as: Float.self))
            parsed.append(
                TouchContact(
                    id: stableID,
                    fingerID: fingerID,
                    state: state,
                    x: x,
                    y: y,
                    vx: vx,
                    vy: vy,
                    size: size,
                    majorAxis: major,
                    minorAxis: minor,
                    angle: angle
                )
            )
        }
    }
    TouchFrameStore.shared.update(parsed)
    return 0
}

/// Direct bridge to Apple's private `MultitouchSupport.framework` for Force Touch haptic tone synthesis
/// and 120 Hz multi-finger raw contact tracking.
public final class MultitouchBridge: HapticActuatorOutput, @unchecked Sendable {
    public static let minSafeFrequencyHz: Double = 45.0
    public static let maxSafeFrequencyHz: Double = 4150.0
    public static let maxSimultaneousTones: Int = 6

    private var stateLock = os_unfair_lock()
    private let frameworkHandle: UnsafeMutableRawPointer?

    private let createListFn: MTCreateListFn?
    private let getIDFn: MTGetIDFn?
    private let isBuiltInFn: MTIsBuiltInFn?
    private let actuatorCreateFn: MTActuatorCreateFn?
    private let actuatorOpenFn: MTActuatorOpenFn?
    private let actuatorCloseFn: MTActuatorCloseFn?
    private let actuationCreateFn: MTActuationCreateFn?
    private let actuationPlayFn: MTActuationPlayFn?
    private let registerCallbackFn: MTRegisterCallbackFn?
    private let unregisterCallbackFn: MTRegisterCallbackFn?
    private let deviceStartFn: MTDeviceStartFn?
    private let deviceStopFn: MTDeviceStopFn?

    private var deviceList: CFArray?
    private var activeDeviceID: UInt64 = 0
    private var actuatorRef: CFTypeRef?
    private var actuatorPointer: UnsafeMutableRawPointer?
    private var touchCaptureRunning = false

    private var _status: HapticHardwareStatus = .frameworkUnavailable("Not initialized")
    private var _availableDevices: [TrackpadDeviceInfo] = []

    @inline(__always)
    private func withStateLock<T>(_ body: () -> T) -> T {
        os_unfair_lock_lock(&stateLock)
        defer { os_unfair_lock_unlock(&stateLock) }
        return body()
    }

    public var status: HapticHardwareStatus {
        withStateLock { _status }
    }

    public var availableDevices: [TrackpadDeviceInfo] {
        withStateLock { _availableDevices }
    }

    public init() {
        let frameworkPath = "/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport"
        let handle = dlopen(frameworkPath, RTLD_NOW)
        self.frameworkHandle = handle

        func resolve<T>(_ name: String, _: T.Type) -> T? {
            guard let handle, let p = dlsym(handle, name) else { return nil }
            return unsafeBitCast(p, to: T.self)
        }

        self.createListFn = resolve("MTDeviceCreateList", MTCreateListFn.self)
        self.getIDFn = resolve("MTDeviceGetDeviceID", MTGetIDFn.self)
        self.isBuiltInFn = resolve("MTDeviceIsBuiltIn", MTIsBuiltInFn.self)
        self.actuatorCreateFn = resolve("MTActuatorCreateFromDeviceID", MTActuatorCreateFn.self)
        self.actuatorOpenFn = resolve("MTActuatorOpen", MTActuatorOpenFn.self)
        self.actuatorCloseFn = resolve("MTActuatorClose", MTActuatorCloseFn.self)
        self.actuationCreateFn = resolve("MTActuationCreateFromDictionary", MTActuationCreateFn.self)
        self.actuationPlayFn = resolve("MTActuationActuate", MTActuationPlayFn.self)
        self.registerCallbackFn = resolve("MTRegisterContactFrameCallback", MTRegisterCallbackFn.self)
        self.unregisterCallbackFn = resolve("MTUnregisterContactFrameCallback", MTRegisterCallbackFn.self)
        self.deviceStartFn = resolve("MTDeviceStart", MTDeviceStartFn.self)
        self.deviceStopFn = resolve("MTDeviceStop", MTDeviceStopFn.self)

        _ = reconnect(deviceID: nil)
    }

    deinit {
        shutdown()
    }

    @discardableResult
    public func reconnect(deviceID preferredID: UInt64?) -> HapticHardwareStatus {
        stopTouchCapture()
        closeActuatorOnly()

        guard
            let createListFn,
            let getIDFn,
            let actuatorCreateFn,
            let actuatorOpenFn,
            actuationCreateFn != nil,
            actuationPlayFn != nil
        else {
            let st = HapticHardwareStatus.frameworkUnavailable(
                "Required MultitouchSupport symbols are missing on this macOS version."
            )
            setStatus(st, devices: [])
            return st
        }

        guard let list = createListFn()?.takeRetainedValue(), CFArrayGetCount(list) > 0 else {
            let st = HapticHardwareStatus.noTrackpadFound(isLaptop: Self.detectIsLaptop())
            setStatus(st, devices: [])
            return st
        }

        var discovered: [TrackpadDeviceInfo] = []
        let count = CFArrayGetCount(list)
        for i in 0..<count {
            guard let raw = CFArrayGetValueAtIndex(list, i) else { continue }
            let dev = UnsafeMutableRawPointer(mutating: raw)
            var id: UInt64 = 0
            guard getIDFn(dev, &id) == 0 else { continue }
            let builtIn = isBuiltInFn?(dev) ?? false
            // Probe whether this device has an actuator
            let hasAct: Bool
            if let probe = actuatorCreateFn(id)?.takeRetainedValue() {
                hasAct = true
                _ = probe
            } else {
                hasAct = false
            }
            discovered.append(TrackpadDeviceInfo(id: id, isBuiltIn: builtIn, hasActuator: hasAct))
        }

        let ordered = discovered.sorted { lhs, rhs in
            if let preferredID {
                if lhs.id == preferredID { return true }
                if rhs.id == preferredID { return false }
            }
            if lhs.isBuiltIn != rhs.isBuiltIn { return lhs.isBuiltIn }
            return lhs.id < rhs.id
        }

        var lastOpenError: Int32?
        for candidate in ordered where candidate.hasActuator {
            if let ref = actuatorCreateFn(candidate.id)?.takeRetainedValue() {
                let err = actuatorOpenFn(ref)
                if err == 0 {
                    os_unfair_lock_lock(&stateLock)
                    self.deviceList = list
                    self.activeDeviceID = candidate.id
                    self.actuatorRef = ref
                    self.actuatorPointer = Unmanaged.passUnretained(ref as AnyObject).toOpaque()
                    self._availableDevices = discovered.filter(\.hasActuator)
                    self._status = .ready(candidate)
                    os_unfair_lock_unlock(&stateLock)
                    return .ready(candidate)
                } else {
                    lastOpenError = err
                }
            }
        }

        let failureStatus: HapticHardwareStatus = lastOpenError.map { .actuatorOpenFailed($0) } ?? .noForceTouchActuator
        setStatus(failureStatus, devices: discovered.filter(\.hasActuator))
        return failureStatus
    }

    public func currentContacts() -> [TouchContact] {
        TouchFrameStore.shared.read()
    }

    /// Plays a chord/timbre of sine partials directly through the trackpad's Force Touch actuator.
    ///
    /// Safety invariant (following nospeaker's hardware findings):
    /// - Tone amplitudes are strictly normalized to sum to 1.0 so the haptic driver never stalls.
    /// - Frequencies are clamped to `45...4150 Hz`.
    /// - Master `level` is strictly clamped to `0.0...1.0`.
    public func play(tones: [HapticTone], durationMs: Double, level: Float) {
        guard !tones.isEmpty, level > 0.0005, durationMs >= 3.0 else { return }

        let pointer = withStateLock { actuatorPointer }

        guard let pointer, let actuationCreateFn, let actuationPlayFn else { return }

        let sanitized = tones
            .filter { $0.amp > 0.0001 && $0.hz.isFinite && $0.amp.isFinite }
            .prefix(Self.maxSimultaneousTones)
            .map {
                HapticTone(
                    hz: min(Self.maxSafeFrequencyHz, max(Self.minSafeFrequencyHz, $0.hz)),
                    amp: max(0.0, $0.amp)
                )
            }

        guard !sanitized.isEmpty else { return }

        let ampSum = max(sanitized.reduce(0.0) { $0 + $1.amp }, 0.0001)
        let clampedMs = min(120.0, max(4.0, durationMs))
        let clampedLevel = min(1.0, max(0.0, level))

        let toneDicts: [[String: Any]] = sanitized.map { tone in
            [
                "Type": "Sine",
                "Amplitude": tone.amp / ampSum,
                "DurationMS": clampedMs,
                "DelayMS": 0.0,
                "FrequencykHz": tone.hz / 1000.0
            ]
        }

        let shape: [String: Any] = [
            "BaseWaveform": [
                "Type": "Gaussian",
                "Amplitude": 0.0,
                "DurationMS": clampedMs
            ],
            "Tones": toneDicts
        ]

        guard let actuation = actuationCreateFn(shape as CFDictionary, 0) else { return }
        _ = actuationPlayFn(actuation, pointer, 0, clampedLevel, 0)
        Unmanaged<AnyObject>.fromOpaque(actuation).release()
    }

    @discardableResult
    public func startTouchCapture() -> Bool {
        let devs: [UnsafeMutableRawPointer]? = withStateLock {
            if touchCaptureRunning { return nil }
            return activeTouchDevicePointersLocked()
        }
        guard let devs else { return true }
        guard let registerCallbackFn, let deviceStartFn, !devs.isEmpty else { return false }

        for dev in devs {
            registerCallbackFn(dev, mtContactCallback)
            deviceStartFn(dev, 0)
        }
        withStateLock { touchCaptureRunning = true }
        return true
    }

    public func stopTouchCapture() {
        let (wasRunning, devs) = withStateLock { () -> (Bool, [UnsafeMutableRawPointer]) in
            let running = touchCaptureRunning
            let activeDevs = activeTouchDevicePointersLocked()
            touchCaptureRunning = false
            return (running, activeDevs)
        }

        if wasRunning {
            for dev in devs {
                unregisterCallbackFn?(dev, mtContactCallback)
                deviceStopFn?(dev)
            }
        }
        TouchFrameStore.shared.clear()
    }

    public func shutdown() {
        stopTouchCapture()
        closeActuatorOnly()
    }

    // MARK: - Private helpers

    private func closeActuatorOnly() {
        let ref: CFTypeRef? = withStateLock {
            let current = actuatorRef
            actuatorRef = nil
            actuatorPointer = nil
            activeDeviceID = 0
            deviceList = nil
            return current
        }
        if let ref {
            _ = actuatorCloseFn?(ref)
        }
    }

    private func setStatus(_ status: HapticHardwareStatus, devices: [TrackpadDeviceInfo]) {
        withStateLock {
            _status = status
            _availableDevices = devices
        }
    }

    private func activeTouchDevicePointersLocked() -> [UnsafeMutableRawPointer] {
        guard let list = deviceList, let getIDFn, activeDeviceID != 0 else { return [] }
        var result: [UnsafeMutableRawPointer] = []
        for i in 0..<CFArrayGetCount(list) {
            guard let raw = CFArrayGetValueAtIndex(list, i) else { continue }
            let dev = UnsafeMutableRawPointer(mutating: raw)
            var id: UInt64 = 0
            if getIDFn(dev, &id) == 0, id == activeDeviceID {
                result.append(dev)
            }
        }
        return result
    }

    private static func detectIsLaptop() -> Bool {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        var buf = [UInt8](repeating: 0, count: max(1, size))
        sysctlbyname("hw.model", &buf, &size, nil, 0)
        let nullIndex = buf.firstIndex(of: 0) ?? buf.count
        let model = String(decoding: buf[..<nullIndex], as: UTF8.self)
        if model.hasPrefix("MacBook") { return true }
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        if service != 0 {
            IOObjectRelease(service)
            return true
        }
        return false
    }
}
