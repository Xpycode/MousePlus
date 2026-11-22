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
///
/// Preferred path: an active session event tap that consumes the configured
/// button's down/drag/up, so the frontmost app never also acts on it (for
/// example Warp switching tabs on a side button). If the tap cannot be created
/// (no Accessibility trust yet), it falls back to passive NSEvent monitors,
/// which observe the button but let it reach other apps as before.
@MainActor
final class MouseButtonTriggerMonitor {
    private var eventTap: CFMachPort?
    private var eventTapSource: CFRunLoopSource?
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

        if startEventTap() { return }

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
        stopEventTap()
        if let m = globalMonitor { NSEvent.removeMonitor(m); globalMonitor = nil }
        if let m = localMonitor { NSEvent.removeMonitor(m); localMonitor = nil }
        onDown = nil
        onDragged = nil
        onUp = nil
    }

    /// True while the consuming event tap (not the passive fallback) is active.
    var isConsumingButton: Bool { eventTap != nil }

    private func startEventTap() -> Bool {
        let mask = (1 << CGEventType.otherMouseDown.rawValue)
            | (1 << CGEventType.otherMouseDragged.rawValue)
            | (1 << CGEventType.otherMouseUp.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: mouseButtonTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return false }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        eventTap = tap
        eventTapSource = source
        return true
    }

    private func stopEventTap() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let source = eventTapSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        eventTap = nil
        eventTapSource = nil
    }

    /// Runs on the main run loop. Returns true when the event belongs to the
    /// trigger button and must not reach any other app.
    fileprivate func handleTapEvent(type: CGEventType, event: CGEvent) -> Bool {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            // macOS disables slow taps; resume immediately so the trigger
            // does not silently fall back to reaching other apps.
            if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: true) }
            return false
        case .otherMouseDown, .otherMouseDragged, .otherMouseUp:
            break
        default:
            return false
        }
        guard Int(event.getIntegerValueField(.mouseEventButtonNumber)) == buttonNumber else {
            return false
        }
        let location = Self.cocoaScreenPoint(fromQuartz: event.location)
        switch type {
        case .otherMouseDown: onDown?(location)
        case .otherMouseDragged: onDragged?(location)
        case .otherMouseUp: onUp?(location)
        default: break
        }
        return true
    }

    /// Quartz event locations are top-left based on the main display; AppKit
    /// screen coordinates are bottom-left based on the same display.
    nonisolated static func cocoaScreenPoint(
        fromQuartz point: CGPoint,
        mainDisplayHeight: CGFloat = CGDisplayBounds(CGMainDisplayID()).height
    ) -> CGPoint {
        CGPoint(x: point.x, y: mainDisplayHeight - point.y)
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

private func mouseButtonTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let monitor = Unmanaged<MouseButtonTriggerMonitor>.fromOpaque(userInfo).takeUnretainedValue()
    // The tap's run-loop source is installed on the main run loop.
    let consumed = MainActor.assumeIsolated {
        monitor.handleTapEvent(type: type, event: event)
    }
    return consumed ? nil : Unmanaged.passUnretained(event)
}
