import AppKit
import SwiftUI
import XynthCore

/// Recessed 1:1 tactile glass trackpad mirror supporting full 5-finger simultaneous play,
/// theme-matched scale fret grid, standing-wave acoustic ripples, comet trails, and resting touch capture.
struct TrackpadSurfaceView: View {
    @Bindable var vm: SynthViewModel

    private var p: XynthPalette { vm.palette }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Dark recessed glass playing surface
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [p.padBgTop, p.padBgBottom],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                // Live 60 fps synth & fingerboard canvas
                Canvas { ctx, size in
                    drawTrackpadCanvas(ctx: &ctx, size: size)
                }
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                // Interactive AppKit catcher (resting touches enabled for 5-finger stability!)
                PadEventCatcherView(
                    isPlayModeLocked: vm.isPlayModeLocked,
                    onVirtualTouch: { x, y, down in
                        vm.setVirtualTouch(x: x, y: y, down: down)
                    }
                )
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                // Top HUD overlay
                VStack {
                    topPadHUD
                    Spacer()
                    if !vm.snapshot.isSounding && !vm.isPlayModeLocked && vm.snapshot.rawTouches.isEmpty {
                        idlePromptOverlay
                        Spacer()
                    }
                }
                .padding(12)
                .allowsHitTesting(false)

