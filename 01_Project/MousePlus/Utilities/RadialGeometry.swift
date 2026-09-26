import SwiftUI
import CoreGraphics
import Foundation

/// One of the three concentric interactive bands of the ring menu.
///
/// See `IMPLEMENTATION_PLAN.md` §2.1. The dead zone (radius `0…r0`) is not a
/// `Band` value — hit-testing returns `nil` there.
enum Band: Equatable {
    /// Inner symbol-only band (`r0…r1`).
    case inner
    /// Middle labeled band (`r1…r2`).
    case middle
    /// On-demand outer band (`r2…r3`) expanded from a parent middle wedge.
    /// Its layout may be a localized arc or a full circle and has item count `M`.
    case outer
}

/// How an expanded middle item distributes its children around the outer band.
/// Static submenus keep the compact parent-centered arc; the running-app
/// switcher uses a complete circle with its first (MRU) item centered on the
/// parent direction so the pointer can continue straight outward.
enum OuterRingLayout: Equatable {
    case localizedArc
    case fullCircle
}

/// Angular layout for one top-level ring band.
///
/// `slotCount` is the effective (auto or fixed) count, including any invisible
/// empty positions. `angularOffset` is normalized to `[0, 2π)` so equivalent
/// persisted rotations produce identical geometry.
struct RingBandGeometry: Equatable {
    let slotCount: Int
    let angularOffset: CGFloat

    init(slotCount: Int, angularOffset: CGFloat = 0) {
        self.slotCount = max(1, slotCount)
        self.angularOffset = RadialGeometry.normalizedAngle(angularOffset)
    }
}

/// Independent geometry for the two top-level bands. Outer geometry is derived
/// from the middle parent, so it deliberately has no independent entry here.
struct TopLevelRingGeometry: Equatable {
    let inner: RingBandGeometry
    let middle: RingBandGeometry

    init(inner: RingBandGeometry, middle: RingBandGeometry) {
        self.inner = inner
        self.middle = middle
    }

    static func shared(spokeCount: Int, angularOffset: CGFloat = 0) -> Self {
        let band = RingBandGeometry(slotCount: spokeCount, angularOffset: angularOffset)
        return Self(inner: band, middle: band)
    }

    func geometry(for band: Band) -> RingBandGeometry {
        switch band {
        case .inner: return inner
        case .middle, .outer: return middle
        }
    }
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

