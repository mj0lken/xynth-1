import SwiftUI
import XynthCore

/// Iconic OP-1 × M-VAVE FM-1 recessed graphic OLED telemetry display:
/// 1) Digital pitch, cents, Hz, segmented VU meter, and 5-finger active LED bank (F1–F5)
/// 2) FM-1-style live harmonic operator/algorithm mini schematic
/// 3) Real-time composite glass oscilloscope
/// 4) Logarithmic motor spectrum (60 Hz – 4 kHz) showing Feel & Sweet Spot bands
struct WaveformScopeView: View {
    @Bindable var vm: SynthViewModel

    private var p: XynthPalette { vm.palette }

    var body: some View {
        HStack(spacing: 12) {
            // 1. Pitch / Volume digital readout + 5-finger active voice LED bank
            readoutAndFingerBank
                .frame(width: 224, alignment: .leading)

            oledDivider

            // 2. M-VAVE FM-1 inspired Operator / Harmonic Algorithm graphic
            algorithmSchematicBox
                .frame(width: 112)
                .xynthHelp(
                    "Harmonic Algorithm (\(vm.timbre.displayName))",
                    detail: "Visualizes how the current timbre stacks carrier & overtone sine partials (plus tactile sub-feel) onto the Force Touch motor."
                )

            oledDivider

            // 3. Real-time composite glass oscilloscope
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text("GLASS OSCILLOSCOPE")
                        .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                        .tracking(1.0)
                        .foregroundStyle(p.oledInkMuted)
                    Spacer()
                    Text(vm.snapshot.isSounding
                         ? String(format: "%.1f ms · %d PARTIAL%@",
                                  vm.snapshot.sliceDurationMs,
                                  vm.snapshot.outputTones.count,
                                  vm.snapshot.outputTones.count == 1 ? "" : "S")
                         : "STANDBY")
                        .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                        .monospacedDigit()
                        .foregroundStyle(vm.snapshot.isSounding ? p.enc1 : p.oledInkMuted)
                }

                Canvas { ctx, size in
                    drawOscilloscope(ctx: &ctx, size: size)
                }
                .frame(height: 62)
            }
            .xynthHelp(
                "Real-Time Glass Waveform",
                detail: "Plots the exact mathematical sum of sine waves vibrating the trackpad glass at this millisecond."
            )

            oledDivider

