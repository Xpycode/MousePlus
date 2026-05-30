import SwiftUI

/// A filled annular sector ("donut slice") spanning two radii and two angles.
///
/// Geometry conventions (must match the hit-testing model in IMPLEMENTATION_PLAN §2.2):
///
/// The plan computes selection from `theta = atan2(dy, dx)` normalized to `[0, 2π)`.
/// Because SwiftUI's y-axis points **down**, that `theta` increases in the direction
/// that reads as **clockwise on screen**, starting from the +x axis (3 o'clock).
///
/// `Path.addArc(center:radius:startAngle:endAngle:clockwise:)` is interpreted in the
/// same flipped (y-down) space, where `clockwise: false` traces the path in the
/// **increasing-angle** direction — i.e. visually clockwise on screen. So to make a
/// wedge cover exactly the angular span that `atan2` would classify into it, we sweep
/// the outer arc forward with `clockwise: false` (start → end, increasing angle), then
/// sweep the inner arc back with `clockwise: true` (end → start). The two radial lines
/// connecting them are added implicitly by the `addLine` / `addArc` continuation, and
/// `closeSubpath()` seals the figure — producing a clean fill with no artifacts.
struct AnnularWedge: Shape {
    var startAngle: Angle
    var endAngle: Angle
    var innerRadius: CGFloat
    var outerRadius: CGFloat

    /// Animate angles and radii together so resizing/sweeping is smooth.
    /// Layout: ((startRadians, endRadians), (innerRadius, outerRadius)).
    var animatableData: AnimatablePair<AnimatablePair<Double, Double>, AnimatablePair<Double, Double>> {
        get {
            AnimatablePair(
                AnimatablePair(startAngle.radians, endAngle.radians),
                AnimatablePair(Double(innerRadius), Double(outerRadius))
            )
        }
        set {
            startAngle = .radians(newValue.first.first)
            endAngle = .radians(newValue.first.second)
            innerRadius = CGFloat(newValue.second.first)
            outerRadius = CGFloat(newValue.second.second)
        }
    }

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)

        var path = Path()

        // Outer arc: start → end in the increasing-angle (screen-clockwise) direction.
        path.addArc(
            center: center,
            radius: outerRadius,
            startAngle: startAngle,
            endAngle: endAngle,
            clockwise: false
        )

        // Radial line inward to the inner arc's end point.
        let innerEnd = CGPoint(
            x: center.x + innerRadius * CGFloat(cos(endAngle.radians)),
            y: center.y + innerRadius * CGFloat(sin(endAngle.radians))
        )
        path.addLine(to: innerEnd)

        // Inner arc: end → start, reversed (screen-counter-clockwise) to walk back.
        path.addArc(
            center: center,
            radius: innerRadius,
            startAngle: endAngle,
            endAngle: startAngle,
            clockwise: true
        )

        path.closeSubpath()
        return path
    }
}

#Preview {
    let inner: CGFloat = 78
    let outer: CGFloat = 150
    let count = 6
    let step = 360.0 / Double(count)
    let highlighted = 1

    return ZStack {
        ForEach(0..<count, id: \.self) { i in
            AnnularWedge(
                startAngle: .degrees(Double(i) * step),
                endAngle: .degrees(Double(i + 1) * step),
                innerRadius: inner,
                outerRadius: outer
            )
            .fill(i == highlighted
                  ? Color.accentColor.opacity(0.85)
                  : Color.secondary.opacity(0.25))
            .overlay(
                AnnularWedge(
                    startAngle: .degrees(Double(i) * step),
                    endAngle: .degrees(Double(i + 1) * step),
                    innerRadius: inner,
                    outerRadius: outer
                )
                .stroke(Color.white.opacity(0.4), lineWidth: 1)
            )
        }
    }
    .frame(width: outer * 2 + 20, height: outer * 2 + 20)
    .background(Color.black.opacity(0.8))
}
