import AppKit

/// Watches keyboard events (through one active event tap) for one keyboard trigger binding.
/// Calls `onDown` when the configured keyCode + normalized chord modifiers are
/// pressed exactly. `onUp` is emitted only for a press this monitor actually
/// accepted; modifiers are ignored on release so any release order closes it.
/// The production event tap consumes the accepted down/up pair so the frontmost
/// application cannot also reject the chord with a system beep.
@MainActor
final class KeyboardTriggerMonitor {
    private let eventTap: any KeystrokeCaptureTapping
    private var keyCode: UInt16 = 0
    private var modifiers: UInt = 0
    private var onDown: (() -> Void)?
    private var onUp: (() -> Void)?
    private var isPressed = false

    /// Called when macOS disables the tap. The monitor does not re-enable it;
    /// the owner decides between `resume()` and teardown.
    var onDisabled: ((InputTapDisableReason) -> Void)?
    var onInstallFailed: (() -> Void)?

    init(eventTap: (any KeystrokeCaptureTapping)? = nil) {
        self.eventTap = eventTap ?? SystemKeystrokeCaptureTap()
    }

    func start(
        keyCode: UInt16,
        modifiers: UInt,
        onDown: @escaping () -> Void,
        onUp: @escaping () -> Void
    ) {
        stop()
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.onDown = onDown
        self.onUp = onUp
        isPressed = false

        do {
            try eventTap.start { [weak self] event in
                guard let self else { return .passThrough }
                return self.handle(event)
            }
        } catch {
            // No passive NSEvent fallback: it would run without consuming the
            // chord and continue to act after permission is lost.
            stop()
            onInstallFailed?()
        }
    }

    /// Re-enables a tap that was reported disabled.
    func resume() {
        eventTap.reenable()
    }

    func stop() {
        eventTap.stop()
        onDown = nil
        onUp = nil
        isPressed = false
    }

    @discardableResult
    func handle(_ event: NSEvent) -> KeystrokeCaptureDisposition {
        let input: KeystrokeCaptureEvent
        switch event.type {
        case .keyDown:
            input = .keyDown(
                keyCode: event.keyCode,
                modifiers: event.modifierFlags.rawValue,
                isRepeat: event.isARepeat
            )
        case .keyUp:
            input = .keyUp(keyCode: event.keyCode)
        default:
            return .passThrough
        }
        return handle(input)
    }

    @discardableResult
    private func handle(_ event: KeystrokeCaptureEvent) -> KeystrokeCaptureDisposition {
        if case let .tapDisabled(reason) = event {
            isPressed = false
            onDisabled?(reason)
            return .passThrough
        }

        if TriggerRecorderService.isRecordingKeyboardShortcut {
            isPressed = false
            return .passThrough
        }

        switch event {

        case let .keyDown(eventKeyCode, eventModifiers, isRepeat) where HUDTriggerRouting.keyboardEventMatches(
            keyCode: eventKeyCode,
            modifiers: eventModifiers,
            bindingKeyCode: keyCode,
            bindingModifiers: modifiers
        ):
            guard !isRepeat, !isPressed else { return .consume }
            isPressed = true
            onDown?()
            return .consume

        case let .keyUp(eventKeyCode) where eventKeyCode == keyCode && isPressed:
            isPressed = false
            onUp?()
            return .consume

        default:
            return .passThrough
        }
    }
}
