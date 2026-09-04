# Dynamic App Switcher — Implementation Plan

**Status:** Planned (2026-09-04). HUD action track; picks up after the ring-controls
reorganization. Ring-UI feature — does not depend on the HID++ decision (#17).

**Relationship to `docs/HUD_ACTIONS_PLAN.md`.** That doc specs this as **Feature C** (§194–230)
and defines the **shared foundation** it depends on: §1.2 async/dynamic `RingViewModel.expand()`
and §1.3 `IconSource` (real app icons in wedges). This plan builds those two shared pieces —
neither exists in the codebase yet — then Feature C on top of them. **Feature A (menu mirror,
`docs/APP_COMMANDS_PLAN.md`) needs the same two pieces**; whichever feature ships first builds
them, the other consumes them unchanged. Do not fork a second `DynamicSource`/`IconSource` type.

**Ground truth (verified 2026-09-04, post ring-controls-reorg — corrects the 2026-05-30 HUD plan
sketch, which predates the current `ActionService`/`ActionContext` shapes):**
- `ActionType` already has `.appSwitch` case, wired end-to-end (`Services/ActionService.swift:100–103`
  via `ActionWorkspace.activateOrLaunch(bundleIdentifier:)`). The switcher's *commit* path needs
  nothing new — only its *population* is new, exactly as the HUD plan says.
- `RingViewModel.expand(_:)` (`ViewModels/RingViewModel.swift:326–334`) is fully synchronous:
  `outerItems = middleItems[parentIndex].subItems ?? []`, gated by
  `OuterRingPolicyState.parentIsAvailable(policy:itemCount:)`. There is no dynamic-source concept,
  no async fetch, no stale-expansion guard. Window Snap (Feature B) never needed one — its 8
  directions are static `subItems` baked in `RingMenuItem.sampleItems` (`Models/RingMenuItem.swift:145–157`).
  **The app switcher is the first feature that genuinely needs live, runtime-populated `outerItems`.**
- `RingMenuItem.icon` is `String` (SF Symbol name only); `WedgeView` has no path for an `NSImage`.
  Running-app icons are `NSImage` and must never enter the `Codable` model (§1.3).
- `ActionContext` already threads a main-actor-captured `frontmostPID` into `ActionService.execute`
  (`RingViewModel.swift:300–304`); the switcher's MRU tracking is a **separate, independent**
  concern (which app was frontmost *before now*, not at commit time) and needs its own service.
- No `AppSwitcherService` exists yet.

---

## 1. Shared foundation this feature builds (§1.2 + §1.3 from the HUD plan)

### 1.1 `DynamicSource` on `RingMenuItem`

```swift
enum DynamicSource: Codable, Hashable {
    case none            // existing static path: outerItems = subItems ?? []
    case runningApps      // THIS feature
    // .appMenuMirror reserved for Feature A when it lands (APP_COMMANDS_PLAN.md)
}
```
Add `var dynamicSource: DynamicSource = .none` to `RingMenuItem`, decode-tolerant
(`decodeIfPresent ?? .none`) matching the project's existing tolerance pattern (`actionData`,
`wedgeColor` in `RingMenuItem.init(from:)` already do this — `Models/RingMenuItem.swift:72–75`).

### 1.2 Async, stale-guarded `expand()`

