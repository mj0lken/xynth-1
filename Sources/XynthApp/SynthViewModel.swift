import AppKit
import CoreAudio
import Foundation
import Observation
import XynthCore

struct TouchTrailPoint: Identifiable {
    let id = UUID()
    let x: Double
    let y: Double
    let timestamp: TimeInterval
}

@MainActor
@Observable
final class SynthViewModel {
    private static let themeDefaultsKey = "com.xynth1.selectedTheme"
    private static let autoUpdateDefaultsKey = "com.xynth1.autoCheckUpdates"
    private static let tooltipsDefaultsKey = "com.xynth1.hoverTooltipsEnabled"

    private let engine: HapticSynthEngine
    let cursorLock: CursorLockController
    let hoverHelp = HoverHelpState()
    let ferroPhysics = FerrofluidPhysics()

    // MARK: - Rear Settings Flip Panel & Auto-Updater
    var showSettings: Bool = false
    var autoCheckUpdatesOnLaunch: Bool = true {
        didSet { UserDefaults.standard.set(autoCheckUpdatesOnLaunch, forKey: Self.autoUpdateDefaultsKey) }
    }
    var hoverTooltipsEnabled: Bool = true {
        didSet {
            UserDefaults.standard.set(hoverTooltipsEnabled, forKey: Self.tooltipsDefaultsKey)
            hoverHelp.isEnabled = hoverTooltipsEnabled
        }
    }
    private(set) var isCheckingUpdates: Bool = false
    private(set) var isInstallingUpdate: Bool = false
    private(set) var availableUpdate: AppReleaseInfo? = nil
    private(set) var updateStatusHeadline: String = "READY TO CHECK"
    private(set) var updateStatusDetail: String = "Checks GitHub Releases (mj0lken/xynth-1) for Apple Silicon macOS updates."

    // MARK: - Expandable Side Bay (Ferrofluid Liquid Magnetic Visualizer)
    var showExpansionBay: Bool = false
    var ferroMode: FerrofluidMode = .spikes
    var ferroMagnetism: Double = 0.88
    var ferroViscosity: Double = 0.35

    enum QuickPatch {
        case velvet, subBass, theremin, glassChime
    }

    // MARK: - Industrial Design Theme (persisted across launches)
    var themePreset: XynthThemePreset = .op1Field {
        didSet {
            UserDefaults.standard.set(themePreset.rawValue, forKey: Self.themeDefaultsKey)
            applyWindowTheme()
        }
    }

    var palette: XynthPalette { themePreset.palette }

    // MARK: - Live Telemetry (updated at ~60 fps)
    private(set) var snapshot: SynthSnapshot = .idle
    private(set) var muteState: SystemAudioMonitor.MuteState = .unknown
    private(set) var availableDevices: [TrackpadDeviceInfo] = []
    private(set) var availableAudioDevices: [AudioOutputDeviceInfo] = []
    private(set) var audioMirrorEnabled: Bool = false
    private(set) var selectedAudioDeviceID: AudioDeviceID? = nil
    private(set) var audioMirrorError: String? = nil
    private(set) var trails: [Int32: [TouchTrailPoint]] = [:]
    private(set) var frameClock: TimeInterval = 0

    var audioOutputGain: Double = 0.78 {
        didSet { engine.setAudioOutputGain(audioOutputGain) }
    }
    var hapticsEnabled: Bool = true {
        didSet { syncEngineParameters() }
    }

    // MARK: - Interaction Mode State
    private(set) var isPlayModeLocked: Bool = false
    private(set) var isOptionHeld: Bool = false
    var alwaysSenseWhenFocused: Bool = false {
        didSet { syncEngineParameters() }
    }
    var showDirectSliders: Bool = false

    // MARK: - Synth Parameters (bound to UI controls)
    var scale: MusicalScale = .pentatonicMinor { didSet { syncEngineParameters() } }
    var root: RootNote = .a { didSet { syncEngineParameters() } }
    var rangePreset: FrequencyRangePreset = .balanced { didSet { syncEngineParameters() } }
    var octaveShift: Int = 0 { didSet { syncEngineParameters() } }
    var timbre: SynthTimbre = .warmOctave { didSet { syncEngineParameters() } }
    var mappingMode: ControlMappingMode = .xyPitchVolume { didSet { syncEngineParameters() } }

