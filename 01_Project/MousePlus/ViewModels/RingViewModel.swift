import AppKit
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

enum RingCommitResult: Equatable {
    case noSelection
    case unavailable
    case expanded
    case executed
}

/// Pure outer-ring policy state shared by the runtime HUD and editor preview.
/// Pointer history is scoped to the HUD invocation: expansion controls whether
/// an outer ring is eligible to render, but it does not start or reset the
/// center-to-outside traversal that Reveal records.
struct OuterRingPolicyState: Equatable {
    private(set) var hasEnteredInnerBoundary = false
    private(set) var hasRevealedOuterRing = false

    struct Resolution: Equatable {
        let state: OuterRingPolicyState
        let isEligible: Bool
        let isVisible: Bool
    }

    static func parentIsAvailable(policy: OuterRingVisibility, itemCount: Int) -> Bool {
        policy != .alwaysHidden && itemCount > 0
    }

    func transition(
        policy: OuterRingVisibility,
        hasExpandedParent: Bool,
        itemCount: Int,
        pointerIsAtOrInsideInnerBoundary: Bool? = nil
    ) -> Resolution {
        var next = self
        if policy == .revealBeyondInnerRing,
           let pointerIsAtOrInsideInnerBoundary {
            if pointerIsAtOrInsideInnerBoundary {
                next.hasEnteredInnerBoundary = true
            } else if next.hasEnteredInnerBoundary {
                next.hasRevealedOuterRing = true
            }
        }

        let eligible = hasExpandedParent && Self.parentIsAvailable(
            policy: policy, itemCount: itemCount
        )
        guard eligible else {
            return Resolution(state: next, isEligible: false, isVisible: false)
        }

        let visible = policy == .alwaysVisible
            || (policy == .revealBeyondInnerRing && next.hasRevealedOuterRing)
        return Resolution(state: next, isEligible: true, isVisible: visible)
    }
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

    /// Runtime-only icons for `.runningApps`-sourced outer items, keyed by item
    /// `id`. Side dictionary — never persisted, never touches the `Codable` model.
    private(set) var dynamicIcons: [RingMenuItem.ID: NSImage] = [:]

    /// Bumped on every `expand()` call (and on `collapse()`/`reset()`) so a stale
    /// in-flight async fetch from a since-collapsed or re-pointed expansion can
    /// never assign late.
    private var expansionEpoch = 0

    /// Band edge radii (defaults from §2.1). Sourced from `AppearanceConfig` via `load(from:)`.
    var radii = BandRadii()

    /// Appearance-driven values the ring view consumes directly (dim opacity,
    /// keepSpokeLit, animation flags). Set from `Configuration.appearance` in `load(from:)`.
    var appearance: AppearanceConfig = .default

    /// Persisted HUD policy and per-band layout loaded with the menu items.
    var hudCustomization: HUDCustomization = .default

    /// Independent effective top-level geometry after resolving auto/fixed mode.
    var geometry: TopLevelRingGeometry {
        TopLevelRingGeometry(
            inner: effectiveGeometry(for: hudCustomization.inner.layout,
                                     itemCount: innerItems.count),
            middle: effectiveGeometry(for: hudCustomization.middle.layout,
                                      itemCount: middleItems.count)
        )
    }

    /// Whether conditional reveal has latched for this invocation.
    private var outerRingPolicyState = OuterRingPolicyState()
    var hasRevealedOuterRing: Bool { outerRingPolicyState.hasRevealedOuterRing }
    /// A reveal is only eligible after the pointer has reached `r1` or inward.
    var hasEnteredInnerBoundary: Bool { outerRingPolicyState.hasEnteredInnerBoundary }

    /// Policy-resolved visibility. Availability still requires an expanded,
    /// non-empty parent branch.
    var isOuterRingVisible: Bool {
        outerRingPolicyState.transition(
            policy: hudCustomization.outerRingVisibility,
            hasExpandedParent: expandedParentIndex != nil,
            itemCount: outerItems.count
        ).isVisible
    }

    /// Whether the ring is on screen.
    var isVisible = false {
        didSet {
            if isVisible != oldValue { reset() }
        }
    }

    /// Frontmost application's PID, captured by the owner (AppDelegate) at
    /// ring-open — *before* our non-activating panel shows — so window/menu
    /// actions target the user's app and not MousePlus. `nil` if none.
    var frontmostPID: pid_t?

    private let actionService: ActionService
    private let actionResultRouter: ActionResultRouter

    init(
        actionService: ActionService = ActionService(),
        actionResultRouter: ActionResultRouter = ActionResultRouter()
    ) {
        self.actionService = actionService
        self.actionResultRouter = actionResultRouter
    }

