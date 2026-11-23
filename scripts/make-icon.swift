import AppKit
import CoreGraphics
import Foundation

guard CommandLine.arguments.count >= 2 else {
    fputs("Usage: make-icon.swift <output-iconset-dir> [optional-preview-png-path]\n", stderr)
    exit(1)
}

let outDir = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

func cgColor(_ hex: UInt32, _ alpha: CGFloat = 1.0) -> CGColor {
    let r = CGFloat((hex >> 16) & 0xFF) / 255.0
    let g = CGFloat((hex >> 8) & 0xFF) / 255.0
    let b = CGFloat(hex & 0xFF) / 255.0
    return CGColor(colorSpace: CGColorSpaceCreateDeviceRGB(), components: [r, g, b, alpha])!
}

/// Builds a mathematically seamless closed continuous radial wave path around `center`.
func continuousRadialWavePath(
    center: CGPoint,
    baseRadius: CGFloat,
    amplitude: CGFloat,
    lobes: Double,
    phaseOffset: Double,
    samples: Int = 720
) -> CGPath {
    let path = CGMutablePath()
    var pts: [CGPoint] = []
    pts.reserveCapacity(samples)
    for i in 0..<samples {
        let theta = (Double(i) / Double(samples)) * 2.0 * .pi
        let r = baseRadius + amplitude * CGFloat(sin(theta * lobes + phaseOffset))
        pts.append(CGPoint(x: center.x + cos(theta) * r, y: center.y + sin(theta) * r))
    }
    let startMid = CGPoint(x: (pts[samples - 1].x + pts[0].x) * 0.5, y: (pts[samples - 1].y + pts[0].y) * 0.5)
    path.move(to: startMid)
    for i in 0..<samples {
        let next = pts[(i + 1) % samples]
        let mid = CGPoint(x: (pts[i].x + next.x) * 0.5, y: (pts[i].y + next.y) * 0.5)
        path.addQuadCurve(to: mid, control: pts[i])
    }
    path.closeSubpath()
    return path
}

/// Draws a flat-cut horizontal-terminal polygonal stroke (sharp modern synth chassis geometry).
func drawParallelogramStroke(ctx: CGContext, from a: CGPoint, to b: CGPoint, halfWidthX: CGFloat, color: CGColor) {
    let p = CGMutablePath()
    p.move(to: CGPoint(x: a.x - halfWidthX, y: a.y))
    p.addLine(to: CGPoint(x: a.x + halfWidthX, y: a.y))
    p.addLine(to: CGPoint(x: b.x + halfWidthX, y: b.y))
    p.addLine(to: CGPoint(x: b.x - halfWidthX, y: b.y))
    p.closeSubpath()
    ctx.setFillColor(color)
    ctx.addPath(p)
    ctx.fillPath()
}

/// Font 1 — Sharp Geometric flat-cut hardware "XY-1" (zero rounded caps, crisp charcoal + tangerine hyphen).
func drawSharpGeometricXY1(ctx: CGContext, center: CGPoint, unit: CGFloat) {
    let dark = cgColor(0x14171C)
    let orange = cgColor(0xFF5A1F)

    let halfH: CGFloat = 68 * unit
    let charHalfW: CGFloat = 46 * unit
    let hw: CGFloat = max(1.0, 13.0 * unit)

    // Optical horizontal layout centered dead-on around center.x:
    // Leftmost X edge = -172, Rightmost 1 edge = +172 (perfect symmetry!)
    let xc = center.x - 114 * unit
    let yc = center.x + 2 * unit
    let dashCenter = center.x + 84 * unit
    let oneX = center.x + 160 * unit

    // "X" (sharp flat horizontal top/bottom cuts)
    drawParallelogramStroke(ctx: ctx, from: CGPoint(x: xc - charHalfW, y: center.y + halfH), to: CGPoint(x: xc + charHalfW, y: center.y - halfH), halfWidthX: hw, color: dark)
    drawParallelogramStroke(ctx: ctx, from: CGPoint(x: xc + charHalfW, y: center.y + halfH), to: CGPoint(x: xc - charHalfW, y: center.y - halfH), halfWidthX: hw, color: dark)

    // "Y" (sharp flat top arms + rectangular stem)
    let junctionY = center.y - 6 * unit
    drawParallelogramStroke(ctx: ctx, from: CGPoint(x: yc - charHalfW, y: center.y + halfH), to: CGPoint(x: yc, y: junctionY), halfWidthX: hw, color: dark)
    drawParallelogramStroke(ctx: ctx, from: CGPoint(x: yc + charHalfW, y: center.y + halfH), to: CGPoint(x: yc, y: junctionY), halfWidthX: hw, color: dark)
    ctx.setFillColor(dark)
    ctx.fill(CGRect(x: yc - hw * 0.90, y: center.y - halfH, width: hw * 1.80, height: junctionY - (center.y - halfH) + 7 * unit))

    // Tangerine "-" hyphen (bold rectangular hardware dash)
    let dashW: CGFloat = 48 * unit
    let dashH: CGFloat = 20 * unit
    ctx.setFillColor(orange)
    ctx.fill(CGRect(x: dashCenter - dashW * 0.5, y: center.y - dashH * 0.5 - 2 * unit, width: dashW, height: dashH))

    // "1" (razor-sharp technical hardware "1": crisp vertical stem + clean chamfered upper-left flag)
    let stemW: CGFloat = hw * 1.84
    let stemLeft = oneX - stemW * 0.5
    ctx.setFillColor(dark)
    ctx.fill(CGRect(x: stemLeft, y: center.y - halfH, width: stemW, height: halfH * 2.0))

    // Clean angled geometric flag extending top-left from the "1" stem
    let flag = CGMutablePath()
    let topY = center.y + halfH
    flag.move(to: CGPoint(x: stemLeft + 2 * unit, y: topY))
    flag.addLine(to: CGPoint(x: stemLeft - 38 * unit, y: topY - 26 * unit))
    flag.addLine(to: CGPoint(x: stemLeft - 38 * unit, y: topY - 49 * unit))
    flag.addLine(to: CGPoint(x: stemLeft + 2 * unit, y: topY - 23 * unit))
    flag.closeSubpath()
    ctx.addPath(flag)
    ctx.fillPath()
}

