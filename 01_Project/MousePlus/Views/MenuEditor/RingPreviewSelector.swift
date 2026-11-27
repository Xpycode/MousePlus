import SwiftUI

/// Preview-only styling for the empty outer band. A faint, unsegmented annulus
/// makes submenu capacity discoverable without presenting phantom wedges. The
/// live HUD never constructs this presentation, and Always Hidden remains a
/// literal absence even in the editor preview.
struct EditorOuterRingGuidePresentation: Equatable {
    let innerRadius: CGFloat
    let outerRadius: CGFloat
    let fillOpacity: Double
    let boundaryOpacity: Double
    let isVisible: Bool

    init(
        radii: BandRadii,
        visibility: OuterRingVisibility,
        hasLocalizedOuterSurface: Bool
    ) {
        innerRadius = radii.r2
        outerRadius = radii.r3
        fillOpacity = 0.04
        boundaryOpacity = 0.14
        isVisible = visibility != .alwaysHidden && !hasLocalizedOuterSurface
    }
}

/// A neutral editor scaffold rather than a material backing: it has no wedge
/// divisions, glyphs, accessibility element, or hit-testing behavior.
struct EditorOuterRingGuide: View {
    let presentation: EditorOuterRingGuidePresentation

    private var bandWidth: CGFloat {
        presentation.outerRadius - presentation.innerRadius
    }

    private var midlineDiameter: CGFloat {
        presentation.outerRadius + presentation.innerRadius
    }

