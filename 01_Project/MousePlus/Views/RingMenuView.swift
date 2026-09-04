import SwiftUI

/// The concentric wedge ("pie") menu.
///
/// Two independently configured top-level rings:
///   - **inner** band: symbol-only quick actions (`r0…r1`)
///   - **middle** band: labeled items, each direct or expandable (`r1…r2`)
/// plus an **on-demand outer** band (`r2…r3`). Static submenus grow as a
/// localized arc; the running-app switcher uses the full circumference.
///
/// Hit-testing is done on a single square container via angle + radius
/// (`RingViewModel.updateActive` → `RadialGeometry.hitTest`), NOT per-wedge
/// `contentShape` — per-wedge containment causes boundary flicker / dead zones
/// (§2.2). Each `WedgeView` is purely presentational.
struct RingMenuView: View {
    @Bindable var viewModel: RingViewModel

    /// Whether this view should drive selection from pointer input. The menu
    /// editor renders the real ring as a preview, but owns selection through its
    /// wedge overlay; disabling this prevents hover events from replacing that
    /// persistent editor selection.
    var interactionEnabled = true

    /// Hold-release commits through the global trigger-up event. Tap-toggle
    /// commits from the in-panel pointer release. Keeping these paths exclusive
    /// prevents an expandable parent from being committed twice on one release.
    var commitsOnPointerRelease = true
    /// Tap-toggle only: moving the native center control relocates the panel.
    var onCenterDrag: ((CGSize) -> Void)?

    /// Runtime and preview use distinct stable namespaces. The preview supplies
    /// a selection callback so VoiceOver activation edits without executing.
    var accessibilityIdentifierPrefix = "hud.wedge"
    var exposesCenterSettings = true
    var onAccessibilitySelection: ((ActiveSelection) -> Void)?
    /// Preview-only editor selection, drawn as a neutral marker. Runtime leaves
    /// this nil and continues to use `activeSelection` exclusively for hover.
    var persistentSelection: ActiveSelection? = nil

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
    private var geometry: TopLevelRingGeometry { viewModel.geometry }
    private var surfacePresentation: RingSurfacePresentation {
        RingSurfacePresentation(radii: radii, isOuterRingVisible: viewModel.isOuterRingVisible)
    }

