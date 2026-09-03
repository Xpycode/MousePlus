import AppKit

/// Installs global and local event monitors that dismiss the ring overlay.
///
/// Two dismissal signals (IMPLEMENTATION_PLAN §T10):
///   - **Escape** (keyCode 53) → `onEscape`. The owner decides whether that
///     collapses an expanded outer ring or fully closes the root.
///   - **Mouse-down in another app** → `onClickOutside` (full dismiss).
///   - **Mouse-down in our panel's transparent corner** → `onLocalMouseDown`.
///
/// Key (Escape) handling needs BOTH a global and a local monitor:
///   - `addGlobalMonitorForEvents` only sees events destined for **other** apps.
///   - `addLocalMonitorForEvents` only sees events destined for **us**.
/// When the ring panel is up, keyboard focus typically rests on MousePlus
/// itself, so Escape arrives as a *local* event the global monitor never sees.
/// Installing both covers either case (an event is local XOR global, so the two
/// can't double-fire for the same keystroke). The local handler returns `nil`
/// for a handled Escape to swallow it (no system beep).
///
/// Global mouse-down needs no frame math: it is by definition destined for
/// another app / the desktop. Local mouse-down is handed to the owner because
/// only the window controller knows the panel's coordinate space and HUD center.
protocol EventMonitorProviding {
    func addGlobalMonitor(matching mask: NSEvent.EventTypeMask,
                          handler: @escaping (NSEvent) -> Void) -> Any?
    func addLocalMonitor(matching mask: NSEvent.EventTypeMask,
                         handler: @escaping (NSEvent) -> NSEvent?) -> Any?
    func removeMonitor(_ monitor: Any)
}

private struct SystemEventMonitorProvider: EventMonitorProviding {
    func addGlobalMonitor(matching mask: NSEvent.EventTypeMask,
                          handler: @escaping (NSEvent) -> Void) -> Any? {
        NSEvent.addGlobalMonitorForEvents(matching: mask, handler: handler)
    }

    func addLocalMonitor(matching mask: NSEvent.EventTypeMask,
                         handler: @escaping (NSEvent) -> NSEvent?) -> Any? {
        NSEvent.addLocalMonitorForEvents(matching: mask, handler: handler)
    }

    func removeMonitor(_ monitor: Any) {
        NSEvent.removeMonitor(monitor)
    }
}

@MainActor
final class DismissMonitor {
    /// Escape key code (kVK_Escape).
    private static let escapeKeyCode: UInt16 = 53

    private var keyMonitorGlobal: Any?
    private var keyMonitorLocal: Any?
    private let provider: EventMonitorProviding
    private var mouseMonitorGlobal: Any?
    private var mouseMonitorLocal: Any?

    init(provider: EventMonitorProviding = SystemEventMonitorProvider()) {
        self.provider = provider
    }

    /// True while monitors are installed.
    var isRunning: Bool {
        keyMonitorGlobal != nil || keyMonitorLocal != nil
            || mouseMonitorGlobal != nil || mouseMonitorLocal != nil
    }

    /// Begin observing. Idempotent — a second `start` before `stop` is a no-op
    /// so we never stack duplicate monitors.
    func start(onEscape: @escaping () -> Void,
               onClickOutside: @escaping () -> Void,
               onLocalMouseDown: @escaping (NSEvent) -> Bool) {
        guard !isRunning else { return }

        // Escape sent to another app (we're not active).
        keyMonitorGlobal = provider.addGlobalMonitor(matching: [.keyDown]) { event in
            guard event.keyCode == DismissMonitor.escapeKeyCode else { return }
            // Global monitor handlers are delivered on the main run loop.
            MainActor.assumeIsolated { onEscape() }
        }

        // Escape sent to us (the ring panel / app holds focus). Swallow it.
        keyMonitorLocal = provider.addLocalMonitor(matching: [.keyDown]) { event in
            guard event.keyCode == DismissMonitor.escapeKeyCode else { return event }
            MainActor.assumeIsolated { onEscape() }
            return nil  // consume — no beep, no propagation
        }

        mouseMonitorGlobal = provider.addGlobalMonitor(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { _ in
            MainActor.assumeIsolated { onClickOutside() }
        }

        mouseMonitorLocal = provider.addLocalMonitor(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { event in
            let shouldConsume = MainActor.assumeIsolated { onLocalMouseDown(event) }
            return shouldConsume ? nil : event
        }
    }

    /// Remove all monitors. Safe to call when not running.
    func stop() {
        if let keyMonitorGlobal {
            provider.removeMonitor(keyMonitorGlobal)
            self.keyMonitorGlobal = nil
        }
        if let keyMonitorLocal {
            provider.removeMonitor(keyMonitorLocal)
            self.keyMonitorLocal = nil
        }
        if let mouseMonitorGlobal {
            provider.removeMonitor(mouseMonitorGlobal)
            self.mouseMonitorGlobal = nil
        }
        if let mouseMonitorLocal {
            provider.removeMonitor(mouseMonitorLocal)
            self.mouseMonitorLocal = nil
        }
    }

    deinit {
        // deinit is nonisolated; `removeMonitor` is thread-safe and the stored
        // tokens are opaque, so tear down directly without hopping actors.
        if let keyMonitorGlobal { provider.removeMonitor(keyMonitorGlobal) }
        if let keyMonitorLocal { provider.removeMonitor(keyMonitorLocal) }
        if let mouseMonitorGlobal { provider.removeMonitor(mouseMonitorGlobal) }
        if let mouseMonitorLocal { provider.removeMonitor(mouseMonitorLocal) }
    }
}
