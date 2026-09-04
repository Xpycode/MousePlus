# Implementation Plan

> Build the shared dynamic-expansion foundation (`DynamicSource`, async epoch-guarded `expand()`, `IconSource`) and the `AppSwitcherService`, then wire a middle "Apps" wedge to expand into MRU-ordered running apps with real icons.

## Goal

Ship the Dynamic App Switcher (HUD Feature C): a middle wedge whose outer ring is populated at expansion time from `NSWorkspace.runningApplications`, MRU-ordered, with real app icons, committing through the existing `.appSwitch` action path unchanged.

## Acceptance Criteria

- [ ] `RingMenuItem` has a decode-tolerant `dynamicSource: DynamicSource` field (`.none` default); existing configs round-trip unchanged.
- [ ] `RingViewModel.expand()` is async/epoch-guarded; the `.none` arm is byte-for-byte behaviorally identical to today (regression guard); `.runningApps` populates `outerItems` from `AppSwitcherService` without a "Loading…" placeholder.
- [ ] `dynamicIcons` side dictionary never enters the `Codable` model; cleared on `reset()`/`collapse()`; a stale/late fetch after collapse or re-expansion can never assign (epoch guard proven, not just asserted).
- [ ] `WedgeView` renders via an explicit `iconSource: IconSource` parameter; SF-symbol wedges are visually unchanged; app icons render full-color, untinted, clipped to a rounded rect.
- [ ] `AppSwitcherService` enumerates regular running apps (self excluded), MRU-first via a launch-time-tracked `didActivateApplicationNotification` observer, alphabetical fallback, capped at ~12.
- [ ] The sample "Apps" middle wedge uses `dynamicSource: .runningApps`; `RingPreviewSelector` shows a fixed placeholder set instead of querying `NSWorkspace` live.
- [ ] Signed build + user-driven live verification: expanding "Apps" shows real running apps with correct icons/MRU order; committing one activates it; rapid re-pointing mid-fetch shows no stale assignment.

## Specs and Evidence

- `docs/APP_SWITCHER_PLAN.md` — full design, ground truth, and phased task breakdown (source of this plan)
- `docs/HUD_ACTIONS_PLAN.md` §1.2/§1.3 (shared foundation), §194–230 (Feature C spec)
- `docs/PROJECT_STATE.md` — current project state

## Tasks

### Wave 1 — Shared model types (parallel, no deps)

- [x] **Task 1.1**: Add `DynamicSource` enum (`.none`, `.runningApps`) and `dynamicSource` field to `RingMenuItem`, decode-tolerant default `.none` matching the existing `actionData`/`wedgeColor` tolerance pattern -> `01_Project/MousePlus/Models/RingMenuItem.swift`
  - Backpressure: builds; a pre-existing `config.json` fixture decodes with `.none`; round-trips through encode/decode.
- [x] **Task 1.2**: Add `IconSource` enum (`.sfSymbol(String)`, `.appIcon(NSImage)`) -> `01_Project/MousePlus/Models/IconSource.swift` (new)
  - Backpressure: builds.

### Wave 2 — RingViewModel/WedgeView plumbing (depends on Wave 1)

- [x] **Task 2.1**: Async, epoch-guarded `expand()`; `dynamicIcons: [RingMenuItem.ID: NSImage]` side dictionary; both cleared (and epoch bumped) in `reset()`/`collapse()`; `.none` arm unchanged behavior -> `01_Project/MousePlus/ViewModels/RingViewModel.swift`
  - Backpressure: builds; existing static-`subItems` wedges (Snap, Menu, Custom) still expand synchronously, unchanged; focused `RingViewModelHUDTests` regression case for the `.none` path.
  - Note: `.runningApps` arm is stubbed with a `TODO(Wave 4)`-marked `Task { }` — no `AppSwitcherService` reference added yet, by design.
- [x] **Task 2.2**: `WedgeView` takes `iconSource: IconSource` instead of reading `item.icon` directly; `RingMenuView` computes it per wedge (`dynamicIcons[item.id].map { .appIcon($0) } ?? .sfSymbol(item.icon)`); app icons render untinted at 28×28, `RoundedRectangle(cornerRadius: 6)` clip -> `01_Project/MousePlus/Views/Components/WedgeView.swift`, `01_Project/MousePlus/Views/RingMenuView.swift`
  - Backpressure: builds; existing SF-symbol wedges render identically (no visible diff on a static config).

### Wave 3 — AppSwitcherService (parallel with Wave 1/2, no file overlap)

