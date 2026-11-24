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

/// Runtime-identical rendering with one preview-only AppKit pointer surface.
/// The surface emits editor selection/add intents and has no action execution path.
@MainActor
struct RingPreviewSelector: View {
    @Bindable var model: MenuEditorModel
    var appearance: AppearanceConfig = .default
    /// App name for the ", customized for <App>" accessibility suffix.
    var appName: String? = nil
    @State private var preview = RingViewModel()
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
        let side = 2 * preview.radii.r3
        let scale = HUDPreviewInteractionSnapshot.fitScale(
            logicalSide: side, canvasSide: canvasSide
        )

        ZStack {
            EditorOuterRingGuide(presentation: outerRingGuidePresentation)
            RingMenuView(
                viewModel: preview,
                interactionEnabled: false,
                presentationMode: .staticEditor,
                accessibilityIdentifierPrefix: "menuItems.preview.wedge",
                exposesCenterSettings: false,
                onAccessibilitySelection: applyAccessibilitySelection,
                persistentSelection: editorActiveSelection,
                accessibilityLabelSuffix: accessibilityLabelSuffix
            )
                .allowsHitTesting(false)
            if !model.customizedItemIDs.isEmpty {
                customizationDots
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            HUDPreviewInteractionView(
                snapshot: snapshot,
                onHover: { preview.activeSelection = $0 },
                onRevealChange: { if $0 { revealPreviewOuterRing() } },
                onIntent: apply,
                deleteTarget: deleteTarget,
                onDelete: delete
            )
            .frame(width: side, height: side)
        }
        .frame(width: side, height: side)
        .scaleEffect(scale)
        .frame(width: canvasSide, height: canvasSide)
        .onChange(of: previewContent, initial: true) { _, content in
            preview.load(from: content.configuration)
            syncPreview()
        }
        .onChange(of: model.selection) { _, _ in syncPreview() }
        .transaction { $0.animation = nil }
    }

    private var previewContent: MenuEditorPreviewContent {
        MenuEditorPreviewContent(
            inner: model.inner, middle: model.middle,
            hudCustomization: model.hudCustomization, appearance: appearance
        )
    }

    // MARK: - Customization marks (App HUD only)

    private func wedgeAngles(_ band: Band, _ index: Int) -> (start: Angle, end: Angle) {
        RadialGeometry.wedgeAngles(
            band: band, index: index, geometry: preview.geometry,
            expandedParentIndex: preview.expandedParentIndex,
            outerCount: preview.outerItems.count,
            outerLayout: preview.outerRingLayout
        )
    }

    private func bandRadii(_ band: Band) -> (inner: CGFloat, outer: CGFloat) {
        switch band {
        case .inner: (preview.radii.r0, preview.radii.r1)
        case .middle: (preview.radii.r1, preview.radii.r2)
        case .outer: (preview.radii.r2, preview.radii.r3)
        }
    }

