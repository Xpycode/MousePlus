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
    private var onDown: ((CGPoint) -> Void)?
    private var onDragged: ((CGPoint) -> Void)?
    private var onUp: ((CGPoint) -> Void)?

    func start(
        buttonNumber: Int,
        onDown: @escaping (CGPoint) -> Void,
        onDragged: @escaping (CGPoint) -> Void,
        onUp: @escaping (CGPoint) -> Void
    ) {
        stop()
        self.buttonNumber = buttonNumber
        self.onDown = onDown
        self.onDragged = onDragged
        self.onUp = onUp

        // A held auxiliary button changes pointer motion from `mouseMoved` to
        // `otherMouseDragged`. The down happened before the HUD existed, so the
        // original app can retain that drag stream; observe it globally.
        let globalMask: NSEvent.EventTypeMask = [
            .otherMouseDown, .otherMouseDragged, .otherMouseUp
        ]
        // If MousePlus owns the event, RingHostingView forwards the drag in HUD
        // coordinates. Excluding it here prevents duplicate selection updates.
        let localMask: NSEvent.EventTypeMask = [.otherMouseDown, .otherMouseUp]

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: globalMask) { [weak self] event in
            Task { @MainActor in self?.handle(event) }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: localMask) { [weak self] event in
            Task { @MainActor in self?.handle(event) }
            return event
        }
    }

    func stop() {
        if let m = globalMonitor { NSEvent.removeMonitor(m); globalMonitor = nil }
        if let m = localMonitor { NSEvent.removeMonitor(m); localMonitor = nil }
        onDown = nil
        onDragged = nil
        onUp = nil
    }

    private func handle(_ event: NSEvent) {
        guard event.buttonNumber == buttonNumber else { return }

        // Preserve the triggering event's pointer position. Reading
        // `NSEvent.mouseLocation` later in the AsyncStream consumer races the
        // SwiftUI release/hover callbacks and can commit a stale selection.
        let screenLocation = event.window.map {
            $0.convertPoint(toScreen: event.locationInWindow)
        } ?? event.locationInWindow

        switch event.type {
        case .otherMouseDown:
            onDown?(screenLocation)
        case .otherMouseDragged:
            onDragged?(screenLocation)
        case .otherMouseUp:
            onUp?(screenLocation)
        default:
            break
        }
    }
}
