import AppKit

/// Watches global + local keyboard events for one keyboard trigger binding.
/// Calls `onDown` when the configured keyCode + normalized chord modifiers are
/// pressed exactly. `onUp` is emitted only for a press this monitor actually
/// accepted; modifiers are ignored on release so any release order closes it.
/// The production event tap consumes the accepted down/up pair so the frontmost
/// application cannot also reject the chord with a system beep.
@MainActor
final class KeyboardTriggerMonitor {
    private let eventTap: any KeystrokeCaptureTapping
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var keyCode: UInt16 = 0
    private var modifiers: UInt = 0
    private var onDown: (() -> Void)?
    private var onUp: (() -> Void)?
    private var isPressed = false

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
            return
        } catch {
            // Preserve trigger functionality if the consumable tap cannot be
            // installed. The Settings permission UI already explains how to
            // restore Accessibility access; this fallback may not suppress the
            // active application's alert sound.
        }

        let mask: NSEvent.EventTypeMask = [.keyDown, .keyUp, .flagsChanged]

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
            MainActor.assumeIsolated { _ = self?.handle(event) }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            let shouldConsume = MainActor.assumeIsolated {
                self?.handle(event) == .consume
            }
            return shouldConsume ? nil : event
        }
    }

    func stop() {
        eventTap.stop()
        if let m = globalMonitor { NSEvent.removeMonitor(m); globalMonitor = nil }
        if let m = localMonitor { NSEvent.removeMonitor(m); localMonitor = nil }
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
        if TriggerRecorderService.isRecordingKeyboardShortcut {
            isPressed = false
            return .passThrough
        }

        switch event {
        case .tapDisabled:
            eventTap.reenable()
            return .passThrough

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
