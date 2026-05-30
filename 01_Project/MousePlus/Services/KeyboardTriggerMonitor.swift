import AppKit

/// Watches global + local keyboard events for one keyboard trigger binding.
/// Calls `onDown` when the configured keyCode + modifier set is pressed,
/// `onUp` when the keyCode is released (modifiers ignored on release so that
/// pressing & releasing in any modifier order still cleanly closes the ring).
@MainActor
final class KeyboardTriggerMonitor {
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var keyCode: UInt16 = 0
    private var modifiers: UInt = 0
    private var onDown: (() -> Void)?
    private var onUp: (() -> Void)?

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
    }

    private func handle(_ event: NSEvent) {
        let modsMatch = (event.modifierFlags.rawValue & modifiers) == modifiers

        switch event.type {
        case .keyDown where event.keyCode == keyCode && modsMatch:
            onDown?()
        case .keyUp where event.keyCode == keyCode:
            onUp?()
        default:
            break
        }
    }
}
