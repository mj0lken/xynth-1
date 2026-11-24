import AppKit
import SwiftUI
import XynthCore

@main
struct XynthApp: App {
    @NSApplicationDelegateAdaptor(XynthAppDelegate.self) private var appDelegate
    @State private var vm = SynthViewModel()

    var body: some Scene {
        WindowGroup("XYNTH-1") {
            XynthMainView(vm: vm)
                .preferredColorScheme(vm.palette.isLightChassis ? .light : .dark)
                .onAppear {
                    vm.applyWindowTheme()
                }
                .onDisappear {
                    vm.shutdown()
                }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1120, height: 815)
        .windowResizability(.contentMinSize)
        .commands {
            CommandMenu("Synth") {
                Button(vm.isPlayModeLocked ? "Unlock Trackpad" : "Lock Trackpad (Play Mode)") {
                    vm.togglePlayMode()
                }
                .keyboardShortcut("l", modifiers: [.command])

                Button(vm.holdDrone ? "Release Hold / Drone" : "Engage Hold / Drone") {
                    vm.toggleHoldDrone()
                }
                .keyboardShortcut("d", modifiers: [.command])

                Button(vm.audioMirrorEnabled ? "Disable Audio Out (Speakers / Rec)" : "Enable Audio Out (Speakers / Rec)") {
                    vm.toggleAudioMirror()
                }
                .keyboardShortcut("r", modifiers: [.command])

                Button(vm.showExpansionBay ? "Hide Ferrofluid Expansion Bay" : "Show Ferrofluid Expansion Bay") {
                    vm.toggleExpansionBay()
                }
                .keyboardShortcut("e", modifiers: [.command])

                Button(vm.showSettings ? "Flip Back to Synth" : "Settings & Service Panel") {
                    vm.toggleSettingsFlip()
                }
                .keyboardShortcut(",", modifiers: [.command])

                Button("Check for Updates…") {
                    if !vm.showSettings { vm.toggleSettingsFlip() }
                    vm.checkForUpdates(userInitiated: true)
                }

                Divider()

                Menu("Hardware Theme") {
                    ForEach(XynthThemePreset.allCases) { preset in
                        Button(preset.displayName) {
                            vm.themePreset = preset
                        }
                    }
                }

                Button("Next Hardware Theme") {
                    vm.cycleTheme()
                }
                .keyboardShortcut("t", modifiers: [.command, .shift])

                Divider()

                Button("Play Short Glass Demo") {
                    vm.triggerShortDemo()
                }
                Button("Play Frequency Sweep (98 Hz – 3.6 kHz)") {
                    vm.triggerSweepDemo()
                }
                Button("Play Trackpad Chord Check") {
                    vm.triggerArpeggioDemo()
                }
                Button("Reconnect Force Touch Trackpad") {
                    vm.reconnectTrackpad()
                }
            }
        }
    }
}

@MainActor
final class XynthAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        DispatchQueue.main.async {
            for window in NSApp.windows {
                window.title = "XYNTH-1"
                window.isOpaque = true
                window.titlebarAppearsTransparent = true
                window.isMovableByWindowBackground = false
                window.minSize = NSSize(width: 1000, height: 760)
                // Guard against oversized/restored frames from earlier layout bugs
                var frame = window.frame
                if frame.width > 1280 || frame.height > 920 || frame.height < 760 {
                    frame.size = NSSize(width: 1120, height: 815)
                    window.setFrame(frame, display: true)
                    window.center()
                }
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationWillTerminate(_ notification: Notification) {
        CGAssociateMouseAndMouseCursorPosition(boolean_t(1))
        NSCursor.unhide()
    }
}

struct XynthMainView: View {
    @Bindable var vm: SynthViewModel

    private var p: XynthPalette { vm.palette }

