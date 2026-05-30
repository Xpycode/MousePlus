import AppKit

/// Installs global event monitors that dismiss the ring overlay.
///
/// Two dismissal signals (IMPLEMENTATION_PLAN §T10):
///   - **Escape** (keyCode 53) → `onEscape`. The owner decides whether that
///     collapses an expanded outer ring or fully closes the root.
///   - **Mouse-down outside our overlay** → `onClickOutside` (full dismiss).
///
/// Why no frame math for click-outside: `NSEvent.addGlobalMonitorForEvents`
/// only observes events destined for **other** applications / outside our key
/// window. Our ring panel is the key window while shown, so any *global*
/// mouse-down inherently means the user clicked elsewhere — "outside" is
/// implied by the event being global at all.
@MainActor
final class DismissMonitor {
    /// Escape key code (kVK_Escape).
    private static let escapeKeyCode: UInt16 = 53

    private var keyMonitor: Any?
    private var mouseMonitor: Any?

    /// True while monitors are installed.
    var isRunning: Bool { keyMonitor != nil || mouseMonitor != nil }

    /// Begin observing. Idempotent — a second `start` before `stop` is a no-op
    /// so we never stack duplicate monitors.
    func start(onEscape: @escaping () -> Void, onClickOutside: @escaping () -> Void) {
        guard !isRunning else { return }

        keyMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown]) { event in
            guard event.keyCode == DismissMonitor.escapeKeyCode else { return }
            // Global monitor handlers are delivered on the main run loop.
            MainActor.assumeIsolated { onEscape() }
        }

        mouseMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { _ in
            MainActor.assumeIsolated { onClickOutside() }
        }
    }

    /// Remove both monitors. Safe to call when not running.
    func stop() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
        if let mouseMonitor {
            NSEvent.removeMonitor(mouseMonitor)
            self.mouseMonitor = nil
        }
    }

    deinit {
        // deinit is nonisolated; `removeMonitor` is thread-safe and the stored
        // tokens are opaque, so tear down directly without hopping actors.
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        if let mouseMonitor { NSEvent.removeMonitor(mouseMonitor) }
    }
}