```swift
private var expansionEpoch = 0

func expand(_ parentIndex: Int) {
    guard parentIndex >= 0, parentIndex < middleItems.count else { return }
    let parent = middleItems[parentIndex]
    expandedParentIndex = parentIndex
    expansionEpoch += 1
    let epoch = expansionEpoch

    switch parent.dynamicSource {
    case .none:
        let items = parent.subItems ?? []
        guard OuterRingPolicyState.parentIsAvailable(
            policy: hudCustomization.outerRingVisibility, itemCount: items.count
        ) else { return }
        outerItems = items
    case .runningApps:
        outerItems = []               // transient empty arc, not a "Loading…" wedge (§3)
        Task {
            let apps = await appSwitcherService.runningApps()
            guard epoch == expansionEpoch, expandedParentIndex == parentIndex else { return }
            let items = apps.map { $0.asRingMenuItem() }
            dynamicIcons = Dictionary(uniqueKeysWithValues: apps.map { ($0.id, $0.icon) })
            guard OuterRingPolicyState.parentIsAvailable(
                policy: hudCustomization.outerRingVisibility, itemCount: items.count
            ) else { return }
            outerItems = items
        }
    }
}
```
`reset()`/`collapse()` (`RingViewModel.swift:337–363`) must clear `dynamicIcons` alongside
`outerItems`, and bumping `expansionEpoch` there too so an in-flight fetch from a since-collapsed
expansion can never assign late.

**Why an epoch, not a boolean:** re-pointing from one dynamic wedge straight to another
(possible with hover-driven reveal — `autoExpandRevealedParentIfNeeded`, `RingViewModel.swift:399`)
must invalidate the first fetch even though `expandedParentIndex` briefly equals neither the old
nor the checked value mid-transition. An incrementing token is the standard fix and is cheap.

### 1.3 `IconSource` — real app icons without touching the `Codable` model

- `enum IconSource { case sfSymbol(String); case appIcon(NSImage) }` in a new
  `Models/IconSource.swift`.
- `RingViewModel` gains `private(set) var dynamicIcons: [RingMenuItem.ID: NSImage] = [:]`
  (side dictionary, never persisted).
- `WedgeView` takes an explicit `iconSource: IconSource` parameter instead of reading `item.icon`
  directly; `RingMenuView` computes it per wedge: `dynamicIcons[item.id].map { .appIcon($0) } ??
  .sfSymbol(item.icon)`.
- Render rule (§1.3 of the HUD plan, unchanged): SF symbol tints white when highlighted; app icon
  **never tints** — full color, `.resizable().frame(width: 28, height: 28)
  .clipShape(RoundedRectangle(cornerRadius: 6))`.

---

## 2. `AppSwitcherService`

```swift
struct AppEntry: Identifiable, Sendable {
    let id: String              // bundleIdentifier
    let name: String
    let icon: NSImage
}

actor AppSwitcherService {
    func startTrackingMRU()                    // call once, at app launch
    func runningApps() async -> [AppEntry]      // MRU-first, alphabetical tie-break, self excluded
}
```
- **Enumeration:** `NSWorkspace.shared.runningApplications`, filtered to
  `activationPolicy == .regular`, excluding `Bundle.main.bundleIdentifier`. Reads `localizedName`,
  `bundleIdentifier`, `icon`.
- **Ordering — self-tracked MRU, no public z-order/MRU API exists.** Observe
  `NSWorkspace.shared.notificationCenter` `didActivateApplicationNotification` **from app launch**
  (`startTrackingMRU()`, called once from `MousePlusApp` init/`applicationDidFinishLaunching`, not
  from ring-open) into a `[String: Date]` bundleID→last-activated map. `runningApps()` sorts
  MRU-first, falling back to alphabetical for apps never observed activating (e.g. launched before
  MousePlus, never yet focused).
