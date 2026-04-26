import AppKit
import SwiftUI

/// Manages the ring menu overlay panel
@MainActor
final class RingWindowController {
    private var panel: NSPanel?
    private var hostingView: NSHostingView<AnyView>?

    var isVisible: Bool {
        panel?.isVisible ?? false
    }

    func show<Content: View>(at point: NSPoint, content: Content) {
        let panel = createPanel()
        let hostingView = NSHostingView(rootView: AnyView(content))

        panel.contentView = hostingView
        self.hostingView = hostingView
        self.panel = panel

        // Size the panel to fit content
        let size = hostingView.fittingSize
        let origin = NSPoint(
            x: point.x - size.width / 2,
            y: point.y - size.height / 2
        )

        panel.setFrame(NSRect(origin: origin, size: size), display: true)
        panel.makeKeyAndOrderFront(nil)
    }

    func hide() {
        panel?.orderOut(nil)
        panel = nil
        hostingView = nil
    }

    private func createPanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: .zero,
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

        return panel
    }
}
