import AppKit

/// Watches global + local keyboard events for one keyboard trigger binding.
/// Calls `onDown` when the configured keyCode + normalized chord modifiers are
/// pressed exactly. `onUp` is emitted only for a press this monitor actually
/// accepted; modifiers are ignored on release so any release order closes it.
@MainActor
final class KeyboardTriggerMonitor {
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var keyCode: UInt16 = 0
    private var modifiers: UInt = 0
    private var onDown: (() -> Void)?
    private var onUp: (() -> Void)?
    private var isPressed = false

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

        let mask: NSEvent.EventTypeMask = [.keyDown, .keyUp, .flagsChanged]

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
            Task { @MainActor in self?.handle(event) }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            Task { @MainActor in self?.handle(event) }
            return event
        }
    }

    func stop() {
        if let m = globalMonitor { NSEvent.removeMonitor(m); globalMonitor = nil }
        if let m = localMonitor { NSEvent.removeMonitor(m); localMonitor = nil }
        onDown = nil
        onUp = nil
        isPressed = false
    }

    func handle(_ event: NSEvent) {
        switch event.type {
        case .keyDown where !isPressed && HUDTriggerRouting.keyboardEventMatches(
            keyCode: event.keyCode,
            modifiers: event.modifierFlags.rawValue,
            bindingKeyCode: keyCode,
            bindingModifiers: modifiers
        ):
            isPressed = true
            onDown?()
        case .keyUp where event.keyCode == keyCode && isPressed:
            isPressed = false
            onUp?()
        default:
            break
        }
    }
}