    /// Pure UI callback the owner (AppDelegate) sets to dismiss the panel after a
    /// *closing* commit (a direct/outer action fired). NOT invoked when a commit
    /// merely expands a middle wedge — the ring must stay open in that case.
    /// Carries no logic; it only requests the window be torn down.
    var requestClose: (() -> Void)?

    /// Pure UI callback for routing the center control to Settings > Menu Items.
    var requestOpenMenuItemsSettings: (() -> Void)?

    /// Clears selectable state before either owner callback, preventing a later
    /// hold-release from committing the wedge active before Settings was pressed.
    func activateCenterSettings() {
        reset()
        requestClose?()
        requestOpenMenuItemsSettings?()
    }

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
        hudCustomization = config.hudCustomization
        reset()
    }

    /// Resolves persisted menu/ring/item presentation through the same path used
    /// by both the runtime HUD and editor preview.
    func iconOrientation(for band: Band) -> IconOrientation {
        ringAppearance(for: band).iconOrientation ?? hudCustomization.iconOrientation
    }

    /// Mirrors `iconOrientation(for:)`'s menu → ring inheritance, but for
    /// caption orientation. Independent of `iconOrientation` so reorienting a
    /// label never perturbs the icon.
    func labelOrientation(for band: Band) -> LabelOrientation {
        ringAppearance(for: band).labelOrientation ?? hudCustomization.labelOrientation
    }

    /// Unlike orientation, visibility has no menu-level default to inherit —
    /// each ring resolves its own `labelVisible` (see `HUDRingAppearance`).
    func isLabelVisible(for band: Band) -> Bool {
        ringAppearance(for: band).labelVisible
    }

    func colorResolution(
        for item: RingMenuItem,
        band: Band,
        application: HUDColorResolver.Overrides,
        backdrop: HUDColor
    ) -> HUDColorResolver.Resolution {
        let ring = ringAppearance(for: band)
        return HUDColorResolver.resolve(
            application: application,
            menu: .init(wedge: hudCustomization.wedgeColor,
                        icon: hudCustomization.iconColor),
            ring: .init(wedge: ring.wedgeColor, icon: ring.iconColor),
            item: .init(wedge: item.wedgeColor, icon: item.iconColor),
            backdrop: backdrop
        )
    }

    private func ringAppearance(for band: Band) -> HUDRingAppearance {
        switch band {
        case .inner: hudCustomization.inner.appearance
        case .middle: hudCustomization.middle.appearance
        case .outer: hudCustomization.outerAppearance
        }
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
        updateRevealState(at: point, center: center)
        if let hit = RadialGeometry.hitTest(point: point,
                                            center: center,
                                            radii: radii,
                                            geometry: geometry,
                                            innerItemCount: innerItems.count,
                                            middleItemCount: middleItems.count,
                                            expandedParentIndex: isOuterRingVisible ? expandedParentIndex : nil,
                                            outerCount: isOuterRingVisible ? outerItems.count : 0) {
            let selection = ActiveSelection(band: hit.band, index: hit.index)
            activeSelection = selection
            autoExpandRevealedParentIfNeeded(selection)
        } else {
            activeSelection = nil
        }
    }

    // MARK: - Commit / expand / collapse (§2.3)

    /// Act on the current `activeSelection`:
    ///   - Expandable middle wedge → re-point expansion in place (`expand`).
    ///   - Any direct item (inner / middle-direct / outer) → execute + `reset()`.
    ///   - Dead zone (nil) → cancel (no-op).
    @discardableResult
    func commitActive() -> RingCommitResult {
        guard let selection = activeSelection,
              let item = item(for: selection) else {
            // Dead zone or empty/placeholder wedge → cancel.
            return .noSelection
        }

        // Expandable middle wedge → re-point expansion. Outer items are
        // direct-only (depth cap 3), so never expand from `.outer`.
        if selection.band == .middle, item.hasSubItems {
            // A hidden submenu parent is unavailable. In particular, never
            // execute its marker action as a fallback.
            guard OuterRingPolicyState.parentIsAvailable(
                policy: hudCustomization.outerRingVisibility,
                itemCount: item.subItems?.count ?? 0
            ) else {
                activeSelection = nil
                return .unavailable
            }
            expand(selection.index)
            return .expanded
        }

        // Direct item → fire and fully reset, then ask the owner to close the panel.
        // Build the action context HERE, on the main actor: front-app PID (captured
        // at ring-open) plus a live screen-geometry snapshot for window snapping.
        // Cheap to build unconditionally; passed across the actor boundary as Sendable.
        let context = ActionContext(frontmostPID: frontmostPID,
                                    screenLayout: ScreenLayout.capture())
        Task {
            let result = await actionService.execute(item, context: context)
            await actionResultRouter.routeRuntimeResult(result, for: item.id)
        }
        reset()
        requestClose?()
        return .executed
    }

    /// Pointer-release/click commit path. Re-hit-tests at the event's final
    /// location so a stale hover can never be committed after crossing a band,
    /// an invisible slot, or the center dead zone.
    @discardableResult
    func commit(at point: CGPoint, center: CGPoint) -> RingCommitResult {
        updateActive(at: point, center: center)
        return commitActive()
    }

    /// Expand a middle wedge: point `expandedParentIndex` at it and populate the
    /// outer band from its sub-items (`.none`) or a runtime source (`.runningApps`).
    /// Switching branches = just call with a different index (re-points in place,
    /// no explicit collapse needed).
    func expand(_ parentIndex: Int) {
        guard parentIndex >= 0, parentIndex < middleItems.count else { return }
        expansionEpoch += 1
        let parent = middleItems[parentIndex]

        switch parent.dynamicSource {
        case .none:
            let items = parent.subItems ?? []
            guard OuterRingPolicyState.parentIsAvailable(
                policy: hudCustomization.outerRingVisibility, itemCount: items.count
            ) else { return }
            expandedParentIndex = parentIndex
            outerItems = items

        case .runningApps:
            expandedParentIndex = parentIndex
            // Transient empty arc — no "Loading…" placeholder; `NSWorkspace`
            // enumeration is effectively instant (APP_SWITCHER_PLAN.md §3).
            outerItems = []
            Task {
                // TODO(Wave 4): capture `let epoch = expansionEpoch` before this
                // Task, call AppSwitcherService.runningApps(), map the result to
                // RingMenuItems (actionType: .appSwitch, actionData: bundleIdentifier),
                // stash icons into dynamicIcons, cap at ~12, then
                //   guard epoch == expansionEpoch, expandedParentIndex == parentIndex
                //   else { return }
                // before assigning outerItems.
            }
        }
    }

    /// Collapse the outer band back to root (keeps any active selection).
    func collapse() {
        expandedParentIndex = nil
        outerItems = []
        dynamicIcons = [:]
        expansionEpoch += 1
    }

    /// Returns `true` when Escape should close the invocation. An expanded
    /// branch consumes the first Escape by collapsing back to root.
    func handleEscape() -> Bool {
        guard expandedParentIndex != nil else { return true }
        collapse()
        activeSelection = nil
        return false
    }

    var hiddenSubmenuUnavailableReason: String? {
        hudCustomization.outerRingVisibility == .alwaysHidden
            ? "Submenu hidden by HUD setting"
            : nil
    }

    /// Full reset to root state — used on show/hide and after a direct commit.
    func reset() {
        activeSelection = nil
        expandedParentIndex = nil
        outerItems = []
        dynamicIcons = [:]
        expansionEpoch += 1
        outerRingPolicyState = OuterRingPolicyState()
    }

    // MARK: - Effective geometry and invocation reveal

    private func effectiveGeometry(for layout: HUDRingLayout,
                                   itemCount: Int) -> RingBandGeometry {
        let boundedItems = min(max(itemCount, 1), HUDRingLayout.supportedSlotRange.upperBound)
        let slots: Int
        switch layout.slotCountMode {
        case .auto:
            slots = boundedItems
        case .fixed:
            // A malformed/stale fixed value must never overlap configured
            // items. Preserve all items while staying within the ring limit.
            slots = min(max(HUDRingLayout.clampedSlotCount(layout.fixedSlotCount),
                            boundedItems),
                        HUDRingLayout.supportedSlotRange.upperBound)
        }
        return RingBandGeometry(slotCount: slots,
                                angularOffset: CGFloat(layout.angularOffset * .pi / 180))
    }

    private func updateRevealState(at point: CGPoint, center: CGPoint) {
        let radius = hypot(point.x - center.x, point.y - center.y)
        outerRingPolicyState = outerRingPolicyState.transition(
            policy: hudCustomization.outerRingVisibility,
            hasExpandedParent: expandedParentIndex != nil,
            itemCount: outerItems.count,
            pointerIsAtOrInsideInnerBoundary: radius <= radii.r1
        ).state
    }

    /// Reveal mode is a hover-driven submenu interaction: once the invocation's
    /// center-to-outside traversal latches, entering an expandable middle wedge
    /// immediately points the outer arc at that parent. Always keeps its
    /// click/release-to-expand behavior, and Hidden remains unavailable.
    private func autoExpandRevealedParentIfNeeded(_ selection: ActiveSelection) {
        guard hudCustomization.outerRingVisibility == .revealBeyondInnerRing,
              hasRevealedOuterRing,
              selection.band == .middle,
              middleItems.indices.contains(selection.index),
              middleItems[selection.index].hasSubItems,
              expandedParentIndex != selection.index else { return }
        expand(selection.index)
    }
}
