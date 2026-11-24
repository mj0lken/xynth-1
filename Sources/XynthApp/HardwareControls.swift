import AppKit
import SwiftUI

/// Illuminated physical LED pip with optional hover "warm wake" pre-glow.
struct HardwareLEDPip: View {
    let isOn: Bool
    let color: Color
    let offColor: Color
    var size: CGFloat = 6.5
    var isHovered: Bool = false

    var body: some View {
        ZStack {
            if isOn || isHovered {
                Circle()
                    .fill(color.opacity(isOn ? 0.58 : 0.34))
                    .frame(width: size * (isOn ? 2.4 : 2.0), height: size * (isOn ? 2.4 : 2.0))
                    .blur(radius: isOn ? 2.8 : 2.0)
            }
            Circle()
                .fill(isOn ? color : (isHovered ? color.opacity(0.42) : offColor))
                .frame(width: size, height: size)
                .overlay(
                    Circle()
                        .fill(Color.white.opacity(isOn ? 0.65 : (isHovered ? 0.32 : 0.14)))
                        .frame(width: size * 0.36, height: size * 0.36)
                        .offset(x: -size * 0.14, y: -size * 0.14)
                )
                .overlay(
                    Circle()
                        .strokeBorder(Color.black.opacity(0.35), lineWidth: 0.6)
                )
        }
        .frame(width: size * 1.4, height: size * 1.4)
        .animation(.easeOut(duration: 0.15), value: isOn)
        .animation(.easeOut(duration: 0.15), value: isHovered)
    }
}

/// Reusable tactile spring hover button style for compact pills, utility chips, and icon actions.
struct HardwarePillButtonStyle: ButtonStyle {
    var accent: Color
    var isActive: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        HardwarePillButtonBody(
            configuration: configuration,
            accent: accent,
            isActive: isActive
        )
    }
}

private struct HardwarePillButtonBody: View {
    let configuration: ButtonStyle.Configuration
    let accent: Color
    let isActive: Bool
    @State private var isHovered = false

    var body: some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.965 : (isHovered ? 1.028 : 1.0))
            .offset(y: configuration.isPressed ? 0.9 : (isHovered ? -0.8 : 0))
            .brightness(isHovered && !configuration.isPressed ? 0.04 : 0)
            .shadow(
                color: isHovered ? accent.opacity(isActive ? 0.42 : 0.28) : .clear,
                radius: isHovered ? 7 : 0,
                y: isHovered ? 2 : 0
            )
            .animation(.spring(response: 0.22, dampingFraction: 0.72), value: isHovered)
            .animation(.spring(response: 0.14, dampingFraction: 0.80), value: configuration.isPressed)
            .onHover { hovering in
                isHovered = hovering
            }
    }
}

/// Tactile press + spring hover button style used for all hardware keycaps across XYNTH-1.
private struct KeycapPressStyle: ButtonStyle {
    let isActive: Bool
    let ledColor: Color
    let palette: XynthPalette
    let isHovered: Bool

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        configuration.label
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(
                            isActive
                                ? palette.keycapActiveBg
                                : (pressed ? palette.keycapPressedBg : palette.keycapBg)
                        )

                    // Luminous tinted glass wash on hover
                    if isHovered && !pressed {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(ledColor.opacity(isActive ? 0.12 : 0.09))
                    }

                    // Subtle metallic chamfer + reactive hover border
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    (isActive || isHovered)
                                        ? ledColor.opacity(isActive ? 0.92 : 0.72)
                                        : Color.white.opacity(palette.isLightChassis ? 0.55 : 0.18),
                                    isActive
                                        ? ledColor.opacity(0.48)
                                        : (isHovered ? ledColor.opacity(0.40) : palette.keycapBorder)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: (isActive || isHovered) ? 1.35 : 1.0
                        )
                }
                .shadow(
                    color: (isActive || isHovered)
                        ? ledColor.opacity(isActive ? (isHovered ? 0.48 : 0.32) : 0.26)
                        : palette.keycapShadow,
                    radius: isHovered ? 8 : (isActive ? 6 : 2),
                    y: pressed ? 0.4 : (isHovered ? 2.4 : 1.5)
                )
            )
            .scaleEffect(pressed ? 0.965 : (isHovered ? 1.024 : 1.0))
            .offset(y: pressed ? 1.0 : (isHovered ? -1.0 : 0))
            .animation(.spring(response: 0.20, dampingFraction: 0.70), value: isHovered)
            .animation(.spring(response: 0.12, dampingFraction: 0.80), value: pressed)
    }
}