    var body: some View {
        ZStack {
            // Persistent backing stops at the middle band's outer edge. The
            // on-demand outer surface is rendered with `outerBand` below so a
            // hidden submenu never leaves a misleading r2…r3 halo.
            Circle()
                .fill(.ultraThinMaterial)
                .frame(
                    width: surfacePresentation.persistentOuterRadius * 2,
                    height: surfacePresentation.persistentOuterRadius * 2
                )

            // Dead-zone indicator (radius ~ r0) — cancel/back region.
            Circle()
                .fill(.secondary.opacity(0.3))
                .frame(width: radii.r0 * 2, height: radii.r0 * 2)

            HUDCenterSettingsControl(
                action: { viewModel.activateCenterSettings() },
                draggingEnabled: onCenterDrag != nil,
                onDrag: { delta in
                    // A center drag is panel manipulation, never wedge selection.
                    viewModel.activeSelection = nil
                    onCenterDrag?(delta)
                }
            )
            .frame(width: radii.r0 * 1.6, height: radii.r0 * 1.6)
            .allowsHitTesting(interactionEnabled)
            .accessibilityHidden(!exposesCenterSettings)

            innerBand
            middleBand

            // Outer band — localized arc, only while expanded. Wrapped so it can
            // scale/opacity in from the parent wedge centroid (T7).
            if viewModel.isOuterRingVisible {
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
            if interactionEnabled, case .active(let location) = phase {
                viewModel.updateActive(at: location, center: center)
            }
            // .ended → leave selection as-is; a click commits it.
        }
        // Primary-pointer gesture: drag updates selection and tap-toggle commits
        // on release. Hold-release commits from its global trigger-up callback,
        // which independently re-hit-tests that event's final pointer position.
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    guard interactionEnabled else { return }
                    viewModel.updateActive(at: value.location, center: center)
                }
                .onEnded { value in
                    guard interactionEnabled else { return }
                    guard commitsOnPointerRelease else { return }
                    viewModel.commit(at: value.location, center: center)
                }
        )
    }

    // MARK: - Bands

    /// Inner symbol-only band. Fixed but unused slots remain part of `geometry`
    /// without producing a SwiftUI or accessibility element.
    private var innerBand: some View {
        ForEach(Array(0..<geometry.inner.slotCount), id: \.self) { index in
            if index < viewModel.innerItems.count {
                let item = viewModel.innerItems[index]
                let angles = RadialGeometry.wedgeAngles(
                    band: .inner, index: index, geometry: geometry,
                    expandedParentIndex: viewModel.expandedParentIndex,
                    outerCount: viewModel.outerItems.count
                )
                WedgeView(
                    item: item,
                    iconSource: iconSource(for: item),
                    startAngle: angles.start,
                    endAngle: angles.end,
                    innerRadius: radii.r0,
                    outerRadius: radii.r1,
                    centroid: centroid(.inner, index),
                    size: size,
                    labelPresentation: labelPresentation(
                        for: item, band: .inner, startAngle: angles.start, endAngle: angles.end
                    ),
                    isHighlighted: isActive(.inner, index),
                    dimmed: dimmed(band: .inner, index: index),
                    dimOpacity: dimOpacity,
                    presentation: presentation(
                        for: item,
                        band: .inner,
                        hovered: isActive(.inner, index),
                        offBranch: dimmed(band: .inner, index: index)
                    ),
                    showsSelectionMarker: isPersistentSelection(.inner, index)
                )
                .hudWedgeAccessibility(
                    presentation: wedgeAccessibility(item, band: .inner, index: index),
                    activate: { accessibilityActivate(.inner, index) }
                )
            }
        }
    }

    /// Middle labeled band, using its own effective slot count and rotation.
    private var middleBand: some View {
        ForEach(Array(0..<geometry.middle.slotCount), id: \.self) { index in
            if index < viewModel.middleItems.count {
                let item = viewModel.middleItems[index]
                let angles = RadialGeometry.wedgeAngles(
                    band: .middle, index: index, geometry: geometry,
                    expandedParentIndex: viewModel.expandedParentIndex,
                    outerCount: viewModel.outerItems.count
                )
                let hiddenParent = item.hasSubItems &&
                    viewModel.hiddenSubmenuUnavailableReason != nil
                WedgeView(
                    item: item,
                    iconSource: iconSource(for: item),
                    startAngle: angles.start,
                    endAngle: angles.end,
                    innerRadius: radii.r1,
                    outerRadius: radii.r2,
                    centroid: centroid(.middle, index),
                    size: size,
                    labelPresentation: labelPresentation(
                        for: item, band: .middle, startAngle: angles.start, endAngle: angles.end
                    ),
                    isHighlighted: isActive(.middle, index),
                    dimmed: dimmed(band: .middle, index: index),
                    dimOpacity: dimOpacity,
                    presentation: presentation(
                        for: item,
                        band: .middle,
                        hovered: isActive(.middle, index),
                        offBranch: dimmed(band: .middle, index: index)
                    ),
                    showsSelectionMarker: isPersistentSelection(.middle, index),
                    showsExpandAffordance: !hiddenParent
                )
                .hudWedgeAccessibility(
                    presentation: wedgeAccessibility(
                        item, band: .middle, index: index,
                        unavailableReason: hiddenParent ? viewModel.hiddenSubmenuUnavailableReason : nil
                    ),
                    activate: hiddenParent ? nil : { accessibilityActivate(.middle, index) }
                )
            }
        }
    }

    /// Outer band — a localized arc of the expanded parent's sub-items (§2.3).
    /// Always lit (it IS the live branch).
    ///
    /// Iterates the items themselves keyed by stable `id`, NOT `0..<count`. A
    /// constant-range `ForEach(0..<count)` captures the range at graph-build time;
    /// when `outerItems` empties on commit/collapse/reset, SwiftUI re-renders the
    /// stale indices and `outerItems[index]` traps "Index out of range" (crashed
    /// the app on selecting a sub-item, 2026-05-31). Enumerate so `index` (the arc
    /// offset the geometry needs) comes from the *current* snapshot.
    private var outerBand: some View {
        ZStack {
            ForEach(Array(viewModel.outerItems.enumerated()), id: \.element.id) { index, outerItem in
                let angles = RadialGeometry.wedgeAngles(
                    band: .outer, index: index, geometry: geometry,
                    expandedParentIndex: viewModel.expandedParentIndex,
                    outerCount: viewModel.outerItems.count,
                    outerLayout: viewModel.outerRingLayout
                )
                OuterWedgeBacking(
                    startAngle: angles.start,
                    endAngle: angles.end,
                    innerRadius: radii.r2,
                    outerRadius: radii.r3,
                    size: size
                )
                .accessibilityHidden(true)

                WedgeView(
                    item: outerItem,
                    iconSource: iconSource(for: outerItem),
                    startAngle: angles.start,
                    endAngle: angles.end,
                    innerRadius: radii.r2,
                    outerRadius: radii.r3,
                    centroid: centroid(.outer, index),
                    size: size,
                    labelPresentation: labelPresentation(
                        for: outerItem, band: .outer, startAngle: angles.start, endAngle: angles.end
                    ),
                    isHighlighted: isActive(.outer, index),
                    dimmed: false,
                    presentation: presentation(
                        for: outerItem,
                        band: .outer,
                        hovered: isActive(.outer, index),
                        offBranch: false
                    ),
                    showsSelectionMarker: isPersistentSelection(.outer, index)
                )
                .hudWedgeAccessibility(
                    presentation: wedgeAccessibility(outerItem, band: .outer, index: index),
                    activate: { accessibilityActivate(.outer, index) }
                )
            }
        }
    }

    // MARK: - Geometry helpers

    /// A dynamic-source item with a fetched icon renders that live app icon;
    /// everything else falls back to its configured SF Symbol.
    private func iconSource(for item: RingMenuItem) -> IconSource {
        viewModel.dynamicIcons[item.id].map { .appIcon($0) } ?? .sfSymbol(item.icon)
    }

    private func presentation(
        for item: RingMenuItem,
        band: Band,
        hovered: Bool,
        offBranch: Bool
    ) -> WedgePresentation {
        let secondary = HUDColor(nsColor: .secondaryLabelColor)
            ?? HUDColor(red: 0.5, green: 0.5, blue: 0.5)
        let normalWedge = HUDColor(
            red: secondary.red,
            green: secondary.green,
            blue: secondary.blue,
            alpha: 0.2
        )
        let foreground = HUDColor(nsColor: .labelColor) ?? .white
        let resolution = viewModel.colorResolution(
            for: item,
            band: band,
            application: .init(wedge: normalWedge, icon: foreground),
            backdrop: HUDColor(nsColor: .windowBackgroundColor) ?? .black
        )
        return WedgePresentation(
            // Draw the same deterministic composite used for contrast checks.
            // Otherwise translucent overrides blend against SwiftUI material,
            // which differs between the live panel and Settings preview.
            wedgeColor: resolution.renderedWedge,
            iconColor: resolution.renderedIcon,
            labelColor: resolution.renderedLabel,
            orientation: viewModel.iconOrientation(for: band),
            state: WedgePresentation.state(
                hovered: hovered, offBranch: offBranch, dimOpacity: dimOpacity
            )
        )
    }

    /// Resolves the same menu → ring label policy used by the editor preview
    /// (both render through this view), independent of icon orientation.
    private func labelPresentation(
        for item: RingMenuItem, band: Band, startAngle: Angle, endAngle: Angle
    ) -> LabelPresentation {
        LabelPresentation(
            accessibilityLabel: item.label,
            orientation: viewModel.labelOrientation(for: band),
            isVisible: viewModel.isLabelVisible(for: band),
            startAngle: startAngle,
            endAngle: endAngle
        )
    }

    private func centroid(_ band: Band, _ index: Int) -> CGPoint {
        RadialGeometry.centroid(
            band: band, index: index, center: center, radii: radii,
            geometry: geometry,
            expandedParentIndex: viewModel.expandedParentIndex,
            outerCount: viewModel.outerItems.count,
            outerLayout: viewModel.outerRingLayout
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

    private func isActive(_ band: Band, _ index: Int) -> Bool {
        viewModel.activeSelection == ActiveSelection(band: band, index: index)
    }

    private func isPersistentSelection(_ band: Band, _ index: Int) -> Bool {
        persistentSelection == ActiveSelection(band: band, index: index)
    }

    private func wedgeAccessibility(
        _ item: RingMenuItem, band: Band, index: Int, unavailableReason: String? = nil
    ) -> RingWedgeAccessibility {
        let name = band == .inner ? "Inner" : (band == .middle ? "Middle" : "Outer")
        return RingWedgeAccessibility(
            item: item, band: name, position: index,
            selected: persistentSelection.map { $0 == ActiveSelection(band: band, index: index) }
                ?? isActive(band, index),
            unavailableReason: unavailableReason,
            identifierPrefix: accessibilityIdentifierPrefix
        )
    }

    private func accessibilityActivate(_ band: Band, _ index: Int) {
        let selection = ActiveSelection(band: band, index: index)
        if let onAccessibilitySelection { onAccessibilitySelection(selection) }
        else {
            viewModel.activeSelection = selection
            viewModel.commitActive()
        }
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
            return !(keepSpokeLit && index == RadialGeometry.alignedIndex(
                sourceIndex: parent,
                sourceGeometry: geometry.middle,
                targetGeometry: geometry.inner
            ))
        case .outer:
            return false
        }
    }
}

private extension View {
    @ViewBuilder
    func hudWedgeAccessibility(
        presentation: RingWedgeAccessibility,
        activate: (() -> Void)?
    ) -> some View {
        if let activate {
            self
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(presentation.label)
                .accessibilityValue(presentation.value)
                .accessibilityIdentifier(presentation.identifier)
                .accessibilityAddTraits(presentation.isSelected ? .isSelected : [])
                .accessibilityAction { activate() }
        } else {
            self
                .disabled(true)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(presentation.label)
                .accessibilityValue(presentation.value)
                .accessibilityIdentifier(presentation.identifier)
                .accessibilityAddTraits(presentation.isSelected ? .isSelected : [])
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
