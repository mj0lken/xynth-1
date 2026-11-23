import SwiftUI
import XynthCore

/// OP-1 × M-VAVE FM-1 tactile hardware control deck:
/// - 5 color-coded rotary encoder knobs (drag / scroll / double-click reset)
/// - Sculpted square LED push-keycaps showing active modes, timbres, bands, and 5-finger voice slots
/// - Theme-matched hover documentation on every single control
struct ControlDeckView: View {
    @Bindable var vm: SynthViewModel

    private var p: XynthPalette { vm.palette }

    var body: some View {
        VStack(spacing: 9) {
            // Deck A: Color-coded Rotary Encoders (left) + Performance & Mapping Keycaps (right)
            HStack(spacing: 10) {
                encodersModule
                performanceAndMappingModule
                    .frame(width: 410)
            }

            // Deck B: 7 Harmonic Algorithm / Timbre LED Keycaps (Shortcuts 1–7)
            timbreKeycapRow

            // Deck C: Scale, Root Key, Frequency Band, Octave & 5-Finger Voice Polyphony
            pitchAndVoicesRow

            // Optional Deck D: Direct Pitch & Volume Faders (when Hold or Faders active)
            if vm.showDirectSliders || vm.holdDrone || vm.manualSynthActive {
                directFadersRow
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.easeOut(duration: 0.16), value: vm.showDirectSliders)
        .animation(.easeOut(duration: 0.16), value: vm.holdDrone)
        .animation(.easeOut(duration: 0.16), value: vm.manualSynthActive)
    }

    // MARK: - Deck A Left: 5 Color-Coded Rotary Encoders

    private var encodersModule: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("ENCODERS · DRAG / SCROLL / 2×CLICK RESET")
                    .font(.system(size: 8.5, weight: .black, design: .monospaced))
                    .tracking(0.9)
                    .foregroundStyle(p.inkMuted)
                Spacer()
                Text("ENC 1–5")
                    .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(p.inkMuted)
            }

            HStack(spacing: 8) {
                HardwareRotaryKnob(
                    label: "VOL",
                    valueText: "\(Int((vm.masterVolume * 100).rounded()))%",
                    value: $vm.masterVolume,
                    range: 0.0...1.0,
                    defaultValue: 0.90,
                    accent: p.enc1,
                    palette: p
                )
                .xynthHelp(
                    "Master Motor Volume",
                    shortcut: "↑ / ↓",
                    detail: "Sets the maximum Force Touch actuator drive strength (0–100%). Drag or scroll to dial; double-click resets to 90%."
                )

                HardwareRotaryKnob(
                    label: "SUB FEEL",
                    valueText: vm.subFeelAmount < 0.01 ? "OFF" : "\(Int((vm.subFeelAmount * 200).rounded()))%",
                    value: $vm.subFeelAmount,
                    range: 0.0...0.5,
                    defaultValue: 0.24,
                    accent: p.enc2,
                    palette: p,
                    isOn: vm.subFeelAmount >= 0.01
                )
                .xynthHelp(
                    "Tactile Sub-Feel",
                    shortcut: "H",
                    detail: "Blends a phase-locked sub-octave into the 110–245 Hz fingertip sweet spot under higher notes so you feel rich physical buzz in your fingers."
                )

                HardwareRotaryKnob(
                    label: "GLIDE",
                    valueText: vm.glideAmount < 0.02 ? "SNAP" : "\(Int((vm.glideAmount * 100).rounded()))%",
                    value: $vm.glideAmount,
                    range: 0.0...1.0,
                    defaultValue: 0.28,
                    accent: p.enc3,
                    palette: p,
                    isOn: vm.glideAmount >= 0.02
                )
                .xynthHelp(
                    "Portamento Glide",
                    detail: "Controls pitch transition speed between notes — 0% snaps crisply between frets; higher values create silky Theremin-like glides."
                )

                HardwareRotaryKnob(
                    label: "TONE",
                    valueText: "\(Int((vm.brightness * 100).rounded()))%",
                    value: $vm.brightness,
                    range: 0.0...1.0,
                    defaultValue: 0.55,
                    accent: p.enc4,
                    palette: p
                )
                .xynthHelp(
                    "Harmonic Tone / Formant",
                    detail: "Shapes upper overtone energy on Warm, Hollow, Saw, Fifth & Bell timbres — and morphs vowel formants (oo→oh→ah→eh→ee) on Voice."
                )

                HardwareRotaryKnob(
                    label: "VIBRATO",
                    valueText: vm.vibratoDepth < 0.02 ? "OFF" : String(format: "%.2fst", vm.vibratoDepth),
                    value: $vm.vibratoDepth,
                    range: 0.0...0.8,
                    defaultValue: 0.14,
                    accent: p.enc5,
                    palette: p,
                    isOn: vm.vibratoDepth >= 0.02
                )
                .xynthHelp(
                    "Pitch Vibrato LFO",
                    shortcut: "← / →",
                    detail: "Adds expressive 5.4 Hz pitch shimmer in semitones after note onset. Set to 0 for pure steady glass tones."
                )
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .hardwareModule(p, cornerRadius: 12)
    }