/// Sculpted square/pill synth keycap inspired by OP-1 & M-VAVE FM-1 push-buttons,
/// featuring a recessed top LED indicator, bevel shadow, spring hover lift, LED pre-glow, and crisp click press.
struct HardwareKeyButton: View {
    let title: String
    var subtitle: String? = nil
    var shortcut: String? = nil
    let isActive: Bool
    let ledColor: Color
    let palette: XynthPalette
    var compact: Bool = false
    var fullWidth: Bool = false
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: compact ? 3 : 4) {
                HStack(spacing: 5) {
                    HardwareLEDPip(
                        isOn: isActive,
                        color: ledColor,
                        offColor: palette.ledOff,
                        size: compact ? 5.5 : 6.5,
                        isHovered: isHovered
                    )
                    if let shortcut, !shortcut.isEmpty {
                        if fullWidth {
                            Spacer(minLength: 2)
                        }
                        Text(shortcut)
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .foregroundStyle((isActive || isHovered) ? ledColor : palette.keycapMutedInk)
                    }
                }

                HStack(spacing: 4) {
                    Text(title)
                        .font(.system(size: compact ? 9.5 : 10.5, weight: isActive ? .black : .bold, design: .monospaced))
                        .tracking(0.5)
                        .foregroundStyle(isActive ? palette.keycapActiveInk : palette.keycapInk)
                        .lineLimit(1)
                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 8.5, weight: .semibold, design: .monospaced))
                            .foregroundStyle((isActive || isHovered) ? ledColor : palette.keycapMutedInk)
                    }
                }
            }
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .padding(.horizontal, compact ? 8 : 11)
            .padding(.vertical, compact ? 6 : 7)
            .fixedSize(horizontal: !fullWidth, vertical: true)
        }
        .buttonStyle(
            KeycapPressStyle(
                isActive: isActive,
                ledColor: ledColor,
                palette: palette,
                isHovered: isHovered
            )
        )
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

/// 100% custom theme-matched hardware dropdown selector with lively hover states on trigger and rows.
struct HardwareDropdownOption<ID: Hashable>: Identifiable {
    let id: ID
    let label: String
    var detail: String? = nil
}

struct HardwareDropdown<Selection: Hashable>: View {
    let selection: Selection
    let options: [HardwareDropdownOption<Selection>]
    let palette: XynthPalette
    let accent: Color
    var width: CGFloat? = nil
    var columns: Int = 1
    let onSelect: (Selection) -> Void

    @State private var isOpen = false
    @State private var isTriggerHovered = false

    private var currentLabel: String {
        options.first(where: { $0.id == selection })?.label ?? "—"
    }