            // 4. Logarithmic motor spectrum (60 Hz – 4 kHz)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text("MOTOR SPECTRUM")
                        .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                        .tracking(1.0)
                        .foregroundStyle(p.oledInkMuted)
                    Spacer()
                    Text("\(vm.snapshot.actuationCount.formatted())")
                        .font(.system(size: 8.5, weight: .semibold, design: .monospaced))
                        .monospacedDigit()
                        .foregroundStyle(p.oledInkMuted)
                }

                Canvas { ctx, size in
                    drawSpectrum(ctx: &ctx, size: size)
                }
                .frame(height: 62)
            }
            .frame(width: 225)
            .xynthHelp(
                "Trackpad Motor Spectrum",
                detail: "Shows every active partial across 60 Hz–4 kHz. FEEL (110–250 Hz) maximizes fingertip vibration; SWEET (700–1600 Hz) is acoustically loudest."
            )
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(p.oledBg)
                if p.hasRetroGrid {
                    // Subtle vintage CRT scanlines on 80s Tech & Neon Cyber
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color.white.opacity(0.03), .clear, Color.white.opacity(0.02)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                }
            }
            .shadow(color: Color.black.opacity(p.isLightChassis ? 0.25 : 0.55), radius: 5, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(p.oledBorder, lineWidth: 1.5)
        )
    }

    private var oledDivider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.09))
            .frame(width: 1, height: 68)
    }

    // MARK: - Pitch Readout + 5-Finger LED Matrix

    private var readoutAndFingerBank: some View {
        let active = vm.snapshot.isSounding
        let note = vm.snapshot.primaryNote
        let hz = vm.snapshot.primaryHz
        let vol = vm.snapshot.effectiveLevel
        let activeFingerCount = vm.snapshot.activeVoices.count

        return HStack(spacing: 12) {
            // Vertical 12-segment LED peak meter
            VStack(spacing: 2) {
                ForEach((0..<12).reversed(), id: \.self) { seg in
                    let threshold = Double(seg + 1) / 12.0
                    let lit = active && vol >= (threshold - 0.04)
                    let segColor: Color = seg >= 10 ? p.ledAlert : (seg >= 7 ? p.enc2 : p.enc1)
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(lit ? segColor : Color.white.opacity(0.09))
                        .frame(width: 7, height: 4.5)
                        .shadow(color: lit ? segColor.opacity(0.6) : .clear, radius: 2)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(active ? note.name : "---")
                        .font(.system(size: 25, weight: .black, design: .monospaced))
                        .monospacedDigit()
                        .foregroundStyle(active ? p.oledInkPrimary : p.oledInkMuted.opacity(0.45))
                        .frame(minWidth: 52, alignment: .leading)

                    if active {
                        let sign = note.cents >= 0 ? "+" : ""
                        Text("\(sign)\(note.cents)¢")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .monospacedDigit()
                            .foregroundStyle(abs(note.cents) <= 8 ? p.ledGood : p.enc2)
                    }
                    Spacer(minLength: 2)
                    Text(active ? String(format: "%3d%%", Int((vol * 100).rounded())) : "  0%")
                        .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                        .monospacedDigit()
                        .foregroundStyle(active ? p.enc2 : p.oledInkMuted)
                }

                HStack(spacing: 8) {
                    Text(active ? String(format: "%6.1f Hz", hz) : "   0.0 Hz")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .monospacedDigit()
                        .foregroundStyle(active ? p.enc1 : p.oledInkMuted)
                    Spacer()
                    Text("\(vm.scale.displayName.uppercased())")
                        .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(p.oledInkMuted)
                        .lineLimit(1)
                }

                // 5-Finger Live Polyphony LED Strip (F1..F5)
                HStack(spacing: 5) {
                    ForEach(0..<5, id: \.self) { idx in
                        let enabledSlot = idx < vm.maxVoices
                        let fingerActive = idx < activeFingerCount
                        let dotColor = p.color(forVoiceIndex: idx)
                        HStack(spacing: 3) {
                            HardwareLEDPip(
                                isOn: fingerActive,
                                color: dotColor,
                                offColor: enabledSlot ? Color.white.opacity(0.16) : Color.white.opacity(0.05),
                                size: 5.5
                            )
                            Text("F\(idx + 1)")
                                .font(.system(size: 8, weight: fingerActive ? .black : .semibold, design: .monospaced))
                                .foregroundStyle(
                                    fingerActive ? dotColor : (enabledSlot ? p.oledInkMuted : p.oledInkMuted.opacity(0.35))
                                )
                        }
                    }
                }
                .padding(.top, 2)
                .xynthHelp(
                    "5-Finger Polyphony Bank (F1–F5)",
                    detail: "Lights up individually as up to 5 fingers touch your trackpad simultaneously. Adjust max voice limit with keys 1–5 in the Voices strip."
                )
            }
        }
    }

    // MARK: - M-VAVE FM-1 Inspired Harmonic Operator Block

    private var algorithmSchematicBox: some View {
        let active = vm.snapshot.isSounding
        let subActive = vm.subFeelAmount > 0.01

        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("ALG 0\(vm.timbre.shortcutIndex)")
                    .font(.system(size: 8.5, weight: .black, design: .monospaced))
                    .foregroundStyle(p.enc2)
                Spacer()
                Text(vm.timbre.shortName)
                    .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(p.oledInkPrimary)
            }

            // Operator mini-matrix (FM-1 homage)
            Canvas { ctx, size in
                let w = size.width
                let h = size.height
                let boxes: [(x: CGFloat, y: CGFloat, label: String, color: Color, lit: Bool)] = [
                    (w * 0.22, h * 0.28, "F1", p.enc1, active),
                    (w * 0.56, h * 0.28, "H2", p.enc4, active && vm.timbre != .pureSine),
                    (w * 0.86, h * 0.28, "H3", p.enc3, active && [.hollow, .brassSaw, .fifthOrgan, .glassBell, .vocalFormant].contains(vm.timbre)),
                    (w * 0.22, h * 0.76, "SB", p.enc2, active && subActive),
                    (w * 0.68, h * 0.76, "MT", p.ledGood, active)
                ]

                // Routing wires
                var wires = Path()
                wires.move(to: CGPoint(x: boxes[0].x, y: boxes[0].y + 8))
                wires.addLine(to: CGPoint(x: boxes[4].x, y: boxes[4].y - 8))
                wires.move(to: CGPoint(x: boxes[1].x, y: boxes[1].y + 8))
                wires.addLine(to: CGPoint(x: boxes[4].x, y: boxes[4].y - 8))
                wires.move(to: CGPoint(x: boxes[2].x, y: boxes[2].y + 8))
                wires.addLine(to: CGPoint(x: boxes[4].x, y: boxes[4].y - 8))
                wires.move(to: CGPoint(x: boxes[3].x + 11, y: boxes[3].y))
                wires.addLine(to: CGPoint(x: boxes[4].x - 13, y: boxes[4].y))

                ctx.stroke(
                    wires,
                    with: .color(active ? p.enc1.opacity(0.45) : Color.white.opacity(0.14)),
                    lineWidth: 1.0
                )

                for b in boxes {
                    let rect = CGRect(x: b.x - 11, y: b.y - 8, width: 22, height: 16)
                    let path = Path(roundedRect: rect, cornerRadius: 3)
                    ctx.fill(path, with: .color(b.lit ? b.color.opacity(0.26) : Color.white.opacity(0.05)))
                    ctx.stroke(path, with: .color(b.lit ? b.color : Color.white.opacity(0.20)), lineWidth: b.lit ? 1.2 : 0.8)
                    let lbl = Text(b.label)
                        .font(.system(size: 7.5, weight: .black, design: .monospaced))
                        .foregroundStyle(b.lit ? b.color : p.oledInkMuted)
                    ctx.draw(lbl, at: CGPoint(x: b.x, y: b.y))
                }
            }
            .frame(height: 58)
        }
    }

    // MARK: - Oscilloscope & Spectrum Canvases

    private func drawOscilloscope(ctx: inout GraphicsContext, size: CGSize) {
        let w = size.width
        let h = size.height
        let midY = h * 0.5

        // Subtle OLED reticle
        var axis = Path()
        axis.move(to: CGPoint(x: 0, y: midY))
        axis.addLine(to: CGPoint(x: w, y: midY))
        for q in [0.25, 0.5, 0.75] {
            axis.move(to: CGPoint(x: w * q, y: 4))
            axis.addLine(to: CGPoint(x: w * q, y: h - 4))
        }
        ctx.stroke(axis, with: .color(Color.white.opacity(0.08)), lineWidth: 0.7)

        let tones = vm.snapshot.outputTones
        let level = vm.snapshot.effectiveLevel
        guard vm.snapshot.isSounding, !tones.isEmpty, level > 0.005 else {
            var flat = Path()
            flat.move(to: CGPoint(x: 6, y: midY))
            flat.addLine(to: CGPoint(x: w - 6, y: midY))
            ctx.stroke(flat, with: .color(p.enc1.opacity(0.32)), lineWidth: 1.3)
            return
        }

        let windowSec = 0.016
        let phaseOffset = vm.frameClock * 0.85
        let samples = max(84, Int(w / 1.8))
        let maxAmpPx = (h * 0.42) * min(1.0, max(0.18, level))

        var wave = Path()
        for i in 0...samples {
            let u = Double(i) / Double(samples)
            let t = u * windowSec + phaseOffset
            var yVal = 0.0
            for tone in tones {
                yVal += tone.amp * sin(2.0 * .pi * tone.hz * t)
            }
            let edgeFade = sin(u * .pi)
            let tapered = yVal * (0.35 + 0.65 * pow(edgeFade, 0.35))
            let px = u * w
            let py = midY - tapered * maxAmpPx
            if i == 0 { wave.move(to: CGPoint(x: px, y: py)) }
            else { wave.addLine(to: CGPoint(x: px, y: py)) }
        }

        ctx.stroke(wave, with: .color(p.enc1.opacity(0.28)), lineWidth: 5.0)
        ctx.stroke(wave, with: .color(p.enc1), lineWidth: 1.8)
    }

    private func drawSpectrum(ctx: inout GraphicsContext, size: CGSize) {
        let w = size.width
        let h = size.height
        let minHz = 60.0
        let maxHz = 4000.0
        let logSpan = log(maxHz / minHz)

        func xForHz(_ hz: Double) -> CGFloat {
            let clamped = min(maxHz, max(minHz, hz))
            return CGFloat(log(clamped / minHz) / logSpan) * w
        }

        // Tactile Feel band (110–250 Hz)
        let tactileX0 = xForHz(110)
        let tactileX1 = xForHz(250)
        ctx.fill(
            Path(CGRect(x: tactileX0, y: 0, width: tactileX1 - tactileX0, height: h - 12)),
            with: .color(p.enc2.opacity(0.11))
        )

        // Acoustic Singing Sweet Spot (700–1600 Hz)
        let sweetX0 = xForHz(700)
        let sweetX1 = xForHz(1600)
        ctx.fill(
            Path(CGRect(x: sweetX0, y: 0, width: sweetX1 - sweetX0, height: h - 12)),
            with: .color(p.enc1.opacity(0.08))
        )

        for (hz, text) in [(100.0, "100"), (250.0, "250"), (1000.0, "1k"), (3500.0, "3.5k")] {
            let x = xForHz(hz)
            var tick = Path()
            tick.move(to: CGPoint(x: x, y: h - 11))
            tick.addLine(to: CGPoint(x: x, y: h))
            ctx.stroke(tick, with: .color(Color.white.opacity(0.14)), lineWidth: 0.7)
            let lbl = Text(text)
                .font(.system(size: 7.5, weight: .semibold, design: .monospaced))
                .foregroundStyle(p.oledInkMuted)
            ctx.draw(lbl, at: CGPoint(x: min(w - 13, max(13, x)), y: h - 6))
        }

        ctx.draw(
            Text("FEEL").font(.system(size: 7.5, weight: .black, design: .monospaced)).foregroundStyle(p.enc2.opacity(0.75)),
            at: CGPoint(x: (tactileX0 + tactileX1) * 0.5, y: 7)
        )
        ctx.draw(
            Text("SWEET").font(.system(size: 7.5, weight: .black, design: .monospaced)).foregroundStyle(p.enc1.opacity(0.75)),
            at: CGPoint(x: (sweetX0 + sweetX1) * 0.5, y: 7)
        )

        guard vm.snapshot.isSounding else { return }

        let level = vm.snapshot.effectiveLevel
        for tone in vm.snapshot.outputTones {
            let x = xForHz(tone.hz)
            let barH = max(5.0, CGFloat(tone.amp * level) * (h - 20))
            let isTactile = tone.hz < 260.0
            let barColor = isTactile ? p.enc2 : p.enc1
            let rect = CGRect(x: x - 2.5, y: h - 13 - barH, width: 5, height: barH)
            ctx.fill(Path(roundedRect: rect, cornerRadius: 2), with: .color(barColor))
            let glow = CGRect(x: x - 5, y: h - 13 - barH, width: 10, height: barH)
            ctx.fill(Path(roundedRect: glow, cornerRadius: 4), with: .color(barColor.opacity(0.24)))
        }
    }
}
