import SwiftUI

/// The concentric wedge ("pie") menu.
///
/// Two aligned rings share spoke geometry (§2.1):
///   - **inner** band: symbol-only quick actions (`r0…r1`)
///   - **middle** band: labeled items, each direct or expandable (`r1…r2`)
/// plus an **on-demand outer** band (`r2…r3`) that grows as a localized arc from
/// the expanded middle wedge (§2.3).
///
/// Hit-testing is done on a single square container via angle + radius
/// (`RingViewModel.updateActive` → `RadialGeometry.hitTest`), NOT per-wedge
/// `contentShape` — per-wedge containment causes boundary flicker / dead zones
/// (§2.2). Each `WedgeView` is purely presentational.
struct RingMenuView: View {
    @Bindable var viewModel: RingViewModel

    // T11: sourced from `AppearanceConfig` via the view model (persisted in Settings):
    //   - `keepSpokeLit`: also keep inner wedge `p` lit on the live branch (§2.3).
    //   - `animationEnabled`: instant vs animated transitions (§2.3).
    //   - `dimOpacity`: opacity of off-branch wedges when something is expanded (§2.3).
    private var keepSpokeLit: Bool { viewModel.appearance.keepSpokeLit }
    private var animationEnabled: Bool { viewModel.appearance.animationEnabled }
    private var dimOpacity: Double { viewModel.appearance.dimOpacity }
    private var animationDuration: Double { viewModel.appearance.animationDuration }

    /// Full square side — `2 · r3`. WedgeView fills this square so every slice is
    /// concentric with the menu center (its arc center == rect center).
    private var size: CGFloat { viewModel.radii.r3 * 2 }

    /// Ring center in the container's local (top-left origin) space. Matches
    /// RadialGeometry's `+y`-down convention, so gesture locations map directly.
    private var center: CGPoint { CGPoint(x: size / 2, y: size / 2) }

    private var radii: BandRadii { viewModel.radii }
    private var spokeCount: Int { viewModel.spokeCount }
    private var isExpanded: Bool { viewModel.expandedParentIndex != nil }

