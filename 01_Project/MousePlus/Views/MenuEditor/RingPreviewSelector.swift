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
            innerCount: model.inner.count,
            middleCount: model.middle.count,
            expandedParentIndex: preview.expandedParentIndex,
            outerCount: preview.outerItems.count,
            outerVisibility: model.hudCustomization.outerRingVisibility,
            outerLayout: preview.outerRingLayout
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
                  parent.item.dynamicSource == .none,
                  let subs = parent.item.subItems, subs.indices.contains(index) else { return }
            model.activeBand = .middle
            model.selection = SlotSelection(band: .middle, itemID: parent.item.id,
                                            subItemID: subs[index].id)
        }
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
