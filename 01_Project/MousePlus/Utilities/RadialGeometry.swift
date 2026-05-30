import SwiftUI
import CoreGraphics
import Foundation

/// One of the three concentric interactive bands of the ring menu.
///
/// See `IMPLEMENTATION_PLAN.md` §2.1. The dead zone (radius `0…r0`) is not a
/// `Band` value — hit-testing returns `nil` there.
enum Band: Equatable {
    /// Inner symbol-only band (`r0…r1`). Shares spoke geometry with `.middle`.
    case inner
    /// Middle labeled band (`r1…r2`). Shares spoke geometry with `.inner`.
    case middle
    /// On-demand outer band (`r2…r3`) — a localized arc expanded from a parent
    /// middle wedge. Has its own item count `M`.
    case outer
}

/// Band edge radii (default values from `IMPLEMENTATION_PLAN.md` §2.1).
///
/// These will eventually be supplied by `AppearanceConfig`; callers may pass an
/// alternate set. Invariant expected by the math: `0 ≤ r0 < r1 < r2 < r3`.
struct BandRadii {
    /// Dead-zone outer edge (cancel/back region).
    var r0: CGFloat = 24
    /// Inner band outer edge.
    var r1: CGFloat = 78
    /// Middle band outer edge.
    var r2: CGFloat = 150
    /// Outer band outer edge.
    var r3: CGFloat = 224

    init(r0: CGFloat = 24, r1: CGFloat = 78, r2: CGFloat = 150, r3: CGFloat = 224) {
        self.r0 = r0
        self.r1 = r1
        self.r2 = r2
        self.r3 = r3
    }
}

/// Pure, stateless math for the concentric ring menu's band/angle geometry.
///
/// No SwiftUI views, no app state — every function is a deterministic transform
/// of its inputs, so the geometry can be unit-tested and audited in isolation.
///
/// ## Coordinate convention
/// All math is in **view space**, where `+y` points **down** (SwiftUI / AppKit
/// `NSHostingView`). Consequently `atan2(dy, dx)` increases **clockwise** on
/// screen, starting from the `+x` axis (straight right of center). Angles are
/// normalized to `[0, 2π)`. This matches `IMPLEMENTATION_PLAN.md` §2.2 exactly.
enum RadialGeometry {

    /// Full turn in radians (`2π`).
    static let twoPi: CGFloat = 2 * .pi

    // MARK: - Spoke count

    /// The locked spoke count `N` shared by the inner and middle bands.
    ///
    /// `N = min(8, max(innerCount, middleCount))` (§2.1). Both bands render `N`
    /// angular wedges on the same divider lines; the shorter band pads the
    /// remainder with dim placeholders. Guaranteed `≥ 1` so wedge width is
    /// well-defined even when both counts are zero/empty.
    static func spokeCount(innerCount: Int, middleCount: Int) -> Int {
        max(1, min(8, max(innerCount, middleCount)))
    }

    // MARK: - Hit-testing (§2.2)

    /// Maps a pointer location to the band + item index it selects, or `nil`
    /// for the dead zone / out-of-bounds (§2.2).
    ///
    /// Selection follows cursor *direction* (angle) + *distance* (radius), not
    /// per-wedge polygon containment — this avoids boundary flicker.
    ///
    /// - Parameters:
    ///   - point: Pointer location in view space (`+y` down).
    ///   - center: Ring center in view space.
    ///   - radii: Band edge radii.
    ///   - N: Locked spoke count for inner/middle (see `spokeCount`).
    ///   - expandedParentIndex: The currently expanded middle wedge, if any.
    ///     Required for the outer band to be hittable.
    ///   - M: Item count of the outer band.
    /// - Returns: `(band, index)` with `index` clamped to the band's valid
    ///   range, or `nil` for the dead zone or angles outside the outer arc.
    static func hitTest(point: CGPoint,
                        center: CGPoint,
                        radii: BandRadii,
                        spokeCount N: Int,
                        expandedParentIndex: Int?,
                        outerCount M: Int) -> (band: Band, index: Int)? {
        let dx = point.x - center.x
        let dy = point.y - center.y
        let dist = hypot(dx, dy)
        let theta = normalizedAngle(atan2(dy, dx))

        // Dead zone / cancel region.
        if dist <= radii.r0 { return nil }

        let n = max(1, N)
        let wedge = twoPi / CGFloat(n)

        if dist <= radii.r1 {
            let index = clamp(Int(floor(theta / wedge)), lower: 0, upper: n - 1)
            return (.inner, index)
        }

        if dist <= radii.r2 {
            let index = clamp(Int(floor(theta / wedge)), lower: 0, upper: n - 1)
            return (.middle, index)
        }

        if dist <= radii.r3,
           let parent = expandedParentIndex,
           M > 0 {
            let span = outerArcSpan(parentIndex: parent, spokeCount: n, outerCount: M)
            let start = CGFloat(span.start.radians)
            let total = CGFloat(span.end.radians) - start // always ≥ 0 (see outerArcSpan)

            // Angular offset of theta from the arc start, measured forward
            // (clockwise) and wrapped into [0, 2π). Inside the arc ⇔ offset < total.
            let offset = normalizedAngle(theta - start)
            guard offset < total else { return nil }

            let perItem = total / CGFloat(M)
            let index = clamp(Int(floor(offset / perItem)), lower: 0, upper: M - 1)
            return (.outer, index)
        }

        return nil
    }