    var body: some View {
        Button {
            isOpen.toggle()
        } label: {
            HStack(spacing: 6) {
                HardwareLEDPip(
                    isOn: isOpen,
                    color: accent,
                    offColor: accent.opacity(0.52),
                    size: 5,
                    isHovered: isTriggerHovered
                )
                Text(currentLabel.uppercased())
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(isOpen ? palette.keycapActiveInk : palette.keycapInk)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 4)
                Image(systemName: isOpen ? "chevron.up" : "chevron.down")
                    .font(.system(size: 8.5, weight: .black))
                    .foregroundStyle(accent)
                    .offset(y: isTriggerHovered && !isOpen ? 1.0 : 0)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 6.5)
            .frame(width: width)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(isOpen ? palette.keycapActiveBg : palette.keycapBg)
                    if isTriggerHovered && !isOpen {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(accent.opacity(0.09))
                    }
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(
                            (isOpen || isTriggerHovered) ? accent.opacity(isOpen ? 0.95 : 0.70) : palette.keycapBorder,
                            lineWidth: (isOpen || isTriggerHovered) ? 1.25 : 1
                        )
                )
                .shadow(
                    color: (isOpen || isTriggerHovered) ? accent.opacity(0.30) : palette.keycapShadow,
                    radius: (isOpen || isTriggerHovered) ? 7 : 1.5,
                    y: isTriggerHovered ? 2 : 1
                )
            )
            .scaleEffect(isTriggerHovered ? 1.02 : 1.0)
            .offset(y: isTriggerHovered ? -0.8 : 0)
            .animation(.spring(response: 0.20, dampingFraction: 0.72), value: isTriggerHovered)
            .animation(.easeOut(duration: 0.14), value: isOpen)
        }
        .buttonStyle(.plain)
        .onHover { isTriggerHovered = $0 }
        .popover(isPresented: $isOpen, arrowEdge: .bottom) {
            dropdownMenuContent
        }
    }

    @ViewBuilder
    private var dropdownMenuContent: some View {
        let gridCols = Array(repeating: GridItem(.flexible(), spacing: 5), count: max(1, columns))
        VStack(alignment: .leading, spacing: 5) {
            if columns > 1 {
                LazyVGrid(columns: gridCols, spacing: 5) {
                    ForEach(options) { opt in
                        DropdownOptionRow(
                            opt: opt,
                            selected: opt.id == selection,
                            palette: palette,
                            accent: accent
                        ) {
                            onSelect(opt.id)
                            isOpen = false
                        }
                    }
                }
            } else {
                VStack(spacing: 3) {
                    ForEach(options) { opt in
                        DropdownOptionRow(
                            opt: opt,
                            selected: opt.id == selection,
                            palette: palette,
                            accent: accent
                        ) {
                            onSelect(opt.id)
                            isOpen = false
                        }
                    }
                }
            }
        }
        .padding(8)
        .frame(width: columns > 1 ? 188 : max(176, (width ?? 140) + 34))
        .xynthPopoverSurface(palette)
    }
}

extension View {
    /// Unified hardware popover container styling shared by custom dropdowns and header utility popovers.
    func xynthPopoverSurface(_ palette: XynthPalette, borderColor: Color? = nil) -> some View {
        self
            .background(palette.dropdownBg)
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(borderColor ?? palette.dropdownBorder, lineWidth: 1.1)
                    .padding(1)
            )
            .preferredColorScheme(.dark)
    }
}

private struct DropdownOptionRow<Selection: Hashable>: View {
    let opt: HardwareDropdownOption<Selection>
    let selected: Bool
    let palette: XynthPalette
    let accent: Color
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                HardwareLEDPip(
                    isOn: selected,
                    color: accent,
                    offColor: Color.white.opacity(0.16),
                    size: 5,
                    isHovered: isHovered
                )
                VStack(alignment: .leading, spacing: 1) {
                    Text(opt.label.uppercased())
                        .font(.system(size: 10, weight: (selected || isHovered) ? .black : .semibold, design: .monospaced))
                        .foregroundStyle((selected || isHovered) ? palette.oledInkPrimary : Color.white.opacity(0.76))
                        .lineLimit(1)
                    if let detail = opt.detail {
                        Text(detail)
                            .font(.system(size: 8.5, design: .monospaced))
                            .foregroundStyle(Color.white.opacity(0.45))
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 2)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5.5)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(selected ? accent.opacity(0.24) : (isHovered ? accent.opacity(0.12) : Color.white.opacity(0.03)))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(
                                selected ? accent.opacity(0.80) : (isHovered ? accent.opacity(0.45) : Color.clear),
                                lineWidth: 1
                            )
                    )
            )
            .offset(x: isHovered && !selected ? 2.0 : 0)
            .animation(.spring(response: 0.18, dampingFraction: 0.76), value: isHovered)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

/// OP-1 × M-VAVE FM-1 color-coded rotary encoder knob with precision radial calibration ticks,
/// responsive hover halo + cap zoom, drag/scroll turning, and double-click reset.
struct HardwareRotaryKnob: View {
    let label: String
    let valueText: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let defaultValue: Double
    let accent: Color
    let palette: XynthPalette
    var isOn: Bool = true
    var size: CGFloat = 54

    @State private var dragStartValue: Double? = nil
    @State private var isHovered = false

    private var isEngaged: Bool { isHovered || dragStartValue != nil }

