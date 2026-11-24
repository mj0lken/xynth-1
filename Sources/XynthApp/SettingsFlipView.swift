import AppKit
import SwiftUI
import XynthCore

/// Rear hardware service panel revealed via a 3D window flip when clicking the top-right Settings gear.
/// Contains macOS Multi-Finger Trackpad Shortcuts deep-link, GitHub Releases Auto-Updater,
/// interface preferences, and silkscreened hardware specifications.
struct SettingsFlipView: View {
    @Bindable var vm: SynthViewModel

    private var p: XynthPalette { vm.palette }

    var body: some View {
        VStack(spacing: 12) {
            // Backplate top header bar
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    ForEach(Array(p.stripeColors.enumerated()), id: \.offset) { _, color in
                        Rectangle().fill(color)
                    }
                }
                .frame(height: 2.5)

                HStack(spacing: 10) {
                    HardwareLEDPip(isOn: true, color: p.enc1, offColor: p.ledOff, size: 7.5)
                    Text("XYNTH-1 // REAR SERVICE PANEL")
                        .font(.system(size: 14, weight: .black, design: .monospaced))
                        .tracking(1.8)
                        .foregroundStyle(p.inkPrimary)

                    SpeakerGrilleDots(palette: p)

                    Spacer()

                    Text("v\(AppUpdateService.currentAppVersion.description)")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(p.inkSecondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 5)
                                .fill(p.isLightChassis ? Color.black.opacity(0.07) : Color.white.opacity(0.08))
                        )

                    HardwareKeyButton(
                        title: "FLIP TO SYNTH",
                        shortcut: "ESC",
                        isActive: true,
                        ledColor: p.enc1,
                        palette: p,
                        compact: true
                    ) {
                        vm.toggleSettingsFlip()
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .hardwareModule(p, cornerRadius: 12)

            // Main 2-column hardware backplate deck
            HStack(alignment: .top, spacing: 12) {
                VStack(spacing: 12) {
                    trackpadGesturesCard
                    autoUpdateCard
                }
                .frame(maxWidth: .infinity)

                VStack(spacing: 12) {
                    preferencesCard
                    hardwareSpecAndLinksCard
                }
                .frame(maxWidth: .infinity)
            }

            Spacer(minLength: 0)

            // Silkscreened model serial stamp along bottom backplate rail
            HStack {
                Text("XYNTH-1 · TACTILE FORCE TOUCH SYNTHESIZER · MIT OPEN SOURCE")
                    .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(p.inkMuted)
                Spacer()
                Text("APPLE SILICON · MACOS 14+ · INSPIRED BY OS6/NOSPEAKER")
                    .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(p.inkMuted)
            }
            .padding(.horizontal, 4)
        }
    }

    // MARK: - 1. macOS Multi-Finger Trackpad Shortcuts Card

