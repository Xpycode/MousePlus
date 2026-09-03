import SwiftUI

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
        identifierPrefix: String = "hud.wedge"
    ) {
        let itemLabel = item.label.isEmpty ? "unlabeled" : item.label
        let symbolState = SFSymbol.isValid(item.icon) ? "" : ", invalid symbol; placeholder shown"
        label = "\(band) wedge, position \(position + 1), \(itemLabel), action \(item.actionType.displayName)\(symbolState)"
        isSelected = selected
        isUnavailable = unavailableReason != nil
        value = [
            selected ? "Selected" : "Not selected",
            unavailableReason.map { "Unavailable. \($0)" }
        ].compactMap { $0 }.joined(separator: ". ")
        identifier = "\(identifierPrefix).\(band.lowercased()).\(position + 1)"
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
    @State private var preview = RingViewModel()
    private let canvasSide: CGFloat = 448

    var body: some View {
        let side = 2 * preview.radii.r3
        let scale = HUDPreviewInteractionSnapshot.fitScale(
            logicalSide: side, canvasSide: canvasSide
        )

        ZStack {
            RingMenuView(
                viewModel: preview,
                interactionEnabled: false,
                accessibilityIdentifierPrefix: "menuItems.preview.wedge",
                exposesCenterSettings: false,
                onAccessibilitySelection: applyAccessibilitySelection,
                persistentSelection: editorActiveSelection
            )
                .allowsHitTesting(false)
            HUDPreviewInteractionView(
                snapshot: snapshot,
                onHover: { preview.activeSelection = $0 },
                onRevealChange: { if $0 { revealPreviewOuterRing() } },
                onIntent: apply,
                onDeleteIntent: delete
            )
            .frame(width: side, height: side)
        }
        .frame(width: side, height: side)
        .scaleEffect(scale)
        .frame(width: canvasSide, height: canvasSide)
        .onAppear { syncPreview() }
        .onChange(of: model.inner) { _, _ in syncPreview() }
        .onChange(of: model.middle) { _, _ in syncPreview() }
        .onChange(of: model.hudCustomization) { _, _ in syncPreview() }
        .onChange(of: model.selection) { _, _ in syncPreview() }
        .transaction { $0.animation = nil }
    }

    private var snapshot: HUDPreviewInteractionSnapshot {
        HUDPreviewInteractionSnapshot(
            geometry: preview.geometry,
            radii: preview.radii,
            innerCount: model.inner.count,
            middleCount: model.middle.count,
            expandedParentIndex: preview.expandedParentIndex,
            outerCount: preview.outerItems.count,
            outerVisibility: model.hudCustomization.outerRingVisibility
        )
    }

    private func apply(_ intent: HUDPreviewIntent) {
        switch intent {
        case let .selectTopLevel(band, index):
            let items = band == .inner ? model.inner : model.middle
            guard items.indices.contains(index) else { return }
            model.activeBand = band
            model.selection = SlotSelection(band: band, itemID: items[index].id, subItemID: nil)
        case let .selectOuter(index):
            guard let parent = expandedMiddleParent(),
                  let subs = parent.item.subItems, subs.indices.contains(index) else { return }
            model.activeBand = .middle
            model.selection = SlotSelection(band: .middle, itemID: parent.item.id,
                                            subItemID: subs[index].id)
        }
    }

    private func syncPreview() {
        preview.appearance.animationEnabled = false
        preview.innerItems = model.inner
        preview.middleItems = model.middle
        preview.hudCustomization = model.hudCustomization
        if let parent = expandedMiddleParent() { preview.expand(parent.index) }
        else { preview.reset() }
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

    private func delete(_ intent: HUDPreviewIntent) {
        apply(intent)
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
        preview.updateActive(
            at: CGPoint(x: center.x + preview.radii.r1, y: center.y), center: center
        )
        preview.updateActive(
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
