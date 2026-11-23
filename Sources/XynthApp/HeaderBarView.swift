import CoreAudio
import SwiftUI
import XynthCore

/// Machined top faceplate nameplate & utility bar:
/// XYNTH-1 emblem + speaker grille dots + Theme switcher + Actuator status + Audio Out +
/// Mute proof + Sound checks + Ferrofluid Bay toggle + Top-Right Settings Flip Gear.
struct HeaderBarView: View {
    @Bindable var vm: SynthViewModel
    @State private var showMuteHint = false
    @State private var showAudioRouting = false
    @State private var showThemePicker = false
    @State private var showHardwareMenu = false
    @State private var hoveredThemeSwatch = false
    @State private var hoveredThemeCycle = false
    @State private var hoveredHardwarePill = false
    @State private var hoveredAudioToggle = false
    @State private var hoveredAudioChevron = false
    @State private var hoveredMutePill = false
    @State private var hoveredSettingsGear = false

    private var p: XynthPalette { vm.palette }

    var body: some View {
        VStack(spacing: 0) {
            // Signature theme color stripe along top edge
            HStack(spacing: 0) {
                ForEach(Array(p.stripeColors.enumerated()), id: \.offset) { _, color in
                    Rectangle().fill(color)
                }
            }
            .frame(height: 2.5)
            .shadow(color: p.hasNeonTube ? p.enc2.opacity(0.85) : .clear, radius: 5)

            HStack(spacing: 8) {
                // Brand emblem + live motor LED + consistent machined dot-matrix grille
                HStack(spacing: 8) {
                    HardwareLEDPip(
                        isOn: vm.snapshot.hardwareStatus.isReady,
                        color: statusLedColor,
                        offColor: p.ledAlert,
                        size: 8
                    )
                    .scaleEffect(vm.snapshot.isSounding ? 1.0 + vm.snapshot.effectiveLevel * 0.25 : 1.0)
                    .animation(.easeOut(duration: 0.08), value: vm.snapshot.effectiveLevel)
                    .xynthHelp(
                        "Motor Power LED",
                        detail: "Pulses with live Taptic Engine energy. Solid when connected; red if no Force Touch trackpad is detected."
                    )

                    Text("XYNTH-1")
                        .font(.system(size: 15.5, weight: .black, design: .monospaced))
                        .tracking(2.0)
                        .foregroundStyle(p.inkPrimary)
                        .fixedSize(horizontal: true, vertical: false)

                    SpeakerGrilleDots(palette: p)
                        .padding(.leading, 2)
                }

                Spacer(minLength: 6)

                themeSwitcherControl
                hardwarePill
                audioOutControl
                muteProofPill

                // Quick tactile checks
                HStack(spacing: 5) {
                    HardwareKeyButton(
                        title: "SWEEP",
                        shortcut: "T",
                        isActive: vm.snapshot.demoLabel?.contains("SWEEP") == true,
                        ledColor: p.enc1,
                        palette: p,
                        compact: true
                    ) {
                        vm.triggerSweepDemo()
                    }
                    .xynthHelp(
                        "Frequency Sweep",
                        shortcut: "T",
                        detail: "Glides from 98 Hz to 3.6 kHz across the trackpad glass so you can hear and feel every resonant band."
                    )

                    HardwareKeyButton(
                        title: "CHORD",
                        isActive: vm.snapshot.demoLabel?.contains("CHORD") == true,
                        ledColor: p.enc4,
                        palette: p,
                        compact: true
                    ) {
                        vm.triggerArpeggioDemo()
                    }
                    .xynthHelp(
                        "Chord Check",
                        detail: "Plays an ascending A-minor 9 arpeggio directly through the Force Touch motor."
                    )

                    HardwareKeyButton(
                        title: "PULSE",
                        isActive: vm.snapshot.demoLabel?.contains("PULSE") == true,
                        ledColor: p.enc3,
                        palette: p,
                        compact: true
                    ) {
                        vm.triggerHeartbeatDemo()
                    }
                    .xynthHelp(
                        "Tactile Pulse",
                        detail: "Triggers two deep low-frequency heartbeat thumps felt strongly in your fingertips."
                    )
                }

                // Expandable Ferrofluid Bay Toggle
                HardwareKeyButton(
                    title: "FERRO",
                    shortcut: "V",
                    isActive: vm.showExpansionBay,
                    ledColor: p.ferroRim,
                    palette: p,
                    compact: true
                ) {
                    vm.toggleExpansionBay()
                }
                .xynthHelp(
                    "Liquid Magnetic Expansion Bay",
                    shortcut: "V",
                    detail: "Expands XYNTH-1 to the right with a real-time Ferrofluid visualizer, LFO rate knob, patches & live partials."
                )

                // Top-Right Settings Gear (3D flips window to Rear Service Panel)
                settingsGearButton
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 8.5)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .hardwareModule(p, cornerRadius: 12)
    }

    private var statusLedColor: Color {
        if !vm.snapshot.hardwareStatus.isReady { return p.ledAlert }
        if vm.snapshot.isSounding { return vm.audioMirrorEnabled ? p.enc4 : p.enc1 }
        if vm.isPlayModeLocked { return p.ledGood }
        return p.enc1.opacity(0.65)
    }

    // MARK: - Top-Right Settings Flip Gear

    private var settingsGearButton: some View {
        let hasUpdate = vm.availableUpdate != nil
        let accent = hasUpdate ? p.enc2 : p.enc1

        return Button {
            vm.toggleSettingsFlip()
        } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(hoveredSettingsGear ? accent : p.keycapInk)
                    .rotationEffect(.degrees(hoveredSettingsGear ? 48 : 0))
                    .frame(width: 28, height: 26)
                    .background(
                        ZStack {
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(p.keycapBg)
                            if hoveredSettingsGear {
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(accent.opacity(0.12))
                            }
                        }
                        .overlay(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .strokeBorder(
                                    (hoveredSettingsGear || hasUpdate) ? accent.opacity(0.75) : p.keycapBorder,
                                    lineWidth: (hoveredSettingsGear || hasUpdate) ? 1.25 : 1
                                )
                        )
                        .shadow(
                            color: (hoveredSettingsGear || hasUpdate) ? accent.opacity(0.32) : p.keycapShadow,
                            radius: hoveredSettingsGear ? 7 : 1.5,
                            y: hoveredSettingsGear ? 2 : 1
                        )
                    )

                if hasUpdate {
                    HardwareLEDPip(isOn: true, color: p.enc2, offColor: p.ledOff, size: 5.5)
                        .offset(x: 2, y: -2)
                }
            }
            .scaleEffect(hoveredSettingsGear ? 1.06 : 1.0)
            .offset(y: hoveredSettingsGear ? -0.9 : 0)
            .animation(.spring(response: 0.24, dampingFraction: 0.68), value: hoveredSettingsGear)
        }
        .buttonStyle(.plain)
        .onHover { hoveredSettingsGear = $0 }
        .xynthHelp(
            hasUpdate ? "Settings (Update Available!)" : "Settings & Service Panel",
            shortcut: "⌘,",
            detail: "Flips XYNTH-1 over to access macOS multi-finger trackpad gesture shortcuts, GitHub auto-updates & preferences."
        )
    }

    // MARK: - 8-Theme Selector Pill

    private var themeSwitcherControl: some View {
        let anyHovered = hoveredThemeSwatch || hoveredThemeCycle
        return HStack(spacing: 0) {
            Button {
                showThemePicker.toggle()
            } label: {
                HStack(spacing: 5) {
                    HStack(spacing: 2.5) {
                        ForEach(0..<3, id: \.self) { i in
                            Circle()
                                .fill(p.swatchColors[i])
                                .frame(width: 7, height: 7)
                                .overlay(Circle().strokeBorder(Color.black.opacity(0.32), lineWidth: 0.6))
                        }
                    }
                    Text(vm.themePreset.shortCode)
                        .font(.system(size: 9.5, weight: .black, design: .monospaced))
                        .foregroundStyle(hoveredThemeSwatch ? p.enc1 : p.keycapInk)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .black))
                        .foregroundStyle(p.enc1)
                        .offset(y: hoveredThemeSwatch ? 1.0 : 0)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(hoveredThemeSwatch ? p.enc1.opacity(0.10) : Color.clear)
            }
            .buttonStyle(.plain)
            .onHover { hoveredThemeSwatch = $0 }
            .popover(isPresented: $showThemePicker, arrowEdge: .bottom) {
                ThemeGalleryPopover(vm: vm) { showThemePicker = false }
            }
            .xynthHelp(
                "Theme: \(vm.themePreset.displayName)",
                shortcut: "C",
                detail: "Pick from 8 bold industrial designs: OP-1 Field, 80s Tech, Dieter White, Obsidian, Neon Cyber, Inca Gold, Acid Modern & Koto Clay."
            )

            Rectangle()
                .fill(anyHovered ? p.enc1.opacity(0.45) : p.keycapBorder)
                .frame(width: 1, height: 14)

            Button {
                vm.cycleTheme()
            } label: {
                Text("C")
                    .font(.system(size: 8.5, weight: .black, design: .monospaced))
                    .foregroundStyle(hoveredThemeCycle ? p.oledBg : p.enc2)
                    .padding(.horizontal, 6.5)
                    .padding(.vertical, 6)
                    .background(hoveredThemeCycle ? p.enc2 : Color.clear)
            }
            .buttonStyle(.plain)
            .onHover { hoveredThemeCycle = $0 }
            .xynthHelp(
                "Cycle Theme",
                shortcut: "C",
                detail: "Instantly steps to the next hardware colorway — works live even while Play Mode is locked."
            )
        }
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(p.keycapBg)
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(anyHovered ? p.enc1.opacity(0.75) : p.keycapBorder, lineWidth: anyHovered ? 1.25 : 1)
                )
                .shadow(
                    color: anyHovered ? p.enc1.opacity(0.28) : p.keycapShadow,
                    radius: anyHovered ? 6 : 1.5,
                    y: anyHovered ? 2 : 1
                )
        )
        .scaleEffect(anyHovered ? 1.025 : 1.0)
        .offset(y: anyHovered ? -0.9 : 0)
        .animation(.spring(response: 0.20, dampingFraction: 0.72), value: anyHovered)
    }

    // MARK: - Trackpad Actuator Pill

    private var hardwarePill: some View {
        let accent = vm.snapshot.hardwareStatus.isReady ? p.ledGood : p.ledAlert
        return Button {
            showHardwareMenu.toggle()
        } label: {
            HStack(spacing: 5) {
                HardwareLEDPip(
                    isOn: vm.snapshot.hardwareStatus.isReady,
                    color: p.ledGood,
                    offColor: p.ledAlert,
                    size: 5.5,
                    isHovered: hoveredHardwarePill
                )
                Text(vm.snapshot.hardwareStatus.shortLabel.uppercased())
                    .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(hoveredHardwarePill ? accent : p.keycapInk)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 7.5, weight: .black))
                    .foregroundStyle(hoveredHardwarePill ? accent : p.keycapMutedInk)
                    .offset(y: hoveredHardwarePill ? 0.9 : 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(p.keycapBg)
                    if hoveredHardwarePill {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(accent.opacity(0.10))
                    }
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(hoveredHardwarePill ? accent.opacity(0.75) : p.keycapBorder, lineWidth: hoveredHardwarePill ? 1.2 : 1)
                )
                .shadow(
                    color: hoveredHardwarePill ? accent.opacity(0.28) : p.keycapShadow,
                    radius: hoveredHardwarePill ? 6 : 1.5,
                    y: hoveredHardwarePill ? 2 : 1
                )
            )
            .scaleEffect(hoveredHardwarePill ? 1.024 : 1.0)
            .offset(y: hoveredHardwarePill ? -0.9 : 0)
            .animation(.spring(response: 0.20, dampingFraction: 0.72), value: hoveredHardwarePill)
        }
        .buttonStyle(.plain)
        .onHover { hoveredHardwarePill = $0 }
        .popover(isPresented: $showHardwareMenu, arrowEdge: .bottom) {
            HardwareActuatorPopover(vm: vm) { showHardwareMenu = false }
        }
        .xynthHelp(
            "Force Touch Actuator",
            detail: "Shows your connected Taptic Engine trackpad via MultitouchSupport. Click to switch trackpads or reconnect."
        )
    }

    // MARK: - Audio Out / Recording Mirror Split Keycap

    private var audioOutControl: some View {
        let on = vm.audioMirrorEnabled
        let anyHovered = hoveredAudioToggle || hoveredAudioChevron

        return HStack(spacing: 0) {
            Button {
                vm.toggleAudioMirror()
            } label: {
                HStack(spacing: 5) {
                    HardwareLEDPip(
                        isOn: on,
                        color: p.enc4,
                        offColor: p.ledOff,
                        size: 5.5,
                        isHovered: hoveredAudioToggle
                    )
                    Text(on ? "AUDIO·REC" : "AUDIO OUT")
                        .font(.system(size: 9.5, weight: on ? .black : .bold, design: .monospaced))
                        .foregroundStyle(on ? p.keycapActiveInk : (hoveredAudioToggle ? p.enc4 : p.keycapInk))
                    Text("A")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundStyle((on || hoveredAudioToggle) ? p.enc4 : p.keycapMutedInk)
                }
                .padding(.leading, 8)
                .padding(.trailing, 6)
                .padding(.vertical, 6)
                .background(hoveredAudioToggle ? p.enc4.opacity(on ? 0.14 : 0.10) : Color.clear)
            }
            .buttonStyle(.plain)
            .onHover { hoveredAudioToggle = $0 }
            .xynthHelp(
                "Audio Out (Recording Mirror)",
                shortcut: "A",
                detail: "Mirrors live synth sound to macOS speakers or virtual audio (BlackHole/OBS) so screen recordings capture it while the glass vibrates."
            )

            Rectangle()
                .fill((on || anyHovered) ? p.enc4.opacity(0.50) : p.keycapBorder)
                .frame(width: 1, height: 14)

            Button {
                vm.refreshAudioDevices()
                showAudioRouting.toggle()
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .black))
                    .foregroundStyle((on || hoveredAudioChevron) ? p.enc4 : p.keycapMutedInk)
                    .padding(.horizontal, 6.5)
                    .padding(.vertical, 6)
                    .background(hoveredAudioChevron ? p.enc4.opacity(0.14) : Color.clear)
                    .offset(y: hoveredAudioChevron ? 0.9 : 0)
            }
            .buttonStyle(.plain)
            .onHover { hoveredAudioChevron = $0 }
            .popover(isPresented: $showAudioRouting, arrowEdge: .bottom) {
                AudioRoutingPopover(vm: vm)
            }
            .xynthHelp(
                "Audio Output Routing",
                detail: "Pick which macOS output device receives Audio Out (Speakers, BlackHole, Headphones) and trim recording level."
            )
        }
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(on ? p.keycapActiveBg : p.keycapBg)
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder((on || anyHovered) ? p.enc4.opacity(on ? 0.90 : 0.72) : p.keycapBorder, lineWidth: (on || anyHovered) ? 1.25 : 1)
                )
                .shadow(
                    color: (on || anyHovered) ? p.enc4.opacity(anyHovered ? 0.40 : 0.28) : p.keycapShadow,
                    radius: anyHovered ? 7 : (on ? 5 : 1.5),
                    y: anyHovered ? 2 : 1
                )
        )
        .scaleEffect(anyHovered ? 1.025 : 1.0)
        .offset(y: anyHovered ? -0.9 : 0)
        .animation(.spring(response: 0.20, dampingFraction: 0.72), value: anyHovered)
    }

    // MARK: - Speaker Mute Verification Pill

    @ViewBuilder
    private var muteProofPill: some View {
        let isMuted = (vm.muteState == .muted)

        if vm.audioMirrorEnabled {
            if isMuted {
                Button { showMuteHint.toggle() } label: {
                    HStack(spacing: 5) {
                        HardwareLEDPip(isOn: true, color: p.enc2, offColor: p.ledOff, size: 5.5, isHovered: hoveredMutePill)
                        Text("MUTED")
                            .font(.system(size: 9.5, weight: .black, design: .monospaced))
                            .foregroundStyle(p.enc2)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(p.keycapActiveBg)
                            .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(p.enc2.opacity(hoveredMutePill ? 0.95 : 0.6), lineWidth: hoveredMutePill ? 1.25 : 1))
                    )
                }
                .buttonStyle(HardwarePillButtonStyle(accent: p.enc2, isActive: true))
                .onHover { hoveredMutePill = $0 }
                .popover(isPresented: $showMuteHint, arrowEdge: .bottom) {
                    MuteProofPopover(palette: p, audioMirrorEnabled: true)
                }
                .xynthHelp(
                    "Mac Audio Muted Warning",
                    detail: "Audio Out is active while macOS volume is muted. Unmute with F10 or route to BlackHole."
                )
            }
        } else {
            let accent = isMuted ? p.ledGood : p.enc2
            Button { showMuteHint.toggle() } label: {
                HStack(spacing: 5) {
                    HardwareLEDPip(
                        isOn: isMuted,
                        color: p.ledGood,
                        offColor: p.enc2,
                        size: 5.5,
                        isHovered: hoveredMutePill
                    )
                    Text(isMuted ? "0 SPK" : "MUTE")
                        .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(isMuted ? p.ledGood : (hoveredMutePill ? p.enc2 : p.keycapInk))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(
                    ZStack {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(isMuted ? p.keycapActiveBg : p.keycapBg)
                        if hoveredMutePill && !isMuted {
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(accent.opacity(0.10))
                        }
                    }
                    .overlay(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .strokeBorder((isMuted || hoveredMutePill) ? accent.opacity(0.75) : p.keycapBorder, lineWidth: (isMuted || hoveredMutePill) ? 1.2 : 1)
                    )
                )
            }
            .buttonStyle(HardwarePillButtonStyle(accent: accent, isActive: isMuted))
            .onHover { hoveredMutePill = $0 }
            .popover(isPresented: $showMuteHint, arrowEdge: .bottom) {
                MuteProofPopover(palette: p, audioMirrorEnabled: false)
            }
            .xynthHelp(
                isMuted ? "Speakers Muted (Verified)" : "Speaker Mute Check",
                detail: isMuted
                    ? "Your MacBook speakers are muted — 100% of the sound comes directly from the Force Touch trackpad glass."
                    : "Mute your Mac (F10) to verify zero speaker audio, or enable AUDIO OUT (A) for screen recordings."
            )
        }
    }
}
