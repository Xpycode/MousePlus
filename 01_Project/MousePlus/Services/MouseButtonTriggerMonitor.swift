import AppKit

/// Watches global + local `.otherMouseDown` / `.otherMouseUp` for one mouse-button binding.
///
/// `event.buttonNumber` semantics on macOS: 0 = left, 1 = right, 2 = middle (wheel
/// click), 3+ = "other" (back/forward/gesture buttons on extended mice). We only
/// look at `.otherMouseDown/.otherMouseUp`, so left/right/middle reach the
/// dedicated `.leftMouseDown` etc. event types and never collide with the trigger.
///
/// Vendor software (Logi Options+ / SteerMouse / Karabiner) can intercept buttons
/// before macOS sees them. If a user's button doesn't fire, they need to set that
/// button to "No Action" / "Default" in their vendor software.
@MainActor
final class MouseButtonTriggerMonitor {
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var buttonNumber: Int = 0
    private var onDown: (() -> Void)?
    private var onUp: (() -> Void)?

    func start(
        buttonNumber: Int,
        onDown: @escaping () -> Void,
        onUp: @escaping () -> Void
    ) {
        stop()
        self.buttonNumber = buttonNumber
        self.onDown = onDown
        self.onUp = onUp

        let mask: NSEvent.EventTypeMask = [.otherMouseDown, .otherMouseUp]

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
        guard event.buttonNumber == buttonNumber else { return }

        switch event.type {
        case .otherMouseDown:
            onDown?()
        case .otherMouseUp:
            onUp?()
        default:
            break
        }
    }
}