    var body: some View {
        ZStack {
            // Bold industrial-design chassis substrate (unique artwork per theme)
            chassisBackground
                .ignoresSafeArea()

            // 3D Hardware Flip Container: Front Synth Faceplate (0° -> 180°) <-> Rear Service Panel (-180° -> 0°)
            // Rotating each face independently ensures the active Rear Panel settles at a clean 0° identity transform (zero mirroring).
            ZStack {
                frontFaceplateView
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .rotation3DEffect(
                        .degrees(vm.showSettings ? 180 : 0),
                        axis: (x: 0, y: 1, z: 0),
                        perspective: 0.42
                    )
                    .opacity(vm.showSettings ? 0.0 : 1.0)
                    .allowsHitTesting(!vm.showSettings)

                SettingsFlipView(vm: vm)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .rotation3DEffect(
                        .degrees(vm.showSettings ? 0 : -180),
                        axis: (x: 0, y: 1, z: 0),
                        perspective: 0.42
                    )
                    .opacity(vm.showSettings ? 1.0 : 0.0)
                    .allowsHitTesting(vm.showSettings)
            }
            .animation(.spring(response: 0.56, dampingFraction: 0.80), value: vm.showSettings)
            .padding(.horizontal, 16)
            .padding(.top, 26)
            .padding(.bottom, 10)

            // 4 corner machined chassis hex screws
            cornerScrewsOverlay
                .allowsHitTesting(false)

            // Non-blocking, click-dismissed styled floating hover tooltip
            StyledHoverTooltipOverlay(palette: p, helpState: vm.hoverHelp)
        }
        .frame(
            minWidth: vm.showExpansionBay ? 1310 : 1000,
            maxWidth: .infinity,
            minHeight: 750,
            maxHeight: .infinity
        )
        .coordinateSpace(name: "xynthRoot")
        .environment(vm.hoverHelp)
        .onContinuousHover { phase in
            if case .ended = phase {
                vm.hoverHelp.clear()
            }
        }
    }

