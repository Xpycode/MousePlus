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
struct SlotSelection: Hashable {
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
/// 3. **8-spoke cap (per band)** — ``addItem(to:)`` is a no-op once its band has
///    8 items (``atCap(for:)``). The cap is per-band because the shared spoke
///    count is `min(8, max(inner, middle))` — the shorter band growing never
///    pushes N past 8, so it must not be blocked by the longer band being full.
/// 4. **Type-consistent payload** — `actionData`'s meaning is defined by
///    `actionType` (bundle id / `SnapZone` raw value / shell command). When a
///    binding write changes the type but carries the old payload along unchanged,
///    the setters reset `actionData` to the new type's default so the runtime
///    never silently no-ops on a payload minted for a different type.
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
        normalizeSnapPayloads()
    }

    /// Replace the working rings from a full configuration.
    ///
    /// Save reconciliation preserves the selected UUID when it still exists so
    /// an autosave cannot tear down the active editor form (and its keyboard
    /// focus). Initial/recovery loads keep the default clearing behavior.
    func load(from config: Configuration, preservingSelection: Bool = false) {
        let previousSelection = preservingSelection ? selection : nil
        inner = config.inner
        middle = config.middle
        enforceInnerInvariants()
        normalizeSnapPayloads()
        selection = previousSelection.flatMap(validSelection)
    }

    private func validSelection(_ selection: SlotSelection) -> SlotSelection? {
        let items = selection.band == .inner ? inner : middle
        guard let itemID = selection.itemID,
              let parent = items.first(where: { $0.id == itemID }) else { return nil }
        guard let subItemID = selection.subItemID else { return selection }
        guard selection.band == .middle,
              parent.subItems?.contains(where: { $0.id == subItemID }) == true else { return nil }
        return selection
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

    /// Whether the 8-spoke cap has been reached by the LARGER band (drives the
    /// "N of 8" readout). Not an add-gate: use ``atCap(for:)`` for that — the
    /// shorter band may legally grow until it reaches 8 itself, since
    /// `N = min(8, max(inner, middle))` doesn't change when the non-max band adds.
    var atSpokeCap: Bool {
        spokesUsed >= 8
    }

    /// Whether `band` itself is full (8 items) and may not receive another item.
    func atCap(for band: EditorBand) -> Bool {
        self[keyPath: arrayKeyPath(for: band)].count >= 8
    }

    /// Generous cap on sub-items (outer arc) per middle item. High enough to hold
    /// the 10-zone Snap default with headroom, but bounded so the outer arc — which
    /// saturates the full circle near 3·N wedges — can't be packed into unhittable
    /// slivers. Gates ``addSubItem(toMiddle:)`` (the UI also disables the button).
    static let maxSubItems = 12

    /// Whether the middle item `parentID` has reached ``maxSubItems`` sub-items.
    func subItemsAtCap(for parentID: UUID) -> Bool {
        guard let parent = middle.first(where: { $0.id == parentID }) else { return false }
        return (parent.subItems?.count ?? 0) >= Self.maxSubItems
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
                let old = self[keyPath: keyPath][index]
                self[keyPath: keyPath][index] = Self.normalizingTypeSwitch(old: old, new: newValue)
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
                      let subIndex = self.middle[parentIndex].subItems?.firstIndex(where: { $0.id == id }),
                      let old = self.middle[parentIndex].subItems?[subIndex] else {
                    return
                }
                self.middle[parentIndex].subItems?[subIndex] = Self.normalizingTypeSwitch(old: old, new: newValue)
            }
        )
    }

    // MARK: - Mutation API

    /// Append a new blank top-level item to `band` and select it.
    ///
    /// No-op when ``atCap(for:)`` says that band is full (the UI also disables
    /// the button — invariant 3). The cap is per-band: middle at 8 must not
    /// block inner from growing toward 8.
    func addItem(to band: EditorBand) {
        guard !atCap(for: band) else { return }

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
        guard !subItemsAtCap(for: parentID) else { return }   // invariant 3, outer band

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

        // A `.windowSnap` parent that just lost its last sub-item is now a DIRECT
        // snap item with no zone — give it a real one so it doesn't silently no-op
        // while the detail form claims "Left" (invariant 4).
        normalizeSnapPayloads()

        // Repoint selection to the parent middle item.
        selection = SlotSelection(band: .middle, itemID: parentID, subItemID: nil)
    }

    /// Reset both rings to the built-in defaults and clear selection.
    func resetToDefaults() {
        inner = RingMenuItem.sampleInnerItems
        middle = RingMenuItem.sampleItems
        selection = nil
        enforceInnerInvariants()
        normalizeSnapPayloads()
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

    /// Reset a carried-over payload when a binding write switches `actionType`
    /// (invariant 4: type-consistent payload).
    ///
    /// Fires only when the type changed AND the payload came through unchanged —
    /// i.e. the write left the *old type's* payload behind (an action-type picker
    /// change). A caller that deliberately sets type + payload together is untouched.
    private static func normalizingTypeSwitch(old: RingMenuItem, new: RingMenuItem) -> RingMenuItem {
        guard old.actionType != new.actionType else { return new }
        var item = new
        // A picker changes only the type, so any payload owned by the previous
        // type must not follow it. Keep an explicitly supplied replacement,
        // which lets import/migration code set type and payload atomically.
        if old.actionData == new.actionData {
            item.actionData = defaultActionData(for: new.actionType)
        }
        if old.keystrokePayload == new.keystrokePayload {
            item.keystrokePayload = nil
        }
        return item
    }

    /// The payload a freshly (re)typed item starts with. `.windowSnap` defaults to
    /// a real zone (matching `ActionDataEditor`'s display fallback) so what the
    /// picker shows is what the runtime does; everything else starts empty.
    private static func defaultActionData(for type: ActionType) -> String {
        type == .windowSnap ? SnapZone.left.rawValue : ""
    }

    /// Strip `subItems` from every inner item (invariant 1: inner is direct-only).
    ///
    /// Called after any mutation to `inner` so the inner ring can never accumulate
    /// nested sub-items, even via an arbitrary binding write.
    private func enforceInnerInvariants() {
        for index in inner.indices where inner[index].subItems != nil {
            inner[index].subItems = nil
        }
    }

    /// Give a DIRECT `.windowSnap` item a real zone when its payload is missing or
    /// invalid (invariant 4). A wedge whose sub-items were all deleted — or a
    /// hand-edited config — otherwise ends up a `.windowSnap` with an empty
    /// `actionData` that `ActionService` silently no-ops on, while the detail form
    /// misleadingly shows "Left". Setting a real zone makes the runtime match the
    /// UI. Parent markers (items that STILL carry sub-items) are skipped: their
    /// `actionData` is never executed, and rewriting it would needlessly churn the
    /// on-disk sample config (whose Snap parent legitimately has an empty payload).
    private func normalizeSnapPayloads() {
        func fix(_ item: inout RingMenuItem) {
            guard item.actionType == .windowSnap,
                  !item.hasSubItems,
                  SnapZone(rawValue: item.actionData) == nil else { return }
            item.actionData = SnapZone.left.rawValue
        }
        for i in inner.indices { fix(&inner[i]) }
        for i in middle.indices {
            fix(&middle[i])
            if var subs = middle[i].subItems {
                for j in subs.indices { fix(&subs[j]) }
                middle[i].subItems = subs
            }
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
