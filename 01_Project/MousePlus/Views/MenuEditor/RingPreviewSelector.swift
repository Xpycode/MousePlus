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

    var body: some View {
        // The live ring is rendered in a square frame of side 2*r3, centered.
        let side = 2 * preview.radii.r3

        ZStack {
            // 1. Live ring — display only, no interaction.
            RingMenuView(viewModel: preview)
                .allowsHitTesting(false)

            // 2. Selection overlay, matched to the same frame + center.
            overlay(side: side)
        }
        .frame(width: side, height: side)
        .onAppear { syncPreview() }
        .onChange(of: model.inner) { _, _ in syncPreview() }
        .onChange(of: model.middle) { _, _ in syncPreview() }
        .onChange(of: model.selection) { _, _ in syncPreview() }
    }

    // MARK: - Overlay

    @ViewBuilder
    private func overlay(side: CGFloat) -> some View {
        let center = CGPoint(x: side / 2, y: side / 2)

        // Iterate enough spokes to cover both bands plus (optionally) one empty
        // "add" slot, never exceeding the cap. We pass the *real* band counts to
        // the geometry so wedge angles line up with what RingMenuView draws.
        // `Array(0..<slots)` (vs a literal range) avoids the dynamic-range ForEach
        // pitfall when `slots` changes between renders.
        let occupied = max(model.inner.count, model.middle.count)
        let slots = max(0, min(maxSpokes, occupied + (model.atSpokeCap ? 0 : 1)))

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
            // Filled slot — transparent selectable button + selection highlight.
            let item = items[i]
            let isSelected = isSlotSelected(band: band, itemID: item.id)
            // Faint companion highlight: when *this same spoke* is selected in the
            // other band, hint at shared-spoke alignment.
            let isSpokeActive = isSpokeSelected(spoke: i)

            Button {
                model.activeBand = band
                model.selection = SlotSelection(band: band, itemID: item.id, subItemID: nil)
            } label: {
                Circle()
                    .fill(Color.clear)
                    .frame(width: hotspotSize, height: hotspotSize)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .overlay {
                if isSelected {
                    Circle()
                        .stroke(Color.accentColor, lineWidth: 3)
                        .frame(width: hotspotSize, height: hotspotSize)
                } else if isSpokeActive {
                    // Shared-spoke hint on the non-selected band.
                    Circle()
                        .stroke(Color.accentColor.opacity(0.3), lineWidth: 2)
                        .frame(width: hotspotSize, height: hotspotSize)
                }
            }
            .position(pos)
            .help(item.label.isEmpty ? "Empty" : item.label)

        } else if i == items.count && !model.atSpokeCap {
            // First empty spoke for this band — dashed "click to add" ghost.
            Button {
                model.activeBand = band
                model.addItem(to: band) // appends at end == fills this spoke
            } label: {
                Circle()
                    .strokeBorder(
                        style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])
                    )
                    .foregroundStyle(.secondary)
                    .frame(width: hotspotSize, height: hotspotSize)
                    .overlay {
                        Image(systemName: "plus")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .position(pos)
            .help("Add item")
        }
        // Spokes beyond the first empty one render nothing.
    }

    // MARK: - Sub-item hotspots (outer arc)

    /// Sub-item selection for the currently expanded middle slot.
    ///
    /// The runtime outer band is a *localized arc* around the parent spoke, which
    /// is awkward to reproduce pixel-for-pixel. For v1 correctness we render the
    /// sub-item selection as a clearly labeled strip of small buttons below the
    /// ring rather than geometric hotspots — every sub-item stays clickable and
    /// the mapping is unambiguous.
    @ViewBuilder
    private func subItemHotspots() -> some View {
        if let (parent, _) = expandedMiddleParent() {
            let subs = parent.subItems ?? []
            if !subs.isEmpty {
                VStack(spacing: 4) {
                    Spacer()
                    Text("Sub-items:")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 6) {
                        ForEach(subs) { sub in
                            let isSelected = (model.selection?.subItemID == sub.id)
                            Button {
                                model.activeBand = .middle
                                model.selection = SlotSelection(
                                    band: .middle,
                                    itemID: parent.id,
                                    subItemID: sub.id
                                )
                            } label: {
                                Label(
                                    sub.label.isEmpty ? "Item" : sub.label,
                                    systemImage: sub.icon.isEmpty ? "circle" : sub.icon
                                )
                                .labelStyle(.titleAndIcon)
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(
                                    RoundedRectangle(cornerRadius: 5)
                                        .fill(isSelected ? Color.accentColor.opacity(0.25) : Color.secondary.opacity(0.12))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 5)
                                        .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 1.5)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.bottom, 4)
                }
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

    /// Whether the selected top-level slot lives on the given spoke index
    /// (matched by the item's index within its band). Used for the faint
    /// shared-spoke companion highlight.
    private func isSpokeSelected(spoke i: Int) -> Bool {
        guard let sel = model.selection, sel.subItemID == nil,
              let id = sel.itemID else { return false }
        let band = sel.band
        let items = band == .inner ? model.inner : model.middle
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return false }
        return idx == i
    }
}
