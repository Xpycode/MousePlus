import SwiftUI

/// A cursor-driven selection: which band, and which item index within it.
///
/// Drives both highlight and dimming (`IMPLEMENTATION_PLAN.md` §2.2). Kept as a
/// small `Equatable` struct rather than a tuple so `@Observable` change tracking
/// and SwiftUI animations behave predictably.
struct ActiveSelection: Equatable {
    let band: Band
    let index: Int
}

/// Main view model for the concentric wedge ring menu.
///
/// State model (§2):
///   - `innerItems` / `middleItems` are two **independent** action sets that share
///     only spoke geometry — not a parent/child relationship.
///   - `outerItems` are the sub-commands of the currently expanded middle wedge
///     (empty when nothing is expanded). Outer items are **direct only** (depth cap 3).
///   - `expandedParentIndex` is the middle wedge that owns the outer arc, or `nil`.
///   - `activeSelection` is the cursor-driven `(band, index)` highlight.
@MainActor
@Observable
final class RingViewModel {

    // MARK: - New concentric-wedge state (T4)

    /// Inner band — symbol-only quick actions.
    var innerItems: [RingMenuItem] = RingMenuItem.sampleInnerItems
    /// Middle band — labeled items; each direct or expandable.
    var middleItems: [RingMenuItem] = RingMenuItem.sampleItems
    /// Sub-commands of the currently expanded middle wedge. Empty when none.
    var outerItems: [RingMenuItem] = []
    /// Which middle wedge is expanded (nil = none).
    var expandedParentIndex: Int?
    /// Current cursor-driven selection, or nil for the dead zone / out of bounds.
    var activeSelection: ActiveSelection?

    /// Band edge radii (defaults from §2.1). Sourced from `AppearanceConfig` via `load(from:)`.
    var radii = BandRadii()

    /// Appearance-driven values the ring view consumes directly (dim opacity,
    /// keepSpokeLit, animation flags). Set from `Configuration.appearance` in `load(from:)`.
    var appearance: AppearanceConfig = .default

    /// Whether the ring is on screen.
    var isVisible = false

    private let actionService = ActionService()

    /// Pure UI callback the owner (AppDelegate) sets to dismiss the panel after a
    /// *closing* commit (a direct/outer action fired). NOT invoked when a commit
    /// merely expands a middle wedge — the ring must stay open in that case.
    /// Carries no logic; it only requests the window be torn down.
    var requestClose: (() -> Void)?

    /// Locked spoke count `N` shared by inner + middle (§2.1).
    var spokeCount: Int {
        RadialGeometry.spokeCount(innerCount: innerItems.count,
                                  middleCount: middleItems.count)
    }

    // MARK: - Configuration loading

    /// Populate the independent inner/middle action sets from a `Configuration`.
    /// (T9 will call this on config reload; safe to call now.)
    func load(from config: Configuration) {
        innerItems = config.inner
        middleItems = config.middle
        appearance = config.appearance
        radii = config.appearance.bandRadii
        reset()
    }

    // MARK: - Item lookup

    /// Resolves a selection to the underlying item, bounds-checked.
    /// Returns nil for placeholder/empty wedges or out-of-range indices.
    func item(for selection: ActiveSelection) -> RingMenuItem? {
        let items: [RingMenuItem]
        switch selection.band {
        case .inner:  items = innerItems
        case .middle: items = middleItems
        case .outer:  items = outerItems
        }
        guard selection.index >= 0, selection.index < items.count else { return nil }
        return items[selection.index]
    }

    // MARK: - Hit-testing

    /// Maps a pointer location to the current `activeSelection` using
    /// `RadialGeometry.hitTest` with the live spoke/expansion state (§2.2).
    func updateActive(at point: CGPoint, center: CGPoint) {
        if let hit = RadialGeometry.hitTest(point: point,
                                            center: center,
                                            radii: radii,
                                            spokeCount: spokeCount,
                                            expandedParentIndex: expandedParentIndex,
                                            outerCount: outerItems.count) {
            activeSelection = ActiveSelection(band: hit.band, index: hit.index)
        } else {
            activeSelection = nil
        }
    }

    // MARK: - Commit / expand / collapse (§2.3)

    /// Act on the current `activeSelection`:
    ///   - Expandable middle wedge → re-point expansion in place (`expand`).
    ///   - Any direct item (inner / middle-direct / outer) → execute + `reset()`.
    ///   - Dead zone (nil) → cancel (no-op).
    func commitActive() {
        guard let selection = activeSelection,
              let item = item(for: selection) else {
            // Dead zone or empty/placeholder wedge → cancel.
            return
        }

        // Expandable middle wedge → re-point expansion. Outer items are
        // direct-only (depth cap 3), so never expand from `.outer`.
        if selection.band == .middle, item.hasSubItems {
            expand(selection.index)
            return
        }

        // Direct item → fire and fully reset, then ask the owner to close the panel.
        Task {
            try? await actionService.execute(item)
        }
        reset()
        requestClose?()
    }

    /// Expand a middle wedge: point `expandedParentIndex` at it and populate the
    /// outer band from its sub-items. Switching branches = just call with a
    /// different index (re-points in place, no explicit collapse needed).
    func expand(_ parentIndex: Int) {
        guard parentIndex >= 0, parentIndex < middleItems.count else { return }
        expandedParentIndex = parentIndex
        outerItems = middleItems[parentIndex].subItems ?? []
    }

    /// Collapse the outer band back to root (keeps any active selection).
    func collapse() {
        expandedParentIndex = nil
        outerItems = []
    }

    /// Full reset to root state — used on show/hide and after a direct commit.
    func reset() {
        activeSelection = nil
        expandedParentIndex = nil
        outerItems = []
    }
}