    /// Derives the legacy shared spoke count used by compatibility callers.
    ///
    /// New customization-aware callers supply `TopLevelRingGeometry` instead.
    /// Guaranteed `≥ 1` so the legacy wedge width remains well-defined.
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
                        geometry: TopLevelRingGeometry,
                        innerItemCount: Int,
                        middleItemCount: Int,
                        expandedParentIndex: Int?,
                        outerCount M: Int,
                        outerLayout: OuterRingLayout = .localizedArc)
    -> (band: Band, index: Int)? {
        let dx = point.x - center.x
        let dy = point.y - center.y
        let dist = hypot(dx, dy)
        let theta = normalizedAngle(atan2(dy, dx))

        if dist <= radii.r0 { return nil }

        if dist <= radii.r1 {
            let index = topLevelIndex(theta: theta, geometry: geometry.inner)
            return index < max(0, innerItemCount) ? (.inner, index) : nil
        }

        if dist <= radii.r2 {
            let index = topLevelIndex(theta: theta, geometry: geometry.middle)
            return index < max(0, middleItemCount) ? (.middle, index) : nil
        }

        if dist <= radii.r3,
           let parent = expandedParentIndex,
           parent >= 0,
           parent < max(0, middleItemCount),
           M > 0 {
            let span = outerArcSpan(parentIndex: parent,
                                    parentGeometry: geometry.middle,
                                    outerCount: M,
                                    layout: outerLayout)
            let start = CGFloat(span.start.radians)
            let total = CGFloat(span.end.radians) - start
            let rawOffset = normalizedAngle(theta - start)
            let tolerance = 16 * CGFloat.ulpOfOne * max(1, abs(total))
            // `atan2(sin(a), cos(a))` can put an exact wrapped start a few
            // ulps below 2π, or an exact end a few ulps below `total`.
            // Preserve the documented half-open arc `[start, end)` by snapping
            // only those representational seams, not nearby real points.
            let offset = twoPi - rawOffset <= tolerance ? 0 : rawOffset
            guard total - offset > tolerance else { return nil }

            let perItem = total / CGFloat(M)
            return (.outer, clamp(Int(floor(offset / perItem)), lower: 0, upper: M - 1))
        }

        return nil
    }

    /// Compatibility entry point for the pre-customization shared-spoke model.
    static func hitTest(point: CGPoint,
                        center: CGPoint,
                        radii: BandRadii,
                        spokeCount N: Int,
                        expandedParentIndex: Int?,
                        outerCount M: Int) -> (band: Band, index: Int)? {
        let n = max(1, N)
        return hitTest(point: point, center: center, radii: radii,
                       geometry: .shared(spokeCount: n),
                       innerItemCount: n, middleItemCount: n,
                       expandedParentIndex: expandedParentIndex, outerCount: M)
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
                            geometry: TopLevelRingGeometry,
                            expandedParentIndex: Int?,
                            outerCount M: Int,
                            outerLayout: OuterRingLayout = .localizedArc) -> (start: Angle, end: Angle) {
        switch band {
        case .inner, .middle:
            let bandGeometry = geometry.geometry(for: band)
            let wedge = twoPi / CGFloat(bandGeometry.slotCount)
            let i = clamp(index, lower: 0, upper: bandGeometry.slotCount - 1)
            let start = bandGeometry.angularOffset + CGFloat(i) * wedge
            return (.radians(Double(start)), .radians(Double(start + wedge)))
        case .outer:
            let m = max(1, M)
            let span = outerArcSpan(parentIndex: expandedParentIndex ?? 0,
                                    parentGeometry: geometry.middle,
                                    outerCount: m,
                                    layout: outerLayout)
            let start = CGFloat(span.start.radians)
            let perItem = (CGFloat(span.end.radians) - start) / CGFloat(m)
            let i = clamp(index, lower: 0, upper: m - 1)
            let itemStart = start + CGFloat(i) * perItem
            return (.radians(Double(itemStart)), .radians(Double(itemStart + perItem)))
        }
    }

    /// Compatibility entry point for the pre-customization shared-spoke model.
    static func wedgeAngles(band: Band,
                            index: Int,
                            spokeCount N: Int,
                            expandedParentIndex: Int?,
                            outerCount M: Int) -> (start: Angle, end: Angle) {
        wedgeAngles(band: band, index: index, geometry: .shared(spokeCount: N),
                    expandedParentIndex: expandedParentIndex, outerCount: M)
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
                         geometry: TopLevelRingGeometry,
                         expandedParentIndex: Int?,
                         outerCount M: Int,
                         outerLayout: OuterRingLayout = .localizedArc) -> CGPoint {
        let (start, end) = wedgeAngles(band: band, index: index,
                                       geometry: geometry,
                                       expandedParentIndex: expandedParentIndex,
                                       outerCount: M,
                                       outerLayout: outerLayout)
        return centroid(band: band, center: center, radii: radii,
                        start: start, end: end)
    }

    /// Compatibility entry point for the pre-customization shared-spoke model.
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
        return centroid(band: band, center: center, radii: radii,
                        start: start, end: end)
    }

    private static func centroid(band: Band, center: CGPoint, radii: BandRadii,
                                 start: Angle, end: Angle) -> CGPoint {
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
                             parentGeometry: RingBandGeometry,
                             outerCount M: Int,
                             layout: OuterRingLayout = .localizedArc)
    -> (start: Angle, end: Angle) {
        let n = parentGeometry.slotCount
        let m = max(1, M)
        let wedge = twoPi / CGFloat(n)
        let parent = clamp(p, lower: 0, upper: n - 1)
        let parentMid = parentGeometry.angularOffset + (CGFloat(parent) + 0.5) * wedge
        switch layout {
        case .localizedArc:
            let span = min(twoPi, max(wedge, CGFloat(m) * wedge / 3))
            return (.radians(Double(parentMid - span / 2)),
                    .radians(Double(parentMid + span / 2)))
        case .fullCircle:
            let perItem = twoPi / CGFloat(m)
            let start = parentMid - perItem / 2
            return (.radians(Double(start)),
                    .radians(Double(start + twoPi)))
        }
    }

    /// Compatibility entry point for zero-offset shared-spoke geometry.
    static func outerArcSpan(parentIndex p: Int,
                             spokeCount N: Int,
                             outerCount M: Int) -> (start: Angle, end: Angle) {
        outerArcSpan(parentIndex: p,
                     parentGeometry: RingBandGeometry(slotCount: N),
                     outerCount: M)
    }

    // MARK: - Helpers

    /// Returns the target slot whose angular region contains the source slot's
    /// midpoint. This replaces legacy same-index "shared spoke" assumptions for
    /// presentation such as keeping the inner branch lit during expansion.
    static func alignedIndex(sourceIndex: Int,
                             sourceGeometry: RingBandGeometry,
                             targetGeometry: RingBandGeometry) -> Int {
        let sourceWidth = twoPi / CGFloat(sourceGeometry.slotCount)
        let source = min(max(0, sourceIndex), sourceGeometry.slotCount - 1)
        let midpoint = sourceGeometry.angularOffset
            + (CGFloat(source) + 0.5) * sourceWidth
        return topLevelIndex(theta: normalizedAngle(midpoint), geometry: targetGeometry)
    }

    /// Normalizes an angle (radians) into `[0, 2π)`.
    static func normalizedAngle(_ angle: CGFloat) -> CGFloat {
        var a = angle.truncatingRemainder(dividingBy: twoPi)
        if a < 0 { a += twoPi }
        // Guard against `a == 2π` from FP rounding of a small negative input.
        if a >= twoPi { a -= twoPi }
        return a
    }

    private static func topLevelIndex(theta: CGFloat,
                                      geometry: RingBandGeometry) -> Int {
        let relative = normalizedAngle(theta - geometry.angularOffset)
        let wedge = twoPi / CGFloat(geometry.slotCount)
        return clamp(Int(floor(relative / wedge)), lower: 0,
                     upper: geometry.slotCount - 1)
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
