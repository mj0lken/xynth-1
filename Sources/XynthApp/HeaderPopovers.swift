import SwiftUI
import XynthCore

/// Extracted custom-themed popovers for HeaderBarView so the main faceplate stays lean & readable.

struct ThemeGalleryPopover: View {
    @Bindable var vm: SynthViewModel
    let onDismiss: () -> Void
    @State private var hoveredPreset: XynthThemePreset? = nil

    private var p: XynthPalette { vm.palette }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("CHASSIS COLORWAY")
                    .font(.system(size: 10.5, weight: .black, design: .monospaced))
                    .tracking(1.0)
                    .foregroundStyle(p.oledInkPrimary)
                Spacer()
                Text("8 STYLES · KEY C")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(p.enc1)
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(XynthThemePreset.allCases) { preset in
                    let pal = preset.palette
                    let selected = vm.themePreset == preset
                    let hovered = hoveredPreset == preset
                    Button {
                        vm.themePreset = preset
                        onDismiss()
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 5) {
                                HStack(spacing: 3) {
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(pal.chassisTop)
                                        .frame(width: 18, height: 12)
                                        .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(Color.white.opacity(0.28), lineWidth: 0.7))
                                    Circle().fill(pal.enc1).frame(width: 8, height: 8)
                                    Circle().fill(pal.enc2).frame(width: 8, height: 8)
                                    Circle().fill(pal.enc3).frame(width: 8, height: 8)
                                    Circle().fill(pal.enc4).frame(width: 8, height: 8)
                                }
                                Spacer()
                                HardwareLEDPip(
                                    isOn: selected,
                                    color: pal.enc1,
                                    offColor: Color.white.opacity(0.14),
                                    size: 5.5,
                                    isHovered: hovered
                                )
                            }

                            Text(preset.displayName.uppercased())
                                .font(.system(size: 10.5, weight: .black, design: .monospaced))
                                .foregroundStyle(hovered ? pal.enc1 : Color.white.opacity(0.95))

                            Text(preset.tagline)
                                .font(.system(size: 9.5))
                                .foregroundStyle(Color.white.opacity(hovered ? 0.84 : 0.60))
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                        }
                        .padding(9)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(selected ? pal.enc1.opacity(0.20) : (hovered ? pal.enc1.opacity(0.12) : Color.white.opacity(0.04)))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .strokeBorder(
                                            (selected || hovered) ? pal.enc1.opacity(selected ? 1.0 : 0.72) : Color.white.opacity(0.10),
                                            lineWidth: (selected || hovered) ? 1.5 : 1
                                        )
                                )
                        )
                        .scaleEffect(hovered ? 1.025 : 1.0)
                        .offset(y: hovered ? -1.0 : 0)
                        .animation(.spring(response: 0.18, dampingFraction: 0.74), value: hovered)
                    }
                    .buttonStyle(.plain)
                    .onHover { over in
                        hoveredPreset = over ? preset : (hoveredPreset == preset ? nil : hoveredPreset)
                    }
                }
            }
        }
        .padding(14)
        .frame(width: 400)
        .background(p.dropdownBg)
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(p.dropdownBorder, lineWidth: 1.1).padding(1))
        .preferredColorScheme(.dark)
    }
}

struct HardwareActuatorPopover: View {
    @Bindable var vm: SynthViewModel
    let onDismiss: () -> Void

    private var p: XynthPalette { vm.palette }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("FORCE TOUCH ACTUATOR")
                .font(.system(size: 10, weight: .black, design: .monospaced))
                .foregroundStyle(p.enc1)
            Text(vm.snapshot.hardwareStatus.detailMessage)
                .font(.system(size: 10.5))
                .foregroundStyle(Color.white.opacity(0.75))
                .fixedSize(horizontal: false, vertical: true)

            if vm.availableDevices.count > 1 {
                Divider().overlay(Color.white.opacity(0.12))
                ForEach(vm.availableDevices) { dev in
                    Button {
                        vm.reconnectTrackpad(deviceID: dev.id)
                        onDismiss()
                    } label: {
                        HStack(spacing: 7) {
                            HardwareLEDPip(isOn: true, color: p.ledGood, offColor: p.ledOff, size: 5)
                            Text(dev.displayName.uppercased())
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundStyle(.white)
                            Spacer()
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.06)))
                    }
                    .buttonStyle(HardwarePillButtonStyle(accent: p.ledGood))
                }
            }

            Button {
                vm.reconnectTrackpad()
                onDismiss()
            } label: {
                HStack {
                    Spacer()
                    Text("RECONNECT MOTOR")
                        .font(.system(size: 10, weight: .black, design: .monospaced))
                        .foregroundStyle(p.oledBg)
                    Spacer()
                }
                .padding(.vertical, 7)
                .background(RoundedRectangle(cornerRadius: 6).fill(p.enc1))
            }
            .buttonStyle(HardwarePillButtonStyle(accent: p.enc1, isActive: true))
        }
        .padding(12)
        .frame(width: 270)
        .background(p.dropdownBg)
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(p.dropdownBorder, lineWidth: 1.1).padding(1))
        .preferredColorScheme(.dark)
    }
}

struct AudioRoutingPopover: View {
    @Bindable var vm: SynthViewModel
    @State private var hoveredRowID: String? = nil

