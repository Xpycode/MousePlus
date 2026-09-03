import AppKit
import SwiftUI

enum HUDPreviewIntent: Equatable {
    case selectTopLevel(EditorBand, Int)
    case selectOuter(Int)
}

struct HUDPreviewInteractionSnapshot {
    let geometry: TopLevelRingGeometry
    let radii: BandRadii
    let innerCount: Int
    let middleCount: Int
    let expandedParentIndex: Int?
    let outerCount: Int
    let outerVisibility: OuterRingVisibility

    static func fitScale(logicalSide: CGFloat, canvasSide: CGFloat) -> CGFloat {
        guard logicalSide > 0, canvasSide > 0 else { return 1 }
        return min(1, canvasSide / logicalSide)
    }

}

/// Pure preview-only pointer state. It deliberately has no ActionService,
/// application-launching callback, or runtime commit path.
struct HUDPreviewInteractionState {
    private(set) var hasEnteredInnerBoundary = false
    private(set) var hasRevealedOuterRing = false

    mutating func resetReveal() {
        hasEnteredInnerBoundary = false
        hasRevealedOuterRing = false
    }

    mutating func pointerMoved(to point: CGPoint, center: CGPoint,
                               snapshot: HUDPreviewInteractionSnapshot) -> ActiveSelection? {
        let distance = hypot(point.x - center.x, point.y - center.y)
        if distance <= snapshot.radii.r1 { hasEnteredInnerBoundary = true }
        if snapshot.outerVisibility == .revealBeyondInnerRing,
           hasEnteredInnerBoundary, distance > snapshot.radii.r1 {
            hasRevealedOuterRing = true
        }
        return selection(at: point, center: center, snapshot: snapshot)
    }

    func intent(at point: CGPoint, center: CGPoint,
                snapshot: HUDPreviewInteractionSnapshot) -> HUDPreviewIntent? {
        if let selection = selection(at: point, center: center, snapshot: snapshot) {
            switch selection.band {
            case .inner: return .selectTopLevel(.inner, selection.index)
            case .middle: return .selectTopLevel(.middle, selection.index)
            case .outer: return .selectOuter(selection.index)
            }
        }
        return nil
    }

    var outerIsVisible: Bool { hasRevealedOuterRing }

    private func selection(at point: CGPoint, center: CGPoint,
                           snapshot: HUDPreviewInteractionSnapshot) -> ActiveSelection? {
        let visible: Bool
        switch snapshot.outerVisibility {
        case .alwaysVisible: visible = true
        case .revealBeyondInnerRing: visible = hasRevealedOuterRing
        case .alwaysHidden: visible = false
        }
        let hit = RadialGeometry.hitTest(
            point: point, center: center, radii: snapshot.radii,
            geometry: snapshot.geometry,
            innerItemCount: snapshot.innerCount,
            middleItemCount: snapshot.middleCount,
            expandedParentIndex: visible ? snapshot.expandedParentIndex : nil,
            outerCount: visible ? snapshot.outerCount : 0
        )
        return hit.map { ActiveSelection(band: $0.band, index: $0.index) }
    }

}

struct HUDPreviewInteractionView: NSViewRepresentable {
    let snapshot: HUDPreviewInteractionSnapshot
    let onHover: @MainActor (ActiveSelection?) -> Void
    let onRevealChange: @MainActor (Bool) -> Void
    let onIntent: @MainActor (HUDPreviewIntent) -> Void
    let onDeleteIntent: @MainActor (HUDPreviewIntent) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(snapshot: snapshot) }

    func makeNSView(context: Context) -> InteractionNSView {
        let view = InteractionNSView()
        view.coordinator = context.coordinator
        return view
    }

    func updateNSView(_ view: InteractionNSView, context: Context) {
        context.coordinator.onHover = onHover
        context.coordinator.onRevealChange = onRevealChange
        context.coordinator.onIntent = onIntent
        context.coordinator.onDeleteIntent = onDeleteIntent
        context.coordinator.update(snapshot: snapshot)
    }

    @MainActor final class Coordinator {
        var snapshot: HUDPreviewInteractionSnapshot
        var state = HUDPreviewInteractionState()
        var onHover: @MainActor (ActiveSelection?) -> Void = { _ in }
        var onRevealChange: @MainActor (Bool) -> Void = { _ in }
        var onIntent: @MainActor (HUDPreviewIntent) -> Void = { _ in }
        var onDeleteIntent: @MainActor (HUDPreviewIntent) -> Void = { _ in }

        init(snapshot: HUDPreviewInteractionSnapshot) { self.snapshot = snapshot }

        func update(snapshot newSnapshot: HUDPreviewInteractionSnapshot) {
            if snapshot.expandedParentIndex != newSnapshot.expandedParentIndex
                || snapshot.outerVisibility != newSnapshot.outerVisibility {
                state.resetReveal()
                onRevealChange(false)
            }
            snapshot = newSnapshot
        }

        func moved(_ point: CGPoint, center: CGPoint) {
            let before = state.outerIsVisible
            onHover(state.pointerMoved(to: point, center: center, snapshot: snapshot))
            if before != state.outerIsVisible { onRevealChange(state.outerIsVisible) }
        }

        func clicked(_ point: CGPoint, center: CGPoint) {
            if let intent = state.intent(at: point, center: center, snapshot: snapshot) {
                onIntent(intent)
            }
        }

        func intent(at point: CGPoint, center: CGPoint) -> HUDPreviewIntent? {
            state.intent(at: point, center: center, snapshot: snapshot)
        }

        func delete(_ intent: HUDPreviewIntent) {
            onDeleteIntent(intent)
        }
    }
}

final class InteractionNSView: NSView {
    weak var coordinator: HUDPreviewInteractionView.Coordinator?
    private var tracking: NSTrackingArea?
    private var contextIntent: HUDPreviewIntent?
    override var isFlipped: Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let next = NSTrackingArea(rect: bounds, options: [.activeAlways, .mouseMoved, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(next)
        tracking = next
    }

    override func mouseMoved(with event: NSEvent) {
        coordinator?.moved(convert(event.locationInWindow, from: nil), center: center)
    }

    override func mouseDown(with event: NSEvent) {
        coordinator?.clicked(convert(event.locationInWindow, from: nil), center: center)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        guard let intent = coordinator?.intent(
            at: convert(event.locationInWindow, from: nil), center: center
        ) else { return nil }
        contextIntent = intent
        let menu = NSMenu()
        let item = NSMenuItem(
            title: "Delete Item", action: #selector(deleteContextItem), keyEquivalent: ""
        )
        item.target = self
        menu.addItem(item)
        return menu
    }

    @objc private func deleteContextItem() {
        guard let contextIntent else { return }
        coordinator?.delete(contextIntent)
        self.contextIntent = nil
    }

    private var center: CGPoint { CGPoint(x: bounds.midX, y: bounds.midY) }
}