    // MARK: - Wedge angles

    /// The `[start, end]` angular span of a wedge, in view-space radians
    /// (clockwise from `+x`).
    ///
    /// For `.inner` / `.middle`, wedge `i` spans `[i·(2π/N), (i+1)·(2π/N)]`.
    /// For `.outer`, returns the `index`-th sub-slice of the parent arc span
    /// (see `outerArcSpan`).
    static func wedgeAngles(band: Band,
                            index: Int,
                            spokeCount N: Int,
                            expandedParentIndex: Int?,
                            outerCount M: Int) -> (start: Angle, end: Angle) {
        switch band {
        case .inner, .middle:
            let n = max(1, N)
            let wedge = twoPi / CGFloat(n)
            let i = clamp(index, lower: 0, upper: n - 1)
            let start = CGFloat(i) * wedge
            return (.radians(Double(start)), .radians(Double(start + wedge)))

        case .outer:
            let m = max(1, M)
            let parent = expandedParentIndex ?? 0
            let span = outerArcSpan(parentIndex: parent, spokeCount: N, outerCount: m)
            let start = CGFloat(span.start.radians)
            let total = CGFloat(span.end.radians) - start
            let perItem = total / CGFloat(m)
            let i = clamp(index, lower: 0, upper: m - 1)
            let s = start + CGFloat(i) * perItem
            return (.radians(Double(s)), .radians(Double(s + perItem)))
        }
    }

    // MARK: - Centroid

    /// The point at the angular midpoint of a wedge and the radial midpoint of
    /// its band — the natural anchor for an icon or label.
    ///
    /// Uses view-space mapping (`+y` down):
    /// `x = center.x + r·cos(mid)`, `y = center.y + r·sin(mid)`.
    static func centroid(band: Band,
                         index: Int,
                         center: CGPoint,
                         radii: BandRadii,
                         spokeCount N: Int,
                         expandedParentIndex: Int?,
                         outerCount M: Int) -> CGPoint {
        let (start, end) = wedgeAngles(band: band,
                                       index: index,
                                       spokeCount: N,
                                       expandedParentIndex: expandedParentIndex,
                                       outerCount: M)
        let midAngle = CGFloat((start.radians + end.radians) / 2)

        let r: CGFloat
        switch band {
        case .inner:  r = (radii.r0 + radii.r1) / 2
        case .middle: r = (radii.r1 + radii.r2) / 2
        case .outer:  r = (radii.r2 + radii.r3) / 2
        }

        return CGPoint(x: center.x + r * cos(midAngle),
                       y: center.y + r * sin(midAngle))
    }

    // MARK: - Outer arc span (§2.3)

    /// The angular span of the outer band — a **localized arc** centered on the
    /// parent wedge's mid-angle (§2.3).
    ///
    /// ## Growth formula
    /// Let the parent (inner/middle) wedge width be `w = 2π/N` and the per-item
    /// slice be `perItem = w / 3` (so the arc reads as a finer-grained fan than
    /// its parent wedge). The total span grows monotonically with `M`:
    ///
    /// ```
    /// span = min(2π, max(w, M · perItem))   where perItem = (2π/N) / 3
    /// ```
    ///
    /// - For small `M` the arc is at least one parent-wedge wide (`w`), so it
    ///   visually "belongs to" the parent.
    /// - It widens symmetrically as `M` grows, capped at a full circle (`2π`).
    /// - `M ≥ 3·N` saturates to the full `2π` ring.
    ///
    /// The span is centered on the parent's mid-angle, so the returned
    /// `(start, end)` may have `start < 0` or `end > 2π`; only `end - start`
    /// (the arc length) is normalized. `start ≤ end` always holds, and
    /// `end - start ≤ 2π`.
    static func outerArcSpan(parentIndex p: Int,
                             spokeCount N: Int,
                             outerCount M: Int) -> (start: Angle, end: Angle) {
        let n = max(1, N)
        let m = max(1, M)
        let wedge = twoPi / CGFloat(n)
        let perItem = wedge / 3

        let span = min(twoPi, max(wedge, CGFloat(m) * perItem))

        // Mid-angle of the parent wedge p (clockwise from +x).
        let pi = clamp(p, lower: 0, upper: n - 1)
        let parentMid = (CGFloat(pi) + 0.5) * wedge

        let start = parentMid - span / 2
        let end = parentMid + span / 2
        return (.radians(Double(start)), .radians(Double(end)))
    }