    var masterVolume: Double = 0.90 { didSet { syncEngineParameters() } }
    var subFeelAmount: Double = 0.24 { didSet { syncEngineParameters() } }
    var glideAmount: Double = 0.28 { didSet { syncEngineParameters() } }
    var brightness: Double = 0.55 { didSet { syncEngineParameters() } }
    var vibratoDepth: Double = 0.14 { didSet { syncEngineParameters() } }
    var vibratoRateHz: Double = 5.4 { didSet { syncEngineParameters() } }
    var maxVoices: Int = 5 { didSet { syncEngineParameters() } }

    var holdDrone: Bool = false { didSet { syncEngineParameters() } }
    var manualPitchX: Double = 0.50 {
        didSet {
            engine.clearHeldContacts()
            syncEngineParameters()
        }
    }
    var manualVolumeY: Double = 0.72 {
        didSet {
            engine.clearHeldContacts()
            syncEngineParameters()
        }
    }
    var manualSynthActive: Bool = false { didSet { syncEngineParameters() } }

    private var uiTimer: Timer?
    private var lastMuteCheck: TimeInterval = 0
    private var lastNonZeroSubFeel: Double = 0.28

    var isHardwareTouchArmed: Bool {
        isPlayModeLocked || isOptionHeld || alwaysSenseWhenFocused
    }

    var scaleMarkers: [ScaleMarker] {
        MusicalTheory.scaleMarkers(scale: scale, root: root, preset: rangePreset, octaveShift: octaveShift)
    }

    var manualPitchHz: Double {
        MusicalTheory.frequency(
            forNormalizedX: manualPitchX,
            scale: scale,
            root: root,
            preset: rangePreset,
            octaveShift: octaveShift
        )
    }

    var manualNoteLabel: String {
        MusicalTheory.noteReadout(forHz: manualPitchHz).name
    }

