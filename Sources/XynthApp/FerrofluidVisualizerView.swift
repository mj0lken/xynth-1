import SwiftUI
import XynthCore

enum FerrofluidMode: String, CaseIterable, Identifiable {
    case spikes
    case orbit
    case cymatic

    var id: String { rawValue }

    var shortName: String {
        switch self {
        case .spikes: return "SPIKES"
        case .orbit: return "ORBIT"
        case .cymatic: return "CYMATIC"
        }
    }

    var description: String {
        switch self {
        case .spikes: return "Classic Rosensweig ferrofluid spikes erupting radially from harmonic partials."
        case .orbit: return "Multi-finger magnetic attractors pulling glossy droplets & liquid bridges for each finger."
        case .cymatic: return "Top-down Faraday standing-wave patterns resonating across a liquid-metal pool."
        }
    }
}

/// Real-time 60 fps spring-damped ferrofluid surface solver driven by live trackpad tones & voices.
@MainActor
final class FerrofluidPhysics {
    static let vertexCount = 96

    var radii: [Double] = Array(repeating: 1.0, count: FerrofluidPhysics.vertexCount)
    var velocities: [Double] = Array(repeating: 0.0, count: FerrofluidPhysics.vertexCount)
    var smoothedEnergy: Double = 0.0
    var smoothedBass: Double = 0.0
    var phase: Double = 0.0

    func step(
        snapshot: SynthSnapshot,
        magnetism: Double,
        viscosity: Double,
        dt: Double
    ) {
        let clampedDt = min(0.033, max(0.004, dt))
        let targetEnergy = snapshot.isSounding ? snapshot.effectiveLevel : 0.0
        smoothedEnergy += (targetEnergy - smoothedEnergy) * min(1.0, clampedDt * 14.0)

        // Extract low-frequency (tactile feel) energy for deep core swell
        let bassAmp = snapshot.outputTones
            .filter { $0.hz < 280.0 }
            .reduce(0.0) { $0 + $1.amp } * targetEnergy
        smoothedBass += (bassAmp - smoothedBass) * min(1.0, clampedDt * 10.0)

        let speedMult = 1.6 + smoothedEnergy * 5.2 + (snapshot.primaryHz > 0 ? log2(max(65.0, snapshot.primaryHz) / 65.0) * 0.8 : 0.0)
        phase += clampedDt * speedMult

        // Spring constants tuned by user viscosity knob (low viscosity = crisp needles, high = syrupy ooze)
        let stiffness = 130.0 - viscosity * 75.0
        let damping = 7.5 + viscosity * 11.0
        let magGain = 0.35 + magnetism * 1.15

        let tones = snapshot.outputTones
        let voices = snapshot.activeVoices
        let count = Self.vertexCount

        for i in 0..<count {
            let theta = (Double(i) / Double(count)) * 2.0 * .pi

            // Subtle organic idle magnetic shimmer so the fluid always feels alive
            var target = 1.0
                + 0.028 * sin(theta * 3.0 + phase * 0.65)
                + 0.018 * cos(theta * 5.0 - phase * 0.45)

            if smoothedEnergy > 0.004 {
                // Deep magnetic core expansion from bass & volume
                target += smoothedBass * 0.24 * magGain

                // Rosensweig harmonic spikes: each partial frequency excites a distinct angular mode!
                for (tIdx, tone) in tones.enumerated() {
                    let normPitch = max(0.0, min(1.0, log2(max(65.0, tone.hz) / 65.0) / 5.9))
                    let lobes = Double(5 + Int((normPitch * 14.0).rounded()))
                    let dir = tIdx % 2 == 0 ? 1.0 : -1.0
                    let wave = sin(theta * lobes + phase * (1.2 + normPitch * 2.4) * dir + Double(tIdx) * 1.1)
                    // Sharp rectified spike profile (magnetic crown tip!)
                    let spike = pow(max(0.0, wave), 2.35)
                    target += spike * tone.amp * smoothedEnergy * 0.56 * magGain
                }

                // Multi-finger directional magnetic pulls (up to 5 fingers!)
                for (vIdx, voice) in voices.enumerated() {
                    let fingerAngle = (voice.x - 0.5) * 2.2 * .pi + Double(vIdx) * 0.35
                    let angDist = cos(theta - fingerAngle)
                    let pull = pow(max(0.0, angDist), 5.0)
                    target += pull * voice.volume * 0.28 * magGain
                }
            }

            let disp = target - radii[i]
            let accel = disp * stiffness - velocities[i] * damping
            velocities[i] += accel * clampedDt
            radii[i] = max(0.58, min(1.95, radii[i] + velocities[i] * clampedDt))
        }
    }
}