    // MARK: - Helpers

    /// Normalizes an angle (radians) into `[0, 2π)`.
    static func normalizedAngle(_ angle: CGFloat) -> CGFloat {
        var a = angle.truncatingRemainder(dividingBy: twoPi)
        if a < 0 { a += twoPi }
        // Guard against `a == 2π` from FP rounding of a small negative input.
        if a >= twoPi { a -= twoPi }
        return a
    }

    /// Clamps an integer into `[lower, upper]`. If `upper < lower` (empty range)
    /// returns `lower`.
    private static func clamp(_ value: Int, lower: Int, upper: Int) -> Int {
        guard upper >= lower else { return lower }
        return Swift.min(upper, Swift.max(lower, value))
    }
}

#if DEBUG
extension RadialGeometry {
    /// Sanity-check examples for the band/angle math. These document expected
    /// outputs for canonical sample points and can be exercised from a test or
    /// a debug breakpoint. Not compiled into release builds.
    ///
    /// Convention reminder: `+y` is down, so `atan2` is clockwise from `+x`.
    /// With `N = 8`, each wedge is `45°` wide and wedge `i` covers
    /// `[i·45°, (i+1)·45°)` measured clockwise from straight-right.
    static func _debugSelfCheckExamples() -> Bool {
        let radii = BandRadii() // r0=24, r1=78, r2=150, r3=224
        let center = CGPoint(x: 0, y: 0)
        let N = 8

        // Straight right, mid-inner radius (~51): angle 0 → inner wedge 0.
        let pRight = CGPoint(x: 51, y: 0)
        let rRight = hitTest(point: pRight, center: center, radii: radii,
                             spokeCount: N, expandedParentIndex: nil, outerCount: 0)
        assert(rRight?.band == .inner && rRight?.index == 0,
               "point straight right at mid-inner radius → (.inner, 0)")

        // Straight down (+y), mid-middle radius (~114): angle = π/2 (90° CW)
        // → wedge 2 (covers 90°…135°). Band middle.
        let pDown = CGPoint(x: 0, y: 114)
        let rDown = hitTest(point: pDown, center: center, radii: radii,
                            spokeCount: N, expandedParentIndex: nil, outerCount: 0)
        assert(rDown?.band == .middle && rDown?.index == 2,
               "point straight down at mid-middle radius → (.middle, 2)")

        // Inside the dead zone → nil.
        let pDead = CGPoint(x: 10, y: 0)
        let rDead = hitTest(point: pDead, center: center, radii: radii,
                            spokeCount: N, expandedParentIndex: nil, outerCount: 0)
        assert(rDead == nil, "point inside r0 → nil (dead zone)")

        // Beyond r3 → nil.
        let pFar = CGPoint(x: 300, y: 0)
        let rFar = hitTest(point: pFar, center: center, radii: radii,
                           spokeCount: N, expandedParentIndex: nil, outerCount: 0)
        assert(rFar == nil, "point beyond r3 → nil")

        // Outer band requires an expanded parent. Without one → nil.
        let pOuter = CGPoint(x: 187, y: 0) // mid-outer radius (~187)
        let rOuterNone = hitTest(point: pOuter, center: center, radii: radii,
                                 spokeCount: N, expandedParentIndex: nil, outerCount: 4)
        assert(rOuterNone == nil, "outer band with no expanded parent → nil")

        // Outer band, parent wedge 0 (mid-angle 22.5°), M=4. The arc is
        // centered on 22.5°; straight-right (0°) should fall inside it.
        let rOuter = hitTest(point: pOuter, center: center, radii: radii,
                             spokeCount: N, expandedParentIndex: 0, outerCount: 4)
        assert(rOuter?.band == .outer, "outer band with expanded parent 0 → .outer")

        return true
    }
}
#endif
