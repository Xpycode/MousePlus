//
//  MenuEditorModel.swift
//  MousePlus
//
//  The Menu Items editor's working-state model.
//
//  Holds editable working copies of the two rings (inner + middle) that the
//  dedicated editor window mutates. Persistence and live-apply are wired up by
//  other tasks — this type performs pure model logic only (no ConfigurationService,
//  no AppDelegate, no views, no timers).
//

import SwiftUI
import Observation

// MARK: - Supporting Types

/// Which ring band a slot lives in.
enum EditorBand: Hashable {
    case inner
    case middle
}

/// Identifies the currently selected slot in the editor.
///
/// - `subItemID == nil` → a top-level slot in `band`.
/// - `subItemID != nil` → a sub-item (outer arc) of the middle item `itemID`.
struct SlotSelection: Equatable {
    /// The band the (top-level) slot lives in. Sub-items always belong to `.middle`.
    var band: EditorBand

    /// The top-level item. For sub-item editing this is the parent middle item.
    var itemID: UUID?

    /// The sub-item being edited, if any.
    var subItemID: UUID?
}

// MARK: - MenuEditorModel

/// Editor working-state for the Menu Items editor window.
///
/// The UI mutates this model freely; a later task merges the edited rings back
/// into the persisted `Configuration` via ``merged(into:)``.
///
/// ### Invariants enforced here
/// 1. **Inner ring is symbol-only + direct-only** — inner items never carry
///    `subItems` (always `nil`). Enforced by ``enforceInnerInvariants()`` after
///    every mutation to `inner`.
/// 2. **Depth cap 3 / sub-items only on middle** — only middle items may carry
///    sub-items, and sub-items never nest further. Guaranteed by simply not
///    exposing any API to add sub-items to inner items or to nest deeper.
/// 3. **8-spoke cap** — ``addItem(to:)`` is a no-op once ``atSpokeCap`` is true.
///
/// All lookups are by `id` (never by cached index) so the editor cannot trap on
/// an index-out-of-range when items are added/removed concurrently with binding writes.
@MainActor
@Observable
final class MenuEditorModel {

    // MARK: State

    /// Working copy of the inner ring (symbol-only quick actions).
    var inner: [RingMenuItem]

    /// Working copy of the middle ring (primary actions, may drill into sub-items).
    var middle: [RingMenuItem]

    /// The currently selected editor slot, if any.
    var selection: SlotSelection?

    /// Which band the editor UI is currently focused on.
    var activeBand: EditorBand = .middle

    // MARK: Init

    /// Create the model from working copies of the two rings.
    ///
    /// `RingMenuItem` is a value-type struct, so assigning the arrays already
    /// makes independent copies — edits here never touch the caller's arrays.
    init(inner: [RingMenuItem], middle: [RingMenuItem]) {
        self.inner = inner
        self.middle = middle
        enforceInnerInvariants()
    }

    /// Replace the working rings from a full configuration and clear selection.
    func load(from config: Configuration) {
        inner = config.inner
        middle = config.middle
        selection = nil
        enforceInnerInvariants()
    }

    // MARK: Computed

    /// Number of spokes (pie slices) the menu will render, clamped 1...8.
    var spokeCount: Int {
        RadialGeometry.spokeCount(innerCount: inner.count, middleCount: middle.count)
    }

    /// Spokes currently consumed by the larger of the two rings (for "N of 8 used").
    var spokesUsed: Int {
        max(inner.count, middle.count)
    }

    /// Whether the 8-spoke cap has been reached (disables adding more top-level items).
    var atSpokeCap: Bool {
        spokesUsed >= 8
    }

    // MARK: - Identity-keyed safe bindings
    //
    // The UI must NEVER index these arrays by position. These id-keyed bindings
    // look items up by `id` on both read and write; if the item has been removed,
    // the getter returns a harmless placeholder and the setter is a no-op — so a
    // stale binding can never trap.

    /// A harmless placeholder returned when an item lookup fails, so getters never trap.
    private static let placeholder = RingMenuItem(label: "", icon: "", actionType: .custom)

    /// Binding to a TOP-LEVEL item (inner or middle) identified by `id`.
    ///
    /// Returns `nil` if the item is no longer present. The returned binding's own
    /// closures remain crash-safe even if the item disappears after creation.
    func binding(forItem id: UUID, band: EditorBand) -> Binding<RingMenuItem>? {
        let keyPath = arrayKeyPath(for: band)
        guard self[keyPath: keyPath].contains(where: { $0.id == id }) else { return nil }

        return Binding(
            get: { [weak self] in
                guard let self else { return Self.placeholder }
                return self[keyPath: keyPath].first(where: { $0.id == id }) ?? Self.placeholder
            },
            set: { [weak self] newValue in
                guard let self else { return }
                guard let index = self[keyPath: keyPath].firstIndex(where: { $0.id == id }) else { return }
                self[keyPath: keyPath][index] = newValue
                // Re-assert inner invariants if we just wrote to the inner ring.
                if band == .inner { self.enforceInnerInvariants() }
            }
        )
    }

    /// Binding to a SUB-ITEM (outer arc) of the middle item `parentID`, identified by `id`.
    ///
    /// Returns `nil` if the parent or sub-item is gone. The binding's closures are
    /// crash-safe — a missing parent/sub-item makes the setter a no-op.
    func binding(forSubItem id: UUID, ofMiddle parentID: UUID) -> Binding<RingMenuItem>? {
        guard let parent = middle.first(where: { $0.id == parentID }),
              parent.subItems?.contains(where: { $0.id == id }) == true else {
            return nil
        }

        return Binding(
            get: { [weak self] in
                guard let self,
                      let parent = self.middle.first(where: { $0.id == parentID }),
                      let sub = parent.subItems?.first(where: { $0.id == id }) else {
                    return Self.placeholder
                }
                return sub
            },
            set: { [weak self] newValue in
                guard let self,
                      let parentIndex = self.middle.firstIndex(where: { $0.id == parentID }),
                      let subIndex = self.middle[parentIndex].subItems?.firstIndex(where: { $0.id == id }) else {
                    return
                }
                self.middle[parentIndex].subItems?[subIndex] = newValue
            }
        )
    }

