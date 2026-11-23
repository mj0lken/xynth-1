import AppKit
import Foundation
import Observation
import SwiftUI

/// Descriptor shown in the styled floating hover card.
struct HoverHelpItem: Equatable {
    let id: String
    let title: String
    let shortcut: String?
    let detail: String
    let anchorFrame: CGRect
}

/// Shared hover-help state scoped to the XYNTH-1 window coordinate space (`"xynthRoot"`).
/// Uses a polite 480 ms dwell and auto-dismisses immediately on any mouse click/drag
/// so tooltips never cover buttons while clicking or turning knobs.
@MainActor
@Observable
final class HoverHelpState {
    var isEnabled: Bool = true {
        didSet {
            if !isEnabled { clear() }
        }
    }
    private(set) var activeItem: HoverHelpItem? = nil
    private(set) var floatingVisible: Bool = false
    private var dwellTask: Task<Void, Never>? = nil
    private var clickDismissMonitor: Any? = nil
    private var suppressedControlID: String? = nil

    init() {
        // Immediately hide any tooltip the instant the user clicks or starts dragging
        clickDismissMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            self?.dismissForInteraction()
            return event
        }
    }

    func teardown() {
        dwellTask?.cancel()
        dwellTask = nil
        if let clickDismissMonitor {
            NSEvent.removeMonitor(clickDismissMonitor)
            self.clickDismissMonitor = nil
        }
    }

    func enter(_ item: HoverHelpItem) {
        guard isEnabled else { return }
        // If the user just clicked this exact control, stay dismissed until they leave and re-hover
        if suppressedControlID == item.id {
            return
        }
        let sameControl = (activeItem?.id == item.id)
        activeItem = item
        if sameControl && floatingVisible {
            return
        }
        dwellTask?.cancel()
        floatingVisible = false
        dwellTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(480))
            guard !Task.isCancelled else { return }
            self?.floatingVisible = true
        }
    }

    func exit(id: String) {
        if suppressedControlID == id {
            suppressedControlID = nil
        }
        guard activeItem?.id == id else { return }
        dwellTask?.cancel()
        dwellTask = nil
        floatingVisible = false
        activeItem = nil
    }

    func dismissForInteraction() {
        dwellTask?.cancel()
        dwellTask = nil
        suppressedControlID = activeItem?.id
        floatingVisible = false
    }

    func clear() {
        dwellTask?.cancel()
        dwellTask = nil
        suppressedControlID = nil
        floatingVisible = false
        activeItem = nil
    }
}

/// Attaches non-intrusive, theme-styled hover help to any button, knob, toggle, or dropdown.
private struct XynthHoverHelpModifier: ViewModifier {
    @Environment(HoverHelpState.self) private var helpState
    let id: String
    let title: String
    let shortcut: String?
    let detail: String

    @State private var currentFrame: CGRect = .zero

    func body(content: Content) -> some View {
        content
            .background(
                GeometryReader { geo in
                    Color.clear
                        .onAppear {
                            currentFrame = geo.frame(in: .named("xynthRoot"))
                        }
                        .onChange(of: geo.frame(in: .named("xynthRoot"))) { _, newRect in
                            currentFrame = newRect
                        }
                }
            )
            .onHover { hovering in
                if hovering {
                    helpState.enter(
                        HoverHelpItem(
                            id: id,
                            title: title,
                            shortcut: shortcut,
                            detail: detail,
                            anchorFrame: currentFrame
                        )
                    )
                } else {
                    helpState.exit(id: id)
                }
            }
    }
}

extension View {
    func xynthHelp(
        _ title: String,
        shortcut: String? = nil,
        detail: String
    ) -> some View {
        modifier(
            XynthHoverHelpModifier(
                id: "\(title)::\(shortcut ?? "")",
                title: title,
                shortcut: shortcut,
                detail: detail
            )
        )
    }
}

/// Floating theme-matched hardware callout card that appears cleanly offset from the hovered control
/// after a 480 ms dwell and immediately vanishes on click/drag so it never obscures interactions.
struct StyledHoverTooltipOverlay: View {
    let palette: XynthPalette
    let helpState: HoverHelpState

    var body: some View {
        GeometryReader { geo in
            if helpState.floatingVisible, let item = helpState.activeItem, item.anchorFrame.width > 0 {
                let cardWidth: CGFloat = 258
                let estCardHeight: CGFloat = 56
                let halfW = cardWidth * 0.5
                let clampedX = min(
                    geo.size.width - halfW - 14,
                    max(halfW + 14, item.anchorFrame.midX)
                )

                // Smart edge placement:
                // - Near the top half of the window -> place BELOW the control with clean gap
                // - Near the bottom edge -> place ABOVE the control with clean gap
                let spaceBelow = geo.size.height - item.anchorFrame.maxY
                let placeBelow = (item.anchorFrame.minY < 160) || (spaceBelow > estCardHeight + 36 && item.anchorFrame.minY < geo.size.height * 0.72)
                let targetY = placeBelow
                    ? min(geo.size.height - estCardHeight * 0.5 - 12, item.anchorFrame.maxY + estCardHeight * 0.5 + 12)
                    : max(estCardHeight * 0.5 + 12, item.anchorFrame.minY - estCardHeight * 0.5 - 12)

                VStack(alignment: .leading, spacing: 3.5) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(palette.enc1)
                            .frame(width: 5, height: 5)
                            .shadow(color: palette.enc1.opacity(0.8), radius: 3)
                        Text(item.title.uppercased())
                            .font(.system(size: 9.5, weight: .black, design: .monospaced))
                            .tracking(0.7)
                            .foregroundStyle(palette.oledInkPrimary)
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        if let key = item.shortcut, !key.isEmpty {
                            Text(key)
                                .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                                .foregroundStyle(palette.oledBg)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(RoundedRectangle(cornerRadius: 3).fill(palette.enc1))
                        }
                    }

                    Text(item.detail)
                        .font(.system(size: 10, weight: .regular))
                        .foregroundStyle(palette.oledInkPrimary.opacity(0.86))
                        .fixedSize(horizontal: false, vertical: true)
                        .lineSpacing(1.3)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .frame(width: cardWidth, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(palette.tooltipBg)
                        .shadow(color: Color.black.opacity(0.48), radius: 14, y: 6)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(palette.tooltipBorder, lineWidth: 1.1)
                )
                .position(x: clampedX, y: targetY)
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
                .animation(.easeOut(duration: 0.12), value: item.id)
            }
        }
        .allowsHitTesting(false)
    }
}