- **Overflow — v1: cap at ~12 MRU, no pagination.** Depth cap 3 (menu editor's rule) means the
  outer band can't open a deeper ring; typical regular-app counts (8–15) fit comfortably, and
  `RadialGeometry`'s `outerCount` can already exceed `spokeCount`. Deep overflow (a "More…" page)
  is deferred to a v2 refill-in-place, matching the HUD plan's call.
- **Threading — `actor`, matching `WindowService`'s existing pattern** (`Services/WindowService.swift`).
  `NSWorkspace` reads must hop to `@MainActor` internally (strict-concurrency warns otherwise);
  return the plain `[AppEntry]` value out of the actor boundary, mirroring how `ActionContext` is
  built on the main actor and passed in as `Sendable` (`RingViewModel.swift:300–304`).
- **Commit reuses `.appSwitch` unchanged.** Populated items get `actionType: .appSwitch,
  actionData: bundleIdentifier` — `ActionService.execute` already handles this
  (`Services/ActionService.swift:100–103`); zero changes to the execution path.

---

## 3. Ring placement and UX

- A middle wedge, e.g. "Apps" (`square.grid.2x2`, matching the existing sample item at
  `Models/RingMenuItem.swift:134–144`, upgraded from static `subItems` to
  `dynamicSource: .runningApps`), expands the outer arc to MRU running apps with real icons.
- **No "Loading…" placeholder wedge.** Unlike Feature A's AX menu walk (tens–hundreds of ms,
  genuinely needs a placeholder per the HUD plan), `NSWorkspace.runningApplications` is
  synchronous and effectively instant — the `Task` in §1.2 exists for actor-hop correctness, not
  to bridge a perceptible fetch. Show an empty arc for one frame at most; do not build placeholder
  UI for this feature.
- `RingPreviewSelector` (Settings → Menu Items preview) renders through the same `RingMenuView`,
  so it gets this for free — but a dynamic-source wedge previewed there has no "running apps" to
  show. Preview mode must special-case `dynamicSource != .none`: render a fixed 3–4 item
  placeholder set (e.g. "App 1/2/3") so the editor doesn't hang on a live `NSWorkspace` query or
  show an empty arc while editing.

---

## 4. Phased implementation

Each phase is independently shippable and build-gated:
`xcodebuild -workspace 01_Project/MousePlus.xcworkspace -scheme MousePlus -configuration Debug build`

### Phase 0 — Shared foundation (§1 above)

**Skip this phase entirely if Feature A (`APP_COMMANDS_PLAN.md`) ships first** — it builds the
same `DynamicSource`/async-`expand()`/stale-guard machinery for `.appMenuMirror`; this feature
then only adds the `.runningApps` arm and `IconSource`.

##### Wave 1 — models (parallel, no deps)

| # | Task | Target file | Done when |
|---|------|-------------|-----------|
| P0-T1 | `DynamicSource` enum (§1.1) on `RingMenuItem`, decode-tolerant default `.none`. | `Models/RingMenuItem.swift` | Builds; pre-existing `config.json` decodes with `.none`; round-trips |
| P0-T2 | `IconSource` enum (§1.3). | `Models/IconSource.swift` (new) | Builds |

##### Wave 2 — plumbing (needs W1)

| # | Task | Target file | Done when |
|---|------|-------------|-----------|
| P0-T3 | Async, epoch-guarded `expand()` (§1.2); `dynamicIcons` side dictionary; both cleared in `reset()`/`collapse()`. `.none` arm behaves identically to today (regression guard). | `ViewModels/RingViewModel.swift` | Builds; existing static-subItems wedges (Snap, Menu, Custom) still expand synchronously and unchanged |
| P0-T4 | `WedgeView` takes `iconSource: IconSource`; `RingMenuView` computes it per wedge from `dynamicIcons[item.id]` (fallback `.sfSymbol(item.icon)`); render rule (no tint on app icons). | `Views/Components/WedgeView.swift`, `Views/RingMenuView.swift` | Builds; existing SF-symbol wedges render identically (no visible diff on a static config) |

### Phase 1 — `AppSwitcherService` + wiring (needs Phase 0)