func renderIcon(pixelSize: Int) -> Data? {
    let size = CGFloat(pixelSize)
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixelSize,
        pixelsHigh: pixelSize,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else { return nil }

    guard let ctx = NSGraphicsContext(bitmapImageRep: rep)?.cgContext else { return nil }
    ctx.setAllowsAntialiasing(true)
    ctx.setShouldAntialias(true)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)

    let rect = CGRect(x: 0, y: 0, width: size, height: size)
    let inset = size * 0.06
    let cardRect = rect.insetBy(dx: inset, dy: inset)
    let corner = size * 0.22
    let cardPath = CGPath(roundedRect: cardRect, cornerWidth: corner, cornerHeight: corner, transform: nil)
    let center = CGPoint(x: size * 0.5, y: size * 0.5)
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let unit = size / 1024.0

    ctx.saveGState()
    ctx.addPath(cardPath)
    ctx.clip()

    // Pure matte OP-1 anodized aluminum squircle (no circle, no top color strip)
    let bg = CGGradient(
        colorsSpace: colorSpace,
        colors: [cgColor(0xF5F6F2), cgColor(0xDCDFD8)] as CFArray,
        locations: [0.0, 1.0]
    )!
    ctx.drawLinearGradient(bg, start: CGPoint(x: 0, y: size), end: CGPoint(x: 0, y: 0), options: [])

    let wash = CGGradient(
        colorsSpace: colorSpace,
        colors: [cgColor(0xFFFFFF, 0.55), cgColor(0xFFFFFF, 0.0)] as CFArray,
        locations: [0.0, 1.0]
    )!
    ctx.drawRadialGradient(wash, startCenter: center, startRadius: 0, endCenter: center, endRadius: 440 * unit, options: [])

    // Widely expanded twin intertwined continuous waves
    let wavePrimary = continuousRadialWavePath(
        center: center,
        baseRadius: 318 * unit,
        amplitude: 70 * unit,
        lobes: 5,
        phaseOffset: 0.22
    )
    let waveSecondary = continuousRadialWavePath(
        center: center,
        baseRadius: 318 * unit,
        amplitude: 58 * unit,
        lobes: 5,
        phaseOffset: .pi + 0.22
    )

    // Companion harmonic wave
    ctx.saveGState()
    ctx.addPath(waveSecondary.copy(strokingWithWidth: max(1.2, 14 * unit), lineCap: .round, lineJoin: .round, miterLimit: 4))
    ctx.clip()
    let secGrad = CGGradient(
        colorsSpace: colorSpace,
        colors: [cgColor(0x2260FF, 0.42), cgColor(0x00B4DB, 0.36), cgColor(0xFF5A1F, 0.44)] as CFArray,
        locations: [0.0, 0.5, 1.0]
    )!
    ctx.drawLinearGradient(
        secGrad,
        start: CGPoint(x: center.x + 370 * unit, y: center.y + 370 * unit),
        end: CGPoint(x: center.x - 370 * unit, y: center.y - 370 * unit),
        options: []
    )
    ctx.restoreGState()

    // Soft ambient glow behind primary wave
    ctx.setStrokeColor(cgColor(0x00B4DB, 0.20))
    ctx.setLineWidth(max(2.0, 36 * unit))
    ctx.addPath(wavePrimary)
    ctx.strokePath()

    // Primary cyan -> cobalt -> tangerine wave
    ctx.saveGState()
    ctx.addPath(wavePrimary.copy(strokingWithWidth: max(1.8, 20 * unit), lineCap: .round, lineJoin: .round, miterLimit: 4))
    ctx.clip()
    let primGrad = CGGradient(
        colorsSpace: colorSpace,
        colors: [cgColor(0x00C6EE), cgColor(0x2260FF), cgColor(0xFF5A1F)] as CFArray,
        locations: [0.0, 0.52, 1.0]
    )!
    ctx.drawLinearGradient(
        primGrad,
        start: CGPoint(x: center.x - 380 * unit, y: center.y + 380 * unit),
        end: CGPoint(x: center.x + 380 * unit, y: center.y - 380 * unit),
        options: []
    )
    ctx.restoreGState()

    // Font 1 — Sharp Geometric XY-1
    drawSharpGeometricXY1(ctx: ctx, center: center, unit: unit)

    ctx.restoreGState()

    // Subtle machined outer squircle bevel
    ctx.setStrokeColor(cgColor(0x000000, 0.14))
    ctx.setLineWidth(max(1.0, 4.5 * unit))
    ctx.addPath(cardPath)
    ctx.strokePath()

    return rep.representation(using: .png, properties: [:])
}

let specs: [(name: String, px: Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024),
]

for spec in specs {
    if let data = renderIcon(pixelSize: spec.px) {
        try data.write(to: outDir.appendingPathComponent(spec.name))
        if spec.px == 1024, CommandLine.arguments.count >= 3 {
            let previewURL = URL(fileURLWithPath: CommandLine.arguments[2])
            try data.write(to: previewURL)
        }
    }
}