                if !vm.snapshot.hardwareStatus.isReady {
                    hardwareMissingOverlay
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: vm.isPlayModeLocked ? 2.2 : 1.4)
                    .shadow(
                        color: vm.isPlayModeLocked
                            ? p.enc1.opacity(0.45)
                            : (vm.snapshot.isSounding ? p.enc1.opacity(0.24) : .clear),
                        radius: vm.isPlayModeLocked ? 14 : 8
                    )
            )
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .frame(minHeight: 205, idealHeight: 260, maxHeight: .infinity)
    }

    private var borderColor: Color {
        if !vm.snapshot.hardwareStatus.isReady { return p.ledAlert.opacity(0.65) }
        if vm.isPlayModeLocked { return p.enc1 }
        if vm.isOptionHeld { return p.enc4 }
        if vm.snapshot.isSounding { return p.enc1.opacity(0.55) }
        return p.oledBorder
    }

    private var topPadHUD: some View {
        HStack(spacing: 8) {
            if let demoLabel = vm.snapshot.demoLabel {
                hudChip(text: demoLabel, color: p.enc4, dot: true)
            } else if vm.isPlayModeLocked {
                hudChip(
                    text: "PLAY LOCKED · UP TO \(vm.maxVoices) FINGERS · GLIDE LIGHTLY · SPACE / ESC UNLOCKS",
                    color: p.enc1,
                    dot: true
                )
            } else if vm.isOptionHeld {
                hudChip(
                    text: "⌥ MOMENTARY TRACKPAD PLAY ACTIVE",
                    color: p.enc4,
                    dot: true
                )
            } else if vm.holdDrone {
                hudChip(
                    text: "HOLD / DRONE LATCHED · TOUCH OR SCRUB FADERS · TAB RELEASES",
                    color: p.enc2,
                    dot: true
                )
            } else if vm.alwaysSenseWhenFocused {
                hudChip(
                    text: "LIVE GLASS SENSING ON · SPACE LOCKS CURSOR",
                    color: p.ledGood,
                    dot: true
                )
            } else {
                hudChip(
                    text: "SPACE: LOCK CURSOR & PLAY · OR DRAG PAD / HOLD ⌥",
                    color: p.oledInkMuted,
                    dot: false
                )
            }

            Spacer()

            // Live 5-finger raw touch counter badge
            let rawCount = vm.snapshot.rawTouches.count
            let activeCount = vm.snapshot.activeVoices.count
            let shownCount = max(activeCount, rawCount)
            hudChip(
                text: "FINGERS \(shownCount)/\(vm.maxVoices)  ·  X→PITCH  Y→\(vm.mappingMode.yAxisLabel)",
                color: shownCount > 0 ? p.enc1 : p.oledInkMuted,
                dot: shownCount > 0
            )
        }
    }

    private func hudChip(text: String, color: Color, dot: Bool) -> some View {
        HStack(spacing: 5) {
            if dot {
                Circle()
                    .fill(color)
                    .frame(width: 5.5, height: 5.5)
                    .shadow(color: color.opacity(0.8), radius: 3)
            }
            Text(text)
                .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                .foregroundStyle(color)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 4.5)
        .background(
            Capsule()
                .fill(Color.black.opacity(0.62))
                .overlay(Capsule().strokeBorder(color.opacity(0.32), lineWidth: 1))
        )
    }

    private var idlePromptOverlay: some View {
        VStack(spacing: 6) {
            Text("PRESS SPACE TO PLAY UP TO 5 FINGERS ON YOUR TRACKPAD")
                .font(.system(size: 12, weight: .black, design: .monospaced))
                .tracking(1.1)
                .foregroundStyle(p.oledInkPrimary.opacity(0.82))
            Text(vm.mappingMode.hintText)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(p.oledInkMuted)
            Text("Tip: Glide lightly without clicking — feel every note vibrate directly in your fingertips.")
                .font(.system(size: 10))
                .foregroundStyle(p.oledInkMuted.opacity(0.75))
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.black.opacity(0.45))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(p.enc1.opacity(0.18), lineWidth: 1)
                )
        )
    }

    private var hardwareMissingOverlay: some View {
        VStack(spacing: 10) {
            Image(systemName: "hand.tap.fill")
                .font(.system(size: 26))
                .foregroundStyle(p.ledAlert)
            Text(vm.snapshot.hardwareStatus.shortLabel)
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundStyle(p.oledInkPrimary)
            Text(vm.snapshot.hardwareStatus.detailMessage)
                .font(.system(size: 11.5))
                .foregroundStyle(p.oledInkMuted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
            HardwareKeyButton(
                title: "RECONNECT TRACKPAD",
                isActive: false,
                ledColor: p.enc1,
                palette: p,
                compact: true
            ) {
                vm.reconnectTrackpad()
            }
        }
        .padding(22)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.black.opacity(0.86))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(p.ledAlert.opacity(0.55), lineWidth: 1.2)
                )
        )
    }

    // MARK: - 60 FPS Canvas Renderer

    private func drawTrackpadCanvas(ctx: inout GraphicsContext, size: CGSize) {
        let w = size.width
        let h = size.height
        let now = vm.frameClock
        let markers = vm.scaleMarkers

        // 1. Ambient standing-wave resonance wash under active voices (supports all 5 fingers!)
        for (idx, voice) in vm.snapshot.activeVoices.enumerated() {
            let pt = CGPoint(x: voice.x * w, y: (1.0 - voice.y) * h)
            let baseColor = p.color(forVoiceIndex: idx)
            let radius = max(w, h) * (0.20 + voice.volume * 0.30)
            let gradient = Gradient(colors: [
                baseColor.opacity(0.20 * voice.volume),
                baseColor.opacity(0.05 * voice.volume),
                .clear
            ])
            ctx.fill(
                Path(ellipseIn: CGRect(x: pt.x - radius, y: pt.y - radius, width: radius * 2, height: radius * 2)),
                with: .radialGradient(gradient, center: pt, startRadius: 6, endRadius: radius)
            )
        }

        // 2. Quantized scale fret cells or continuous Theremin guides
        if vm.scale != .free, !markers.isEmpty {
            let cellWidth = w / CGFloat(markers.count)
            for (idx, marker) in markers.enumerated() {
                let x0 = CGFloat(idx) * cellWidth
                let rect = CGRect(x: x0, y: 0, width: cellWidth, height: h)
                if marker.isRoot {
                    ctx.fill(Path(rect), with: .color(p.enc1.opacity(0.045)))
                } else if idx % 2 == 1 {
                    ctx.fill(Path(rect), with: .color(Color.white.opacity(0.015)))
                }

                var divider = Path()
                divider.move(to: CGPoint(x: x0, y: 0))
                divider.addLine(to: CGPoint(x: x0, y: h))
                ctx.stroke(
                    divider,
                    with: .color(marker.isRoot ? p.enc1.opacity(0.28) : Color.white.opacity(0.06)),
                    lineWidth: marker.isRoot ? 1.0 : 0.6
                )
            }
        } else {
            for marker in markers {
                let x = marker.normalizedX * w
                var line = Path()
                line.move(to: CGPoint(x: x, y: 0))
                line.addLine(to: CGPoint(x: x, y: h))
                ctx.stroke(
                    line,
                    with: .color(marker.isRoot ? p.enc1.opacity(0.28) : Color.white.opacity(0.08)),
                    style: StrokeStyle(lineWidth: marker.isRoot ? 1.0 : 0.7, dash: marker.isRoot ? [] : [4, 4])
                )
            }
        }

        // 3. Horizontal Y-axis calibration lines
        for step in [0.25, 0.50, 0.75] {
            let y = (1.0 - step) * h
            var hLine = Path()
            hLine.move(to: CGPoint(x: 0, y: y))
            hLine.addLine(to: CGPoint(x: w, y: y))
            ctx.stroke(
                hLine,
                with: .color(Color.white.opacity(step == 0.5 ? 0.09 : 0.045)),
                style: StrokeStyle(lineWidth: 0.7, dash: [3, 5])
            )

            let labelText = Text("\(Int(step * 100))%")
                .font(.system(size: 8.5, weight: .semibold, design: .monospaced))
                .foregroundStyle(p.oledInkMuted.opacity(0.8))
            ctx.draw(labelText, at: CGPoint(x: 22, y: y - 7))
        }

        // Bottom pitch labels
        let labelStride = max(1, Int(ceil(Double(markers.count) / max(1.0, Double(w / 44.0)))))
        for (idx, marker) in markers.enumerated() where marker.isRoot || idx % labelStride == 0 {
            let x = marker.normalizedX * w
            if x > 34 && x < w - 22 {
                let noteText = Text(marker.label)
                    .font(.system(size: marker.isRoot ? 9.5 : 8.5, weight: marker.isRoot ? .black : .medium, design: .monospaced))
                    .foregroundStyle(marker.isRoot ? p.enc1.opacity(0.85) : p.oledInkMuted.opacity(0.75))
                ctx.draw(noteText, at: CGPoint(x: x, y: h - 12))
            }
        }

        // 4. Ghost raw finger indicators when unlocked (mirrors all 5 fingers 1:1 on glass!)
        if !vm.isHardwareTouchArmed {
            for (idx, touch) in vm.snapshot.rawTouches.enumerated() {
                let pt = CGPoint(x: touch.x * w, y: (1.0 - touch.y) * h)
                let r = CGFloat(13.0 + min(20.0, touch.size * 13.0))
                let ghostColor = p.color(forVoiceIndex: idx)
                let circle = Path(ellipseIn: CGRect(x: pt.x - r, y: pt.y - r, width: r * 2, height: r * 2))
                ctx.stroke(circle, with: .color(ghostColor.opacity(0.35)), style: StrokeStyle(lineWidth: 1.2, dash: [4, 3]))
                let dot = Path(ellipseIn: CGRect(x: pt.x - 3, y: pt.y - 3, width: 6, height: 6))
                ctx.fill(dot, with: .color(ghostColor.opacity(0.65)))
            }
        }

        // 5. Luminous comet glide trails
        for (voiceIdx, voice) in vm.snapshot.activeVoices.enumerated() {
            let color = p.color(forVoiceIndex: voiceIdx)
            if let points = vm.trails[voice.id], points.count > 1 {
                for i in 1..<points.count {
                    let prev = points[i - 1]
                    let curr = points[i]
                    let age = now - curr.timestamp
                    let alpha = max(0.0, 1.0 - age / 0.55)
                    var seg = Path()
                    seg.move(to: CGPoint(x: prev.x * w, y: (1.0 - prev.y) * h))
                    seg.addLine(to: CGPoint(x: curr.x * w, y: (1.0 - curr.y) * h))
                    ctx.stroke(
                        seg,
                        with: .color(color.opacity(alpha * 0.65)),
                        style: StrokeStyle(lineWidth: CGFloat(1.5 + alpha * 3.8), lineCap: .round)
                    )
                }
            }
        }

        // 6. Active voice ripples, crosshairs, numbered fingertip nodes & telemetry pills
        for (idx, voice) in vm.snapshot.activeVoices.enumerated() {
            let color = p.color(forVoiceIndex: idx)
            let pt = CGPoint(x: voice.x * w, y: (1.0 - voice.y) * h)

            var vHair = Path()
            vHair.move(to: CGPoint(x: pt.x, y: 0))
            vHair.addLine(to: CGPoint(x: pt.x, y: h))
            ctx.stroke(vHair, with: .color(color.opacity(0.22)), lineWidth: 0.9)

            var hHair = Path()
            hHair.move(to: CGPoint(x: 0, y: pt.y))
            hHair.addLine(to: CGPoint(x: w, y: pt.y))
            ctx.stroke(hHair, with: .color(color.opacity(0.22)), lineWidth: 0.9)

            let waveSpeed = 1.4 + log2(max(65.0, voice.hz) / 65.0) * 0.7
            let maxRippleR = 32.0 + voice.volume * 72.0
            for ring in 0..<3 {
                let phase = (now * waveSpeed + Double(ring) / 3.0).truncatingRemainder(dividingBy: 1.0)
                let r = 13.0 + phase * maxRippleR
                let fade = (1.0 - phase) * (0.35 + voice.volume * 0.55)
                let ringRect = CGRect(x: pt.x - r, y: pt.y - r, width: r * 2, height: r * 2)
                ctx.stroke(
                    Path(ellipseIn: ringRect),
                    with: .color(color.opacity(fade)),
                    lineWidth: CGFloat(1.0 + (1.0 - phase) * 1.9)
                )
            }

            let coreR = CGFloat(11.0 + min(13.0, voice.size * 7.0) + voice.volume * 3.5)
            let halo = CGRect(x: pt.x - coreR * 1.45, y: pt.y - coreR * 1.45, width: coreR * 2.9, height: coreR * 2.9)
            ctx.fill(Path(ellipseIn: halo), with: .color(color.opacity(0.20)))

            let coreRect = CGRect(x: pt.x - coreR, y: pt.y - coreR, width: coreR * 2, height: coreR * 2)
            ctx.fill(Path(ellipseIn: coreRect), with: .color(color.opacity(0.92)))
            ctx.stroke(Path(ellipseIn: coreRect), with: .color(Color.white.opacity(0.88)), lineWidth: 1.5)

            // Finger index stamp inside node (`1`..`5`)
            let fLabel = Text("\(idx + 1)")
                .font(.system(size: 9.5, weight: .black, design: .monospaced))
                .foregroundStyle(Color.black.opacity(0.85))
            ctx.draw(fLabel, at: pt)

            if voice.isHeld {
                let holdR = coreR + 5.5
                let holdRect = CGRect(x: pt.x - holdR, y: pt.y - holdR, width: holdR * 2, height: holdR * 2)
                ctx.stroke(
                    Path(ellipseIn: holdRect),
                    with: .color(p.enc2),
                    style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])
                )
            }

            let hzStr = voice.hz >= 1000
                ? String(format: "%.2fk", voice.hz / 1000.0)
                : String(format: "%.0fHz", voice.hz)
            let volPct = Int((voice.volume * 100.0).rounded())
            let tagString = "F\(idx + 1) \(voice.note.name) · \(hzStr) · \(volPct)%"
            let tagText = Text(tagString)
                .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                .foregroundStyle(Color.white)

            let dx: CGFloat = pt.x > w - 165 ? -84 : 84
            let dy: CGFloat = pt.y < 50 ? 29 : -29
            let tagCenter = CGPoint(
                x: min(w - 82, max(82, pt.x + dx)),
                y: min(h - 24, max(40, pt.y + dy))
            )
            let pillRect = CGRect(x: tagCenter.x - 76, y: tagCenter.y - 10, width: 152, height: 20)
            let pillPath = Path(roundedRect: pillRect, cornerRadius: 5.5)
            ctx.fill(pillPath, with: .color(Color.black.opacity(0.78)))
            ctx.stroke(pillPath, with: .color(color.opacity(0.72)), lineWidth: 1)
            ctx.draw(tagText, at: tagCenter)
        }
    }
}

