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
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @State private var outerMotionState = HUDOuterBranchMotionState()
    @State private var settleOpeningID = 0

    /// Whether this view should drive selection from pointer input. The menu
    /// editor renders the real ring as a preview, but owns selection through its
    /// wedge overlay; disabling this prevents hover events from replacing that
    /// persistent editor selection.
    var interactionEnabled = true

    /// Rendering context is independent of interaction. In particular, the
    /// dedicated noninteractive Settings preview can replay opening motion,
    /// while the editor's interactive selection preview remains static.
    var presentationMode: HUDRingPresentationMode = .live
    /// Explicit replay identity used by the dedicated Settings preview.
    /// Runtime views are recreated per panel invocation and keep the default.
    var openingReplayID = 0

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
    var exposesWedgeAccessibility = true
    var onAccessibilitySelection: ((ActiveSelection) -> Void)?
    /// Preview-only editor selection, drawn as a neutral marker. Runtime leaves
    /// this nil and continues to use `activeSelection` exclusively for hover.
    var persistentSelection: ActiveSelection? = nil

    // T11: sourced from `AppearanceConfig` via the view model (persisted in Settings):
    //   - `keepSpokeLit`: also keep inner wedge `p` lit on the live branch (§2.3).
    //   - `dimOpacity`: opacity of off-branch wedges when something is expanded (§2.3).
    private var keepSpokeLit: Bool { viewModel.appearance.keepSpokeLit }
    private var dimOpacity: Double { viewModel.appearance.dimOpacity }
    private func motion(for role: HUDMotionRole) -> HUDMotionPresentationDescriptor {
        presentationMode.motion(
            for: role,
            configuration: viewModel.appearance.motion,
            reduceMotion: accessibilityReduceMotion
        )
    }
    private var hoverMotion: HUDMotionPresentationDescriptor { motion(for: .hover) }
    private var outerExpansionMotion: HUDMotionPresentationDescriptor { motion(for: .outerExpansion) }

    private var outerBranchIdentity: HUDOuterBranchIdentity {
        HUDOuterBranchIdentity(
            parentID: viewModel.expandedParentIndex.flatMap {
                viewModel.middleItems.indices.contains($0) ? viewModel.middleItems[$0].id : nil
            },
            items: viewModel.isOuterRingVisible ? viewModel.outerItems : []
        )
    }

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
        let identity = outerBranchIdentity
        let nextMotionState = outerMotionState.updating(identity)
        let expansion = nextMotionState.isReplacement ? motion(for: .branchChange) : outerExpansionMotion
        let branchMotion = motion(for: .branchChange)
        let summonMotion = motion(for: .summon)
        // Resolve eagerly: an outgoing view must never read the next branch's
        // mutable model while SwiftUI retains it for its removal transition.
        let wedges = outerWedgeSnapshots

        HUDOpeningMotion(
            request: HUDOpeningMotionRequest(
                descriptor: summonMotion,
                playbackEnabled: presentationMode != .staticEditor,
                invocationID: openingReplayID
            ),
            settleID: settleOpeningID,
            deadZoneRadius: radii.r0,
            revealRadius: radii.r2
        ) { openingFrame in
            ZStack {
                HUDOpeningArtwork(frame: openingFrame, size: size) {
                    ZStack {
                        persistentBacking(openingFrame)

                        // Dead-zone indicator (radius ~ r0) — cancel/back region.
                        Circle()
                            .fill(.secondary.opacity(0.3))
                            .frame(width: radii.r0 * 2, height: radii.r0 * 2)

                        innerBand(openingFrame)
                        middleBand(openingFrame)

                        // Removing this owner also discards any older branches still in
                        // flight, so Escape/reset cannot leave a fading ghost behind.
                        if identity.parentID != nil {
                            ZStack {
                                if viewModel.isOuterRingVisible {
                                    HUDOuterBandMotion(descriptor: expansion) { progress in
                                        ZStack {
                                            ForEach(wedges) { wedge in
                                                wedge.render(descriptor: expansion, progress: progress)
                                            }
                                        }
                                    }
                                    .id(identity)
                                    .transition(HUDOuterBranchTransition())
                                }
                            }
                            .animation(
                                branchMotion.effect != .instant
                                    ? .easeOut(duration: branchMotion.duration) : nil,
                                value: identity
                            )
                            .transition(.identity)
                        }
                    }
                }

                // This native control remains at final geometry. Fade retains
                // its original opacity behavior; spatial effects show it now.
                HUDCenterSettingsControl(
                    action: {
                        settleOpening()
                        viewModel.activateCenterSettings()
                    },
                    draggingEnabled: onCenterDrag != nil,
                    onDrag: { delta in
                        // A center drag is panel manipulation, never wedge selection.
                        settleOpening()
                        viewModel.activeSelection = nil
                        onCenterDrag?(delta)
                    }
                )
                .frame(width: radii.r0 * 1.6, height: radii.r0 * 1.6)
                .opacity(openingFrame.centerOpacity)
                .allowsHitTesting(interactionEnabled)
                .accessibilityHidden(!exposesCenterSettings)

                // Accessibility actions use final wedge geometry and never sit
                // inside opening masks or Bloom's artwork transform.
                accessibilityLayer
                    .allowsHitTesting(false)
            }
            .frame(width: size, height: size)
        }
        .onChange(of: viewModel.activeSelection) { _, selection in
            if selection != nil { settleOpening() }
        }
        .onChange(of: viewModel.expandedParentIndex) { _, parent in
            if parent != nil { settleOpening() }
        }
        .onChange(of: viewModel.appearance) { _, _ in
            settleOpening()
        }
        .onChange(of: viewModel.hudCustomization) { _, _ in
            settleOpening()
        }
        .onChange(of: viewModel.innerItems) { _, _ in
            settleOpening()
        }
        .onChange(of: viewModel.middleItems) { _, _ in
            settleOpening()
        }
        .onChange(of: identity, initial: true) { _, newIdentity in
            outerMotionState = outerMotionState.updating(newIdentity)
            if newIdentity.parentID != nil {
                settleOpening()
            }
        }
        // Single hit-test surface — the whole square is interactive (§2.2).
        .contentShape(Rectangle())
        // Pointer movement (tap-toggle / hover) drives the active wedge.
        .onContinuousHover { phase in
            if interactionEnabled, case .active(let location) = phase {
                viewModel.updateActive(at: location, center: center)
                if viewModel.activeSelection != nil { settleOpening() }
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
                    if viewModel.activeSelection != nil { settleOpening() }
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
    private func innerBand(_ openingFrame: HUDOpeningMotionFrame) -> some View {
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
                    hoverMotion: hoverMotion,
                    showsSelectionMarker: isPersistentSelection(.inner, index)
                )
                .opacity(staggerOpacity(for: .inner, index: index, frame: openingFrame))
                .accessibilityHidden(true)
            }
        }
    }

    /// Middle labeled band, using its own effective slot count and rotation.
    private func middleBand(_ openingFrame: HUDOpeningMotionFrame) -> some View {
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
                    hoverMotion: hoverMotion,
                    showsSelectionMarker: isPersistentSelection(.middle, index),
                    showsExpandAffordance: !hiddenParent
                )
                .opacity(staggerOpacity(for: .middle, index: index, frame: openingFrame))
                .accessibilityHidden(true)
            }
        }
    }

    /// The normal surface is one material disk. During stagger playback it is
    /// temporarily split into final-geometry slots so backing and wedge content
    /// share the same cadence; at completion the original seamless disk returns.
    @ViewBuilder
    private func persistentBacking(_ openingFrame: HUDOpeningMotionFrame) -> some View {
        if openingFrame.effect == .staggeredSegments, openingFrame.progress < 1 {
            ZStack {
                staggeredBackingBand(
                    .inner,
                    innerRadius: radii.r0,
                    outerRadius: radii.r1,
                    frame: openingFrame
                )
                staggeredBackingBand(
                    .middle,
                    innerRadius: radii.r1,
                    outerRadius: radii.r2,
                    frame: openingFrame
                )
            }
        } else {
            Circle()
                .fill(.ultraThinMaterial)
                .frame(
                    width: surfacePresentation.persistentOuterRadius * 2,
                    height: surfacePresentation.persistentOuterRadius * 2
                )
        }
    }

    private func staggeredBackingBand(
        _ band: Band,
        innerRadius: CGFloat,
        outerRadius: CGFloat,
        frame: HUDOpeningMotionFrame
    ) -> some View {
        let bandGeometry = geometry.geometry(for: band)
        return ForEach(Array(0..<bandGeometry.slotCount), id: \.self) { index in
            let angles = RadialGeometry.wedgeAngles(
                band: band,
                index: index,
                geometry: geometry,
                expandedParentIndex: viewModel.expandedParentIndex,
                outerCount: viewModel.outerItems.count
            )
            AnnularWedge(
                startAngle: angles.start,
                endAngle: angles.end,
                innerRadius: innerRadius,
                outerRadius: outerRadius
            )
            .fill(.ultraThinMaterial)
            .frame(width: size, height: size)
            .opacity(staggerOpacity(for: band, index: index, frame: frame))
        }
    }

    private func staggerOpacity(
        for band: Band,
        index: Int,
        frame: HUDOpeningMotionFrame
    ) -> Double {
        guard frame.effect == .staggeredSegments else { return 1 }
        let bandGeometry = geometry.geometry(for: band)
        let rank = HUDOpeningMotionFrame.staggerRank(
            index: index,
            slotCount: bandGeometry.slotCount,
            angularOffset: bandGeometry.angularOffset
        )
        return HUDOpeningMotionFrame.staggerOpacity(
            globalProgress: frame.progress,
            rank: rank,
            slotCount: bandGeometry.slotCount
        )
    }

    @ViewBuilder
    private var accessibilityLayer: some View {
        if exposesWedgeAccessibility {
            ZStack {
                ForEach(Array(viewModel.innerItems.enumerated()), id: \.element.id) { index, item in
                    accessibilityTarget(item, band: .inner, index: index)
                }
                ForEach(Array(viewModel.middleItems.enumerated()), id: \.element.id) { index, item in
                    let hiddenParent = item.hasSubItems &&
                        viewModel.hiddenSubmenuUnavailableReason != nil
                    accessibilityTarget(
                        item,
                        band: .middle,
                        index: index,
                        unavailableReason: hiddenParent ? viewModel.hiddenSubmenuUnavailableReason : nil,
                        activate: hiddenParent ? nil : { accessibilityActivate(.middle, index) }
                    )
                }
                if viewModel.isOuterRingVisible {
                    ForEach(Array(viewModel.outerItems.enumerated()), id: \.element.id) { index, item in
                        accessibilityTarget(item, band: .outer, index: index) {
                            guard viewModel.isOuterRingVisible,
                                  viewModel.outerItems.indices.contains(index),
                                  viewModel.outerItems[index] == item else { return }
                            accessibilityActivate(.outer, index)
                        }
                    }
                }
            }
        }
    }

    private func accessibilityTarget(
        _ item: RingMenuItem,
        band: Band,
        index: Int,
        unavailableReason: String? = nil,
        activate: (() -> Void)? = nil
    ) -> some View {
        let angles = RadialGeometry.wedgeAngles(
            band: band,
            index: index,
            geometry: geometry,
            expandedParentIndex: viewModel.expandedParentIndex,
            outerCount: viewModel.outerItems.count,
            outerLayout: viewModel.outerRingLayout
        )
        let bandRadii: (inner: CGFloat, outer: CGFloat) = switch band {
        case .inner: (radii.r0, radii.r1)
        case .middle: (radii.r1, radii.r2)
        case .outer: (radii.r2, radii.r3)
        }
        let action = activate ?? { accessibilityActivate(band, index) }
        return AnnularWedge(
            startAngle: angles.start,
            endAngle: angles.end,
            innerRadius: bandRadii.inner,
            outerRadius: bandRadii.outer
        )
        .fill(Color.clear)
        .frame(width: size, height: size)
        .hudWedgeAccessibility(
            presentation: wedgeAccessibility(
                item, band: band, index: index, unavailableReason: unavailableReason
            ),
            activate: unavailableReason == nil ? action : nil
        )
    }

    /// Every field used to render an outgoing branch is a value snapshot,
    /// including app icons, geometry, and labels. Accessibility lives in a
    /// separate final-geometry layer outside opening transforms.
    private var outerWedgeSnapshots: [HUDOuterWedgeSnapshot] {
        viewModel.outerItems.enumerated().map { index, item in
            let angles = RadialGeometry.wedgeAngles(
                band: .outer, index: index, geometry: geometry,
                expandedParentIndex: viewModel.expandedParentIndex,
                outerCount: viewModel.outerItems.count,
                outerLayout: viewModel.outerRingLayout
            )
            return HUDOuterWedgeSnapshot(
                item: item,
                iconSource: iconSource(for: item),
                startAngle: angles.start,
                endAngle: angles.end,
                radii: radii,
                centroid: centroid(.outer, index),
                size: size,
                layout: viewModel.outerRingLayout,
                parentMidpoint: expandedParentMidpoint,
                labelPresentation: labelPresentation(
                    for: item, band: .outer, startAngle: angles.start, endAngle: angles.end
                ),
                presentation: presentation(
                    for: item, band: .outer, hovered: isActive(.outer, index), offBranch: false
                ),
                isHighlighted: isActive(.outer, index),
                hoverMotion: hoverMotion,
                showsSelectionMarker: isPersistentSelection(.outer, index)
            )
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

    /// The localized reveal collapses every child wedge to this shared parent
    /// direction. The full-circle reveal ignores it and keeps final angles.
    private var expandedParentMidpoint: Angle {
        guard let parent = viewModel.expandedParentIndex else { return .zero }
        let angles = RadialGeometry.wedgeAngles(
            band: .middle,
            index: parent,
            geometry: geometry,
            expandedParentIndex: viewModel.expandedParentIndex,
            outerCount: viewModel.outerItems.count
        )
        return .radians((angles.start.radians + angles.end.radians) / 2)
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
        settleOpening()
        let selection = ActiveSelection(band: band, index: index)
        if let onAccessibilitySelection { onAccessibilitySelection(selection) }
        else {
            viewModel.activeSelection = selection
            viewModel.commitActive()
        }
    }

    private func settleOpening() {
        settleOpeningID &+= 1
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

extension View {
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
