import AppKit
import CoreGraphics
import Foundation

/// Safely manages Play Mode cursor decoupling (`CGAssociateMouseAndMouseCursorPosition`)
/// and live keyboard shortcuts so the user can glide freely across the Force Touch trackpad
/// without moving the desktop pointer or clicking outside XYNTH-1.
@MainActor
final class CursorLockController {
    private(set) var isLocked = false
    private(set) var isOptionHeld = false
    private var isCursorHidden = false

    private var resignObserver: NSObjectProtocol?
    private var terminateObserver: NSObjectProtocol?
    private var keyDownMonitor: Any?
    private var flagsMonitor: Any?

    var onLockStateChanged: ((Bool) -> Void)?
    var onOptionHeldChanged: ((Bool) -> Void)?
    var onShortcutAction: ((ShortcutAction) -> Void)?

    enum ShortcutAction {
        case togglePlayMode
        case escapePressed
        case selectTimbre(Int) // 1...7
        case octaveDown
        case octaveUp
        case cycleScale
        case cycleMapping
        case toggleSubFeel
        case toggleHoldDrone
        case toggleAudioMirror
        case cycleTheme
        case toggleExpansionBay
        case volumeStep(Double)
        case vibratoStep(Double)
        case triggerSweep
    }

    init() {
        installSafetyObservers()
        installKeyboardMonitors()
    }

    deinit {
        MainActor.assumeIsolated {
            teardown()
        }
    }

    func toggleLock() {
        if isLocked {
            unlock()
        } else {
            lock()
        }
    }

    func lock() {
        guard !isLocked else { return }
        guard NSApp.isActive else { return }

        // Park the cursor safely in the center of XYNTH-1's main window before detaching mouse movement,
        // so accidental clicks while gliding land harmlessly inside our pad instead of external apps.
        if let window = NSApp.keyWindow ?? NSApp.mainWindow ?? NSApp.windows.first {
            let winFrame = window.frame
            if let primaryScreen = NSScreen.screens.first {
                let primaryHeight = primaryScreen.frame.height
                let centerX = winFrame.midX
                let centerYAppKit = winFrame.midY + 45 // roughly center of the Trackpad Surface view
                let centerYCG = primaryHeight - centerYAppKit
                CGWarpMouseCursorPosition(CGPoint(x: centerX, y: centerYCG))
            }
        }

        CGAssociateMouseAndMouseCursorPosition(boolean_t(0))
        if !isCursorHidden {
            NSCursor.hide()
            isCursorHidden = true
        }
        isLocked = true
        onLockStateChanged?(true)
    }

    func unlock() {
        let wasLocked = isLocked
        CGAssociateMouseAndMouseCursorPosition(boolean_t(1))
        if isCursorHidden {
            NSCursor.unhide()
            isCursorHidden = false
        }
        isLocked = false
        if wasLocked {
            onLockStateChanged?(false)
        }
    }

    func teardown() {
        unlock()
        if let resignObserver {
            NotificationCenter.default.removeObserver(resignObserver)
            self.resignObserver = nil
        }
        if let terminateObserver {
            NotificationCenter.default.removeObserver(terminateObserver)
            self.terminateObserver = nil
        }
        if let keyDownMonitor {
            NSEvent.removeMonitor(keyDownMonitor)
            self.keyDownMonitor = nil
        }
        if let flagsMonitor {
            NSEvent.removeMonitor(flagsMonitor)
            self.flagsMonitor = nil
        }
    }

    private func installSafetyObservers() {
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.unlock()
                self?.setOptionHeld(false)
            }
        }

        terminateObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.unlock()
            }
        }
    }

    private func setOptionHeld(_ held: Bool) {
        guard isOptionHeld != held else { return }
        isOptionHeld = held
        onOptionHeldChanged?(held)
    }

    private func installKeyboardMonitors() {
        flagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            guard let self else { return event }
            let optionDown = event.modifierFlags.contains(.option)
            self.setOptionHeld(optionDown)
            return event
        }

        keyDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            // Never hijack standard Command shortcuts (Cmd+Q, Cmd+W, Cmd+H, etc.)
            if event.modifierFlags.contains(.command) {
                return event
            }
            // Don't swallow text entry if an NSTextView ever becomes first responder
            if NSApp.keyWindow?.firstResponder is NSTextView {
                return event
            }

            switch event.keyCode {
            case 49: // Space
                self.onShortcutAction?(.togglePlayMode)
                return nil
            case 53: // Escape
                self.onShortcutAction?(.escapePressed)
                return nil
            case 48: // Tab
                self.onShortcutAction?(.toggleHoldDrone)
                return nil
            case 126: // Up arrow
                self.onShortcutAction?(.volumeStep(0.08))
                return nil
            case 125: // Down arrow
                self.onShortcutAction?(.volumeStep(-0.08))
                return nil
            case 124: // Right arrow
                self.onShortcutAction?(.vibratoStep(0.08))
                return nil
            case 123: // Left arrow
                self.onShortcutAction?(.vibratoStep(-0.08))
                return nil
            default:
                break
            }

            guard let chars = event.charactersIgnoringModifiers?.lowercased(), let first = chars.first else {
                return event
            }

            switch first {
            case "1": self.onShortcutAction?(.selectTimbre(1)); return nil
            case "2": self.onShortcutAction?(.selectTimbre(2)); return nil
            case "3": self.onShortcutAction?(.selectTimbre(3)); return nil
            case "4": self.onShortcutAction?(.selectTimbre(4)); return nil
            case "5": self.onShortcutAction?(.selectTimbre(5)); return nil
            case "6": self.onShortcutAction?(.selectTimbre(6)); return nil
            case "7": self.onShortcutAction?(.selectTimbre(7)); return nil
            case "[": self.onShortcutAction?(.octaveDown); return nil
            case "]": self.onShortcutAction?(.octaveUp); return nil
            case "s": self.onShortcutAction?(.cycleScale); return nil
            case "m": self.onShortcutAction?(.cycleMapping); return nil
            case "h": self.onShortcutAction?(.toggleSubFeel); return nil
            case "a": self.onShortcutAction?(.toggleAudioMirror); return nil
            case "c": self.onShortcutAction?(.cycleTheme); return nil
            case "v": self.onShortcutAction?(.toggleExpansionBay); return nil
            case "t": self.onShortcutAction?(.triggerSweep); return nil
            default:
                return event
            }
        }
    }
}
