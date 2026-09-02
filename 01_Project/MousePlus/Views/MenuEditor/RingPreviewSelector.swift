//
//  RingPreviewSelector.swift
//  MousePlus
//
//  A live, interactive preview of the ring being edited.
//
//  It renders the real `RingMenuView` (with hit-testing disabled) and lays a
//  transparent selection overlay on top, so the user can click the wedge they
//  *see* to select the corresponding slot in the editor. Empty spokes show a
//  dashed "ghost" circle that adds a new item to that band.
//

import SwiftUI

struct RingWedgeAccessibility: Equatable {
    let label: String
    let value: String
    let identifier: String

    init(item: RingMenuItem, band: String, position: Int, selected: Bool) {
        let itemLabel = item.label.isEmpty ? "unlabeled" : item.label
        let symbolState = SFSymbol.isValid(item.icon) ? "" : ", invalid symbol; placeholder shown"
        label = "\(band) wedge, position \(position + 1), \(itemLabel), action \(item.actionType.displayName)\(symbolState)"
        value = selected ? "Selected" : "Not selected"
        identifier = "menuItems.wedge.\(band.lowercased()).\(position + 1)"
    }
}

/// Live ring preview with a click-to-select overlay.
///
/// Shows the concentric ring exactly as the runtime menu would render it, then
/// overlays transparent hotspots aligned to the same spoke geometry. Clicking a
/// hotspot updates `model.selection` / `model.activeBand`. The first empty spoke
/// of each band shows a dashed "add" ghost (respecting the 8-spoke cap).
@MainActor
struct RingPreviewSelector: View {
    @Bindable var model: MenuEditorModel

    /// A private render-only view model that mirrors the editor's bands so the
    /// real `RingMenuView` can draw the live ring. Never mutated by the user
    /// directly — kept in sync from `model` via `syncPreview()`.
    @State private var preview = RingViewModel()

    /// Hardcoded spoke ceiling — the editor caps at 8 spokes.
    private let maxSpokes = 8

    /// Diameter of a hotspot / ghost button.
    private let hotspotSize: CGFloat = 44

    /// Stable square reserved by the editor for the preview. Larger configured
    /// ring radii are scaled down to fit instead of overflowing neighboring UI.
    private let canvasSide: CGFloat = 448

    var body: some View {
        // The live ring is rendered in a square frame of side 2*r3, centered.
        let side = 2 * preview.radii.r3
        let previewScale = min(1, canvasSide / side)

        ZStack {
            // 1. Live ring — display only, no interaction.
            RingMenuView(viewModel: preview, interactionEnabled: false)
                .allowsHitTesting(false)

            // 2. Selection overlay, matched to the same frame + center.
            overlay(side: side)
        }
        .frame(width: side, height: side)
        .scaleEffect(previewScale)
        .frame(width: canvasSide, height: canvasSide)
        .onAppear { syncPreview() }
        .onChange(of: model.inner) { _, _ in syncPreview() }
        .onChange(of: model.middle) { _, _ in syncPreview() }
        .onChange(of: model.selection) { _, _ in syncPreview() }
        // Selection is editor state, not a geometry transition. Prevent the
        // render-only ring from interpolating between highlight/expansion states
        // when the user clicks rapidly across bands.
        .transaction { transaction in
            transaction.animation = nil
        }
    }

    // MARK: - Overlay

    @ViewBuilder
    private func overlay(side: CGFloat) -> some View {
        let center = CGPoint(x: side / 2, y: side / 2)

        // Iterate enough spokes to cover both bands plus one extra index so an
        // empty-band ghost can render at spoke 0, never exceeding the cap.
        // Whether a ghost actually appears is decided per band in `bandHotspot`
        // (it needs a genuinely empty spoke within the current geometry).
        // `Array(0..<slots)` (vs a literal range) avoids the dynamic-range ForEach
        // pitfall when `slots` changes between renders.
        let occupied = max(model.inner.count, model.middle.count)
        let slots = max(1, min(maxSpokes, occupied + 1))

        ZStack {
            ForEach(Array(0..<slots), id: \.self) { i in
                // Inner band hotspot (or ghost).
                bandHotspot(
                    spoke: i,
                    band: .inner,
                    items: model.inner,
                    center: center
                )

                // Middle band hotspot (or ghost).
                bandHotspot(
                    spoke: i,
                    band: .middle,
                    items: model.middle,
                    center: center
                )
            }

            // Sub-item hotspots for an expanded middle slot (outer arc).
            subItemHotspots()

            // An expanded outer arc otherwise has no explicit way back when the
            // parent remains selected. Keep the control in the ring's dead zone,
            // matching the visual language of drill-down navigation.
            if expandedMiddleParent() != nil {
                Button {
                    model.selection = nil
                } label: {
                    Image(systemName: "chevron.backward.circle.fill")
                        .font(.title2)
                        .symbolRenderingMode(.hierarchical)
                }
                .buttonStyle(.plain)
                .help("Close outer ring")
                .accessibilityLabel("Close outer ring")
                .accessibilityIdentifier("menuItems.outer.close")
                .position(center)
            }
        }
        .frame(width: side, height: side)
    }