- [x] **Task 3.1**: `AppEntry` struct + `actor AppSwitcherService` (`startTrackingMRU()`, `runningApps()`): enumerate `NSWorkspace.shared.runningApplications` filtered to `.regular` policy, self excluded; MRU-first via a `didActivateApplicationNotification` observer started at launch, alphabetical fallback; cap ~12; actor-isolated with a `@MainActor` hop for the `NSWorkspace` read, matching `WindowService`'s pattern -> `01_Project/MousePlus/Services/AppSwitcherService.swift` (new)
  - Backpressure: builds; a debug dump of `runningApps()` shows correct names/bundleIDs/icons, MRU-ordered.
- [x] **Task 3.2**: Call `startTrackingMRU()` once at launch, alongside other launch-time services (e.g. `PermissionsService`) -> `01_Project/MousePlus/MousePlusApp.swift`
  - Backpressure: builds; MRU map updates as apps are activated (verify via debug log).

### Wave 4 — Wire the switcher into the ring (depends on Wave 2 + Wave 3)

- [x] **Task 4.1**: Implement the `.runningApps` arm added in Task 2.1: map `[AppEntry]` → `RingMenuItem(actionType: .appSwitch, actionData: bundleIdentifier)`, stash icons into `dynamicIcons`, cap 12 -> `01_Project/MousePlus/ViewModels/RingViewModel.swift`
  - Backpressure: builds; expanding "Apps" with several apps running shows real icons + correct MRU order.
- [x] **Task 4.2**: Update the sample "Apps" middle wedge to `dynamicSource: .runningApps` (drop its static 3-item `subItems`); preview special-case — `RingPreviewSelector`/editor preview renders a fixed 3–4 item placeholder set instead of querying `NSWorkspace` live -> `01_Project/MousePlus/Models/RingMenuItem.swift`, wherever `RingPreviewSelector` resolves preview content
  - Backpressure: builds; Settings → Menu Items preview shows placeholder app slots, not a live/empty query.
  - Note: `hasSubItems` (`RingMenuItem.swift`) had to be extended to also treat `dynamicSource != .none` as expandable — it previously meant "subItems is non-empty" and gated expand-vs-execute, the expand chevron, the hidden-submenu warning, and the editor's `expandedMiddleParent()` lookup everywhere in the codebase. Dropping Apps' static `subItems` without this fix would have silently made it non-expandable again.

### Wave 5 — Closure gate (verification)

- [x] **Task 5.1**: Focused + full automated suite, forbidden-control audit, `git diff --check` -> complete change set
  - Backpressure: focused suites for RingViewModel/WedgeView/AppSwitcherService, full MousePlus test target green, no raw SwiftUI interactive controls introduced.
- [ ] **Task 5.2**: Signed build + user-driven live verification (no synthetic input, per project rule) — user presses their trigger, expands "Apps" with 4+ regular apps running, confirms real names/icons/MRU order, commits one and confirms activation; rapid re-point mid-fetch confirms no stale assignment
  - Backpressure: signed Debug build; user confirmation recorded in session log and `PROJECT_STATE.md`.
  - Partial result (2026-09-04): real names/icons are visible; the user confirmed activation from both a static inner Safari item and the dynamic outer Safari item after the native mouse-up fix. A follow-up full-circle prototype and outer-label visibility toggle are also signed-live confirmed. MRU ordering and rapid re-pointing remain.

## Operational Learnings

- Window Snap never needed a dynamic-source concept — its 8 directions are static `subItems`. The app switcher is the first feature that needs live, runtime-populated `outerItems`; an epoch counter (not a boolean) is required because hover-driven reveal can re-point from one dynamic wedge straight to another mid-fetch.
- `NSImage` must never enter the `Codable` model — `IconSource`/`dynamicIcons` is a side dictionary on the view model only, cleared on `reset()`/`collapse()`.
- No public running-app z-order/MRU API exists on macOS 14; MRU is self-tracked from `didActivateApplicationNotification`, starting empty until the app has seen at least one activation (alphabetical fallback until then).
- Feature A (menu mirror, `APP_COMMANDS_PLAN.md`) will consume the same `DynamicSource`/async-`expand()` machinery unchanged — do not fork a second version if it lands later.

## Blocked Tasks

- None.

---

## Execution Log

| Wave | Started | Completed | Commits |
|------|---------|-----------|---------|
| 1 | 2026-09-04 | 2026-09-04 | `feat(wave-1): add DynamicSource and IconSource model types` |
| 2 | 2026-09-04 | 2026-09-04 | `feat(wave-2): wire async epoch-guarded expand() and per-wedge iconSource` |
| 3 | 2026-09-04 | 2026-09-04 | `feat(wave-3): add AppSwitcherService for MRU running-app enumeration` |
| 4 | 2026-09-04 | 2026-09-04 | `feat(wave-4): wire AppSwitcherService into .runningApps expand() + preview placeholder` |
| 5 | | | |

---
*Delete this file when all tasks complete. Archive the outcome in the session log.*