/// Right-side expandable hardware module bay:
/// Houses the Liquid Magnetic (Ferrofluid) Visualizer, magnetic physics controls,
/// Vibrato LFO rate encoder, 1-click Tactile Patches, and live active partial telemetry.
struct FerrofluidExpansionBayView: View {
    @Bindable var vm: SynthViewModel

    private var p: XynthPalette { vm.palette }

    var body: some View {
        VStack(spacing: 10) {
            // Bay header strip
            HStack(spacing: 8) {
                HardwareLEDPip(
                    isOn: vm.snapshot.isSounding,
                    color: p.ferroRim,
                    offColor: p.enc1.opacity(0.45),
                    size: 6.5
                )
                Text("FERRO-1 // MAGNETIC BAY")
                    .font(.system(size: 10, weight: .black, design: .monospaced))
                    .tracking(1.1)
                    .foregroundStyle(p.inkPrimary)
                Spacer()
                Button {
                    vm.toggleExpansionBay()
                } label: {
                    Image(systemName: "sidebar.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(p.inkSecondary)
                        .padding(5)
                        .background(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(p.keycapBg)
                                .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(p.keycapBorder, lineWidth: 0.9))
                        )
                }
                .buttonStyle(HardwarePillButtonStyle(accent: p.ferroRim))
                .xynthHelp(
                    "Collapse Side Bay",
                    shortcut: "V",
                    detail: "Folds the right-side Ferrofluid visualizer & expansion rack back into the compact synth footprint."
                )
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .hardwareModule(p, cornerRadius: 12)

            // Main Recessed Liquid Magnetic Containment Chamber
            VStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .fill(p.oledBg)

                    Canvas { ctx, size in
                        switch vm.ferroMode {
                        case .spikes:
                            drawFerroSpikes(ctx: &ctx, size: size)
                        case .orbit:
                            drawFerroOrbit(ctx: &ctx, size: size)
                        case .cymatic:
                            drawFerroCymatic(ctx: &ctx, size: size)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))

                    // Subtle glass containment chamber telemetry HUD
                    VStack {
                        HStack {
                            Text("FIELD \(Int((vm.ferroPhysics.smoothedEnergy * vm.ferroMagnetism * 100).rounded())) mT")
                                .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                                .monospacedDigit()
                                .foregroundStyle(p.ferroRim.opacity(0.9))
                            Spacer()
                            Text(vm.ferroMode.shortName)
                                .font(.system(size: 8.5, weight: .black, design: .monospaced))
                                .foregroundStyle(p.oledInkMuted)
                        }
                        Spacer()
                        HStack {
                            Text(vm.snapshot.isSounding
                                 ? "\(vm.snapshot.primaryNote.name) · \(Int(vm.snapshot.primaryHz.rounded())) Hz"
                                 : "MAGNETIC IDLE")
                                .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                                .monospacedDigit()
                                .foregroundStyle(vm.snapshot.isSounding ? p.oledInkPrimary : p.oledInkMuted)
                            Spacer()
                            Text("\(vm.snapshot.activeVoices.count)/\(vm.maxVoices) FINGERS")
                                .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                                .foregroundStyle(p.ferroField)
                        }
                    }
                    .padding(10)
                    .allowsHitTesting(false)
                }
                .frame(height: 256)
                .overlay(
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .strokeBorder(
                            vm.snapshot.isSounding ? p.ferroRim.opacity(0.75) : p.oledBorder,
                            lineWidth: vm.snapshot.isSounding ? 1.6 : 1.3
                        )
                        .shadow(color: vm.snapshot.isSounding ? p.ferroRim.opacity(0.32) : .clear, radius: 10)
                )
                .xynthHelp(
                    "Liquid Magnetic Ferrofluid",
                    detail: "Real-time spring-damped ferrofluid simulation sculpted directly by your trackpad's active sine partials, bass sub-feel, and up to 5 finger positions."
                )

                // 3 Liquid Mode Selector Keycaps
                HStack(spacing: 6) {
                    ForEach(FerrofluidMode.allCases) { mode in
                        HardwareKeyButton(
                            title: mode.shortName,
                            isActive: vm.ferroMode == mode,
                            ledColor: p.ferroRim,
                            palette: p,
                            compact: true,
                            fullWidth: true
                        ) {
                            vm.ferroMode = mode
                        }
                        .xynthHelp(
                            "Ferro Mode: \(mode.shortName)",
                            detail: mode.description
                        )
                    }
                }
            }
            .padding(10)
            .hardwareModule(p, cornerRadius: 12)

            // Extra Modular Encoders: Magnetism, Viscosity & Vibrato LFO Rate
            VStack(alignment: .leading, spacing: 6) {
                Text("FLUID PHYSICS & LFO")
                    .font(.system(size: 8.5, weight: .black, design: .monospaced))
                    .tracking(0.9)
                    .foregroundStyle(p.inkMuted)

                HStack(spacing: 6) {
                    HardwareRotaryKnob(
                        label: "MAGNET",
                        valueText: "\(Int((vm.ferroMagnetism * 100).rounded()))%",
                        value: $vm.ferroMagnetism,
                        range: 0.1...1.5,
                        defaultValue: 0.85,
                        accent: p.ferroRim,
                        palette: p,
                        size: 46
                    )
                    .xynthHelp(
                        "Magnetic Field Strength",
                        detail: "Controls how dramatically sound partials pull spikes and liquid bridges inside the ferrofluid chamber."
                    )

                    HardwareRotaryKnob(
                        label: "VISCOS",
                        valueText: "\(Int((vm.ferroViscosity * 100).rounded()))%",
                        value: $vm.ferroViscosity,
                        range: 0.0...1.0,
                        defaultValue: 0.35,
                        accent: p.ferroField,
                        palette: p,
                        size: 46
                    )
                    .xynthHelp(
                        "Ferrofluid Viscosity",
                        detail: "Low = hyper-fast electric mercury needles; High = heavy, slow-oozing obsidian liquid."
                    )

                    HardwareRotaryKnob(
                        label: "LFO HZ",
                        valueText: String(format: "%.1fHz", vm.vibratoRateHz),
                        value: $vm.vibratoRateHz,
                        range: 2.0...10.0,
                        defaultValue: 5.4,
                        accent: p.enc5,
                        palette: p,
                        size: 46
                    )
                    .xynthHelp(
                        "Vibrato LFO Rate",
                        detail: "Adjusts the speed of pitch vibrato modulation from slow 2 Hz swells to fast 10 Hz shimmer."
                    )
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .hardwareModule(p, cornerRadius: 12)

            // 1-Click Tactile Sound Patches
            VStack(alignment: .leading, spacing: 6) {
                Text("QUICK TACTILE PATCHES")
                    .font(.system(size: 8.5, weight: .black, design: .monospaced))
                    .tracking(0.9)
                    .foregroundStyle(p.inkMuted)

                LazyVGrid(columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)], spacing: 6) {
                    patchButton("VELVET", led: p.enc1, active: vm.timbre == .warmOctave && vm.rangePreset == .balanced, help: "Warm octave lead in Balanced band with tactile sub-feel and silky glide.") {
                        vm.applyQuickPatch(.velvet)
                    }
                    patchButton("SUB BASS", led: p.enc2, active: vm.rangePreset == .subFeel && vm.timbre == .brassSaw, help: "Deep 65–392 Hz sawtooth rumble tuned for maximum physical buzz in your fingertips.") {
                        vm.applyQuickPatch(.subBass)
                    }
                    patchButton("THEREMIN", led: p.enc4, active: vm.scale == .free && vm.timbre == .pureSine, help: "Fretless pure glass sine wave with liquid glide and expressive vibrato.") {
                        vm.applyQuickPatch(.theremin)
                    }
                    patchButton("GLASS BELL", led: p.enc3, active: vm.timbre == .glassBell && vm.rangePreset == .acoustic, help: "Crystalline FM chimes in the trackpad's loudest 523–2093 Hz singing octave.") {
                        vm.applyQuickPatch(.glassChime)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .hardwareModule(p, cornerRadius: 12)

            // Live Harmonic Partial Inspector (recessed mini OLED)
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text("ACTIVE MOTOR PARTIALS")
                        .font(.system(size: 8.5, weight: .black, design: .monospaced))
                        .tracking(0.8)
                        .foregroundStyle(p.oledInkMuted)
                    Spacer()
                    Text("\(vm.snapshot.outputTones.count)/6 TONES")
                        .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(vm.snapshot.isSounding ? p.enc1 : p.oledInkMuted)
                }

                VStack(spacing: 4) {
                    ForEach(0..<6, id: \.self) { idx in
                        let tone = idx < vm.snapshot.outputTones.count ? vm.snapshot.outputTones[idx] : nil
                        let frac = tone.map { $0.amp * vm.snapshot.effectiveLevel } ?? 0.0
                        let barColor = (tone?.hz ?? 500) < 260 ? p.enc2 : p.color(forVoiceIndex: idx)
                        HStack(spacing: 6) {
                            Text("P\(idx + 1)")
                                .font(.system(size: 8, weight: .bold, design: .monospaced))
                                .foregroundStyle(tone != nil ? barColor : p.oledInkMuted.opacity(0.4))
                                .frame(width: 16, alignment: .leading)

                            GeometryReader { g in
                                ZStack(alignment: .leading) {
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(Color.white.opacity(0.07))
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(barColor)
                                        .frame(width: max(0, g.size.width * min(1.0, frac * 1.45)))
                                }
                            }
                            .frame(height: 6)

                            Text(tone.map { String(format: "%4.0f Hz", $0.hz) } ?? "   — Hz")
                                .font(.system(size: 8.5, weight: .semibold, design: .monospaced))
                                .monospacedDigit()
                                .foregroundStyle(tone != nil ? p.oledInkPrimary : p.oledInkMuted.opacity(0.4))
                                .frame(width: 48, alignment: .trailing)
                        }
                    }
                }
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(p.oledBg)
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(p.oledBorder, lineWidth: 1.2))
            )
            .xynthHelp(
                "Active Motor Partials (P1–P6)",
                detail: "Displays the exact frequencies and normalized amplitudes sent to the trackpad's Force Touch actuator in real time."
            )
        }
        .frame(width: 312)
    }

    private func patchButton(_ title: String, led: Color, active: Bool, help: String, action: @escaping () -> Void) -> some View {
        HardwareKeyButton(
            title: title,
            isActive: active,
            ledColor: led,
            palette: p,
            compact: true,
            fullWidth: true,
            action: action
        )
        .xynthHelp("Patch: \(title)", detail: help)
    }

    // MARK: - Mode 1: Rosensweig Liquid Magnetic Spikes

    private func drawFerroSpikes(ctx: inout GraphicsContext, size: CGSize) {
        let center = CGPoint(x: size.width * 0.5, y: size.height * 0.5)
        let baseR = min(size.width, size.height) * 0.255
        let energy = vm.ferroPhysics.smoothedEnergy
        let phase = vm.ferroPhysics.phase
        let radii = vm.ferroPhysics.radii
        let count = radii.count

        // 1. Magnetic containment field glow & concentric flux coils
        let fieldRadius = min(size.width, size.height) * (0.45 + energy * 0.14)
        let bgGlow = Gradient(colors: [
            p.ferroField.opacity(0.24 + energy * 0.25),
            p.ferroRim.opacity(0.09 + energy * 0.14),
            .clear
        ])
        ctx.fill(
            Path(ellipseIn: CGRect(x: center.x - fieldRadius, y: center.y - fieldRadius, width: fieldRadius * 2, height: fieldRadius * 2)),
            with: .radialGradient(bgGlow, center: center, startRadius: 8, endRadius: fieldRadius)
        )

        // Rotating dashed magnetic flux rings
        for ring in 1...3 {
            let r = baseR * (1.28 + Double(ring) * 0.24 + energy * 0.12)
            let rect = CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)
            ctx.stroke(
                Path(ellipseIn: rect),
                with: .color(p.ferroField.opacity(0.14 + energy * 0.16 - Double(ring) * 0.03)),
                style: StrokeStyle(lineWidth: 0.8, dash: [4, 6], dashPhase: CGFloat(phase * 14 * (ring % 2 == 0 ? 1 : -1)))
            )
        }

        // Build smooth closed Catmull/quadratic ferrofluid silhouette path
        let outerPath = smoothRadialBlobPath(center: center, baseRadius: baseR, radii: radii, scale: 1.0)
        let midPath = smoothRadialBlobPath(center: center, baseRadius: baseR * 0.84, radii: radii, scale: 0.86)
        let innerSpecularPath = smoothRadialBlobPath(
            center: CGPoint(x: center.x - baseR * 0.14, y: center.y - baseR * 0.16),
            baseRadius: baseR * 0.48,
            radii: radii,
            scale: 0.55
        )

        // 2. Outer iridescent magnetic aura bloom
        ctx.stroke(outerPath, with: .color(p.ferroRim.opacity(0.32 + energy * 0.45)), lineWidth: 7.5)

        // 3. Glossy dark ferrofluid obsidian/chrome body
        let bodyGrad = Gradient(colors: [
            p.ferroField.opacity(0.45),
            p.ferroCore,
            Color.black
        ])
        ctx.fill(
            outerPath,
            with: .radialGradient(
                bodyGrad,
                center: CGPoint(x: center.x - baseR * 0.25, y: center.y - baseR * 0.28),
                startRadius: 2,
                endRadius: baseR * 1.85
            )
        )

        // 4. Secondary liquid-metal contour ridge
        ctx.stroke(midPath, with: .color(p.ferroField.opacity(0.30 + energy * 0.35)), lineWidth: 1.4)

        // 5. Crisp Fresnel rim light along every magnetic spike tip
        ctx.stroke(outerPath, with: .color(p.ferroRim.opacity(0.75 + energy * 0.25)), lineWidth: 1.7)

        // 6. Specular liquid mercury highlight pool
        let specGrad = Gradient(colors: [
            p.ferroSpecular.opacity(0.58 + energy * 0.28),
            p.ferroRim.opacity(0.18),
            .clear
        ])
        ctx.fill(
            innerSpecularPath,
            with: .radialGradient(
                specGrad,
                center: CGPoint(x: center.x - baseR * 0.22, y: center.y - baseR * 0.24),
                startRadius: 1,
                endRadius: baseR * 0.72
            )
        )

        // 7. Tiny glistening magnetic droplets detaching at peak spike tips!
        if energy > 0.22 {
            for i in stride(from: 0, to: count, by: 6) {
                let rVal = radii[i]
                guard rVal > 1.28 else { continue }
                let theta = (Double(i) / Double(count)) * 2.0 * .pi
                let dist = baseR * (rVal + 0.14 + 0.08 * sin(phase * 3.0 + Double(i)))
                let dropPt = CGPoint(x: center.x + cos(theta) * dist, y: center.y + sin(theta) * dist)
                let dropR = CGFloat(2.0 + (rVal - 1.25) * 4.5)
                let rect = CGRect(x: dropPt.x - dropR, y: dropPt.y - dropR, width: dropR * 2, height: dropR * 2)
                ctx.fill(Path(ellipseIn: rect), with: .color(p.ferroCore))
                ctx.stroke(Path(ellipseIn: rect), with: .color(p.ferroSpecular.opacity(0.85)), lineWidth: 1.1)
            }
        }
    }

    // MARK: - Mode 2: 5-Finger Orbiting Magnetic Droplets & Bridges

    private func drawFerroOrbit(ctx: inout GraphicsContext, size: CGSize) {
        let center = CGPoint(x: size.width * 0.5, y: size.height * 0.5)
        let baseR = min(size.width, size.height) * 0.19
        let energy = vm.ferroPhysics.smoothedEnergy
        let phase = vm.ferroPhysics.phase

        // Ambient chamber field
        let glowR = min(size.width, size.height) * 0.48
        ctx.fill(
            Path(ellipseIn: CGRect(x: center.x - glowR, y: center.y - glowR, width: glowR * 2, height: glowR * 2)),
            with: .radialGradient(
                Gradient(colors: [p.ferroField.opacity(0.22 + energy * 0.24), .clear]),
                center: center,
                startRadius: 4,
                endRadius: glowR
            )
        )

        // Central liquid pool
        let corePath = smoothRadialBlobPath(center: center, baseRadius: baseR, radii: vm.ferroPhysics.radii, scale: 0.72)
        ctx.fill(corePath, with: .color(p.ferroCore))
        ctx.stroke(corePath, with: .color(p.ferroRim.opacity(0.85)), lineWidth: 1.8)

        let voices = vm.snapshot.activeVoices
        if voices.isEmpty {
            // Gentle idle orbiting mercury satellites
            for i in 0..<3 {
                let ang = phase * 0.7 + Double(i) * (2.0 * .pi / 3.0)
                let orbitR = baseR * 1.55
                let pt = CGPoint(x: center.x + cos(ang) * orbitR, y: center.y + sin(ang) * orbitR)
                drawLiquidBridge(ctx: &ctx, from: center, to: pt, color: p.ferroRim.opacity(0.45), thickness: 4)
                let r: CGFloat = 10
                ctx.fill(Path(ellipseIn: CGRect(x: pt.x - r, y: pt.y - r, width: r * 2, height: r * 2)), with: .color(p.ferroCore))
                ctx.stroke(Path(ellipseIn: CGRect(x: pt.x - r, y: pt.y - r, width: r * 2, height: r * 2)), with: .color(p.ferroRim.opacity(0.65)), lineWidth: 1.3)
            }
            return
        }

        // Draw magnetic liquid bridges + glossy orbiting nodes for all active fingers (F1–F5!)
        var nodePoints: [(pt: CGPoint, color: Color, r: CGFloat)] = []
        for (idx, voice) in voices.enumerated() {
            let color = p.color(forVoiceIndex: idx)
            let px = size.width * (0.14 + voice.x * 0.72)
            let py = size.height * (0.16 + (1.0 - voice.y) * 0.68)
            let wobbleX = cos(phase * 3.0 + Double(idx)) * 3.5 * voice.volume
            let wobbleY = sin(phase * 2.6 + Double(idx)) * 3.5 * voice.volume
            let pt = CGPoint(x: px + wobbleX, y: py + wobbleY)
            let r = CGFloat(11.0 + voice.volume * 14.0 * vm.ferroMagnetism)
            nodePoints.append((pt, color, r))

            drawLiquidBridge(ctx: &ctx, from: center, to: pt, color: color, thickness: CGFloat(5.0 + voice.volume * 7.0))
        }

        // Inter-finger magnetic filaments when playing chords
        if nodePoints.count > 1 {
            for i in 0..<(nodePoints.count - 1) {
                drawLiquidBridge(
                    ctx: &ctx,
                    from: nodePoints[i].pt,
                    to: nodePoints[i + 1].pt,
                    color: p.ferroRim.opacity(0.65),
                    thickness: 4.0
                )
            }
        }

        for (idx, item) in nodePoints.enumerated() {
            let rect = CGRect(x: item.pt.x - item.r, y: item.pt.y - item.r, width: item.r * 2, height: item.r * 2)
            ctx.fill(Path(ellipseIn: rect), with: .color(p.ferroCore))
            ctx.stroke(Path(ellipseIn: rect), with: .color(item.color), lineWidth: 2.0)

            let spec = CGRect(x: item.pt.x - item.r * 0.45, y: item.pt.y - item.r * 0.55, width: item.r * 0.55, height: item.r * 0.45)
            ctx.fill(Path(ellipseIn: spec), with: .color(p.ferroSpecular.opacity(0.65)))

            let lbl = Text("F\(idx + 1)")
                .font(.system(size: 8.5, weight: .black, design: .monospaced))
                .foregroundStyle(item.color)
            ctx.draw(lbl, at: item.pt)
        }
    }

    private func drawLiquidBridge(ctx: inout GraphicsContext, from a: CGPoint, to b: CGPoint, color: Color, thickness: CGFloat) {
        let mid = CGPoint(x: (a.x + b.x) * 0.5, y: (a.y + b.y) * 0.5)
        let dx = b.x - a.x
        let dy = b.y - a.y
        let len = max(1.0, hypot(dx, dy))
        let nx = -dy / len
        let ny = dx / len
        let neck = max(2.0, thickness * 0.35)

        var bridge = Path()
        bridge.move(to: CGPoint(x: a.x + nx * thickness, y: a.y + ny * thickness))
        bridge.addQuadCurve(
            to: CGPoint(x: b.x + nx * thickness * 0.7, y: b.y + ny * thickness * 0.7),
            control: CGPoint(x: mid.x + nx * neck, y: mid.y + ny * neck)
        )
        bridge.addLine(to: CGPoint(x: b.x - nx * thickness * 0.7, y: b.y - ny * thickness * 0.7))
        bridge.addQuadCurve(
            to: CGPoint(x: a.x - nx * thickness, y: a.y - ny * thickness),
            control: CGPoint(x: mid.x - nx * neck, y: mid.y - ny * neck)
        )
        bridge.closeSubpath()

        ctx.fill(bridge, with: .color(p.ferroCore.opacity(0.92)))
        ctx.stroke(bridge, with: .color(color.opacity(0.75)), lineWidth: 1.2)
    }

    // MARK: - Mode 3: Faraday / Cymatic Liquid Standing Waves

    private func drawFerroCymatic(ctx: inout GraphicsContext, size: CGSize) {
        let center = CGPoint(x: size.width * 0.5, y: size.height * 0.5)
        let maxR = min(size.width, size.height) * 0.42
        let energy = vm.ferroPhysics.smoothedEnergy
        let phase = vm.ferroPhysics.phase
        let tones = vm.snapshot.outputTones
        let rings = 8

        for ringIdx in 1...rings {
            let frac = Double(ringIdx) / Double(rings)
            let rBase = maxR * frac
            let lobes = tones.isEmpty
                ? Double(4 + ringIdx)
                : Double(4 + Int(log2(max(65.0, tones[ringIdx % tones.count].hz) / 65.0) * 2.8))
            let amp = (0.04 + energy * 0.14 * vm.ferroMagnetism) * (1.0 - frac * 0.35)

            var path = Path()
            let steps = 96
            for s in 0...steps {
                let theta = (Double(s) / Double(steps)) * 2.0 * .pi
                let mod = 1.0 + amp * sin(theta * lobes + phase * (ringIdx % 2 == 0 ? 1.3 : -1.1))
                let r = rBase * mod
                let pt = CGPoint(x: center.x + cos(theta) * r, y: center.y + sin(theta) * r)
                if s == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
            }
            path.closeSubpath()

            let ringColor = ringIdx % 2 == 0 ? p.ferroRim : p.ferroField
            let opacity = (0.22 + energy * 0.65) * (1.15 - frac * 0.65)
            ctx.stroke(path, with: .color(ringColor.opacity(opacity)), lineWidth: ringIdx == rings ? 1.8 : 1.2)
        }

        // Glossy specular center drop
        let coreR = CGFloat(10.0 + vm.ferroPhysics.smoothedBass * 18.0)
        let rect = CGRect(x: center.x - coreR, y: center.y - coreR, width: coreR * 2, height: coreR * 2)
        ctx.fill(Path(ellipseIn: rect), with: .color(p.ferroCore))
        ctx.stroke(Path(ellipseIn: rect), with: .color(p.ferroSpecular.opacity(0.85)), lineWidth: 1.5)
    }

    // MARK: - Smooth Radial Path Builder

    private func smoothRadialBlobPath(center: CGPoint, baseRadius: Double, radii: [Double], scale: Double) -> Path {
        let n = radii.count
        var pts: [CGPoint] = []
        pts.reserveCapacity(n)
        for i in 0..<n {
            let theta = (Double(i) / Double(n)) * 2.0 * .pi
            let r = baseRadius * (1.0 + (radii[i] - 1.0) * scale)
            pts.append(CGPoint(x: center.x + cos(theta) * r, y: center.y + sin(theta) * r))
        }
        var path = Path()
        guard n > 2 else { return path }
        let startMid = CGPoint(x: (pts[n - 1].x + pts[0].x) * 0.5, y: (pts[n - 1].y + pts[0].y) * 0.5)
        path.move(to: startMid)
        for i in 0..<n {
            let next = pts[(i + 1) % n]
            let mid = CGPoint(x: (pts[i].x + next.x) * 0.5, y: (pts[i].y + next.y) * 0.5)
            path.addQuadCurve(to: mid, control: pts[i])
        }
        path.closeSubpath()
        return path
    }
}