    private var p: XynthPalette { vm.palette }

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("AUDIO OUT · RECORDING MIRROR")
                        .font(.system(size: 10.5, weight: .black, design: .monospaced))
                        .foregroundStyle(p.oledInkPrimary)
                    Text("Routes live synth sound to macOS audio for screen capture.")
                        .font(.system(size: 10.5))
                        .foregroundStyle(Color.white.opacity(0.62))
                }
                Spacer()
                Toggle("", isOn: Binding(
                    get: { vm.audioMirrorEnabled },
                    set: { vm.setAudioMirrorEnabled($0) }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .tint(p.enc4)
            }

            Divider().overlay(Color.white.opacity(0.12))

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("OUTPUT DEVICE")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(0.55))
                    Spacer()
                    Button("REFRESH") { vm.refreshAudioDevices() }
                        .font(.system(size: 9, weight: .black, design: .monospaced))
                        .buttonStyle(HardwarePillButtonStyle(accent: p.enc1))
                        .foregroundStyle(p.enc1)
                }

                VStack(spacing: 4) {
                    deviceRow(
                        id: "default",
                        title: "System Default Output",
                        subtitle: vm.availableAudioDevices.first(where: \.isDefault)?.name,
                        selected: vm.selectedAudioDeviceID == nil
                    ) {
                        vm.selectAudioOutputDevice(nil)
                    }

                    ForEach(vm.availableAudioDevices) { dev in
                        deviceRow(
                            id: dev.uid,
                            title: dev.name,
                            subtitle: dev.isDefault ? "Current System Default" : nil,
                            selected: vm.selectedAudioDeviceID == dev.id
                        ) {
                            vm.selectAudioOutputDevice(dev.id)
                        }
                    }
                }
            }

            Divider().overlay(Color.white.opacity(0.12))

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("AUDIO OUT LEVEL")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(0.55))
                    Spacer()
                    Text("\(Int((vm.audioOutputGain * 100).rounded()))%")
                        .font(.system(size: 10, weight: .black, design: .monospaced))
                        .monospacedDigit()
                        .foregroundStyle(p.enc4)
                }
                Slider(value: $vm.audioOutputGain, in: 0.0...1.0)
                    .controlSize(.small)
                    .tint(p.enc4)
            }

            Toggle(isOn: $vm.hapticsEnabled) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Trackpad Haptics")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                    Text("Keep ON to feel vibrations on the glass while recording")
                        .font(.system(size: 9.5))
                        .foregroundStyle(Color.white.opacity(0.58))
                }
            }
            .toggleStyle(.switch)
            .controlSize(.small)
            .tint(p.enc1)

            if let err = vm.audioMirrorError {
                Text(err)
                    .font(.system(size: 10))
                    .foregroundStyle(p.ledAlert)
            }
        }
        .padding(14)
        .frame(width: 315)
        .background(p.dropdownBg)
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(p.dropdownBorder, lineWidth: 1.1).padding(1))
        .preferredColorScheme(.dark)
    }

    private func deviceRow(id: String, title: String, subtitle: String?, selected: Bool, action: @escaping () -> Void) -> some View {
        let hovered = hoveredRowID == id
        return Button(action: action) {
            HStack(spacing: 8) {
                HardwareLEDPip(isOn: selected, color: p.enc4, offColor: Color.white.opacity(0.16), size: 5.5, isHovered: hovered)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 11, weight: (selected || hovered) ? .bold : .medium, design: .monospaced))
                        .foregroundStyle((selected || hovered) ? .white : Color.white.opacity(0.78))
                        .lineLimit(1)
                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 9))
                            .foregroundStyle(Color.white.opacity(0.50))
                            .lineLimit(1)
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5.5)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(selected ? p.enc4.opacity(0.24) : (hovered ? p.enc4.opacity(0.12) : Color.white.opacity(0.04)))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(
                                selected ? p.enc4.opacity(0.80) : (hovered ? p.enc4.opacity(0.45) : Color.clear),
                                lineWidth: 1
                            )
                    )
            )
            .offset(x: hovered && !selected ? 2.0 : 0)
            .animation(.spring(response: 0.18, dampingFraction: 0.76), value: hovered)
        }
        .buttonStyle(.plain)
        .onHover { over in
            hoveredRowID = over ? id : (hoveredRowID == id ? nil : hoveredRowID)
        }
    }
}

struct MuteProofPopover: View {
    let palette: XynthPalette
    let audioMirrorEnabled: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(audioMirrorEnabled ? "MAC OUTPUT IS MUTED" : "ZERO SPEAKERS USED")
                .font(.system(size: 11, weight: .black, design: .monospaced))
                .foregroundStyle(audioMirrorEnabled ? palette.enc2 : palette.ledGood)
            Text(
                audioMirrorEnabled
                    ? "Audio Out is ON while macOS volume is muted. Unmute (F10) or select BlackHole in the Audio Out menu if your screen recorder needs unmuted audio."
                    : "XYNTH-1 drives your Force Touch trackpad motor directly up to 4 kHz. Mute your Mac (F10) to prove every sound radiates from the glass — or toggle AUDIO OUT (A) to record."
            )
            .font(.system(size: 11))
            .foregroundStyle(Color.white.opacity(0.78))
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(13)
        .frame(width: 285)
        .background(palette.dropdownBg)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder((audioMirrorEnabled ? palette.enc2 : palette.dropdownBorder).opacity(0.75), lineWidth: 1.1)
                .padding(1)
        )
        .preferredColorScheme(.dark)
    }
}