| Wave | # | Task | Target file | Done when |
|---|---|------|-------------|-----------|
| **W1** | P1-T1 | `AppEntry`, `actor AppSwitcherService` (§2): `startTrackingMRU()`, `runningApps()`. | `Services/AppSwitcherService.swift` (new) | Builds; a debug dump of `runningApps()` shows correct names/bundleIDs/icons for the apps actually running, MRU-ordered |
| | P1-T2 | Call `startTrackingMRU()` once at app launch (`MousePlusApp` init or `applicationDidFinishLaunching`, alongside where `PermissionsService`/other launch-time services are wired). | `MousePlusApp.swift` | Builds; the MRU map updates as apps are activated (verify via debug log) |
| **W2** (needs W1 + Phase 0) | P1-T3 | `RingViewModel.populateRunningApps` (the `.runningApps` arm added in P0-T3): map `[AppEntry]` → `RingMenuItem(actionType: .appSwitch, actionData: bundleIdentifier)`, stash icons into `dynamicIcons`. Cap at 12. | `ViewModels/RingViewModel.swift` | Builds; expanding the "Apps" wedge with several apps running shows real icons + correct MRU order |
| | P1-T4 | Update the sample "Apps" middle wedge to `dynamicSource: .runningApps` (drop its static 3-item `subItems`). Preview special-case (§3): `RingPreviewSelector`/editor preview renders a fixed placeholder set instead of querying `NSWorkspace` live. | `Models/RingMenuItem.swift`, wherever `RingPreviewSelector` resolves preview content | Builds; Settings → Menu Items preview shows placeholder app slots, not a live/empty query |
| **W3 — verify** | P1-T5 | Launch; with 4+ regular apps running, **user presses their trigger**, expands "Apps", confirms real names/icons/MRU order, commits one, confirms it activates (no synthetic input — the trigger press and gesture are user-driven per the project rule). Collapse-mid-fetch: rapidly re-point to another wedge while apps are many; confirm no stale assignment (log/assert the epoch guard fired). | manual | Correct live population; commit switches apps; no stale-assignment regression |

**Net deliverables:** `Models/DynamicSource` (or reused from Feature A), `Models/IconSource.swift`,
`Services/AppSwitcherService.swift` (new); `ViewModels/RingViewModel.swift`,
`Views/Components/WedgeView.swift`, `Views/RingMenuView.swift`, `MousePlusApp.swift` (edited).
No settings/config UI changes — the switcher wedge is a fixed sample item, not user-curated (that
curation model belongs to Feature A / `APP_COMMANDS_PLAN.md`'s `AppProfile`, not this feature).

---

## 5. Risks

- **Cooperative activation on macOS 14 may fail to focus-steal** from a foreground app in rare
  cases (existing `.appSwitch` path already handles this via `ActionServiceError.activationFailed`
  — low incremental risk, but verify on hardware, user-triggered, per the no-synthetic-input rule).
- **MRU observer starts empty on first launch** — before any `didActivateApplicationNotification`
  fires, `runningApps()` falls back to alphabetical. Acceptable; matches the HUD plan's call.
- **Icon churn:** an app that quits between population and commit leaves a stale `dynamicIcons`
  entry until the next `expand()`/`reset()` — harmless (dictionary is keyed by item ID, cleared on
  collapse), but `ActionService.execute`'s existing `applicationNotFound`/`activationFailed`
  handling is the actual safety net if the bundle ID is gone by commit time.
- **Strict concurrency:** reading `NSWorkspace` from inside the `actor` may warn — hop the read to
  `@MainActor` internally and return the `Sendable` `[AppEntry]` value, as noted in §2.

## 6. Decisions to log in `decisions.md`

- App switcher population is genuinely async/runtime; Window Snap's static-`subItems` pattern does
  not generalize — this is the feature that justifies building `DynamicSource` + epoch-guarded
  `expand()` at all.
- MRU is self-tracked from `didActivateApplicationNotification` at launch time; no public
  z-order/MRU API exists on macOS 14.
- `IconSource` keeps `NSImage` out of the `Codable` model permanently — a side dictionary on the
  view model, cleared on `reset()`/`collapse()`, is the only place app icons live.
- v1 caps at ~12 MRU apps, no pagination; overflow paging deferred to v2.
