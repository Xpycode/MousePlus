import AppKit

/// Installs global event monitors that dismiss the ring overlay.
///
/// Two dismissal signals (IMPLEMENTATION_PLAN §T10):
///   - **Escape** (keyCode 53) → `onEscape`. The owner decides whether that
///     collapses an expanded outer ring or fully closes the root.
///   - **Mouse-down outside our overlay** → `onClickOutside` (full dismiss).
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
/// Click-outside needs no frame math: a *global* mouse-down is by definition a
/// click destined for another app / the desktop, i.e. outside our overlay.
@MainActor
final class DismissMonitor {
    /// Escape key code (kVK_Escape).
    private static let escapeKeyCode: UInt16 = 53

    private var keyMonitorGlobal: Any?
    private var keyMonitorLocal: Any?
    private var mouseMonitor: Any?

    /// True while monitors are installed.
    var isRunning: Bool { keyMonitorGlobal != nil || keyMonitorLocal != nil || mouseMonitor != nil }

    /// Begin observing. Idempotent — a second `start` before `stop` is a no-op
    /// so we never stack duplicate monitors.
    func start(onEscape: @escaping () -> Void, onClickOutside: @escaping () -> Void) {
        guard !isRunning else { return }

        // Escape sent to another app (we're not active).
        keyMonitorGlobal = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown]) { event in
            guard event.keyCode == DismissMonitor.escapeKeyCode else { return }
            // Global monitor handlers are delivered on the main run loop.
            MainActor.assumeIsolated { onEscape() }
        }

        // Escape sent to us (the ring panel / app holds focus). Swallow it.
        keyMonitorLocal = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            guard event.keyCode == DismissMonitor.escapeKeyCode else { return event }
            MainActor.assumeIsolated { onEscape() }
            return nil  // consume — no beep, no propagation
        }

        mouseMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { _ in
            MainActor.assumeIsolated { onClickOutside() }
        }
    }

    /// Remove all monitors. Safe to call when not running.
    func stop() {
        if let keyMonitorGlobal {
            NSEvent.removeMonitor(keyMonitorGlobal)
            self.keyMonitorGlobal = nil
        }
        if let keyMonitorLocal {
            NSEvent.removeMonitor(keyMonitorLocal)
            self.keyMonitorLocal = nil
        }
        if let mouseMonitor {
            NSEvent.removeMonitor(mouseMonitor)
            self.mouseMonitor = nil
        }
    }

    deinit {
        // deinit is nonisolated; `removeMonitor` is thread-safe and the stored
        // tokens are opaque, so tear down directly without hopping actors.
        if let keyMonitorGlobal { NSEvent.removeMonitor(keyMonitorGlobal) }
        if let keyMonitorLocal { NSEvent.removeMonitor(keyMonitorLocal) }
        if let mouseMonitor { NSEvent.removeMonitor(mouseMonitor) }
    }
}
