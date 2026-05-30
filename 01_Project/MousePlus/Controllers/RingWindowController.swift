import AppKit
import SwiftUI

/// An `NSHostingView` subclass that accepts the first mouse click.
///
/// The ring overlay lives in a non-activating panel, so without this the very
/// first click after the panel appears would only activate/raise the window and
/// be swallowed before SwiftUI ever sees it (see `IMPLEMENTATION_PLAN.md` §6
/// "NSPanel first-click swallowed"). Returning `true` makes that first click a
/// real event the ring can act on.
private final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Manages the ring menu overlay panel.
@MainActor
final class RingWindowController {
    private var panel: NSPanel?
    private var hostingView: FirstMouseHostingView<AnyView>?

    /// Side length of the (square) overlay panel.
    ///
    /// Derived from the outermost band radius (`r3`) so the full ring — plus a
    /// little breathing room for shadow/hover affordances — always fits:
    /// `side = 2 * r3 + pad` (`IMPLEMENTATION_PLAN.md` §2.1). With the default
    /// `BandRadii` (`r3 = 224`) and `pad = 24` this is `472pt`.
    private let panelSide: CGFloat = {
        let pad: CGFloat = 24
        return 2 * BandRadii().r3 + pad
    }()

    var isVisible: Bool {
        panel?.isVisible ?? false
    }

    func show<Content: View>(at point: NSPoint, content: Content) {
        let panel = createPanel()
        let side = panelSide
        let squareSize = NSSize(width: side, height: side)

        let hostingView = FirstMouseHostingView(rootView: AnyView(content))
        hostingView.frame = NSRect(origin: .zero, size: squareSize)

        panel.contentView = hostingView
        self.hostingView = hostingView
        self.panel = panel

        // Center the fixed square on the pointer, then clamp it onto the screen
        // under the cursor so the whole ring stays on-screen.
        let origin = clampedOrigin(forSquareSide: side, centeredOn: point)
        panel.setFrame(NSRect(origin: origin, size: squareSize), display: true)

        // Non-activating: show without stealing key/focus from the frontmost app.
        // `acceptsFirstMouse` (above) + `acceptsMouseMovedEvents` ensure clicks
        // and hover still reach the SwiftUI content.
        panel.orderFrontRegardless()
    }

    func hide() {
        panel?.orderOut(nil)
        panel = nil
        hostingView = nil
    }

    /// Computes the panel origin (bottom-left, global screen coords) for a square
    /// of `side` centered on `point`, clamped to stay fully within the
    /// `visibleFrame` of the screen under the cursor.
    private func clampedOrigin(forSquareSide side: CGFloat, centeredOn point: NSPoint) -> NSPoint {
        // Pointer-centered origin (bottom-left).
        var origin = NSPoint(x: point.x - side / 2, y: point.y - side / 2)

        // Screen under the cursor; fall back to main.
        let screen = NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return origin }

        // If the screen is smaller than the panel in a dimension, pin to the
        // min edge rather than producing an inverted clamp range.
        if visible.width >= side {
            origin.x = min(max(origin.x, visible.minX), visible.maxX - side)
        } else {
            origin.x = visible.minX
        }

        if visible.height >= side {
            origin.y = min(max(origin.y, visible.minY), visible.maxY - side)
        } else {
            origin.y = visible.minY
        }

        return origin
    }

    private func createPanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: NSSize(width: panelSide, height: panelSide)),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovable = false
        panel.hasShadow = true

        // Floating overlay behavior: stay up while focus moves (dismissal is
        // handled by T10), only become key if a control truly needs it, and
        // deliver mouse-moved events so SwiftUI's `onContinuousHover` fires.
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.acceptsMouseMovedEvents = true

        return panel
    }
}