    private var trackpadGesturesCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                HardwareLEDPip(isOn: true, color: p.enc3, offColor: p.ledOff, size: 6.5)
                Text("MACOS MULTI-FINGER TRACKPAD SHORTCUTS")
                    .font(.system(size: 10, weight: .black, design: .monospaced))
                    .tracking(0.8)
                    .foregroundStyle(p.inkPrimary)
                Spacer()
                Text("5-FINGER TIP")
                    .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(p.enc3)
            }

            Text("macOS system gestures like 4-finger Mission Control or 5-finger Launchpad pinch can intercept chords while playing XYNTH-1. Jump straight to System Settings → Trackpad → More Gestures to disable any conflicting shortcuts:")
                .font(.system(size: 11))
                .foregroundStyle(p.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(2)

            // Recessed mini checklist box
            VStack(alignment: .leading, spacing: 5) {
                gestureRow("Mission Control & App Exposé", detail: "Disable 3/4-finger swipe up/down")
                gestureRow("Launchpad & Show Desktop", detail: "Disable 4/5-finger thumb pinch/spread")
                gestureRow("Swipe Between Full-Screen Apps", detail: "Disable 3/4-finger horizontal swipe")
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(p.oledBg)
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(p.oledBorder, lineWidth: 1))
            )

            HStack(spacing: 8) {
                HardwareKeyButton(
                    title: "OPEN TRACKPAD SETTINGS ↗",
                    isActive: true,
                    ledColor: p.enc3,
                    palette: p,
                    fullWidth: true
                ) {
                    vm.openMacOSTrackpadSettings()
                }

                HardwareKeyButton(
                    title: "MISSION CONTROL ↗",
                    isActive: false,
                    ledColor: p.enc4,
                    palette: p,
                    compact: true
                ) {
                    vm.openMacOSMissionControlSettings()
                }
            }
        }
        .padding(14)
        .hardwareModule(p, cornerRadius: 12)
    }

    private func gestureRow(_ name: String, detail: String) -> some View {
        HStack(spacing: 7) {
            Circle()
                .fill(p.enc3)
                .frame(width: 4.5, height: 4.5)
            Text(name)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(p.oledInkPrimary)
            Spacer()
            Text(detail)
                .font(.system(size: 9.5))
                .foregroundStyle(p.oledInkMuted)
        }
    }

    // MARK: - 2. GitHub Releases Auto-Update Card

    private var autoUpdateCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                HardwareLEDPip(
                    isOn: vm.availableUpdate != nil || vm.isCheckingUpdates,
                    color: vm.availableUpdate != nil ? p.enc2 : p.ledGood,
                    offColor: p.ledGood.opacity(0.65),
                    size: 6.5
                )
                Text("SOFTWARE AUTO-UPDATE")
                    .font(.system(size: 10, weight: .black, design: .monospaced))
                    .tracking(0.8)
                    .foregroundStyle(p.inkPrimary)
                Spacer()
                Text("CURRENT v\(AppUpdateService.currentAppVersion.description)")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(p.inkMuted)
            }

            // Status OLED readout
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(vm.updateStatusHeadline)
                        .font(.system(size: 10.5, weight: .black, design: .monospaced))
                        .foregroundStyle(vm.availableUpdate != nil ? p.enc2 : p.enc1)
                    Spacer()
                    if vm.isCheckingUpdates || vm.isInstallingUpdate {
                        ProgressView()
                            .controlSize(.mini)
                    }
                }
                Text(vm.updateStatusDetail)
                    .font(.system(size: 10))
                    .foregroundStyle(p.oledInkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(p.oledBg)
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(p.oledBorder, lineWidth: 1))
            )

            Toggle(isOn: $vm.autoCheckUpdatesOnLaunch) {
                Text("Automatically check GitHub Releases for updates on launch")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(p.inkPrimary)
            }
            .toggleStyle(.switch)
            .controlSize(.small)
            .tint(p.enc1)

            HStack(spacing: 8) {
                HardwareKeyButton(
                    title: vm.isCheckingUpdates ? "CHECKING…" : "CHECK FOR UPDATES",
                    isActive: false,
                    ledColor: p.enc1,
                    palette: p,
                    compact: true,
                    fullWidth: true
                ) {
                    vm.checkForUpdates(userInitiated: true)
                }
                .disabled(vm.isCheckingUpdates || vm.isInstallingUpdate)

                if let release = vm.availableUpdate {
                    HardwareKeyButton(
                        title: vm.isInstallingUpdate ? "INSTALLING…" : "INSTALL \(release.tagName)",
                        isActive: true,
                        ledColor: p.enc2,
                        palette: p,
                        compact: true,
                        fullWidth: true
                    ) {
                        vm.installAvailableUpdate()
                    }
                    .disabled(vm.isInstallingUpdate)
                }

                HardwareKeyButton(
                    title: "RELEASES ↗",
                    isActive: false,
                    ledColor: p.enc4,
                    palette: p,
                    compact: true
                ) {
                    NSWorkspace.shared.open(AppUpdateService.releasesURL)
                }
            }
        }
        .padding(14)
        .hardwareModule(p, cornerRadius: 12)
    }

    // MARK: - 3. Interface & Synth Preferences Card

    private var preferencesCard: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 7) {
                HardwareLEDPip(isOn: true, color: p.enc4, offColor: p.ledOff, size: 6.5)
                Text("INTERFACE & SYNTH PREFERENCES")
                    .font(.system(size: 10, weight: .black, design: .monospaced))
                    .tracking(0.8)
                    .foregroundStyle(p.inkPrimary)
                Spacer()
            }

            VStack(alignment: .leading, spacing: 9) {
                Toggle(isOn: $vm.hoverTooltipsEnabled) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Floating Hover Help Tooltips")
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(p.inkPrimary)
                        Text("Shows styled setting explanations when hovering over buttons & encoders")
                            .font(.system(size: 9.5))
                            .foregroundStyle(p.inkMuted)
                    }
                }
                .toggleStyle(.switch)
                .controlSize(.small)
                .tint(p.enc1)

                Toggle(isOn: $vm.hapticsEnabled) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Force Touch Trackpad Haptics")
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(p.inkPrimary)
                        Text("Drive the trackpad motor directly for physical vibration + glass acoustics")
                            .font(.system(size: 9.5))
                            .foregroundStyle(p.inkMuted)
                    }
                }
                .toggleStyle(.switch)
                .controlSize(.small)
                .tint(p.enc2)

                Toggle(isOn: $vm.alwaysSenseWhenFocused) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Always-Live Trackpad Sensing")
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(p.inkPrimary)
                        Text("Sound immediately whenever XYNTH-1 is focused without locking cursor")
                            .font(.system(size: 9.5))
                            .foregroundStyle(p.inkMuted)
                    }
                }
                .toggleStyle(.switch)
                .controlSize(.small)
                .tint(p.ledGood)
            }

            Divider().overlay(p.moduleBorder)

            // Quick 8-Theme Selector Strip right on the backplate
            VStack(alignment: .leading, spacing: 6) {
                Text("CHASSIS THEME")
                    .font(.system(size: 8.5, weight: .black, design: .monospaced))
                    .foregroundStyle(p.inkMuted)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 5), count: 4), spacing: 5) {
                    ForEach(XynthThemePreset.allCases) { preset in
                        HardwareKeyButton(
                            title: preset.shortCode,
                            isActive: vm.themePreset == preset,
                            ledColor: preset.palette.enc1,
                            palette: p,
                            compact: true,
                            fullWidth: true
                        ) {
                            vm.themePreset = preset
                        }
                    }
                }
            }
        }
        .padding(14)
        .hardwareModule(p, cornerRadius: 12)
    }

    // MARK: - 4. Hardware Safety Specs & Public Links

    private var hardwareSpecAndLinksCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                HardwareLEDPip(isOn: vm.snapshot.hardwareStatus.isReady, color: p.ledGood, offColor: p.ledAlert, size: 6.5)
                Text("ACTUATOR SAFETY & PROJECT LINKS")
                    .font(.system(size: 10, weight: .black, design: .monospaced))
                    .tracking(0.8)
                    .foregroundStyle(p.inkPrimary)
                Spacer()
            }

            VStack(spacing: 5) {
                specRow("TRACKPAD", vm.snapshot.hardwareStatus.shortLabel.uppercased())
                specRow("SAFE FREQ SPAN", "45 Hz – 4,150 Hz")
                specRow("ANTI-STALL LIMIT", "Σ AMP = 1.0 · MAX 6 PARTIALS")
                specRow("POLYPHONY", "UP TO 5 FINGERS (32ms ANTI-FLICKER)")
                specRow("REPOSITORY", AppUpdateService.defaultRepo.uppercased())
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(p.oledBg)
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(p.oledBorder, lineWidth: 1))
            )

            HStack(spacing: 7) {
                HardwareKeyButton(
                    title: "GITHUB ↗",
                    isActive: false,
                    ledColor: p.enc1,
                    palette: p,
                    compact: true,
                    fullWidth: true
                ) {
                    NSWorkspace.shared.open(AppUpdateService.repoURL)
                }

                HardwareKeyButton(
                    title: "WEB DEMO ↗",
                    isActive: false,
                    ledColor: p.enc4,
                    palette: p,
                    compact: true,
                    fullWidth: true
                ) {
                    NSWorkspace.shared.open(AppUpdateService.landingPageURL)
                }

                HardwareKeyButton(
                    title: "ISSUES ↗",
                    isActive: false,
                    ledColor: p.enc2,
                    palette: p,
                    compact: true,
                    fullWidth: true
                ) {
                    if let url = URL(string: "\(AppUpdateService.repoURL.absoluteString)/issues") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
        }
        .padding(14)
        .hardwareModule(p, cornerRadius: 12)
    }

    private func specRow(_ key: String, _ val: String) -> some View {
        HStack {
            Text(key)
                .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                .foregroundStyle(p.oledInkMuted)
            Spacer()
            Text(val)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(p.oledInkPrimary)
        }
    }
}
