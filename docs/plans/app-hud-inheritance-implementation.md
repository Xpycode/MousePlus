# Implementation Plan — App HUD Inheritance

> **Persists across sessions.** Execute using the shared `commands/execute.md` procedure.
> Repair scheduling errors while preserving task IDs, completed evidence and approved scope.
> Task state/evidence is authoritative here; TASKS links here and holds backlog/inbox.

**Progress:** 11/11 tasks; E1 and E2 passed; external acceptance: E1 (Atlas Settings check), E2 (user live acceptance).
**Task states:** unchecked = pending / implemented-unverified / blocked (name gate);
checked = complete with required evidence.

## Goal

App HUD items follow their Global item, matched by item ID, until they are customized, hidden or
reordered for that app. Existing App HUDs migrate without any visible change.

Journey: record Command-C on Global Copy, then Save. In Safari, the Safari HUD's inherited Copy
sends Command-C, and Settings shows that item as "Follows Global".

## Acceptance Criteria

All criteria are in [`specs/app-hud-inheritance.md`](../../specs/app-hud-inheritance.md): AC1–AC19,
including AC12a and AC12b. Task mapping: AC1–8 and AC16–18 go to 1.1 and 2.1. AC9–13 go to 2.2,
3.1, 4.1 and 4.2. AC12b goes to 1.2 and 4.1. AC14 goes to 1.1, 3.1 and 4.1. AC15 goes to 2.1.
AC19 goes to 3.1.

## Design (fixed before dispatch; from the spec, code survey and web research 2026-11-22)

**Storage: sparse overrides.** This follows Kubernetes strategic-merge patches and Xcode build
setting levels: overrides keyed by ID, deletion markers kept as their own list, order kept apart
from content. An inheriting App HUD stores no `layout` key. Older builds therefore treat it as
unreadable, fall back to Global and keep the entry. That is accepted, because older-build
compatibility is not a goal.

```
AppHUDProfile (schemaVersion 2)
  rings.inner / rings.middle : RingInheritance
RingInheritance
  overrides   : [UUID: RingMenuItem]    // whole-item app copy; keeps item-level unknown JSON
  hidden      : Set<UUID>               // Global IDs hidden in this app
  appOnly     : [AppOnlyItem]           // { item: RingMenuItem, after: UUID? }  (nil = ring start)
  customOrder : [UUID]?                 // nil = follows Global order
```

**Resolution:** `AppHUDResolver.resolve(global:profile:) -> ResolvedAppLayout`. This is a pure
function. Its result holds the resolved layout plus the origin of each item (`.inherited`,
`.customized`, `.appOnly`), plus `notShown` (items beyond 8, per ring).

- **Follows Global (`customOrder == nil`):** go through the full Global list, hidden items
  included.
  - Emit app-only items whose anchor is `nil` first.
  - For each Global item, emit it (its override if one exists) unless it is hidden. Then emit the
    app-only items anchored to it, in stored order, with a cycle guard.
  - A hidden anchor therefore doesn't move the items anchored to it.
- **Custom order:**
  - Go through `customOrder` and keep only live, visible IDs.
  - Append Global items that are not in the list, in Global order. The spec says "at the end".
  - Append any app-only items still missing.
- **Overflow:** keep the first 8 items and put the rest in `notShown`. This rule is deterministic.
- **Unknown IDs:** a hidden or override ID that no longer exists is skipped when resolving and
  removed on the next save.

**Global deletions:**

- An override whose Global item no longer exists becomes an app-only item. It is anchored to the
  deleted item's former Global predecessor, or placed at the end if that can't be found.
- This repair runs when Global is saved. A fallback runs again on load.
- Nothing is dropped silently. Figma's silent override drops are a well-known complaint.

**Turning an edit back into storage:** `AppHUDResolver.diff(edited:previous:global:) ->
RingInheritance`, an inverse function. An edited item with a Global ID and different content
becomes an override.

- An explicit **Customize** creates an override identical to Global. Identical overrides are
  never dropped automatically, so Customize sticks.
- A Global ID missing from the edited list is added to hidden.
- When the relative order of inherited items differs from Global's, `customOrder` is set.
- App-only items always get a recomputed anchor (`after` = the item before them in the list).

**Migration of copied (version 1) profiles:**