    // MARK: - Top-level band hotspot

    /// A single spoke's hotspot for one band: a selectable button when the slot
    /// is filled, a dashed "add" ghost at the first empty spoke, or nothing.
    @ViewBuilder
    private func bandHotspot(
        spoke i: Int,
        band: EditorBand,
        items: [RingMenuItem],
        center: CGPoint
    ) -> some View {
        // Use the SAME geometry the live ring uses, so "click the wedge you see"
        // lands correctly. The geometry's spoke count is derived from the actual
        // band counts (matching RadialGeometry.spokeCount), so wedge angles align.
        let geoBand: Band = (band == .inner) ? .inner : .middle
        let n = RadialGeometry.spokeCount(
            innerCount: model.inner.count,
            middleCount: model.middle.count
        )
        let pos = RadialGeometry.centroid(
            band: geoBand,
            index: i,
            center: center,
            radii: preview.radii,
            spokeCount: n,
            expandedParentIndex: nil,
            outerCount: 0
        )

        if i < items.count {
            // Filled slot — the entire visible annular wedge is selectable.
            // The former 44pt circular hotspot made clicks work only on/near the
            // icon and left most of the pane inert.
            let item = items[i]
            let isSelected = isSlotSelected(band: band, itemID: item.id)
            let accessibility = RingWedgeAccessibility(
                item: item,
                band: band == .inner ? "Inner" : "Middle",
                position: i,
                selected: isSelected
            )
            let angles = RadialGeometry.wedgeAngles(
                band: geoBand,
                index: i,
                spokeCount: n,
                expandedParentIndex: nil,
                outerCount: 0
            )
            let radii = preview.radii
            let shape = AnnularWedge(
                startAngle: angles.start,
                endAngle: angles.end,
                innerRadius: geoBand == .inner ? radii.r0 : radii.r1,
                outerRadius: geoBand == .inner ? radii.r1 : radii.r2
            )
            let side = 2 * radii.r3

            Button {
                model.activeBand = band
                model.selection = SlotSelection(band: band, itemID: item.id, subItemID: nil)
            } label: {
                shape
                    .fill(Color.white.opacity(0.001))
            }
            .buttonStyle(.plain)
            .contentShape(shape)
            .frame(width: side, height: side)
            .accessibilityLabel(accessibility.label)
            .accessibilityValue(accessibility.value)
            .accessibilityIdentifier(accessibility.identifier)
            .help(item.label.isEmpty ? "Empty" : item.label)

        } else if i == items.count, i < n {
            // First empty spoke for this band — dashed "click to add" ghost.
            // The `i < n` guard matters: when a band is already full to the current
            // spoke count, `centroid` would clamp the index and park the ghost ON
            // TOP of the last real wedge's hotspot (stealing its clicks). A band
            // full to N gets no in-ring ghost — the toolbar "Add" button covers it.
            // (`i < n` also implies the band is under the 8-item cap, since n ≤ 8.)
            AppKitButton(
                title: "",
                accessibilityLabel: "Add \(band == .inner ? "inner" : "middle") item at position \(i + 1)",
                accessibilityIdentifier: "menuItems.wedge.\(band == .inner ? "inner" : "middle").add.\(i + 1)"
            ) {
                model.activeBand = band
                model.addItem(to: band) // appends at end == fills this spoke
            }
            .frame(width: hotspotSize, height: hotspotSize)
            .opacity(0.02)
            .overlay {
                Circle()
                    .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                    .foregroundStyle(.secondary)
                    .allowsHitTesting(false)
                    .overlay {
                        Image(systemName: "plus")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
            }
            .position(pos)
            .help("Add item")
        }
        // Spokes beyond the first empty one render nothing.
    }

    // MARK: - Sub-item hotspots (outer arc)

    /// Sub-item selection for the currently expanded middle slot.
    ///
    /// Uses the same localized-arc geometry as `RingMenuView`, so each visible
    /// outer wedge is directly clickable without a second button strip that can
    /// overflow the preview canvas.
    @ViewBuilder
    private func subItemHotspots() -> some View {
        if let (parent, parentIndex) = expandedMiddleParent() {
            let subs = parent.subItems ?? []
            let spokeCount = preview.spokeCount
            let radii = preview.radii
            let side = 2 * radii.r3

            ForEach(Array(subs.enumerated()), id: \.element.id) { position, sub in
                let isSelected = model.selection?.subItemID == sub.id
                let accessibility = RingWedgeAccessibility(
                    item: sub,
                    band: "Outer",
                    position: position,
                    selected: isSelected
                )
                let angles = RadialGeometry.wedgeAngles(
                    band: .outer,
                    index: position,
                    spokeCount: spokeCount,
                    expandedParentIndex: parentIndex,
                    outerCount: subs.count
                )
                let shape = AnnularWedge(
                    startAngle: angles.start,
                    endAngle: angles.end,
                    innerRadius: radii.r2,
                    outerRadius: radii.r3
                )

                Button {
                    model.activeBand = .middle
                    model.selection = SlotSelection(
                        band: .middle,
                        itemID: parent.id,
                        subItemID: sub.id
                    )
                } label: {
                    shape
                        .fill(Color.white.opacity(0.001))
                }
                .buttonStyle(.plain)
                .contentShape(shape)
                .frame(width: side, height: side)
                .accessibilityLabel(accessibility.label)
                .accessibilityValue(accessibility.value)
                .accessibilityIdentifier(accessibility.identifier)
                .help(sub.label.isEmpty ? "Outer item" : sub.label)
            }
        }
    }

    // MARK: - Sync

    /// Mirror the editor's bands into the render-only `preview` view model, and
    /// drive outer-arc expansion based on the current selection.
    ///
    /// `RingViewModel.reset()` only clears the outer band, so we always re-assign
    /// the inner/middle items afterwards to stay in sync.
    private func syncPreview() {
        // The editor is a deterministic selector, not the runtime HUD. Runtime
        // springs and the parent-centroid scale transition make outer arcs appear
        // to fly in from whichever side owns the selected parent and make rapid
        // slot selection feel jumpy. Keep the user's HUD preference untouched;
        // disable animation only on this private render-only model.
        preview.appearance.animationEnabled = false
        preview.innerItems = model.inner
        preview.middleItems = model.middle

        if let (_, index) = expandedMiddleParent() {
            preview.expand(index)
        } else {
            preview.reset()
        }

        // Re-assert items in case reset/expand touched ordering expectations.
        preview.innerItems = model.inner
        preview.middleItems = model.middle
        preview.activeSelection = previewSelection()
    }

    /// Mirror editor identity selection into the render model's index selection.
    /// The real `WedgeView` then owns the highlight, guaranteeing its geometry is
    /// identical to the visible slice instead of redrawing a second outline layer.
    private func previewSelection() -> ActiveSelection? {
        guard let selection = model.selection else { return nil }
        switch selection.band {
        case .inner:
            guard let itemID = selection.itemID,
                  let index = model.inner.firstIndex(where: { $0.id == itemID })
            else { return nil }
            return ActiveSelection(band: .inner, index: index)
        case .middle:
            guard let itemID = selection.itemID,
                  let parentIndex = model.middle.firstIndex(where: { $0.id == itemID })
            else { return nil }
            if let subItemID = selection.subItemID,
               let subIndex = model.middle[parentIndex].subItems?.firstIndex(where: { $0.id == subItemID }) {
                return ActiveSelection(band: .outer, index: subIndex)
            }
            return ActiveSelection(band: .middle, index: parentIndex)
        }
    }

    // MARK: - Selection helpers

    /// The middle top-level item that should be expanded (selected, has subitems),
    /// together with its index in `model.middle`. Nil if none.
    private func expandedMiddleParent() -> (item: RingMenuItem, index: Int)? {
        guard let sel = model.selection,
              sel.band == .middle,
              let parentID = sel.itemID else { return nil }
        guard let index = model.middle.firstIndex(where: { $0.id == parentID }) else { return nil }
        let item = model.middle[index]
        guard item.hasSubItems else { return nil }
        return (item, index)
    }

    /// Whether the given (band, item) is the currently selected top-level slot.
    private func isSlotSelected(band: EditorBand, itemID: UUID) -> Bool {
        guard let sel = model.selection else { return false }
        return sel.band == band && sel.itemID == itemID && sel.subItemID == nil
    }

}