    // MARK: - Mutation API

    /// Append a new blank top-level item to `band` and select it.
    ///
    /// No-op when ``atSpokeCap`` (the UI also disables the button — invariant 3).
    func addItem(to band: EditorBand) {
        guard !atSpokeCap else { return }

        // Inner items are symbol-only and never carry sub-items (invariant 1).
        let newItem = RingMenuItem(
            label: band == .inner ? "" : "New",
            icon: "questionmark",
            actionType: .custom
        )

        switch band {
        case .inner:
            inner.append(newItem)
            enforceInnerInvariants()
        case .middle:
            middle.append(newItem)
        }

        selection = SlotSelection(band: band, itemID: newItem.id, subItemID: nil)
    }

    /// Remove the currently selected item (top-level or sub-item) by id and
    /// repoint the selection sensibly.
    func removeSelectedItem() {
        guard let selection else { return }

        // Sub-item removal.
        if let subItemID = selection.subItemID, let parentID = selection.itemID {
            removeSubItem(subItemID, fromMiddle: parentID)
            return
        }

        // Top-level removal.
        guard let itemID = selection.itemID else { return }
        let band = selection.band
        let keyPath = arrayKeyPath(for: band)

        guard let index = self[keyPath: keyPath].firstIndex(where: { $0.id == itemID }) else {
            self.selection = nil
            return
        }

        self[keyPath: keyPath].remove(at: index)
        if band == .inner { enforceInnerInvariants() }

        // Repoint: prefer the item that shifted into this slot, else the previous,
        // else clear selection if the band is now empty.
        let array = self[keyPath: keyPath]
        if array.isEmpty {
            self.selection = nil
        } else {
            let newIndex = min(index, array.count - 1)
            self.selection = SlotSelection(band: band, itemID: array[newIndex].id, subItemID: nil)
        }
    }

    /// Move a top-level item left/right within its band (offset `-1` / `+1`).
    ///
    /// Clamps at the array ends — moving past an edge is a no-op.
    func moveItem(id: UUID, in band: EditorBand, by offset: Int) {
        let keyPath = arrayKeyPath(for: band)
        guard let index = self[keyPath: keyPath].firstIndex(where: { $0.id == id }) else { return }

        let target = index + offset
        guard target >= 0, target < self[keyPath: keyPath].count else { return }

        let item = self[keyPath: keyPath].remove(at: index)
        self[keyPath: keyPath].insert(item, at: target)
    }

    /// Append a blank sub-item to the middle item `parentID` and select it.
    ///
    /// Creates the `subItems` array if it was `nil`. Only middle items may carry
    /// sub-items (invariant 2); there is deliberately no inner equivalent.
    func addSubItem(toMiddle parentID: UUID) {
        guard let parentIndex = middle.firstIndex(where: { $0.id == parentID }) else { return }

        let newSub = RingMenuItem(label: "New", icon: "questionmark", actionType: .custom)
        if middle[parentIndex].subItems == nil {
            middle[parentIndex].subItems = [newSub]
        } else {
            middle[parentIndex].subItems?.append(newSub)
        }

        selection = SlotSelection(band: .middle, itemID: parentID, subItemID: newSub.id)
    }

    /// Remove a sub-item from the middle item `parentID`, repointing selection.
    func removeSubItem(_ id: UUID, fromMiddle parentID: UUID) {
        guard let parentIndex = middle.firstIndex(where: { $0.id == parentID }),
              let subIndex = middle[parentIndex].subItems?.firstIndex(where: { $0.id == id }) else {
            return
        }

        middle[parentIndex].subItems?.remove(at: subIndex)

        // If the array is now empty, normalize it back to nil so `hasSubItems` is false.
        if middle[parentIndex].subItems?.isEmpty == true {
            middle[parentIndex].subItems = nil
        }

        // Repoint selection to the parent middle item.
        selection = SlotSelection(band: .middle, itemID: parentID, subItemID: nil)
    }

    /// Reset both rings to the built-in defaults and clear selection.
    func resetToDefaults() {
        inner = RingMenuItem.sampleInnerItems
        middle = RingMenuItem.sampleItems
        selection = nil
        enforceInnerInvariants()
    }

    // MARK: - Merge

    /// Build a full `Configuration` to persist.
    ///
    /// Starts from `base` (the current on-disk config) so `triggers`, `appearance`
    /// and `behavior` are preserved, and swaps in the edited rings.
    func merged(into base: Configuration) -> Configuration {
        var config = base
        config.inner = inner
        config.middle = middle
        return config
    }

    // MARK: - Invariants

    /// Strip `subItems` from every inner item (invariant 1: inner is direct-only).
    ///
    /// Called after any mutation to `inner` so the inner ring can never accumulate
    /// nested sub-items, even via an arbitrary binding write.
    private func enforceInnerInvariants() {
        for index in inner.indices where inner[index].subItems != nil {
            inner[index].subItems = nil
        }
    }

    // MARK: - Helpers

    /// Writable key path to the array backing a band — keeps mutation code DRY
    /// while still routing every access through `id`-keyed lookups.
    private func arrayKeyPath(for band: EditorBand) -> ReferenceWritableKeyPath<MenuEditorModel, [RingMenuItem]> {
        switch band {
        case .inner: return \.inner
        case .middle: return \.middle
        }
    }
}