- Run once, after both Global and the profiles have been decoded.
- An item identical to its Global item (all fields and unknown JSON) is inherited. A different
  item becomes an override. An ID not in Global becomes app-only. A Global item missing from the
  app becomes hidden.
- Custom order is set only if the inherited items' relative order differs from Global's.
- Migration is idempotent.
- Before the first save after migration, write a backup copy of the old JSON next to the
  configuration file.

**Merge guard (AC19):** the save reconcile compares stored profile metadata, not resolved
layouts. A Global-only edit leaves App HUD storage byte-equal.

**Research notes:**

- Prior art (Figma, Xcode) overrides per field. The user chose whole-item overrides on 2026-11-22,
  so the UI must say clearly that a customized item no longer follows Global. The editor status
  row does this.
- Research also suggested inserting new Global items after their predecessor in custom-order
  rings. Not adopted: the spec says append.

## Execution schedule and ownership

- **Execution scope/limits:** Wave 1 requested, then "continue" (2026-11-22). Focused test runs authorized for this execution run.
- **Testing limit:** `xcodebuild test` launches the app on the user's desktop. It is excluded
  from the standing permissions (`34_testing.md`), so each wave's test run needs the user to
  authorize it or to run it themselves. Building with `xcodebuild build` is allowed. Pure model
  tests (1.1) can't run as a logic-only target in this project.
- **Coordinator-owned (main session):** `MousePlus.xcodeproj` (new files get added to the
  target), the build directory, `docs/`, the spec, git, and any string catalog.
- **Interfaces to freeze in 1.1:** `RingInheritance`, `AppOnlyItem`, `ItemOrigin`,
  `ResolvedAppLayout` (`layout`, `origins: [UUID: ItemOrigin]`, `notShown: [Band: [RingMenuItem]]`),
  `AppHUDResolver.resolve`, `AppHUDResolver.diff`, `AppHUDResolver.migrate(v1Layout:global:)` and
  `AppHUDResolver.repairAfterGlobalChange(profile:oldGlobal:newGlobal:)`.

Paths: S = `01_Project/MousePlus`, T = `01_Project/MousePlusTests` (folders are Xcode synchronized groups; new files join the target automatically).

## Tasks

### Wave 1 (parallel — no mutual dependencies)

- [x] **1.1**: Inheritance model, resolver, inverse diff, migration and repair (pure, no UI).
  - Depends on / external gates: none
  - Owns: `S/Models/AppHUDProfile.swift` (v2 coding: `rings`, `schemaVersion`, unknown-field
    preservation, v1 `layout` still decoded for migration) and new `S/Models/AppHUDResolver.swift`.
    New tests in `T/AppHUDInheritanceTests.swift`. Existing `T/AppSpecificHUDModelTests.swift`
    must be updated where the v1 shape is asserted.
  - Interface: the frozen types and functions listed above.
  - Compatibility (staged refactor): keep the existing `AppHUDProfile.layout`, `inner` and
    `middle` callers compiling. Do this through a temporary compatibility path (v1 profiles keep
    their layout until migration), so the app still builds before 2.1 and 3.1 move the callers
    over. **Removal gate:** 3.1 deletes the compatibility path once a `grep` for `.layout` on
    profiles finds no remaining uses and the 3.1 tests pass.
  - Success: unit tests cover AC1–AC8 (resolution), AC14 (overflow), AC16 (migration, idempotent,
    no visible change), AC17 (round-trip with unknown JSON) and AC18 (quarantine). Also covered:
    anchor deleted, cycle guard, a hidden anchor, an override whose Global item was deleted, and
    an explicit identical override that survives `diff`.
  - Backpressure: `xcodebuild … build` succeeds. Then the focused run
    `-only-testing:MousePlusTests/AppHUDInheritanceTests -only-testing:MousePlusTests/AppSpecificHUDModelTests`
    (needs test authorization).

- [x] **1.2**: Test Action shows where the item comes from (AC12b).
  - Depends on / external gates: none
  - Owns: `S/Views/MenuEditor/TestActionControl.swift`, `S/ViewModels/TestActionController.swift`
    and `T/TestActionControllerTests.swift`.
  - Interface: `TestActionControl(…, sourceLabel: String?)`. It shows a caption ("from Global",
    "customized for Safari", "only in Safari") and adds it to the result's accessibility value.
    `nil` means no caption, which is what Global uses.
  - Success: the label shows only when non-nil. Existing behavior is unchanged when nil.
  - Backpressure: build succeeds; `-only-testing:MousePlusTests/TestActionControllerTests`.