private struct PadEventCatcherView: NSViewRepresentable {
    var isPlayModeLocked: Bool
    var onVirtualTouch: (Double, Double, Bool) -> Void

    func makeNSView(context: Context) -> PadMouseNSView {
        let view = PadMouseNSView()
        view.allowedTouchTypes = [.indirect]
        view.wantsRestingTouches = true
        view.isPlayModeLocked = isPlayModeLocked
        view.onVirtualTouch = onVirtualTouch
        return view
    }

    func updateNSView(_ nsView: PadMouseNSView, context: Context) {
        nsView.isPlayModeLocked = isPlayModeLocked
        nsView.onVirtualTouch = onVirtualTouch
    }
}

private final class PadMouseNSView: NSView {
    var isPlayModeLocked: Bool = false
    var onVirtualTouch: ((Double, Double, Bool) -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        guard !isPlayModeLocked else { return }
        emit(event: event, down: true)
    }

    override func mouseDragged(with event: NSEvent) {
        guard !isPlayModeLocked else { return }
        emit(event: event, down: true)
    }

    override func mouseUp(with event: NSEvent) {
        guard !isPlayModeLocked else { return }
        emit(event: event, down: false)
    }

    override func pressureChange(with event: NSEvent) {
        // Absorb Force Touch pressure changes so macOS never triggers Look Up popups while playing
    }

    private func emit(event: NSEvent, down: Bool) {
        let loc = convert(event.locationInWindow, from: nil)
        let w = max(1.0, bounds.width)
        let h = max(1.0, bounds.height)
        let x = min(1.0, max(0.0, Double(loc.x / w)))
        let y = min(1.0, max(0.0, Double(loc.y / h)))
        onVirtualTouch?(x, y, down)
    }
}