    private var normalized: Double {
        let span = max(0.0001, range.upperBound - range.lowerBound)
        return min(1.0, max(0.0, (value - range.lowerBound) / span))
    }

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                HardwareLEDPip(
                    isOn: isOn && normalized > 0.01,
                    color: accent,
                    offColor: palette.ledOff,
                    size: 5,
                    isHovered: isEngaged
                )
                Text(label)
                    .font(.system(size: 8.5, weight: .black, design: .monospaced))
                    .tracking(0.8)
                    .foregroundStyle(isEngaged ? palette.inkPrimary : palette.inkSecondary)
            }

            ZStack {
                // Soft magnetic hover aura ring behind dial
                Circle()
                    .fill(accent.opacity(isEngaged ? 0.16 : 0.0))
                    .frame(width: size + 8, height: size + 8)
                    .blur(radius: 5)

                // 11 machined radial index ticks around perimeter
                Canvas { ctx, sz in
                    let c = CGPoint(x: sz.width * 0.5, y: sz.height * 0.5)
                    let outerR = sz.width * 0.49
                    let innerR = sz.width * 0.43
                    for i in 0...10 {
                        let frac = Double(i) / 10.0
                        let deg = 135.0 + frac * 270.0
                        let rad = deg * .pi / 180.0
                        var tick = Path()
                        tick.move(to: CGPoint(x: c.x + cos(rad) * innerR, y: c.y + sin(rad) * innerR))
                        tick.addLine(to: CGPoint(x: c.x + cos(rad) * outerR, y: c.y + sin(rad) * outerR))
                        let lit = frac <= normalized + 0.02 && isOn
                        ctx.stroke(
                            tick,
                            with: .color(lit ? accent.opacity(isEngaged ? 1.0 : 0.88) : palette.inkMuted.opacity(isEngaged ? 0.65 : 0.38)),
                            lineWidth: (i == 0 || i == 5 || i == 10) ? 1.4 : 0.9
                        )
                    }
                }
                .frame(width: size + 6, height: size + 6)

                // Background radial LED track
                Circle()
                    .trim(from: 0.0, to: 0.75)
                    .stroke(palette.ledOff.opacity(0.40), style: StrokeStyle(lineWidth: 3.0, lineCap: .round))
                    .rotationEffect(.degrees(135))
                    .frame(width: size - 4, height: size - 4)

                // Active luminous LED arc
                Circle()
                    .trim(from: 0.0, to: max(0.01, normalized * 0.75))
                    .stroke(accent, style: StrokeStyle(lineWidth: isEngaged ? 3.8 : 3.2, lineCap: .round))
                    .shadow(color: accent.opacity(isEngaged ? 0.85 : 0.58), radius: isEngaged ? 6 : 3.5)
                    .rotationEffect(.degrees(135))
                    .frame(width: size - 4, height: size - 4)

                // Deep recessed well
                Circle()
                    .fill(Color.black.opacity(palette.isLightChassis ? 0.22 : 0.58))
                    .frame(width: size - 13, height: size - 13)

                // Machined color-coded OP-1 style cap with spring hover zoom
                let capSize = size - 19
                ZStack {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    accent.opacity(1.0),
                                    accent.opacity(0.70)
                                ],
                                center: .topLeading,
                                startRadius: 1,
                                endRadius: capSize * 0.72
                            )
                        )
                        .frame(width: capSize, height: capSize)
                        .overlay(
                            Circle()
                                .strokeBorder(
                                    LinearGradient(
                                        colors: [Color.white.opacity(isEngaged ? 0.78 : 0.52), Color.black.opacity(0.35)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: isEngaged ? 1.5 : 1.2
                                )
                        )
                        .shadow(color: isEngaged ? accent.opacity(0.42) : Color.black.opacity(0.40), radius: isEngaged ? 6 : 3.5, y: 2)

                    Circle()
                        .strokeBorder(Color.white.opacity(0.24), lineWidth: 0.7)
                        .frame(width: capSize * 0.56, height: capSize * 0.56)

                    Circle()
                        .fill(Color.black.opacity(0.16))
                        .frame(width: capSize * 0.44, height: capSize * 0.44)

                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(Color.white)
                        .frame(width: 2.8, height: capSize * 0.30)
                        .offset(y: -capSize * 0.31)
                        .shadow(color: Color.black.opacity(0.55), radius: 1)
                }
                .scaleEffect(dragStartValue != nil ? 1.07 : (isHovered ? 1.045 : 1.0))
                .rotationEffect(.degrees(-135 + normalized * 270))

                ScrollWheelCatcher { deltaY in
                    let span = range.upperBound - range.lowerBound
                    let step = deltaY * 0.0045 * span
                    value = min(range.upperBound, max(range.lowerBound, value + step))
                }
                .frame(width: size + 4, height: size + 4)
            }
            .frame(width: size + 6, height: size + 6)
            .contentShape(Circle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        if dragStartValue == nil { dragStartValue = value }
                        let start = dragStartValue ?? value
                        let span = range.upperBound - range.lowerBound
                        let delta = (-drag.translation.height + drag.translation.width * 0.45) / 115.0
                        value = min(range.upperBound, max(range.lowerBound, start + delta * span))
                    }
                    .onEnded { _ in dragStartValue = nil }
            )
            .onTapGesture(count: 2) {
                value = defaultValue
            }

            Text(valueText)
                .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(isEngaged ? accent : palette.inkPrimary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(isEngaged ? accent.opacity(0.14) : (palette.isLightChassis ? Color.black.opacity(0.07) : Color.white.opacity(0.07)))
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .strokeBorder(isEngaged ? accent.opacity(0.45) : Color.clear, lineWidth: 0.8)
                        )
                )
        }
        .frame(maxWidth: .infinity)
        .onHover { isHovered = $0 }
        .animation(.spring(response: 0.22, dampingFraction: 0.70), value: isHovered)
        .animation(.spring(response: 0.16, dampingFraction: 0.75), value: dragStartValue != nil)
    }
}

