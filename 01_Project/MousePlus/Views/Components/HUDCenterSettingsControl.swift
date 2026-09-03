import AppKit
import SwiftUI

/// The HUD dead-zone's dedicated Settings action, backed by a native button.
struct HUDCenterSettingsControl: NSViewRepresentable {
    static let accessibilityIdentifier = "hud.center.settings"
    static let accessibilityLabel = "Open MousePlus Settings"

    let action: @MainActor () -> Void
    var draggingEnabled = false
    var onDrag: @MainActor (CGSize) -> Void = { _ in }

    func makeCoordinator() -> Coordinator { Coordinator(action: action, onDrag: onDrag) }

    func makeNSView(context: Context) -> NSButton {
        let image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: Self.accessibilityLabel) ?? NSImage()
        let button = HUDCenterTrackingButton(image: image, target: context.coordinator, action: #selector(Coordinator.activate))
        button.bezelStyle = .circular
        button.imagePosition = .imageOnly
        button.toolTip = "Open Settings"
        button.onDrag = { [weak coordinator = context.coordinator] delta in
            coordinator?.drag(delta)
        }
        button.draggingEnabled = draggingEnabled
        configure(button)
        return button
    }

    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.action = action
        context.coordinator.onDrag = onDrag
        if let button = button as? HUDCenterTrackingButton {
            button.draggingEnabled = draggingEnabled
        }
        configure(button)
    }

    private func configure(_ button: NSButton) {
        button.setAccessibilityLabel(Self.accessibilityLabel)
        button.setAccessibilityIdentifier(Self.accessibilityIdentifier)
    }

    @MainActor final class Coordinator: NSObject {
        var action: @MainActor () -> Void
        var onDrag: @MainActor (CGSize) -> Void
        init(action: @escaping @MainActor () -> Void,
             onDrag: @escaping @MainActor (CGSize) -> Void) {
            self.action = action
            self.onDrag = onDrag
        }
        @objc func activate() { action() }
        func drag(_ delta: CGSize) { onDrag(delta) }
    }
}

/// Pure click/drag arbitration used by the native center control.
struct HUDCenterDragState {
    static let threshold: CGFloat = 4

    private(set) var isDragging = false
    private var start: CGPoint?
    private var previous: CGPoint?

    mutating func begin(at point: CGPoint) {
        isDragging = false
        start = point
        previous = point
    }

    mutating func move(to point: CGPoint) -> CGSize? {
        guard let start, let previous else { return nil }
        if !isDragging {
            guard hypot(point.x - start.x, point.y - start.y) > Self.threshold else { return nil }
            isDragging = true
        }
        self.previous = point
        return CGSize(width: point.x - previous.x, height: point.y - previous.y)
    }

    mutating func end() -> Bool {
        let shouldClick = !isDragging
        isDragging = false
        start = nil
        previous = nil
        return shouldClick
    }
}

/// Tracks in global coordinates so moving the panel beneath the pointer does not
/// perturb subsequent drag deltas.
private final class HUDCenterTrackingButton: NSButton {
    var draggingEnabled = false
    var onDrag: @MainActor (CGSize) -> Void = { _ in }
    private var dragState = HUDCenterDragState()

    override func mouseDown(with event: NSEvent) {
        guard draggingEnabled, let window else {
            super.mouseDown(with: event)
            return
        }

        dragState.begin(at: NSEvent.mouseLocation)
        highlight(true)
        defer { highlight(false) }

        while let next = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
            switch next.type {
            case .leftMouseDragged:
                if let delta = dragState.move(to: NSEvent.mouseLocation) {
                    onDrag(delta)
                }
            case .leftMouseUp:
                if dragState.end() {
                    sendAction(action, to: target)
                }
                return
            default:
                break
            }
        }
    }
}