    private var frontFaceplateView: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 10) {
                HeaderBarView(vm: vm)
                    .fixedSize(horizontal: false, vertical: true)

                // Recessed OP-1 × FM-1 Graphic OLED Telemetry Display
                WaveformScopeView(vm: vm)
                    .fixedSize(horizontal: false, vertical: true)

                // Centerpiece 1:1 Tactile Glass Fingerboard (fills exact remaining middle height)
                TrackpadSurfaceView(vm: vm)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                // OP-1 × FM-1 Encoders, Mode LED Keycaps, Timbres & 5-Voice Strip
                ControlDeckView(vm: vm)
                    .fixedSize(horizontal: false, vertical: true)

                // Minimal silkscreened chassis shortcut footer
                silkscreenFooter
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if vm.showExpansionBay {
                FerrofluidExpansionBayView(vm: vm)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.22), value: vm.showExpansionBay)
    }

    private var silkscreenFooter: some View {
        HStack(spacing: 10) {
            Text("SPC PLAY · 1–7 TIMBRE · [ ] OCT · S SCALE · M MAP · H SUB · A AUDIO · C THEME · V FERRO · ESC UNLOCK")
                .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                .tracking(0.4)
                .foregroundStyle(p.inkMuted.opacity(0.85))
                .lineLimit(1)
            Spacer(minLength: 6)
            Text(vm.audioMirrorEnabled
                 ? "MIRROR: \(vm.selectedAudioDeviceName.uppercased())"
                 : "XYNTH-1 // INSPIRED BY OS6/NOSPEAKER")
                .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                .foregroundStyle(vm.audioMirrorEnabled ? p.enc4 : p.inkMuted.opacity(0.8))
                .lineLimit(1)
        }
        .padding(.horizontal, 4)
    }

    @ViewBuilder
    private var chassisBackground: some View {
        ZStack {
            LinearGradient(
                colors: [p.chassisTop, p.chassisBottom],
                startPoint: .top,
                endPoint: .bottom
            )

            // Subtle top-to-bottom ambient theme radiance
            RadialGradient(
                colors: [p.chassisGlow, .clear],
                center: .top,
                startRadius: 20,
                endRadius: 560
            )

            // NEON CYBER: glowing magenta-to-cyan neon perimeter frame tube!
            if p.hasNeonTube {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [p.enc2, p.enc5, p.enc1],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 2.2
                    )
                    .shadow(color: p.enc2.opacity(0.65), radius: 12)
                    .padding(4)
            }

            // INCA GOLD: bold burnished 24k stepped Andean fretwork along top & bottom chassis rails
            if p.hasIncaTrim {
                Canvas { ctx, size in
                    let step: CGFloat = 22
                    var topFrieze = Path()
                    var botFrieze = Path()
                    var x: CGFloat = 26
                    while x < size.width - 26 {
                        topFrieze.move(to: CGPoint(x: x, y: 14))
                        topFrieze.addLine(to: CGPoint(x: x + 7, y: 14))
                        topFrieze.addLine(to: CGPoint(x: x + 7, y: 8))
                        topFrieze.addLine(to: CGPoint(x: x + 15, y: 8))
                        topFrieze.addLine(to: CGPoint(x: x + 15, y: 14))

                        let by = size.height - 6
                        botFrieze.move(to: CGPoint(x: x, y: by - 6))
                        botFrieze.addLine(to: CGPoint(x: x + 7, y: by - 6))
                        botFrieze.addLine(to: CGPoint(x: x + 7, y: by))
                        botFrieze.addLine(to: CGPoint(x: x + 15, y: by))
                        botFrieze.addLine(to: CGPoint(x: x + 15, y: by - 6))
                        x += step
                    }
                    ctx.stroke(topFrieze, with: .color(p.enc1.opacity(0.62)), lineWidth: 1.5)
                    ctx.stroke(botFrieze, with: .color(p.enc1.opacity(0.45)), lineWidth: 1.3)

                    // Turquoise inlay diamonds between frieze repeats
                    var dx: CGFloat = 37
                    while dx < size.width - 30 {
                        let d = Path { path in
                            path.move(to: CGPoint(x: dx, y: 11))
                            path.addLine(to: CGPoint(x: dx + 2.5, y: 13.5))
                            path.addLine(to: CGPoint(x: dx, y: 16))
                            path.addLine(to: CGPoint(x: dx - 2.5, y: 13.5))
                            path.closeSubpath()
                        }
                        ctx.fill(d, with: .color(p.enc2.opacity(0.65)))
                        dx += step * 2
                    }
                }
            }

            // ACID MODERN: brutalist electric chartreuse hazard diagonal ticks on top rail
            if p.hasHazardStripe {
                Canvas { ctx, size in
                    var ticks = Path()
                    var x: CGFloat = 90
                    while x < size.width - 28 {
                        ticks.move(to: CGPoint(x: x, y: 16))
                        ticks.addLine(to: CGPoint(x: x + 9, y: 6))
                        x += 18
                    }
                    ctx.stroke(ticks, with: .color(p.enc1.opacity(0.42)), lineWidth: 2.2)
                }
            }

            // 80s TECH & NEON CYBER: subtle crisp technical background grid
            if p.hasRetroGrid {
                Canvas { ctx, size in
                    let spacing: CGFloat = 24
                    var grid = Path()
                    var gx: CGFloat = spacing
                    while gx < size.width {
                        grid.move(to: CGPoint(x: gx, y: 0))
                        grid.addLine(to: CGPoint(x: gx, y: size.height))
                        gx += spacing
                    }
                    var gy: CGFloat = spacing
                    while gy < size.height {
                        grid.move(to: CGPoint(x: 0, y: gy))
                        grid.addLine(to: CGPoint(x: size.width, y: gy))
                        gy += spacing
                    }
                    ctx.stroke(
                        grid,
                        with: .color(p.isLightChassis ? Color.black.opacity(0.05) : p.enc2.opacity(0.11)),
                        lineWidth: 0.7
                    )
                }
            }

            // KOTO CLAY: warm woven ceramic speckle grain + persimmon hanko accent line
            if p.hasWashiGrain {
                Canvas { ctx, size in
                    var line = Path()
                    line.move(to: CGPoint(x: 84, y: 11))
                    line.addLine(to: CGPoint(x: size.width - 28, y: 11))
                    ctx.stroke(line, with: .color(p.enc1.opacity(0.55)), lineWidth: 2.0)
                }
            }
        }
    }

    private var cornerScrewsOverlay: some View {
        VStack {
            HStack {
                Spacer()
                ChassisScrewView(palette: p)
            }
            Spacer()
            HStack {
                ChassisScrewView(palette: p)
                Spacer()
                ChassisScrewView(palette: p)
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 6)
    }
}