/// Subtle machined hex fastener screw for authentic hardware synth chassis corners.
struct ChassisScrewView: View {
    let palette: XynthPalette

    var body: some View {
        ZStack {
            Circle()
                .fill(palette.isLightChassis ? Color.black.opacity(0.16) : Color.white.opacity(0.14))
                .frame(width: 8.5, height: 8.5)
            Circle()
                .fill(palette.isLightChassis ? Color.black.opacity(0.09) : Color.black.opacity(0.60))
                .frame(width: 5.5, height: 5.5)
            Rectangle()
                .fill(palette.isLightChassis ? Color.white.opacity(0.50) : Color.white.opacity(0.24))
                .frame(width: 4.5, height: 1.0)
                .rotationEffect(.degrees(-35))
        }
    }
}

/// Iconic machined dot-matrix grille detail rendered consistently across every theme.
struct SpeakerGrilleDots: View {
    let palette: XynthPalette

    var body: some View {
        Canvas { ctx, size in
            let cols = 7
            let rows = 3
            let dx = size.width / CGFloat(cols)
            let dy = size.height / CGFloat(rows)
            let dotColor = palette.isLightChassis ? Color.black.opacity(0.28) : Color.black.opacity(0.68)
            let rimColor = palette.isLightChassis ? Color.white.opacity(0.45) : palette.enc1.opacity(0.22)
            for r in 0..<rows {
                for c in 0..<cols {
                    let pt = CGPoint(x: (CGFloat(c) + 0.5) * dx, y: (CGFloat(r) + 0.5) * dy)
                    let rect = CGRect(x: pt.x - 1.35, y: pt.y - 1.35, width: 2.7, height: 2.7)
                    ctx.fill(Path(ellipseIn: rect), with: .color(dotColor))
                    ctx.stroke(Path(ellipseIn: rect), with: .color(rimColor), lineWidth: 0.5)
                }
            }
        }
        .frame(width: 44, height: 18)
    }
}

private struct ScrollWheelCatcher: NSViewRepresentable {
    var onScroll: (Double) -> Void

    func makeNSView(context: Context) -> ScrollCatcherNSView {
        let view = ScrollCatcherNSView()
        view.onScroll = onScroll
        return view
    }

    func updateNSView(_ nsView: ScrollCatcherNSView, context: Context) {
        nsView.onScroll = onScroll
    }
}

private final class ScrollCatcherNSView: NSView {
    var onScroll: ((Double) -> Void)?

    override func scrollWheel(with event: NSEvent) {
        let delta = event.hasPreciseScrollingDeltas ? Double(event.scrollingDeltaY) : Double(event.deltaY) * 6.0
        if abs(delta) > 0.01 {
            onScroll?(delta)
        }
    }
}
