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

    var isVisible: Bool {
        panel?.isVisible ?? false
    }

    /// Returns whether a local mouse-down targets this panel outside the HUD's
    /// circular outer edge. The square panel includes transparent padding and
    /// corners, so panel-frame containment alone is insufficient.
    func shouldDismiss(forLocalMouseDown event: NSEvent, outerRadius: CGFloat) -> Bool {
        guard let panel, let hostingView, event.window === panel else { return false }
        let point = hostingView.convert(event.locationInWindow, from: nil)
        let center = CGPoint(x: hostingView.bounds.midX, y: hostingView.bounds.midY)
        return HUDDismissalGeometry.isOutsideHUD(
            point: point,
            center: center,
            outerRadius: outerRadius
        )
    }

    func show<Content: View>(at point: NSPoint, outerRadius: CGFloat, content: Content) {
        let side = HUDPanelGeometry.squareSide(outerRadius: outerRadius)
        let panel = createPanel(side: side)
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

    /// Moves the current HUD by a global-coordinate delta while keeping the
    /// complete square inside the visible frame of the screen under the pointer.
    func movePanel(by delta: CGSize) {
        guard let panel else { return }
        let proposed = CGPoint(x: panel.frame.origin.x + delta.width,
                               y: panel.frame.origin.y + delta.height)
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) }
            ?? panel.screen ?? NSScreen.main
        let origin = screen.map {
            HUDPanelGeometry.clampedOrigin(proposed, size: panel.frame.size, in: $0.visibleFrame)
        } ?? proposed
        panel.setFrameOrigin(origin)
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

    private func createPanel(side: CGFloat) -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: NSSize(width: side, height: side)),
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

/// Pure boundary math shared by runtime dismissal and focused unit tests.
enum HUDDismissalGeometry {
    static func isOutsideHUD(point: CGPoint, center: CGPoint, outerRadius: CGFloat) -> Bool {
        hypot(point.x - center.x, point.y - center.y) > outerRadius
    }
}

enum HUDPanelGeometry {
    /// Full HUD diameter plus breathing room for shadows and hover affordances.
    static func squareSide(outerRadius: CGFloat, padding: CGFloat = 24) -> CGFloat {
        max(0, 2 * outerRadius + padding)
    }

    static func clampedOrigin(_ origin: CGPoint, size: CGSize, in visibleFrame: CGRect) -> CGPoint {
        CGPoint(
            x: clamped(origin.x, extent: size.width, min: visibleFrame.minX, max: visibleFrame.maxX),
            y: clamped(origin.y, extent: size.height, min: visibleFrame.minY, max: visibleFrame.maxY)
        )
    }

    private static func clamped(_ value: CGFloat, extent: CGFloat,
                                min minimum: CGFloat, max maximum: CGFloat) -> CGFloat {
        guard maximum - minimum >= extent else { return minimum }
        return Swift.min(Swift.max(value, minimum), maximum - extent)
    }
}
