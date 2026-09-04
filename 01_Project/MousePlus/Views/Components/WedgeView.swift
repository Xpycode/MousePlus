import SwiftUI

/// Testable radial bounds for the material surfaces rendered by the ring.
struct RingSurfacePresentation: Equatable {
    let persistentOuterRadius: CGFloat
    let localizedOuterInnerRadius: CGFloat?
    let localizedOuterOuterRadius: CGFloat?

    init(radii: BandRadii, isOuterRingVisible: Bool) {
        persistentOuterRadius = radii.r2
        localizedOuterInnerRadius = isOuterRingVisible ? radii.r2 : nil
        localizedOuterOuterRadius = isOuterRingVisible ? radii.r3 : nil
    }
}

/// Material surface for one localized outer-ring segment. The caller owns the
/// policy gate; keeping this shape separate from `WedgeView` lets translucent
/// configured wedge colors sit on material without extending the persistent
/// circular backing beyond r2.
struct OuterWedgeBacking: View {
    let startAngle: Angle
    let endAngle: Angle
    let innerRadius: CGFloat
    let outerRadius: CGFloat
    let size: CGFloat

    var body: some View {
        AnnularWedge(
            startAngle: startAngle,
            endAngle: endAngle,
            innerRadius: innerRadius,
            outerRadius: outerRadius
        )
        .fill(.ultraThinMaterial)
        .frame(width: size, height: size)
    }
}

/// Renders ONE wedge of the concentric ring menu: an annular slice plus its
/// icon (and, for labeled bands, a caption) anchored at the wedge centroid.
///
/// Replaces the old inline `RingItemView` from the legacy circular layout
/// (see `RingMenuView.swift`). Visual idiom is matched: accent fill + white
/// glyph when highlighted, `Color.secondary.opacity(0.2)` fill + `.primary`
/// glyph otherwise, icon at `.title2`, label at `.caption`.
///
/// ## Coordinate space (the key invariant)
/// `WedgeView` draws into a **square of side `size`** (`size == 2 · r3`, the
/// outer band's outer edge). Because `AnnularWedge.path(in:)` uses the rect's
/// center as the arc center, filling the whole square makes the slice concentric
/// with the menu center by construction. The caller (T6) computes the glyph
/// anchor with `RadialGeometry.centroid(...)` **in that same square's local
/// space** (i.e. center == `size/2`) and passes it as `centroid`; this view then
/// `.position(centroid)`s the glyph, so slice and glyph share one origin and the
/// glyph lands at the band mid-radius / wedge mid-angle.
///
/// The caller is responsible for centering this `size × size` view on the menu
/// center inside its parent `ZStack`.
struct WedgeView: View {
    /// The menu item this wedge represents.
    let item: RingMenuItem
    /// Wedge angular start (view space, CW from +x). From `RadialGeometry.wedgeAngles`.
    let startAngle: Angle
    /// Wedge angular end (view space, CW from +x). From `RadialGeometry.wedgeAngles`.
    let endAngle: Angle
    /// Band inner radial edge.
    let innerRadius: CGFloat
    /// Band outer radial edge.
    let outerRadius: CGFloat
    /// Glyph anchor in this view's local space (center == `size/2`).
    /// From `RadialGeometry.centroid` mapped to a `center = (size/2, size/2)`.
    let centroid: CGPoint
    /// Full side length of the square this view fills (`2 · r3`). Guarantees the
    /// slice's arc center coincides with the menu center.
    let size: CGFloat
    /// Resolved caption visibility and readable rotation, independent of icon
    /// presentation. Governs the `Text` only — the icon and chevron never move.
    let labelPresentation: LabelPresentation
    /// This wedge is the active selection → accent fill, white glyph.
    let isHighlighted: Bool
    /// Off the live branch → drop the whole wedge to `dimOpacity` (§2.3).
    let dimmed: Bool
    /// Opacity applied when `dimmed` (config-driven, default 0.30; §2.3).
    let dimOpacity: Double
    /// Fully resolved colors, orientation, and interaction state.
    let presentation: WedgePresentation
    /// Editor-only persistent selection. This neutral marker is independent of
    /// hover emphasis so it never changes the configured fill or glyph colors.
    let showsSelectionMarker: Bool
    let showsExpandAffordance: Bool

    init(
        item: RingMenuItem,
        startAngle: Angle,
        endAngle: Angle,
        innerRadius: CGFloat,
        outerRadius: CGFloat,
        centroid: CGPoint,
        size: CGFloat,
        labelPresentation: LabelPresentation? = nil,
        isHighlighted: Bool = false,
        dimmed: Bool = false,
        dimOpacity: Double = 0.30,
        presentation: WedgePresentation? = nil,
        showsSelectionMarker: Bool = false,
        showsExpandAffordance: Bool = true
    ) {
        self.item = item
        self.startAngle = startAngle
        self.endAngle = endAngle
        self.innerRadius = innerRadius
        self.outerRadius = outerRadius
        self.centroid = centroid
        self.size = size
        self.labelPresentation = labelPresentation ?? LabelPresentation(
            accessibilityLabel: item.label,
            orientation: .upright,
            isVisible: true,
            startAngle: startAngle,
            endAngle: endAngle
        )
        self.isHighlighted = isHighlighted
        self.dimmed = dimmed
        self.dimOpacity = dimOpacity
        self.presentation = presentation ?? .applicationDefault(
            selected: isHighlighted,
            offBranch: dimmed && !isHighlighted,
            dimOpacity: dimOpacity
        )
        self.showsSelectionMarker = showsSelectionMarker
        self.showsExpandAffordance = showsExpandAffordance
    }