- [x] **1.3**: Ring preview marks customized items (spec, Editor controls).
  - Depends on / external gates: none
  - Owns: `S/Views/MenuEditor/RingPreviewSelector.swift` and `T/MenuEditorPreviewSyncTests.swift`.
  - Interface: a new input `customizedItemIDs: Set<UUID>` and an `appName: String?` used in the
    accessibility suffix ", customized for <App>". The default (empty set) changes nothing.
  - Success: a small dot appears on marked items. It is decoration only: no hit target and no
    change to selection. The accessibility label gets the suffix.
  - Backpressure: build succeeds; `-only-testing:MousePlusTests/MenuEditorPreviewSyncTests`.

### Wave 2 (parallel — both consume 1.1; disjoint files)

- [x] **2.1**: Configuration storage, migration at load, and runtime resolution (AC15, AC16).
  - Depends on: 1.1
  - Owns: `S/Models/Configuration.swift` (migration after decode, `appHUDProfile` accessors
    returning resolved data, `makeAppHUDProfileFromGlobal` → an empty `RingInheritance`,
    `resolveHUD` via the resolver), `S/Models/HUDInvocation.swift`, `S/MousePlusApp.swift`
    (`resolveInvocation`), `S/Services/ConfigurationService.swift` (one-time pre-migration backup),
    and tests `T/AppSpecificHUDRuntimeTests.swift` and `T/ConfigurationServiceTests.swift`.
  - Interface: `Configuration.resolvedAppLayout(forBundleIdentifier:) -> ResolvedAppLayout?`
    and `Configuration.setAppHUDInheritance(_:forBundleIdentifier:)`.
  - Success: the runtime HUD shows resolved items and resolves once per opening (AC15). A v1 file
    loads with an identical resolved result, a backup is written once, and a second load is a
    no-op.
  - Backpressure: build succeeds; `AppSpecificHUDRuntimeTests`, `ConfigurationServiceTests`,
    `HUDTriggerRoutingTests`, `RingViewModelHUDTests`.

- [x] **2.2**: The editor model knows each item's origin, the hidden items and the order mode.
  - Depends on: 1.1
  - Owns: `S/ViewModels/MenuEditorModel.swift` and `T/MenuEditorModelRegressionTests.swift`.
  - Interface:
    - `load(resolved: ResolvedAppLayout?, …)`; `nil` means Global.
    - `origin(of:) -> ItemOrigin?`, `hiddenItems: [RingMenuItem]`, `hasCustomOrder(band:)` and
      `notShown(band:)`.
    - Actions: `customize(id:)`, `revertToGlobal(id:)`, `revertOrder(band:)` and `show(hidden:)`.
    - `removeSelectedItem` hides an inherited item and deletes anything else.
    - Edits through bindings or sub-items mark the item customized. `moveItem` sets custom order.
  - Success: unit tests cover AC9–AC12a at model level. Global editing behaves exactly as today
    (AC13).
  - Backpressure: build succeeds; `MenuEditorModelRegressionTests`.

### Wave 3 (serial — the riskiest integration, one owner)

- [x] **3.1**: The coordinator loads, merges, reconciles, creates, resets and restores with
  inheritance. Overflow warnings.
  - Depends on: 2.1, 2.2
  - Serial reason: `SettingsWorkspaceCoordinator.swift` is the single owner of the save path and
    the external-change guards.
  - Owns: `S/ViewModels/SettingsWorkspaceCoordinator.swift` and
    `T/SettingsWorkspaceCoordinatorTests.swift`.
  - Work:
    - `loadSelectedProfileIntoEditor` passes the resolved layout to the editor model.
    - `mergeEditorIntoSelectedProfile` calls `AppHUDResolver.diff`.
    - `editorDiffersFromSelectedProfile` and `selectedActionLayout` go through the resolver.
    - `reconcileAppHUDProfileChanges` compares and applies the stored inheritance metadata.
    - A Global save runs `repairAfterGlobalChange` for every App HUD.
    - `createAppHUD` and `resetMenuItems` produce an empty inheritance (everything inherited).
    - Backup and restore round-trip v2.
    - Publish `overflowWarnings: [(appName, band, count)]` after each Global save.
  - Success: AC19 (a Global-only edit leaves App HUD storage byte-equal, and external-change
    refusals still fire), AC7 after a Global delete, AC14 warning list, and all existing
    coordinator tests pass.
  - Backpressure: build succeeds; `SettingsWorkspaceCoordinatorTests`, `SettingsWorkspaceStateTests`.