    /// Fixed-size overlay in the ring's own square: it cannot shift layout,
    /// and the caller disables hit-testing and hides it from accessibility.
    private var customizationDots: some View {
        let side = 2 * preview.radii.r3
        let center = CGPoint(x: side / 2, y: side / 2)
        let marks: [(band: Band, index: Int, id: UUID)] =
            preview.innerItems.enumerated().map { (.inner, $0.offset, $0.element.id) }
            + preview.middleItems.enumerated().map { (.middle, $0.offset, $0.element.id) }
        return ZStack {
            ForEach(marks.indices.filter { isCustomized(marks[$0].id, in: marks[$0].band) }, id: \.self) { index in
                let mark = marks[index]
                let angles = wedgeAngles(mark.band, mark.index)
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: RingPreviewCustomizationMarker.dotDiameter,
                           height: RingPreviewCustomizationMarker.dotDiameter)
                    .position(RingPreviewCustomizationMarker.dotPosition(
                        start: angles.start, end: angles.end,
                        outerRadius: bandRadii(mark.band).outer, center: center
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

    private var outerRingGuidePresentation: EditorOuterRingGuidePresentation {
        EditorOuterRingGuidePresentation(
            radii: preview.radii,
            visibility: model.hudCustomization.outerRingVisibility,
            hasLocalizedOuterSurface: preview.isOuterRingVisible
        )
    }

    private var snapshot: HUDPreviewInteractionSnapshot {
        HUDPreviewInteractionSnapshot(
            geometry: preview.geometry,
            radii: preview.radii,
            innerCount: preview.innerItems.count,
            middleCount: preview.middleItems.count,
            expandedParentIndex: preview.expandedParentIndex,
            outerCount: preview.outerItems.count,
            outerVisibility: model.hudCustomization.outerRingVisibility,
            outerLayout: preview.outerRingLayout
        )
    }

    private func previewSlot(for intent: HUDPreviewIntent) -> SlotSelection? {
        switch intent {
        case let .selectTopLevel(band, index):
            let items = band == .inner ? preview.innerItems : preview.middleItems
            guard items.indices.contains(index) else { return nil }
            return SlotSelection(band: band, itemID: items[index].id, subItemID: nil)
        case let .selectOuter(index):
            guard let parentIndex = preview.expandedParentIndex,
                  preview.middleItems.indices.contains(parentIndex),
                  preview.outerItems.indices.contains(index) else { return nil }
            let parent = preview.middleItems[parentIndex]
            guard parent.dynamicSource == .none else { return nil }
            return SlotSelection(band: .middle, itemID: parent.id, subItemID: preview.outerItems[index].id)
        }
    }

    private func contains(_ slot: SlotSelection) -> Bool {
        let items = slot.band == .inner ? model.inner : model.middle
        guard let parent = items.first(where: { $0.id == slot.itemID }) else { return false }
        guard let child = slot.subItemID else { return true }
        return slot.band == .middle && parent.dynamicSource == .none
            && parent.subItems?.contains { $0.id == child } == true
    }

    private func apply(_ intent: HUDPreviewIntent) {
        guard let slot = previewSlot(for: intent), contains(slot) else { return }
        model.activeBand = slot.band
        model.selection = slot
    }

    private func syncPreview() {
        preview.appearance.motion.isEnabled = false
        preview.innerItems = model.inner
        preview.middleItems = model.middle
        preview.hudCustomization = model.hudCustomization
        if let parent = expandedMiddleParent() {
            if parent.item.dynamicSource == .runningApps {
                preview.expandedParentIndex = parent.index
                preview.outerItems = Self.runningAppsPreviewPlaceholder
            } else {
                preview.expand(parent.index)
            }
        } else {
            preview.reset()
        }
        preview.innerItems = model.inner
        preview.middleItems = model.middle
        preview.hudCustomization = model.hudCustomization
        preview.activeSelection = nil
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

    private func deleteTarget(for intent: HUDPreviewIntent) -> SlotSelection? {
        guard let slot = previewSlot(for: intent), canDelete(slot) else { return nil }
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

    private func applyAccessibilitySelection(_ selection: ActiveSelection) {
        switch selection.band {
        case .inner: apply(.selectTopLevel(.inner, selection.index))
        case .middle: apply(.selectTopLevel(.middle, selection.index))
        case .outer: apply(.selectOuter(selection.index))
        }
    }

    private func revealPreviewOuterRing() {
        let center = CGPoint(x: preview.radii.r3, y: preview.radii.r3)
        preview.updateOuterRingReveal(
            at: CGPoint(x: center.x + preview.radii.r1, y: center.y), center: center
        )
        preview.updateOuterRingReveal(
            at: CGPoint(x: center.x + preview.radii.r1 + 1, y: center.y), center: center
        )
    }

    private func expandedMiddleParent() -> (item: RingMenuItem, index: Int)? {
        guard let selection = model.selection, selection.band == .middle,
              let id = selection.itemID,
              let index = model.middle.firstIndex(where: { $0.id == id }),
              model.middle[index].hasSubItems else { return nil }
        return (model.middle[index], index)
    }
}

/// One observed snapshot includes both the editable profile and shared geometry.
/// Loading it uses the same configuration path as the live HUD.
struct MenuEditorPreviewContent: Equatable {
    let inner: [RingMenuItem]
    let middle: [RingMenuItem]
    let hudCustomization: HUDCustomization
    let appearance: AppearanceConfig

    var configuration: Configuration {
        Configuration(inner: inner, middle: middle, appearance: appearance,
                      hudCustomization: hudCustomization)
    }
}