    // Highlight implies the live branch, so a highlighted wedge is never dimmed.
    private var effectiveOpacity: Double { presentation.opacity }

    private var slice: AnnularWedge {
        AnnularWedge(
            startAngle: startAngle,
            endAngle: endAngle,
            innerRadius: innerRadius,
            outerRadius: outerRadius
        )
    }

    private var fillColor: Color {
        Color(nsColor: presentation.wedgeColor.nsColor)
    }

    private var normalizedMidpoint: Angle {
        let start = startAngle.degrees
        var sweep = endAngle.degrees - start
        if sweep < 0 { sweep += 360 }
        let midpoint = (start + sweep / 2).truncatingRemainder(dividingBy: 360)
        return .degrees(midpoint < 0 ? midpoint + 360 : midpoint)
    }

    var body: some View {
        ZStack {
            // Slice background — concentric with the menu center because the
            // shape fills the full `size × size` square.
            slice
                .fill(fillColor)
                .overlay(slice.fill(Color.accentColor.opacity(presentation.emphasisOpacity)))
                .overlay(
                    slice.stroke(Color.white.opacity(presentation.borderOpacity), lineWidth: 1)
                )
                .overlay(
                    slice.stroke(
                        Color.primary.opacity(showsSelectionMarker ? 0.8 : 0),
                        style: StrokeStyle(lineWidth: 2, dash: [4, 3])
                    )
                )

            glyph
                .position(centroid)
        }
        .frame(width: size, height: size)
        .opacity(effectiveOpacity)
    }

    @ViewBuilder
    private var glyph: some View {
        let iconColor = Color(nsColor: presentation.iconColor.nsColor)
        let labelColor = Color(nsColor: presentation.labelColor.nsColor)

        if labelPresentation.isCaptionVisible {
            VStack(spacing: 4) {
                HStack(spacing: 3) {
                    OrientedHUDIcon(
                        systemName: SFSymbol.resolved(item.icon),
                        orientation: presentation.orientation,
                        wedgeMidpoint: normalizedMidpoint,
                        color: iconColor
                    )
                    // Subtle "expandable" hint for items with sub-items.
                    if item.hasSubItems && showsExpandAffordance {
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(iconColor.opacity(0.7))
                    }
                }
                Text(item.label)
                    .font(.caption)
                    .lineLimit(1)
                    .foregroundStyle(labelColor)
                    // Rotate only the caption, around its own center — the
                    // icon/chevron above keep their independently resolved
                    // orientation untouched.
                    .rotationEffect(.degrees(labelPresentation.rotationDegrees))
            }
        } else {
            OrientedHUDIcon(
                systemName: SFSymbol.resolved(item.icon),
                orientation: presentation.orientation,
                wedgeMidpoint: normalizedMidpoint,
                color: iconColor
            )
        }
    }
}

#Preview {
    // Build a realistic partial ring using RadialGeometry so the component is
    // verifiable with /preview. N = 6 spokes; one middle wedge is expandable.
    let radii = BandRadii()           // r0=24, r1=78, r2=150, r3=224
    let size = radii.r3 * 2           // full square side
    let center = CGPoint(x: size / 2, y: size / 2)
    let N = 6

    func centroid(_ band: Band, _ index: Int) -> CGPoint {
        RadialGeometry.centroid(
            band: band, index: index, center: center, radii: radii,
            spokeCount: N, expandedParentIndex: nil, outerCount: 0
        )
    }
    func angles(_ band: Band, _ index: Int) -> (start: Angle, end: Angle) {
        RadialGeometry.wedgeAngles(
            band: band, index: index, spokeCount: N,
            expandedParentIndex: nil, outerCount: 0
        )
    }

    let inner = RingMenuItem(label: "Copy", icon: "doc.on.doc", actionType: .custom)
    let labeled = RingMenuItem(label: "Snap", icon: "rectangle.split.2x1", actionType: .windowSnap)
    let expandable = RingMenuItem(
        label: "Apps", icon: "square.grid.2x2", actionType: .appSwitch,
        subItems: [RingMenuItem(label: "Safari", icon: "safari", actionType: .appSwitch)]
    )

    return ZStack {
        // Symbol-only inner wedge (index 0).
        WedgeView(
            item: inner,
            startAngle: angles(.inner, 0).start, endAngle: angles(.inner, 0).end,
            innerRadius: radii.r0, outerRadius: radii.r1,
            centroid: centroid(.inner, 0), size: size,
            labelPresentation: LabelPresentation(
                accessibilityLabel: inner.label, orientation: .upright, isVisible: false,
                startAngle: angles(.inner, 0).start, endAngle: angles(.inner, 0).end
            )
        )

        // Labeled middle wedge (index 1).
        WedgeView(
            item: labeled,
            startAngle: angles(.middle, 1).start, endAngle: angles(.middle, 1).end,
            innerRadius: radii.r1, outerRadius: radii.r2,
            centroid: centroid(.middle, 1), size: size
        )

        // Highlighted expandable middle wedge (index 2) — shows chevron hint.
        WedgeView(
            item: expandable,
            startAngle: angles(.middle, 2).start, endAngle: angles(.middle, 2).end,
            innerRadius: radii.r1, outerRadius: radii.r2,
            centroid: centroid(.middle, 2), size: size,
            isHighlighted: true
        )

        // Dimmed middle wedge (index 3) — off the live branch.
        WedgeView(
            item: labeled,
            startAngle: angles(.middle, 3).start, endAngle: angles(.middle, 3).end,
            innerRadius: radii.r1, outerRadius: radii.r2,
            centroid: centroid(.middle, 3), size: size,
            dimmed: true
        )

    }
    .frame(width: size, height: size)
    .background(Color.black.opacity(0.85))
}