### Wave 4 (parallel — both consume 3.1; disjoint files)

- [x] **4.1**: Profile bar, Hidden Items, messages, warnings and wiring.
  - Depends on: 3.1, 1.2, 1.3
  - Owns: `S/Views/MenuEditor/MenuItemsPane.swift`.
  - Work:
    - The copy hint becomes "App HUDs follow Global until you edit an item."
    - Add a **Hidden Items (N)…** `AppKitButton` after Delete…. It shows only for an App HUD and
      is disabled at 0. It opens a popover list with **Show** for each item.
    - Rewrite the `addAppHUD` and `profileSemantics` text.
    - Show the overflow warning ("Not enough space in <App> HUD's <ring> ring: N items not shown").
    - Pass `sourceLabel` to TestActionControl (1.2) and `customizedItemIDs` to the preview (1.3).
  - Success: AC10, AC11, AC12b, AC13 and AC14 visible in Settings. Only AppKit-backed controls
    are used.
  - Backpressure: build succeeds; `WorkspaceAccessibilityTests`.

- [x] **4.2**: Status row and footer controls in the selected-item editor.
  - Depends on: 3.1 (2.2's actions)
  - Owns: `S/Views/MenuEditor/SlotEditorForm.swift`.
  - Work:
    - Top status row, App HUD only:
      - Inherited: "Follows Global" plus a **Customize** button.
      - Customized: "Customized for <App>" plus **Revert to Global**.
      - App-only: "Only in <App>".
    - Footer: **Revert Order** directly after **Move Later**, shown only when that ring has its
      own order.
    - In an App HUD, **Delete Item** reads **Hide in <App>** for inherited items.
  - Success: AC3, AC9, AC10, AC12, AC12a and AC13 in the UI. Accessibility labels and
    identifiers follow the existing `menuItems.*` naming.
  - Backpressure: build succeeds; `WorkspaceAccessibilityTests`.

### Wave 5 (verification)

- [x] **5.1**: Full focused suite plus build.
  - Depends on: 4.1, 4.2
  - Owns: test evidence (coordinator).
  - Success: all focused classes pass with a count no lower than before. The list is the
    app-specific HUD plan's set plus `AppHUDInheritanceTests`, `MenuEditorModelRegressionTests`,
    `MenuEditorPreviewSyncTests` and `TestActionControllerTests`.
  - Backpressure: the exact `xcodebuild … test -only-testing:` command and the pass count
    (needs test authorization).

- [x] **5.2**: Independent review of the save path and migration.
  - Depends on: 4.1, 4.2
  - Owns: the review report. Findings go back to the task owner.
  - Success: no unresolved findings on data loss, guard bypass, a migration that changes what is
    shown, or orphaned overrides.
  - Backpressure: a fresh-context review of the diff against this plan and the spec.

## External checks

- [x] **E1**: Atlas helper Settings check (standing Atlas authorization).
  - Depends on: 5.1
  - Requires: `atlas doctor` ready, and the fresh build copied into the helper.
  - Gates: the claims that the 4.1 and 4.2 UI renders correctly.
  - Success / verification: screenshots of a Safari App HUD showing an inherited item ("Follows
    Global", Customize), a customized item (Revert to Global, preview dot), Hidden Items (1),
    Revert Order after a move, and "Hide in Safari".
  - While unavailable: model and coordinator work stays valid. UI claims stay unverified.

- [x] **E2**: User live acceptance on real apps. **Passed 2026-11-22:** after Revert to Global on Safari's migrated Copy (which had no keystroke), Copy in Safari copies; HUDs looked unchanged after upgrade. AC2/AC7/AC14 left to automated tests.
  - Depends on: E1, 5.2
  - Requires: the user, and an unsigned build, which means granting Accessibility again by hand.
    If a signing identity exists by then, that step goes away.
  - Gates: overall completion. Checks AC1 (the journey), AC2, AC7, AC14 and AC16 (your existing
    Safari HUD looks unchanged after upgrading).
  - Success / verification: the user confirms each flow in Safari and Finder.
  - While unavailable: nothing else is blocked. The feature stays "implemented, not accepted".

---

## Operational Learnings

- **Worktree agents** branch from `origin/main` (e456859), not local `main`; tell agents to `git merge --ff-only main` first (Wave 2 agents did).
- **1.1 → 2.1/3.1 window:** the COMPAT `layout`/`inner`/`middle` accessors return an empty layout for a v2 profile, and assigning them reverts the profile to a v1 copy. Once 2.1 migrates at load, the coordinator's old paths (`SettingsWorkspaceCoordinator` ~lines 278, 538, 557) misbehave until 3.1 lands. Do not ship or live-test between 2.1 and 3.1; treat Waves 2–3 as one unit before any user build.
- **`diff` contract (for 2.2/3.1):** `edited` must be the *complete* ring including not-shown items, or those Global items become hidden. Pass `origins` so `.customized` forces an override and `.inherited` drops an identical one (Revert to Global). Load-time fallback repair: `repairAfterGlobalChange(profile:, oldGlobal: g, newGlobal: g)`.
- **Extra 1.1 API beyond the frozen list:** `AppHUDRings` container (`profile.rings`), `resolve(global:rings:)`, `AppHUDProfile.migrated(global:)`, `setRings`, `ringCapacity`, JSON-preservation helpers. A v1 profile passed to `resolve` is migrated in memory.
- **2.1 API:** `resolvedAppLayout(forBundleIdentifier:)` (display), `setAppHUDInheritance(_ rings: AppHUDRings, forBundleIdentifier:) -> Bool` (existing readable profiles only), `repairAppHUDProfiles(afterGlobalChangeFrom:)` (for the Global-save repair). `appHUDProfile`/`validAppHUDProfiles` still return *stored* metadata (needed for the AC19 compare). Backup: `config.pre-app-hud-inheritance.json`, written once by `save()` when the on-disk file still needs migration.
- **2.2 API:** `load(resolved:global:hudCustomization:preservingSelection:normalizeStoredValues:)`, `inheritanceEditState: AppHUDEditState?` (`edited` = full rings incl. not-shown, `origins`, `global`), `customizedItemIDs`, `origin(of:)`, `hiddenItems(band:)`, `hasCustomOrder(band:)` (derived), `notShown(band:)`, `customize/revertToGlobal/revertOrder/show(hidden:)`. Dirty check must compare `diff` output vs stored profile, not visible arrays. Reload with `load(resolved:)` after reset/create (`resetToDefaults` leaves stale origins).
- **3.1:** `overflowWarnings: [AppHUDOverflowWarning]` (`bundleIdentifier`, `band`, `count`), recomputed on load and after each Menu Items save. 4.1 maps the bundle ID to a name with `MenuItemsPane.profileTitle`. Known residual risks (accepted, fail-closed): an external Global delete repairs orphans to the ring end; an in-memory repair can make an App HUD save be refused if another writer edited the same profile.
- **1.3 hook:** `RingMenuView.accessibilityLabelSuffix: ((RingMenuItem) -> String)?` (nil at runtime). 4.1 must pass `customizedItemIDs`/`appName` at the preview call site (`MenuEditorView.swift:30`) and `sourceLabel:` to `TestActionControl`.

## Blocked Tasks

- (none)

---

## Execution Log

| Wave / task IDs | Assignments or serial reason | Validation / evidence | Commits or exception | Remaining gates / next action or stop reason |
|---|---|---|---|---|
| Wave 1: 1.1, 1.2, 1.3 | Three parallel fresh-context agents in isolated worktrees (one per task); 1.3 was reassigned `RingMenuView.swift` to replace a duplicate accessibility layer with a suffix hook | Integrated `build-for-testing` (Debug, unsigned) in the main checkout: TEST BUILD SUCCEEDED; no new warnings. 27 tests in 1.1, 2 in 1.2, 4 in 1.3 compiled, **not run** (needs user test authorization) | d495f9a; test fix in the next commit | Focused run (user-authorized): AppHUDInheritanceTests, AppSpecificHUDModelTests, TestActionControllerTests, MenuEditorPreviewSyncTests, **56/56 passed** after narrowing one over-strict assertion (the resolved runtime layout doesn't carry layout-level unknown JSON; storage does, and that's asserted). Complete. Next: Wave 2 |
| Wave 2: 2.1, 2.2 | Two parallel fresh-context agents in worktrees (fast-forwarded to 5d7ff79) | Integrated focused run: AppSpecificHUDRuntimeTests, ConfigurationServiceTests, HUDTriggerRoutingTests, RingViewModelHUDTests, MenuEditorModelRegressionTests, AppHUDInheritanceTests, TestActionControllerTests, MenuEditorPreviewSyncTests, **152/152 passed**. AppSpecificHUDModelTests and SettingsWorkspaceCoordinatorTests are known-broken (crash on empty `makeAppHUDProfileFromGlobal().inner`); fixing them is in 3.1's scope | See the Wave 2 commit | 3.1 next. Interim: the coordinator shows empty App HUD rings and an edit would save a v1 copy. No build handoff until 3.1 |
| Wave 3: 3.1 | One fresh-context agent (serial: single owner of the save path) | Integrated run of 12 classes (coordinator, state, model, inheritance, config service, runtime, routing, ring VM, editor model, test action, preview sync, workspace accessibility): **240/241**. The one failure, `WorkspaceAccessibilityTests.testFillUnusedSlots…`, also fails at e456859, so it was already broken (TASKS backlog) | See the Wave 3 commit | COMPAT accessors removed; `init(layout:)` kept as the v1 migration-input constructor for test fixtures. Next: Wave 4 (4.1, 4.2) |
| Wave 4: 4.1, 4.2 + 5.1 | Two parallel fresh-context agents in worktrees; the coordinator merged both edits to `WorkspaceAccessibilityTests` and wired `SlotEditorForm(appName:)`. A fresh agent fixed the new tests' failures: the test helpers' `XCTUnwrap` recorded failures for misses inside `try?`, plus a render-lag wait. The UI was fine | 5.1: 14 classes, **250/251**; the only failure is the one that was already broken (`testFillUnusedSlots…`). Result: `$TMPDIR/mp-wave1-dd/Logs/Test/Test-MousePlus-2026.11.22_20-20-15-+0100.xcresult` | See the Wave 4 commit | UI claims still need E1 (Atlas). Next: 5.2 review |
| 5.2 | Fresh-context `feature-dev:code-reviewer` (read-only, files at HEAD) | No findings at confidence ≥80 across data loss, guard bypass/AC19, migration, orphaned overrides and resolver. Two sub-threshold observations moved to the TASKS backlog | n/a (review only) | — |
| E1 | Atlas helper, fresh Debug build `$TMPDIR/mp-wave1-dd/Build/Products/Debug/MousePlus.app` (31d9f3b) | Activity Monitor App HUD (Safari isn't offered by the app picker in the helper). Global: new hint shown, no Hidden Items button. App HUD: Hidden Items (0) disabled; "Follows Global" + Customize; "from Global" caption → Customize → "Customized for Activity Monitor" + Revert to Global, preview dot, wedge AX suffix, caption; Move Later → Revert Order appears; "Hide in Activity Monitor" → Hidden Items (1) popover "Copy (inner ring)" + Show → back to (0), disabled. Screenshots: `~/Library/Application Support/Atlas/runs/1795375362083829000-capture.png`, `…1795375369364074000…`, `…1795375387425999000…`, `…1795375396894892000…`. **Found two layout bugs:** the App HUD semantics text is clipped to one line, and the four-button footer overflows the editor column (right edge clipped) | Layout fixes (wrapping `MenuItemsProfileLabel.sizeThatFits`, `SlotEditorFooterLayout`) in the E1 fix commit; WorkspaceAccessibilityTests 16/17 (the one failure was already broken) | Re-checked in Atlas: the semantics text wraps to 2 lines and the footer wraps to 2 rows with nothing clipped (`…/runs/1795376506075372000-capture.png`). Cosmetic follow-ups are in the TASKS backlog. The overflow warning (needs 9+ items) is covered by tests only. Next: E2 |

---
*Keep active while required work or acceptance is incomplete. On completion, archive with execution
evidence.*
