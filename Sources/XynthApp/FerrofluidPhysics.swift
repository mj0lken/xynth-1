import Foundation
import XynthCore

/// Visual physics presets for the expandable Ferrofluid Magnetic Bay.
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