    init(engine: HapticSynthEngine = HapticSynthEngine()) {
        self.engine = engine
        self.cursorLock = CursorLockController()
        if let saved = UserDefaults.standard.string(forKey: Self.themeDefaultsKey),
           let parsed = XynthThemePreset(rawValue: saved) {
            self.themePreset = parsed
        }
        if UserDefaults.standard.object(forKey: Self.autoUpdateDefaultsKey) != nil {
            self.autoCheckUpdatesOnLaunch = UserDefaults.standard.bool(forKey: Self.autoUpdateDefaultsKey)
        }
        if UserDefaults.standard.object(forKey: Self.tooltipsDefaultsKey) != nil {
            self.hoverTooltipsEnabled = UserDefaults.standard.bool(forKey: Self.tooltipsDefaultsKey)
        }
        self.hoverHelp.isEnabled = self.hoverTooltipsEnabled

        self.availableDevices = engine.availableDevices
        self.availableAudioDevices = engine.availableAudioOutputDevices()
        self.muteState = SystemAudioMonitor.currentMuteState()
        engine.setAudioOutputGain(audioOutputGain)

        bindCursorLockCallbacks()
        syncEngineParameters()
        engine.start()
        startTimers()
        applyWindowTheme()

        if autoCheckUpdatesOnLaunch {
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(2))
                self?.checkForUpdates(userInitiated: false)
            }
        }
    }

    func toggleSettingsFlip() {
        hoverHelp.clear()
        if !showSettings && isPlayModeLocked {
            unlockPlayMode()
        }
        showSettings.toggle()
    }

    func openMacOSTrackpadSettings() {
        let primary = URL(string: "x-apple.systempreferences:com.apple.Trackpad-Settings.extension")!
        let fallback = URL(string: "x-apple.systempreferences:com.apple.preference.trackpad")!
        if !NSWorkspace.shared.open(primary) {
            NSWorkspace.shared.open(fallback)
        }
    }

    func openMacOSMissionControlSettings() {
        let primary = URL(string: "x-apple.systempreferences:com.apple.Desktop-Settings.extension")!
        let fallback = URL(string: "x-apple.systempreferences:com.apple.preference.expose")!
        if !NSWorkspace.shared.open(primary) {
            NSWorkspace.shared.open(fallback)
        }
    }

    func checkForUpdates(userInitiated: Bool) {
        guard !isCheckingUpdates else { return }
        isCheckingUpdates = true
        if userInitiated {
            updateStatusHeadline = "CHECKING GITHUB RELEASES…"
            updateStatusDetail = "Querying \(AppUpdateService.defaultRepo) for the latest macOS build."
        }
        Task { [weak self] in
            let result = await AppUpdateService.checkLatestRelease()
            guard let self else { return }
            self.isCheckingUpdates = false
            switch result {
            case .updateAvailable(let current, let release):
                self.availableUpdate = release
                self.updateStatusHeadline = "UPDATE AVAILABLE · \(release.tagName)"
                self.updateStatusDetail = release.notes.isEmpty
                    ? "New release \(release.tagName) is ready (installed: v\(current))."
                    : String(release.notes.prefix(160))
            case .upToDate(let current, let latest):
                self.availableUpdate = nil
                self.updateStatusHeadline = "UP TO DATE · v\(current)"
                self.updateStatusDetail = "You're running the latest release (v\(latest)) of XYNTH-1."
            case .noReleasesPublished(let current):
                self.availableUpdate = nil
                self.updateStatusHeadline = "CURRENT · v\(current)"
                self.updateStatusDetail = "No newer GitHub releases published yet on \(AppUpdateService.defaultRepo)."
            case .failed(let message):
                if userInitiated {
                    self.updateStatusHeadline = "UPDATE CHECK FAILED"
                    self.updateStatusDetail = message
                }
            }
        }
    }

    func installAvailableUpdate() {
        guard let release = availableUpdate, !isInstallingUpdate else { return }
        isInstallingUpdate = true
        updateStatusHeadline = "DOWNLOADING \(release.tagName)…"
        updateStatusDetail = "Fetching macOS app bundle from GitHub Releases."
        Task { [weak self] in
            guard let self else { return }
            do {
                let staged = try await AppUpdateService.downloadAndStageInstall(release: release)
                self.updateStatusHeadline = "INSTALLING & RELAUNCHING…"
                self.updateStatusDetail = "Swapping XYNTH-1.app and restarting cleanly."
                try AppUpdateService.launchSwapHelperAndExit(stagedAppURL: staged)
                self.shutdown()
                NSApp.terminate(nil)
            } catch {
                self.isInstallingUpdate = false
                self.updateStatusHeadline = "OPENING GITHUB RELEASE"
                self.updateStatusDetail = error.localizedDescription
                NSWorkspace.shared.open(release.htmlURL)
            }
        }
    }

    func cycleTheme() {
        let all = XynthThemePreset.allCases
        if let idx = all.firstIndex(of: themePreset) {
            themePreset = all[(idx + 1) % all.count]
        }
    }

    func applyWindowTheme() {
        let bg = palette.windowNSColor
        let appearanceName: NSAppearance.Name = palette.isLightChassis ? .aqua : .darkAqua
        DispatchQueue.main.async {
            for window in NSApp.windows {
                window.backgroundColor = bg
                window.appearance = NSAppearance(named: appearanceName)
            }
        }
    }

    func shutdown() {
        uiTimer?.invalidate()
        uiTimer = nil
        hoverHelp.teardown()
        cursorLock.teardown()
        engine.stop()
    }

    func toggleExpansionBay() {
        let next = !showExpansionBay
        showExpansionBay = next
        resizeWindowForExpansionBay(expanded: next)
    }

    func applyQuickPatch(_ patch: QuickPatch) {
        switch patch {
        case .velvet:
            timbre = .warmOctave
            rangePreset = .balanced
            scale = .pentatonicMinor
            subFeelAmount = 0.26
            glideAmount = 0.30
            brightness = 0.55
            vibratoDepth = 0.14
        case .subBass:
            timbre = .brassSaw
            rangePreset = .subFeel
            scale = .pentatonicMinor
            subFeelAmount = 0.38
            glideAmount = 0.18
            brightness = 0.45
            vibratoDepth = 0.06
        case .theremin:
            timbre = .pureSine
            rangePreset = .balanced
            scale = .free
            subFeelAmount = 0.18
            glideAmount = 0.58
            brightness = 0.50
            vibratoDepth = 0.26
            vibratoRateHz = 5.8
        case .glassChime:
            timbre = .glassBell
            rangePreset = .acoustic
            scale = .hirajoshi
            subFeelAmount = 0.15
            glideAmount = 0.10
            brightness = 0.80
            vibratoDepth = 0.12
        }
    }

    private func resizeWindowForExpansionBay(expanded: Bool) {
        let deltaWidth: CGFloat = 324
        DispatchQueue.main.async {
            guard let window = NSApp.keyWindow ?? NSApp.mainWindow ?? NSApp.windows.first else { return }
            let targetMinW: CGFloat = expanded ? 1290 : 980
            window.minSize = NSSize(width: targetMinW, height: 740)
            var frame = window.frame
            let desiredW = expanded ? max(targetMinW, frame.width + deltaWidth) : max(980, frame.width - deltaWidth)
            if let screen = window.screen ?? NSScreen.main {
                let visible = screen.visibleFrame
                frame.size.width = min(desiredW, visible.width - 24)
                if frame.maxX > visible.maxX {
                    frame.origin.x = max(visible.minX + 12, visible.maxX - frame.size.width - 12)
                }
            } else {
                frame.size.width = desiredW
            }
            window.setFrame(frame, display: true, animate: true)
        }
    }

    // MARK: - Actions

    func togglePlayMode() {
        cursorLock.toggleLock()
    }

    func unlockPlayMode() {
        cursorLock.unlock()
    }

    func setVirtualTouch(x: Double, y: Double, down: Bool) {
        engine.setVirtualTouch(x: x, y: y, down: down)
    }

    func triggerSweepDemo() {
        engine.triggerSweepDemo()
    }

    func triggerArpeggioDemo() {
        engine.triggerArpeggioDemo()
    }

    func triggerHeartbeatDemo() {
        engine.triggerHeartbeatDemo()
    }

    func triggerShortDemo() {
        engine.triggerShortDemo()
    }

    func reconnectTrackpad(deviceID: UInt64? = nil) {
        _ = engine.reconnectHardware(deviceID: deviceID)
        availableDevices = engine.availableDevices
        snapshot = engine.snapshot()
    }

    func shiftOctave(_ delta: Int) {
        octaveShift = min(2, max(-2, octaveShift + delta))
    }

    func selectTimbre(byShortcut index: Int) {
        if let match = SynthTimbre.allCases.first(where: { $0.shortcutIndex == index }) {
            timbre = match
        }
    }

    func cycleScale() {
        let all = MusicalScale.allCases
        if let idx = all.firstIndex(of: scale) {
            scale = all[(idx + 1) % all.count]
        }
    }

    func cycleMappingMode() {
        let all = ControlMappingMode.allCases
        if let idx = all.firstIndex(of: mappingMode) {
            mappingMode = all[(idx + 1) % all.count]
        }
    }

    func toggleSubFeel() {
        if subFeelAmount > 0.01 {
            lastNonZeroSubFeel = subFeelAmount
            subFeelAmount = 0.0
        } else {
            subFeelAmount = max(0.22, lastNonZeroSubFeel)
        }
    }

    var selectedAudioDeviceName: String {
        guard let selectedAudioDeviceID else {
            if let def = availableAudioDevices.first(where: \.isDefault) {
                return "System Default (\(def.name))"
            }
            return "System Default"
        }
        return availableAudioDevices.first(where: { $0.id == selectedAudioDeviceID })?.name ?? "Custom Output"
    }

    func toggleAudioMirror() {
        setAudioMirrorEnabled(!audioMirrorEnabled)
    }

    func setAudioMirrorEnabled(_ enabled: Bool) {
        refreshAudioDevices()
        let ok = engine.setAudioMirrorEnabled(enabled)
        audioMirrorEnabled = engine.isAudioMirrorEnabled
        audioMirrorError = ok ? nil : engine.audioMirrorError
    }

    func selectAudioOutputDevice(_ deviceID: AudioDeviceID?) {
        let ok = engine.selectAudioOutputDevice(deviceID)
        selectedAudioDeviceID = engine.selectedAudioOutputDeviceID
        audioMirrorEnabled = engine.isAudioMirrorEnabled
        audioMirrorError = ok ? nil : engine.audioMirrorError
    }

    func refreshAudioDevices() {
        availableAudioDevices = engine.availableAudioOutputDevices()
    }

    func toggleHoldDrone() {
        holdDrone.toggle()
        if holdDrone {
            showDirectSliders = true
        }
    }

    // MARK: - Private wiring

    private func bindCursorLockCallbacks() {
        cursorLock.onLockStateChanged = { [weak self] locked in
            guard let self else { return }
            self.isPlayModeLocked = locked
            self.syncEngineParameters()
        }

        cursorLock.onOptionHeldChanged = { [weak self] held in
            guard let self else { return }
            self.isOptionHeld = held
            self.syncEngineParameters()
        }

        cursorLock.onShortcutAction = { [weak self] action in
            guard let self else { return }
            switch action {
            case .togglePlayMode:
                self.togglePlayMode()
            case .escapePressed:
                if self.showSettings {
                    self.toggleSettingsFlip()
                } else if self.isPlayModeLocked {
                    self.unlockPlayMode()
                } else {
                    self.holdDrone = false
                    self.manualSynthActive = false
                    self.engine.cancelDemo()
                }
            case .selectTimbre(let idx):
                self.selectTimbre(byShortcut: idx)
            case .octaveDown:
                self.shiftOctave(-1)
            case .octaveUp:
                self.shiftOctave(1)
            case .cycleScale:
                self.cycleScale()
            case .cycleMapping:
                self.cycleMappingMode()
            case .toggleSubFeel:
                self.toggleSubFeel()
            case .toggleHoldDrone:
                self.toggleHoldDrone()
            case .toggleAudioMirror:
                self.toggleAudioMirror()
            case .cycleTheme:
                self.cycleTheme()
            case .toggleExpansionBay:
                self.toggleExpansionBay()
            case .volumeStep(let delta):
                self.masterVolume = min(1.0, max(0.0, self.masterVolume + delta))
            case .vibratoStep(let delta):
                self.vibratoDepth = min(0.8, max(0.0, self.vibratoDepth + delta))
            case .triggerSweep:
                self.triggerSweepDemo()
            }
        }
    }

    private func syncEngineParameters() {
        var p = SynthParameters()
        p.scale = scale
        p.root = root
        p.rangePreset = rangePreset
        p.octaveShift = octaveShift
        p.timbre = timbre
        p.mappingMode = mappingMode
        p.masterVolume = masterVolume
        p.subFeelAmount = subFeelAmount
        p.glideAmount = glideAmount
        p.brightness = brightness
        p.vibratoDepth = vibratoDepth
        p.vibratoRateHz = vibratoRateHz
        p.maxVoices = maxVoices
        p.holdDrone = holdDrone
        p.manualPitchX = manualPitchX
        p.manualVolumeY = manualVolumeY
        p.manualSynthActive = manualSynthActive
        p.hardwareTouchArmed = isHardwareTouchArmed
        p.hapticsEnabled = hapticsEnabled
        engine.parameters = p
    }

    private func startTimers() {
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.uiTimer = timer
    }

    private func tick() {
        let now = ProcessInfo.processInfo.systemUptime
        let dt = frameClock > 0 ? (now - frameClock) : (1.0 / 60.0)
        frameClock = now

        let snap = engine.snapshot()
        snapshot = snap

        if showExpansionBay {
            ferroPhysics.step(
                snapshot: snap,
                magnetism: ferroMagnetism,
                viscosity: ferroViscosity,
                dt: dt
            )
        }

        // Update luminous finger glide trails
        for voice in snap.activeVoices {
            var list = trails[voice.id] ?? []
            if let last = list.last {
                let dx = voice.x - last.x
                let dy = voice.y - last.y
                if dx * dx + dy * dy > 0.00008 || (now - last.timestamp) > 0.035 {
                    list.append(TouchTrailPoint(x: voice.x, y: voice.y, timestamp: now))
                }
            } else {
                list.append(TouchTrailPoint(x: voice.x, y: voice.y, timestamp: now))
            }
            if list.count > 26 {
                list.removeFirst(list.count - 26)
            }
            trails[voice.id] = list
        }

        // Prune expired trail points (> 0.55 s old)
        for key in Array(trails.keys) {
            let filtered = (trails[key] ?? []).filter { now - $0.timestamp < 0.55 }
            if filtered.isEmpty {
                trails.removeValue(forKey: key)
            } else {
                trails[key] = filtered
            }
        }

        // Poll system speaker mute proof twice per second
        if now - lastMuteCheck > 0.5 {
            lastMuteCheck = now
            muteState = SystemAudioMonitor.currentMuteState()
        }
    }
}
