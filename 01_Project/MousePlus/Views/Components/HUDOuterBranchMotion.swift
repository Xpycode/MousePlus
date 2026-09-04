import SwiftUI

/// Item values distinguish content generations even if a static item's ID is
/// preserved during an edit. Hover/icon presentation never changes this key.
struct HUDOuterBranchIdentity: Hashable {
    let parentID: UUID?
    let items: [RingMenuItem]
}

/// View-local history: a pending dynamic fetch remembers whether it replaced a
/// branch, but never retains that branch's items or participates in interaction.
struct HUDOuterBranchMotionState: Equatable {
    private(set) var identity = HUDOuterBranchIdentity(parentID: nil, items: [])
    private(set) var isReplacement = false

    func updating(_ next: HUDOuterBranchIdentity) -> Self {
        guard next != identity else { return self }
        var result = self
        result.identity = next
        if next.parentID == nil {
            result.isReplacement = false
        } else if next.parentID != identity.parentID {
            result.isReplacement = identity.parentID != nil
        } else if !identity.items.isEmpty {
            result.isReplacement = true
        }
        return result
    }
}

/// The incoming branch has its own reveal/fade phase. Only removal fades here.
/// Outgoing content loses accessibility immediately; the root owns pointer input.
struct HUDOuterBranchTransition: Transition {
    func body(content: Content, phase: TransitionPhase) -> some View {
        content
            .opacity(phase == .didDisappear ? 0 : 1)
            .accessibilityHidden(phase == .didDisappear)
            .allowsHitTesting(phase != .didDisappear)
    }
}

/// Frozen render inputs prevent an outgoing Apps branch from borrowing Snap's
/// geometry, labels, or icons while SwiftUI finishes its removal transition.
struct HUDOuterWedgeSnapshot: Identifiable {
    let item: RingMenuItem
    let iconSource: IconSource
    let startAngle: Angle
    let endAngle: Angle
    let radii: BandRadii
    let centroid: CGPoint
    let size: CGFloat
    let layout: OuterRingLayout
    let parentMidpoint: Angle
    let labelPresentation: LabelPresentation
    let presentation: WedgePresentation
    let isHighlighted: Bool
    let hoverMotion: HUDMotionPresentationDescriptor
    let showsSelectionMarker: Bool

    var id: UUID { item.id }

    func render(descriptor: HUDMotionPresentationDescriptor, progress: CGFloat) -> some View {
        let frame = HUDOuterBandMotionFrame.resolve(
            layout: layout, descriptor: descriptor, progress: progress,
            parentMidpoint: parentMidpoint,
            finalStartAngle: startAngle, finalEndAngle: endAngle,
            innerRadius: radii.r2, outerRadius: radii.r3
        )
        return ZStack {
            OuterWedgeBacking(
                startAngle: frame.startAngle, endAngle: frame.endAngle,
                innerRadius: frame.innerRadius, outerRadius: frame.outerRadius, size: size
            )
            .accessibilityHidden(true)

            WedgeView(
                item: item, iconSource: iconSource,
                startAngle: frame.startAngle, endAngle: frame.endAngle,
                contentStartAngle: startAngle, contentEndAngle: endAngle,
                innerRadius: frame.innerRadius, outerRadius: frame.outerRadius,
                contentInnerRadius: radii.r2, contentOuterRadius: radii.r3,
                centroid: centroid, size: size, labelPresentation: labelPresentation,
                isHighlighted: isHighlighted, dimmed: false,
                presentation: presentation, hoverMotion: hoverMotion,
                showsSelectionMarker: showsSelectionMarker
            )
            .accessibilityHidden(true)
        }
        .opacity(frame.contentOpacity)
    }
}