    var body: some View {
        ZStack {
            // Visual backing for the whole ring.
            Circle()
                .fill(.ultraThinMaterial)
                .frame(width: size, height: size)

            // Dead-zone indicator (radius ~ r0) — cancel/back region.
            Circle()
                .fill(.secondary.opacity(0.3))
                .frame(width: radii.r0 * 2, height: radii.r0 * 2)

            innerBand
            middleBand

            // Outer band — localized arc, only while expanded. Wrapped so it can
            // scale/opacity in from the parent wedge centroid (T7).
            if isExpanded {
                outerBand
                    .transition(
                        .scale(scale: 0.1, anchor: parentCentroidUnitPoint)
                            .combined(with: .opacity)
                    )
            }
        }
        .frame(width: size, height: size)
        // Single hit-test surface — the whole square is interactive (§2.2).
        .contentShape(Rectangle())
        // Animate expansion/collapse + selection changes when enabled; nil = instant.
        .animation(animationEnabled ? .spring(response: animationDuration, dampingFraction: 0.8) : nil,
                   value: viewModel.expandedParentIndex)
        .animation(animationEnabled ? .spring(response: animationDuration, dampingFraction: 0.8) : nil,
                   value: viewModel.activeSelection)
        // Pointer movement (tap-toggle / hover) drives the active wedge.
        .onContinuousHover { phase in
            if case .active(let location) = phase {
                viewModel.updateActive(at: location, center: center)
            }
            // .ended → leave selection as-is; a click commits it.
        }
        // Hold-release: drag updates the active wedge, release commits it.
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    viewModel.updateActive(at: value.location, center: center)
                }
                .onEnded { _ in
                    viewModel.commitActive()
                }
        )
        // Tap-toggle: a plain click commits the active wedge.
        .onTapGesture {
            viewModel.commitActive()
        }
    }

    // MARK: - Bands

    /// Inner symbol-only band. `N` wedges; indices past `innerItems` are dim
    /// padding placeholders so spokes stay aligned with the middle band (§2.1).
    private var innerBand: some View {
        ForEach(0..<spokeCount, id: \.self) { index in
            let angles = RadialGeometry.wedgeAngles(
                band: .inner, index: index, spokeCount: spokeCount,
                expandedParentIndex: viewModel.expandedParentIndex,
                outerCount: viewModel.outerItems.count
            )
            let isPlaceholder = index >= viewModel.innerItems.count
            WedgeView(
                item: item(in: viewModel.innerItems, at: index),
                startAngle: angles.start,
                endAngle: angles.end,
                innerRadius: radii.r0,
                outerRadius: radii.r1,
                centroid: centroid(.inner, index),
                size: size,
                symbolOnly: true,
                isHighlighted: isActive(.inner, index),
                dimmed: dimmed(band: .inner, index: index),
                dimOpacity: dimOpacity,
                isPlaceholder: isPlaceholder
            )
        }
    }

    /// Middle labeled band. Same spoke geometry as inner; placeholder past
    /// `middleItems`.
    private var middleBand: some View {
        ForEach(0..<spokeCount, id: \.self) { index in
            let angles = RadialGeometry.wedgeAngles(
                band: .middle, index: index, spokeCount: spokeCount,
                expandedParentIndex: viewModel.expandedParentIndex,
                outerCount: viewModel.outerItems.count
            )
            let isPlaceholder = index >= viewModel.middleItems.count
            WedgeView(
                item: item(in: viewModel.middleItems, at: index),
                startAngle: angles.start,
                endAngle: angles.end,
                innerRadius: radii.r1,
                outerRadius: radii.r2,
                centroid: centroid(.middle, index),
                size: size,
                symbolOnly: false,
                isHighlighted: isActive(.middle, index),
                dimmed: dimmed(band: .middle, index: index),
                dimOpacity: dimOpacity,
                isPlaceholder: isPlaceholder
            )
        }
    }

    /// Outer band — a localized arc of the expanded parent's sub-items (§2.3).
    /// Always lit (it IS the live branch).
    private var outerBand: some View {
        ForEach(0..<viewModel.outerItems.count, id: \.self) { index in
            let angles = RadialGeometry.wedgeAngles(
                band: .outer, index: index, spokeCount: spokeCount,
                expandedParentIndex: viewModel.expandedParentIndex,
                outerCount: viewModel.outerItems.count
            )
            WedgeView(
                item: viewModel.outerItems[index],
                startAngle: angles.start,
                endAngle: angles.end,
                innerRadius: radii.r2,
                outerRadius: radii.r3,
                centroid: centroid(.outer, index),
                size: size,
                symbolOnly: false,
                isHighlighted: isActive(.outer, index),
                dimmed: false,
                isPlaceholder: false
            )
        }
    }

    // MARK: - Geometry helpers

    private func centroid(_ band: Band, _ index: Int) -> CGPoint {
        RadialGeometry.centroid(
            band: band, index: index, center: center, radii: radii,
            spokeCount: spokeCount,
            expandedParentIndex: viewModel.expandedParentIndex,
            outerCount: viewModel.outerItems.count
        )
    }

    /// Scale anchor for the outer-band transition: the expanded parent (middle)
    /// wedge centroid, expressed as a `UnitPoint` (`centroid / size`) so the arc
    /// grows out of the parent wedge (§2.3).
    private var parentCentroidUnitPoint: UnitPoint {
        guard let parent = viewModel.expandedParentIndex else { return .center }
        let c = centroid(.middle, parent)
        return UnitPoint(x: c.x / size, y: c.y / size)
    }

    // MARK: - State helpers

    /// Item at `index`, or a blank placeholder item for padding wedges so
    /// `WedgeView` always has something to render.
    private func item(in items: [RingMenuItem], at index: Int) -> RingMenuItem {
        guard index >= 0, index < items.count else {
            return RingMenuItem(label: "", icon: "", actionType: .custom)
        }
        return items[index]
    }

    private func isActive(_ band: Band, _ index: Int) -> Bool {
        viewModel.activeSelection == ActiveSelection(band: band, index: index)
    }

    /// Dimming (§2.3): when something is expanded, everything dims to 0.30 EXCEPT
    /// the live branch — the expanded middle wedge (and, if `keepSpokeLit`, its
    /// aligned inner wedge). Outer wedges pass `dimmed: false` directly. When
    /// nothing is expanded, nothing is dimmed.
    private func dimmed(band: Band, index: Int) -> Bool {
        guard let parent = viewModel.expandedParentIndex else { return false }
        switch band {
        case .middle:
            return index != parent
        case .inner:
            return !(keepSpokeLit && index == parent)
        case .outer:
            return false
        }
    }
}

// MARK: - Previews

/// REST state — two aligned rings, with one middle wedge pre-highlighted.
#Preview("Rest") {
    let viewModel = RingViewModel()
    viewModel.innerItems = RingMenuItem.sampleInnerItems
    viewModel.middleItems = RingMenuItem.sampleItems
    viewModel.activeSelection = ActiveSelection(band: .middle, index: 1)

    return RingMenuView(viewModel: viewModel)
        .padding(40)
        .background(Color.black.opacity(0.6))
}

/// EXPANDED state — an outer arc radiating from a parent middle wedge, rest dimmed.
#Preview("Expanded") {
    let viewModel = RingViewModel()
    viewModel.innerItems = RingMenuItem.sampleInnerItems
    viewModel.middleItems = RingMenuItem.sampleItems

    // Expand the first middle wedge that actually has sub-items so the arc is real.
    let parent = viewModel.middleItems.firstIndex(where: { $0.hasSubItems }) ?? 0
    viewModel.expand(parent)
    viewModel.activeSelection = ActiveSelection(band: .outer, index: 0)

    return RingMenuView(viewModel: viewModel)
        .padding(40)
        .background(Color.black.opacity(0.6))
}