    // MARK: - Deck A Right: Mode Switches & Axis Mapping Keycaps

    private var performanceAndMappingModule: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text("PERFORMANCE & AXIS MAP")
                    .font(.system(size: 8.5, weight: .black, design: .monospaced))
                    .tracking(0.9)
                    .foregroundStyle(p.inkMuted)
                Spacer()
                Text("MAP KEY M")
                    .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(p.inkMuted)
            }

            // Primary mode LED keycaps
            HStack(spacing: 6) {
                HardwareKeyButton(
                    title: vm.isPlayModeLocked ? "UNLOCK" : "PLAY",
                    shortcut: "SPC",
                    isActive: vm.isPlayModeLocked,
                    ledColor: p.enc1,
                    palette: p,
                    fullWidth: true
                ) {
                    vm.togglePlayMode()
                }
                .xynthHelp(
                    "Cursor-Locked Play Mode",
                    shortcut: "SPACE",
                    detail: "Freezes your desktop cursor so you can glide up to 5 fingers freely across the glass without clicking other windows. Space or Esc unlocks."
                )

                HardwareKeyButton(
                    title: "HOLD",
                    shortcut: "TAB",
                    isActive: vm.holdDrone,
                    ledColor: p.enc2,
                    palette: p,
                    fullWidth: true
                ) {
                    vm.toggleHoldDrone()
                }
                .xynthHelp(
                    "Hold / Drone Latch",
                    shortcut: "TAB",
                    detail: "Freezes your active chord or opens manual pitch/volume faders so the trackpad keeps singing while you rest your hand on the glass."
                )

                HardwareKeyButton(
                    title: "LIVE",
                    isActive: vm.alwaysSenseWhenFocused,
                    ledColor: p.ledGood,
                    palette: p,
                    compact: true,
                    fullWidth: true
                ) {
                    vm.alwaysSenseWhenFocused.toggle()
                }
                .xynthHelp(
                    "Always-Live Glass Sensing",
                    detail: "When lit, touching the trackpad plays immediately whenever XYNTH-1 is focused — even without locking the cursor."
                )

                HardwareKeyButton(
                    title: "FADERS",
                    isActive: vm.showDirectSliders,
                    ledColor: p.enc3,
                    palette: p,
                    compact: true,
                    fullWidth: true
                ) {
                    vm.showDirectSliders.toggle()
                }
                .xynthHelp(
                    "Direct Pitch & Volume Faders",
                    detail: "Opens manual Pitch and Volume faders so you can scrub frequency and intensity directly while feeling vibrations on the trackpad."
                )
            }

            // 3 Axis Mapping LED keycaps
            HStack(spacing: 6) {
                ForEach(ControlMappingMode.allCases) { mode in
                    let selected = vm.mappingMode == mode
                    HardwareKeyButton(
                        title: shortMappingLabel(mode),
                        isActive: selected,
                        ledColor: p.enc4,
                        palette: p,
                        compact: true,
                        fullWidth: true
                    ) {
                        vm.mappingMode = mode
                    }
                    .xynthHelp(
                        "Axis Map: \(mode.displayName)",
                        shortcut: "M",
                        detail: mode.hintText
                    )
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .hardwareModule(p, cornerRadius: 12)
    }

    private func shortMappingLabel(_ mode: ControlMappingMode) -> String {
        switch mode {
        case .xyPitchVolume: return "XY: P+V"
        case .pressureVolumeYTimbre: return "PR·V Y·TONE"
        case .pressureVolumeYVibrato: return "PR·V Y·VIB"
        }
    }

    // MARK: - Deck B: 7 Timbre / Algorithm LED Keycaps

    private var timbreKeycapRow: some View {
        HStack(spacing: 7) {
            VStack(alignment: .leading, spacing: 1) {
                Text("TIMBRE")
                    .font(.system(size: 8.5, weight: .black, design: .monospaced))
                    .tracking(0.9)
                    .foregroundStyle(p.inkMuted)
                Text("KEYS 1–7")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundStyle(p.inkMuted.opacity(0.75))
            }
            .frame(width: 56, alignment: .leading)

            ForEach(SynthTimbre.allCases) { item in
                let active = vm.timbre == item
                let led = timbreLedColor(item)
                HardwareKeyButton(
                    title: item.shortName,
                    shortcut: "\(item.shortcutIndex)",
                    isActive: active,
                    ledColor: led,
                    palette: p,
                    compact: true,
                    fullWidth: true
                ) {
                    vm.timbre = item
                }
                .xynthHelp(
                    "Timbre \(item.shortcutIndex): \(item.displayName)",
                    shortcut: "\(item.shortcutIndex)",
                    detail: timbreHelpDetail(item)
                )
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .hardwareModule(p, cornerRadius: 12)
    }

    private func timbreLedColor(_ timbre: SynthTimbre) -> Color {
        switch timbre {
        case .pureSine: return p.enc1
        case .warmOctave: return p.enc2
        case .hollow: return p.enc3
        case .brassSaw: return p.enc5
        case .fifthOrgan: return p.enc4
        case .glassBell: return p.enc1
        case .vocalFormant: return p.enc2
        }
    }

    private func timbreHelpDetail(_ timbre: SynthTimbre) -> String {
        switch timbre {
        case .pureSine: return "Single pure sine wave — cleanest whistling glass pitch and silky fingertip sensation."
        case .warmOctave: return "Fundamental + warm 2nd & 3rd overtones — lush Rhodes/flute warmth with strong acoustic body."
        case .hollow: return "Odd harmonics (1×, 3×, 5×) — woody clarinet-like resonance with distinct tactile texture."
        case .brassSaw: return "5-harmonic sawtooth stack — gritty, buzzy analog synth character you strongly feel in the glass."
        case .fifthOrgan: return "Power fifth + octave stack — turns every single fingertip into a lush electric organ chord."
        case .glassBell: return "Inharmonic metallic partials (1×, 2.76×, 5.40×) — crystalline FM chime sparkle."
        case .vocalFormant: return "Dynamic vowel formants (oo→ah→ee) controlled by Tone knob — homage to os6/nospeaker."
        }
    }

    // MARK: - Deck C: Scale, Root Key, Band, Octave & 5-Finger Voice Bank

    private var pitchAndVoicesRow: some View {
        HStack(spacing: 11) {
            // Custom Theme-Matched Musical Scale Dropdown (replaces stock macOS Picker)
            HStack(spacing: 6) {
                Text("SCALE")
                    .font(.system(size: 8.5, weight: .black, design: .monospaced))
                    .foregroundStyle(p.inkMuted)
                HardwareDropdown(
                    selection: vm.scale,
                    options: MusicalScale.allCases.map {
                        HardwareDropdownOption(id: $0, label: $0.displayName)
                    },
                    palette: p,
                    accent: p.enc1,
                    width: 146
                ) { selected in
                    vm.scale = selected
                }
            }
            .xynthHelp(
                "Musical Scale (\(vm.scale.displayName))",
                shortcut: "S",
                detail: "Snaps horizontal X motion to a musical scale, or choose Free (Theremin) for continuous fretless pitch gliding."
            )

            // Custom Theme-Matched Root Key Grid Dropdown (replaces stock macOS Picker)
            HStack(spacing: 5) {
                Text("KEY")
                    .font(.system(size: 8.5, weight: .black, design: .monospaced))
                    .foregroundStyle(p.inkMuted)
                HardwareDropdown(
                    selection: vm.root,
                    options: RootNote.allCases.map {
                        HardwareDropdownOption(id: $0, label: $0.label)
                    },
                    palette: p,
                    accent: p.enc2,
                    width: 66,
                    columns: 3
                ) { selected in
                    vm.root = selected
                }
            }
            .xynthHelp(
                "Root Key (\(vm.root.label))",
                detail: "Transposes the active scale and highlights root frets on the glass trackpad mirror."
            )

            rowDivider

            // 4 Frequency Band LED Keycaps
            HStack(spacing: 5) {
                Text("BAND")
                    .font(.system(size: 8.5, weight: .black, design: .monospaced))
                    .foregroundStyle(p.inkMuted)

                ForEach(FrequencyRangePreset.allCases) { preset in
                    let selected = vm.rangePreset == preset
                    HardwareKeyButton(
                        title: shortBandLabel(preset),
                        isActive: selected,
                        ledColor: p.enc3,
                        palette: p,
                        compact: true
                    ) {
                        vm.rangePreset = preset
                    }
                    .xynthHelp(
                        "Range Band: \(preset.displayName)",
                        detail: "\(preset.subtitle). Switches the horizontal frequency span of your trackpad."
                    )
                }
            }

            Spacer(minLength: 4)

            // Octave Shift Hardware Stepper
            HStack(spacing: 4) {
                Text("OCT")
                    .font(.system(size: 8.5, weight: .black, design: .monospaced))
                    .foregroundStyle(p.inkMuted)

                HardwareKeyButton(
                    title: "−",
                    isActive: vm.octaveShift < 0,
                    ledColor: p.enc1,
                    palette: p,
                    compact: true
                ) {
                    vm.shiftOctave(-1)
                }
                .disabled(vm.octaveShift <= -2)
                .xynthHelp("Octave Down", shortcut: "[", detail: "Drops the trackpad pitch range by one full octave (down to -2).")

                Text(vm.octaveShift == 0 ? "0" : (vm.octaveShift > 0 ? "+\(vm.octaveShift)" : "\(vm.octaveShift)"))
                    .font(.system(size: 10.5, weight: .black, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(vm.octaveShift == 0 ? p.inkSecondary : p.enc1)
                    .frame(width: 24)

                HardwareKeyButton(
                    title: "+",
                    isActive: vm.octaveShift > 0,
                    ledColor: p.enc1,
                    palette: p,
                    compact: true
                ) {
                    vm.shiftOctave(1)
                }
                .disabled(vm.octaveShift >= 2)
                .xynthHelp("Octave Up", shortcut: "]", detail: "Raises the trackpad pitch range by one full octave (up to +2).")
            }

            rowDivider

            // Full 5-Finger Polyphony Selector Keycaps (1–5)
            HStack(spacing: 4) {
                Text("VOICES")
                    .font(.system(size: 8.5, weight: .black, design: .monospaced))
                    .foregroundStyle(p.inkMuted)

                ForEach(1...5, id: \.self) { count in
                    VoiceSlotKeyButton(
                        count: count,
                        isMaxSelected: vm.maxVoices == count,
                        isWithinCap: count <= vm.maxVoices,
                        isCurrentlySounding: count <= vm.snapshot.activeVoices.count,
                        slotColor: p.color(forVoiceIndex: count - 1),
                        palette: p
                    ) {
                        vm.maxVoices = count
                    }
                    .xynthHelp(
                        "\(count)-Finger Polyphony",
                        detail: count == 5
                            ? "Maxed 5-finger trackpad mode: recognizes all 5 fingers simultaneously and guarantees every finger's fundamental pitch."
                            : "Limits simultaneous trackpad voices to \(count) finger\(count == 1 ? "" : "s") (fewer voices allocate more harmonic overtones per finger)."
                    )
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .hardwareModule(p, cornerRadius: 12)
    }

    private func shortBandLabel(_ preset: FrequencyRangePreset) -> String {
        switch preset {
        case .subFeel: return "SUB"
        case .balanced: return "BAL"
        case .acoustic: return "ACOUST"
        case .fullSpectrum: return "FULL"
        }
    }

    private var rowDivider: some View {
        Rectangle()
            .fill(p.moduleBorder)
            .frame(width: 1, height: 24)
    }

    // MARK: - Deck D: Direct Manual Pitch & Volume Faders

    private var directFadersRow: some View {
        HStack(spacing: 14) {
            HardwareKeyButton(
                title: (vm.manualSynthActive || vm.holdDrone) ? "TONE ON" : "TONE OFF",
                isActive: vm.manualSynthActive || vm.holdDrone,
                ledColor: p.enc2,
                palette: p,
                compact: true
            ) {
                vm.manualSynthActive.toggle()
                if !vm.manualSynthActive && vm.holdDrone {
                    vm.holdDrone = false
                }
            }
            .xynthHelp(
                "Manual Continuous Tone",
                detail: "Turns on a continuous sustained pitch controlled by the Direct Pitch & Volume faders so you can feel vibrations without sliding."
            )

            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text("DIRECT PITCH")
                        .font(.system(size: 8.5, weight: .black, design: .monospaced))
                        .foregroundStyle(p.inkMuted)
                    Spacer()
                    Text("\(vm.manualNoteLabel) · \(Int(vm.manualPitchHz.rounded())) Hz")
                        .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                        .monospacedDigit()
                        .foregroundStyle(p.enc1)
                }
                Slider(value: $vm.manualPitchX, in: 0.0...1.0)
                    .controlSize(.small)
                    .tint(p.enc1)
            }
            .xynthHelp(
                "Direct Pitch Fader",
                detail: "Sweeps frequency directly across the active scale and band while resting your fingers lightly on the trackpad."
            )

            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text("DIRECT VOLUME")
                        .font(.system(size: 8.5, weight: .black, design: .monospaced))
                        .foregroundStyle(p.inkMuted)
                    Spacer()
                    Text("\(Int((vm.manualVolumeY * 100).rounded()))%")
                        .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                        .monospacedDigit()
                        .foregroundStyle(p.enc2)
                }
                Slider(value: $vm.manualVolumeY, in: 0.0...1.0)
                    .controlSize(.small)
                    .tint(p.enc2)
            }
            .xynthHelp(
                "Direct Volume Fader",
                detail: "Controls direct motor vibration amplitude while Tone On or Hold is latched."
            )
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .hardwareModule(p, cornerRadius: 12, accentBorder: p.enc2.opacity(0.45))
    }
}

private struct VoiceSlotKeyButton: View {
    let count: Int
    let isMaxSelected: Bool
    let isWithinCap: Bool
    let isCurrentlySounding: Bool
    let slotColor: Color
    let palette: XynthPalette
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        let activeColor = isCurrentlySounding ? slotColor : palette.enc4
        Button(action: action) {
            VStack(spacing: 2.5) {
                HardwareLEDPip(
                    isOn: isCurrentlySounding || isMaxSelected,
                    color: activeColor,
                    offColor: isWithinCap ? palette.enc4.opacity(0.32) : palette.ledOff,
                    size: 4.5,
                    isHovered: isHovered
                )
                Text("\(count)")
                    .font(.system(size: 9.5, weight: (isMaxSelected || isHovered) ? .black : .bold, design: .monospaced))
                    .foregroundStyle(isMaxSelected ? palette.keycapActiveInk : (isHovered ? activeColor : palette.keycapInk))
            }
            .frame(width: 26, height: 29)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isMaxSelected ? palette.keycapActiveBg : palette.keycapBg)
                    if isHovered && !isMaxSelected {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(activeColor.opacity(0.11))
                    }
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(
                            (isMaxSelected || isHovered) ? activeColor.opacity(isMaxSelected ? 0.85 : 0.65) : palette.keycapBorder,
                            lineWidth: (isMaxSelected || isHovered) ? 1.25 : 0.9
                        )
                )
                .shadow(
                    color: (isMaxSelected || isHovered) ? activeColor.opacity(0.32) : palette.keycapShadow,
                    radius: isHovered ? 6 : (isMaxSelected ? 4 : 1.5),
                    y: isHovered ? 2 : 1
                )
            )
            .scaleEffect(isHovered ? 1.06 : 1.0)
            .offset(y: isHovered ? -1.2 : 0)
            .animation(.spring(response: 0.20, dampingFraction: 0.68), value: isHovered)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}
