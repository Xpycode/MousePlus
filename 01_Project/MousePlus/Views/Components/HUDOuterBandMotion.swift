import SwiftUI

/// Drives one presentation-only reveal phase for the complete outer band.
///
/// The caller continues to expose the final `RadialGeometry` to hit testing.
/// Only the shapes supplied to `content` interpolate, so input never waits for
/// this view-local animation and a twelve-item full circle starts as one unit.
struct HUDOuterBandMotion<Content: View>: View {
    let descriptor: HUDMotionPresentationDescriptor
    @ViewBuilder let content: (CGFloat) -> Content

    @State private var progress: CGFloat

    init(
        descriptor: HUDMotionPresentationDescriptor,
        @ViewBuilder content: @escaping (CGFloat) -> Content
    ) {
        self.descriptor = descriptor
        self.content = content
        _progress = State(initialValue: descriptor.effect == .instant ? 1 : 0)
    }

    var body: some View {
        content(progress)
            .onAppear {
                guard descriptor.effect != .instant else {
                    progress = 1
                    return
                }
                withAnimation(.easeOut(duration: descriptor.duration)) {
                    progress = 1
                }
            }
    }
}

/// Render geometry for one outer wedge at a point in the reveal. This is kept
/// pure so localized and full-circle behavior can be verified without relying
/// on animation timing or mutating `RingViewModel`.
struct HUDOuterBandMotionFrame: Equatable {
    let startAngle: Angle
    let endAngle: Angle
    let innerRadius: CGFloat
    let outerRadius: CGFloat
    let contentOpacity: Double

    static func resolve(
        layout: OuterRingLayout,
        descriptor: HUDMotionPresentationDescriptor,
        progress rawProgress: CGFloat,
        parentMidpoint: Angle,
        finalStartAngle: Angle,
        finalEndAngle: Angle,
        innerRadius: CGFloat,
        outerRadius: CGFloat
    ) -> Self {
        let progress = min(max(rawProgress, 0), 1)

        switch descriptor.effect {
        case .instant:
            return final(
                startAngle: finalStartAngle,
                endAngle: finalEndAngle,
                innerRadius: innerRadius,
                outerRadius: outerRadius
            )
        case .fade:
            return Self(
                startAngle: finalStartAngle,
                endAngle: finalEndAngle,
                innerRadius: innerRadius,
                outerRadius: outerRadius,
                contentOpacity: Double(progress)
            )
        case .radialReveal:
            let startAngle: Angle
            let endAngle: Angle
            switch layout {
            case .localizedArc:
                startAngle = interpolate(parentMidpoint, finalStartAngle, progress: progress)
                endAngle = interpolate(parentMidpoint, finalEndAngle, progress: progress)
            case .fullCircle:
                // Keep every Apps wedge at its final angle so the whole ring
                // grows outward together rather than sweeping clockwise.
                startAngle = finalStartAngle
                endAngle = finalEndAngle
            }
            return Self(
                startAngle: startAngle,
                endAngle: endAngle,
                innerRadius: innerRadius,
                outerRadius: interpolate(innerRadius, outerRadius, progress: progress),
                contentOpacity: Double(progress)
            )
        case .emphasis, .circularSweep, .irisReveal, .bloom, .staggeredSegments:
            // Outer expansion never requests hover or summon-only effects.
            // Falling back to final geometry is safer than coupling roles.
            return final(
                startAngle: finalStartAngle,
                endAngle: finalEndAngle,
                innerRadius: innerRadius,
                outerRadius: outerRadius
            )
        }
    }

    private static func final(
        startAngle: Angle,
        endAngle: Angle,
        innerRadius: CGFloat,
        outerRadius: CGFloat
    ) -> Self {
        Self(
            startAngle: startAngle,
            endAngle: endAngle,
            innerRadius: innerRadius,
            outerRadius: outerRadius,
            contentOpacity: 1
        )
    }

    private static func interpolate(_ start: Angle, _ end: Angle, progress: CGFloat) -> Angle {
        .radians(start.radians + (end.radians - start.radians) * Double(progress))
    }

    private static func interpolate(_ start: CGFloat, _ end: CGFloat, progress: CGFloat) -> CGFloat {
        start + (end - start) * progress
    }
}