    var body: some View {
        if presentation.isVisible {
            ZStack {
                Circle()
                    .stroke(
                        Color.primary.opacity(presentation.fillOpacity),
                        lineWidth: bandWidth
                    )
                    .frame(width: midlineDiameter, height: midlineDiameter)

                Circle()
                    .strokeBorder(
                        Color.primary.opacity(presentation.boundaryOpacity),
                        lineWidth: 1
                    )
                    .frame(
                        width: presentation.outerRadius * 2,
                        height: presentation.outerRadius * 2
                    )

                Circle()
                    .stroke(
                        Color.primary.opacity(presentation.boundaryOpacity),
                        lineWidth: 1
                    )
                    .frame(
                        width: presentation.innerRadius * 2,
                        height: presentation.innerRadius * 2
                    )
            }
            .frame(
                width: presentation.outerRadius * 2,
                height: presentation.outerRadius * 2
            )
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}

struct RingWedgeAccessibility: Equatable {
    let label: String
    let value: String
    let identifier: String
    let isSelected: Bool
    let isUnavailable: Bool

    init(
        item: RingMenuItem,
        band: String,
        position: Int,
        selected: Bool,
        unavailableReason: String? = nil,
        identifierPrefix: String = "hud.wedge",
        labelSuffix: String = ""
    ) {
        let itemLabel = item.label.isEmpty ? "unlabeled" : item.label
        let symbolState = SFSymbol.isValid(item.icon) ? "" : ", invalid symbol; placeholder shown"
        label = "\(band) wedge, position \(position + 1), \(itemLabel), action \(item.actionType.displayName)\(symbolState)\(labelSuffix)"
        isSelected = selected
        isUnavailable = unavailableReason != nil
        value = [
            selected ? "Selected" : "Not selected",
            unavailableReason.map { "Unavailable. \($0)" }
        ].compactMap { $0 }.joined(separator: ". ")
        identifier = "\(identifierPrefix).\(band.lowercased()).\(position + 1)"
    }
}

/// Editor-preview marking for items an App HUD has customized. Decoration
/// only: the dot never hit-tests and never alters selection geometry. The
/// accessibility label gains a suffix so the mark is not visual-only.
enum RingPreviewCustomizationMarker {
    static let dotDiameter: CGFloat = 6
    /// Inset from the band's outer edge, keeping the dot clear of the
    /// centroid glyph and caption.
    static let dotEdgeInset: CGFloat = 7

    static func accessibilitySuffix(
        itemID: UUID, customizedItemIDs: Set<UUID>, appName: String?
    ) -> String {
        guard customizedItemIDs.contains(itemID) else { return "" }
        guard let appName, !appName.isEmpty else { return ", customized" }
        return ", customized for \(appName)"
    }

    /// The wedge's angular midpoint, just inside its band's outer edge, in the
    /// ring's top-left-origin local space (`+y` down, like `RadialGeometry`).
    static func dotPosition(
        start: Angle, end: Angle, outerRadius: CGFloat, center: CGPoint
    ) -> CGPoint {
        let mid = CGFloat((start.radians + end.radians) / 2)
        let r = outerRadius - dotEdgeInset
        return CGPoint(x: center.x + r * cos(mid), y: center.y + r * sin(mid))
    }
}

/// A testable description of the configured wedges that are actually exposed.
/// Fixed empty positions never enter the item arrays, and policy-hidden outer
/// items are deliberately omitted here just as they are from `RingMenuView`.
struct RingAccessibilitySnapshot {
    let inner: [RingWedgeAccessibility]
    let middle: [RingWedgeAccessibility]
    let outer: [RingWedgeAccessibility]

    init(
        innerItems: [RingMenuItem],
        middleItems: [RingMenuItem],
        outerItems: [RingMenuItem],
        selected: ActiveSelection?,
        outerVisible: Bool,
        hiddenSubmenuReason: String? = nil,
        identifierPrefix: String = "hud.wedge"
    ) {
        inner = Self.presentations(innerItems, band: .inner, selected: selected,
                                   identifierPrefix: identifierPrefix)
        middle = middleItems.enumerated().map { index, item in
            RingWedgeAccessibility(
                item: item, band: "Middle", position: index,
                selected: selected == ActiveSelection(band: .middle, index: index),
                unavailableReason: item.hasSubItems ? hiddenSubmenuReason : nil,
                identifierPrefix: identifierPrefix
            )
        }
        outer = outerVisible
            ? Self.presentations(outerItems, band: .outer, selected: selected,
                                 identifierPrefix: identifierPrefix)
            : []
    }

    private static func presentations(
        _ items: [RingMenuItem], band: Band, selected: ActiveSelection?,
        identifierPrefix: String
    ) -> [RingWedgeAccessibility] {
        let name = band == .inner ? "Inner" : "Outer"
        return items.enumerated().map { index, item in
            RingWedgeAccessibility(
                item: item, band: name, position: index,
                selected: selected == ActiveSelection(band: band, index: index),
                identifierPrefix: identifierPrefix
            )
        }
    }
}

/// One frame of the editor. Both the visual wedges and pointer callbacks
/// retain these item identities, including during a profile replacement.
struct EditorRingPresentation: RingMenuPresentation {
    let innerItems: [RingMenuItem]
    let middleItems: [RingMenuItem]
    let outerItems: [RingMenuItem]
    let expandedParentIndex: Int?
    let activeSelection: ActiveSelection?
    let appearance: AppearanceConfig
    let hudCustomization: HUDCustomization
    let isOuterRingVisible: Bool
    var radii: BandRadii { appearance.bandRadii }
    var runtime: RingViewModel? { nil }

    var outerRingGuidePresentation: EditorOuterRingGuidePresentation {
        EditorOuterRingGuidePresentation(
            radii: radii,
            visibility: hudCustomization.outerRingVisibility,
            hasLocalizedOuterSurface: isOuterRingVisible
        )
    }

    var interactionSnapshot: HUDPreviewInteractionSnapshot {
        HUDPreviewInteractionSnapshot(
            geometry: geometry,
            radii: radii,
            innerCount: innerItems.count,
            middleCount: middleItems.count,
            expandedParentIndex: expandedParentIndex,
            outerCount: outerItems.count,
            outerVisibility: hudCustomization.outerRingVisibility,
            outerLayout: outerRingLayout
        )
    }

    func slot(for intent: HUDPreviewIntent) -> SlotSelection? {
        switch intent {
        case let .selectTopLevel(band, index):
            let items = band == .inner ? innerItems : middleItems
            guard items.indices.contains(index) else { return nil }
            return SlotSelection(band: band, itemID: items[index].id, subItemID: nil)
        case let .selectOuter(index):
            guard let parentIndex = expandedParentIndex,
                  middleItems.indices.contains(parentIndex),
                  outerItems.indices.contains(index) else { return nil }
            let parent = middleItems[parentIndex]
            guard parent.dynamicSource == .none else { return nil }
            return SlotSelection(band: .middle, itemID: parent.id, subItemID: outerItems[index].id)
        }
    }
}

/// Runtime-identical rendering with one preview-only AppKit pointer surface.
/// The surface emits editor selection/add intents and has no action execution path.
@MainActor
struct RingPreviewSelector: View {
    @Bindable var model: MenuEditorModel
    var appearance: AppearanceConfig = .default
    /// App name for the ", customized for <App>" accessibility suffix.
    var appName: String? = nil
    @State private var hover: ActiveSelection?
    @State private var pointer = HUDPreviewInteractionState()
    private let canvasSide: CGFloat = 448

    /// Fixed stand-in for `.runningApps` parents — the editor preview never
    /// queries the live `AppSwitcherService`/`NSWorkspace`.
    private static let runningAppsPreviewPlaceholder: [RingMenuItem] = [
        RingMenuItem(label: "Safari", icon: "safari", actionType: .appSwitch, actionData: "com.apple.Safari"),
        RingMenuItem(label: "Finder", icon: "folder", actionType: .appSwitch, actionData: "com.apple.finder"),
        RingMenuItem(label: "Mail", icon: "envelope", actionType: .appSwitch, actionData: "com.apple.mail"),
        RingMenuItem(label: "Messages", icon: "message", actionType: .appSwitch, actionData: "com.apple.MobileSMS"),
    ]

    var body: some View {
        // Resolve the displayed profile before constructing either layer. SwiftUI
        // can coalesce a mount with a load, or replace the profile at the same index.
        let artwork = self.artwork
        let preview = artwork.viewModel
        let side = 2 * preview.radii.r3
        let scale = HUDPreviewInteractionSnapshot.fitScale(
            logicalSide: side, canvasSide: canvasSide
        )

        return ZStack {
            EditorOuterRingGuide(presentation: preview.outerRingGuidePresentation)
            artwork
                .allowsHitTesting(false)
            if !model.customizedItemIDs.isEmpty {
                customizationDots(preview)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            HUDPreviewInteractionView(
                snapshot: preview.interactionSnapshot,
                onHover: { if hover != $0 { hover = $0 } },
                pointer: pointer,
                onIntent: { apply($0, in: preview) },
                deleteTarget: { deleteTarget(for: $0, in: preview) },
                onDelete: delete
            )
            .frame(width: side, height: side)
        }
        .frame(width: side, height: side)
        .scaleEffect(scale)
        .frame(width: canvasSide, height: canvasSide)
        .transaction { $0.animation = nil }
    }

    var artwork: RingMenuView<EditorRingPresentation> {
        let preview = makePreview()
        return RingMenuView(
            viewModel: preview,
            interactionEnabled: false,
            presentationMode: .staticEditor,
            accessibilityIdentifierPrefix: "menuItems.preview.wedge",
            exposesCenterSettings: false,
            onAccessibilitySelection: { applyAccessibilitySelection($0, in: preview) },
            persistentSelection: editorActiveSelection,
            accessibilityLabelSuffix: accessibilityLabelSuffix
        )
    }

    private func makePreview() -> EditorRingPresentation {
        let parent = expandedMiddleParent()
        let children = parent?.item.dynamicSource == .runningApps
            ? Self.runningAppsPreviewPlaceholder : parent?.item.subItems ?? []
        let policy = model.hudCustomization.outerRingVisibility
        let outer = pointer.outerRingPolicyState.transition(
            policy: policy, hasExpandedParent: parent != nil, itemCount: children.count
        )
        return EditorRingPresentation(
            innerItems: model.inner, middleItems: model.middle,
            outerItems: outer.isEligible ? children : [],
            expandedParentIndex: outer.isEligible ? parent?.index : nil,
            activeSelection: hover, appearance: appearance, hudCustomization: model.hudCustomization,
            isOuterRingVisible: outer.isVisible
        )
    }

    // MARK: - Customization marks (App HUD only)

    private func wedgeAngles(_ band: Band, _ index: Int, in preview: EditorRingPresentation) -> (start: Angle, end: Angle) {
        RadialGeometry.wedgeAngles(
            band: band, index: index, geometry: preview.geometry,
            expandedParentIndex: preview.expandedParentIndex,
            outerCount: preview.outerItems.count,
            outerLayout: preview.outerRingLayout
        )
    }

    private func bandRadii(_ band: Band, in preview: EditorRingPresentation) -> (inner: CGFloat, outer: CGFloat) {
        switch band {
        case .inner: (preview.radii.r0, preview.radii.r1)
        case .middle: (preview.radii.r1, preview.radii.r2)
        case .outer: (preview.radii.r2, preview.radii.r3)
        }
    }

    /// Fixed-size overlay in the ring's own square: it cannot shift layout,
    /// and the caller disables hit-testing and hides it from accessibility.
    private func customizationDots(_ preview: EditorRingPresentation) -> some View {
        let side = 2 * preview.radii.r3
        let center = CGPoint(x: side / 2, y: side / 2)
        let marks: [(band: Band, index: Int, id: UUID)] =
            preview.innerItems.enumerated().map { (.inner, $0.offset, $0.element.id) }
            + preview.middleItems.enumerated().map { (.middle, $0.offset, $0.element.id) }
        return ZStack {
            ForEach(marks.indices.filter { isCustomized(marks[$0].id, in: marks[$0].band) }, id: \.self) { index in
                let mark = marks[index]
                let angles = wedgeAngles(mark.band, mark.index, in: preview)
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: RingPreviewCustomizationMarker.dotDiameter,
                           height: RingPreviewCustomizationMarker.dotDiameter)
                    .position(RingPreviewCustomizationMarker.dotPosition(
                        start: angles.start, end: angles.end,
                        outerRadius: bandRadii(mark.band, in: preview).outer, center: center
                    ))
            }
        }
        .frame(width: side, height: side)
    }

    /// Handed to RingMenuView so its single wedge accessibility layer labels
    /// marked items ", customized for <App>". Nil when nothing is marked.
    private var accessibilityLabelSuffix: ((RingMenuItem, Band) -> String)? {
        guard !model.customizedItemIDs.isEmpty else { return nil }
        return { item, band in
            guard band != .outer else { return "" }
            let ids = model.customizedItemIDs(band: band == .inner ? .inner : .middle)
            return RingPreviewCustomizationMarker.accessibilitySuffix(
                itemID: item.id, customizedItemIDs: ids, appName: appName
            )
        }
    }

    private func isCustomized(_ id: UUID, in band: Band) -> Bool {
        model.origin(of: id, band: band == .inner ? .inner : .middle) == .customized
    }

    private func contains(_ slot: SlotSelection) -> Bool {
        let items = slot.band == .inner ? model.inner : model.middle
        guard let parent = items.first(where: { $0.id == slot.itemID }) else { return false }
        guard let child = slot.subItemID else { return true }
        return slot.band == .middle && parent.dynamicSource == .none
            && parent.subItems?.contains { $0.id == child } == true
    }

    private func apply(_ intent: HUDPreviewIntent, in preview: EditorRingPresentation) {
        guard let slot = preview.slot(for: intent), contains(slot) else { return }
        model.activeBand = slot.band
        model.selection = slot
    }

    private var editorActiveSelection: ActiveSelection? {
        guard let selection = model.selection, let itemID = selection.itemID else { return nil }
        if selection.band == .inner,
           let index = model.inner.firstIndex(where: { $0.id == itemID }) {
            return ActiveSelection(band: .inner, index: index)
        } else if let subID = selection.subItemID,
                  let parent = expandedMiddleParent(),
                  let index = parent.item.subItems?.firstIndex(where: { $0.id == subID }) {
            return ActiveSelection(band: .outer, index: index)
        } else if let index = model.middle.firstIndex(where: { $0.id == itemID }) {
            return ActiveSelection(band: .middle, index: index)
        }
        return nil
    }

    private func deleteTarget(for intent: HUDPreviewIntent, in preview: EditorRingPresentation) -> SlotSelection? {
        guard let slot = preview.slot(for: intent), canDelete(slot) else { return nil }
        return slot
    }

    func canDelete(_ slot: SlotSelection) -> Bool {
        !model.followsGlobal(slot.band) && contains(slot)
    }

    func delete(_ slot: SlotSelection) {
        guard canDelete(slot) else { return }
        model.activeBand = slot.band
        model.selection = slot
        model.removeSelectedItem()
    }

    private func applyAccessibilitySelection(_ selection: ActiveSelection, in preview: EditorRingPresentation) {
        switch selection.band {
        case .inner: apply(.selectTopLevel(.inner, selection.index), in: preview)
        case .middle: apply(.selectTopLevel(.middle, selection.index), in: preview)
        case .outer: apply(.selectOuter(selection.index), in: preview)
        }
    }

    private func expandedMiddleParent() -> (item: RingMenuItem, index: Int)? {
        guard let selection = model.selection, selection.band == .middle,
              let id = selection.itemID,
              let index = model.middle.firstIndex(where: { $0.id == id }),
              model.middle[index].hasSubItems else { return nil }
        return (model.middle[index], index)
    }
}
