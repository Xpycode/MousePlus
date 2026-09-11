# Implementation Plan — App-Specific HUDs

**Created:** 2026-09-11 · **Status:** Automated implementation complete — E1 signed-live acceptance pending

## Goal

Add complete per-application action layouts with deterministic Global fallback, independent
Contextual/Global invocation routes, safe in-place switching, profile editing in the existing
Settings workspace, and signed-live Finder acceptance.

## Acceptance Criteria

The authoritative behavior and AC1–AC19 live in the linked specification.

- [x] Existing configurations remain the Global HUD; app profiles copy, persist, edit, delete,
  recover, and fall back without damaging unrelated configuration (AC1–AC5).
- [x] Contextual resolution uses a stable frontmost-app snapshot, exact bundle-ID matching,
  in-memory lookup, Global fallback, and an invocation-frozen layout/target (AC6–AC9).
- [x] The independent Global route bypasses app resolution and switches safely in either direction,
  preserving panel position and preventing stale release commits or ambiguous bindings (AC10–AC15).
- [x] The center and Settings surfaces expose the active/editing profile through native,
  accessible controls and preserve Reduce Motion and existing interaction contracts (AC16–AC18).
- [ ] A signed fresh build passes the Finder/unconfigured-app end-to-end acceptance flow, including
  save/relaunch and both invocation routes (AC19).

## Specs and Current Code Evidence

- [App-specific HUD specification](specs/app-specific-huds.md) — authoritative scope, behavior,
  edge cases, UI placement, and acceptance criteria.
- `Models/Configuration.swift` — existing `inner`/`middle` are the backward-compatible Global
  layout; `TriggersConfig` already has tolerant per-field decoding but no Global HUD binding.
- `MousePlusApp.swift` — captures only the frontmost PID before showing the panel and currently
  reloads one global configuration directly into `RingViewModel`.
- `ViewModels/RingViewModel.swift` — already resets selection/outer expansion, snapshots the PID for
  actions, protects asynchronous App Switcher expansion, and loads one pair of action rings.
- `Services/TriggerService.swift` — one keyboard and one mouse monitor currently emit source/mode
  events without an invocation route or release owner.
- `ViewModels/SettingsWorkspaceCoordinator.swift` and `MenuEditorModel.swift` — one safe writer and
  one working action-layout editor already provide load gates, fresh-base merge, backup, reset,
  save status, and live apply; they currently edit only Global.
- `Views/MenuEditor/MenuItemsPane.swift` and `AppPickerSheet.swift` — existing Menu Items workspace
  and installed-app picker are the intended profile-management surface.
- `Views/Components/HUDCenterSettingsControl.swift` — the native center button owns one Settings
  action and drag arbitration; context presentation must preserve both.

Paths in tasks are relative to `01_Project/MousePlus/`, unless prefixed otherwise. The Xcode project
uses filesystem-synchronized groups, so new source/test files should receive target membership
automatically; verify test discovery instead of editing the project file preemptively.

## Execution Schedule and Ownership

- **Execution scope/limits:** this plan covers the approved v1 specification. Creating the plan does
  not authorize implementation; `/execute` starts work. Sparse overrides, app-command search, per-app
  presentation, and a second native Global mouse slot remain out of scope.
- **Existing dirty work:** preserve the retained Opening Styles regression and documentation edits
  listed by `git status`. The prior completed root plan was intentionally moved under `docs/plans/`;
  this new root plan becomes the active plan and must not restore or overwrite the archived plan.
- **Coordinator-owned shared resources:** `MousePlusApp.swift`, final integration fixes, root plan,
  project state/task/session documents, Xcode invocations, derived-data paths, app termination/launch,
  and Git operations. No commit, push, pull, branch switch, or worktree operation is authorized by
  this planning request.
- **Interfaces established by Task 1.1:** `HUDActionLayout`, a stable Global/app profile reference,
  an invocation route (`contextual`/`global`), an immutable frontmost-app snapshot, resolved-profile
  metadata, decode-tolerant/lossless profile storage, and `TriggersConfig.globalHUDShortcut`.
- **Dependency audit:** Wave 2 tasks consume only Task 1.1 and have disjoint source/test ownership.
  Wave 3 runtime and Settings tasks consume different Wave 2 interfaces and remain disjoint. Center
  rendering waits for the runtime context contract. Final integration begins only after every
  producer is integrated. There are no dependency cycles or same-wave write conflicts.
- **Serial-wave reasons:** Wave 1 owns the central configuration schema used by every consumer;
  Wave 4 owns the native center/RingMenuView seam; Wave 5 may touch any affected integration file
  while resolving concrete review findings, so each runs under one coordinator.

## Validation Commands

Run from the repository root. Use the configured signing identity and normal Xcode environment. Do
not weaken signing or use the user's live Application Support configuration in automated tests.

**B — authoritative build**

```bash
xcodebuild -workspace 01_Project/MousePlus.xcworkspace \
  -scheme MousePlus -configuration Debug build
```

**F — focused feature suite**

```bash
xcodebuild -workspace 01_Project/MousePlus.xcworkspace \
  -scheme MousePlus -configuration Debug -destination 'platform=macOS' test \
  -only-testing:MousePlusTests/AppSpecificHUDModelTests \
  -only-testing:MousePlusTests/AppSpecificHUDRuntimeTests \
  -only-testing:MousePlusTests/HUDTriggerRoutingTests \
  -only-testing:MousePlusTests/ConfigurationServiceTests \
  -only-testing:MousePlusTests/SettingsWorkspaceCoordinatorTests \
  -only-testing:MousePlusTests/RingViewModelHUDTests \
  -only-testing:MousePlusTests/HUDCenterSettingsTests \
  -only-testing:MousePlusTests/WorkspaceAccessibilityTests \
  -only-testing:MousePlusTests/DismissMonitorTests
```

Before a proposed class exists, omit it rather than treating a zero-test selection as evidence. For
each task, narrow F to the named classes and inspect test discovery/result counts.

**T — complete scheme test plan**

```bash
xcodebuild -workspace 01_Project/MousePlus.xcworkspace \
  -scheme MousePlus -configuration Debug -destination 'platform=macOS' test
```

**D — documentation and whitespace**

```bash
git diff --check
```

## Tasks

### Wave 1 — Durable contracts (serial foundation)

- [x] **1.1: Add lossless app-profile, resolution, and Global-trigger configuration contracts.**
  - Depends on / external gates: none.
  - Owns: `Models/Configuration.swift`; new `Models/AppHUDProfile.swift` and
    `Models/HUDInvocation.swift`; new `../MousePlusTests/AppSpecificHUDModelTests.swift`;
    relevant additions to `../MousePlusTests/ConfigurationServiceTests.swift` and JSON fixtures.
  - Work: retain `Configuration.inner`/`middle` as Global and add bundle-ID-keyed profiles whose
    complete action layouts do not duplicate global presentation/behavior. Creating a typed profile
    must support independent value semantics. Add the unbound, decode-tolerant Global HUD shortcut.
  - Work: make malformed individual profile payloads unavailable to runtime resolution while
    preserving their raw JSON losslessly through unrelated saves; a user-created replacement for
    that exact bundle ID may intentionally replace the opaque payload. Unknown future data and all
    unrelated Global fields must round-trip. Do not convert a corrupt present file into defaults.
  - Work: define pure exact-match resolution for Contextual/Global routes, including MousePlus,
    missing-bundle-ID, unavailable-profile, and no-profile fallbacks. The resolved result includes
    action layout and context metadata but no disk I/O or mutable `NSRunningApplication` reference.
  - Interface: supplies `HUDActionLayout`, `HUDProfileReference`, `HUDInvocationRoute`,
    `FrontmostAppSnapshot`, `ResolvedHUDProfile`, `Configuration.resolveHUD(...)`, valid-profile
    access/mutation, and `TriggersConfig.globalHUDShortcut` to Tasks 2.1–4.1.
  - Success: AC1, model portions of AC2–AC7, AC9, and trigger migration decode/round-trip cases pass;
    existing fixtures and unknown-action preservation remain green.
  - Backpressure: F narrowed to `AppSpecificHUDModelTests` and `ConfigurationServiceTests`; B; D.

### Wave 2 — Independent consumers (parallel after 1.1)

- [x] **2.1: Make the Settings coordinator edit one selected action profile safely.**
  - Depends on: 1.1. External gates: none.
  - Owns: `ViewModels/SettingsWorkspaceCoordinator.swift`, `ViewModels/MenuEditorModel.swift`, and
    `../MousePlusTests/SettingsWorkspaceCoordinatorTests.swift`.
  - Work: add non-persisted Global/app editor selection; load the selected action layout into the
    existing editor while always using global HUD customization. Create App HUD by copying current
    Global, reject/select duplicates, delete only app profiles, and preserve selection sensibly after
    load/delete/missing-app states.
  - Work: route editor changes into Global or the selected app profile without cross-profile writes.
    Extend `.menuItems` fresh-base merge, dirty generations, live apply, backup/restore, close barrier,
    reset, and session undo to preserve the complete profile collection. Global reset retains current
    semantics; App HUD reset restores a fresh copy of current Global without resetting global HUD
    customization.
  - Interface: coordinator profile list/selection plus create/delete/select operations consumed by
    Task 3.2; no view code and no second persistence writer.
  - Success: AC2–AC5 and AC17 model behavior pass, including save failure/retry, mid-session
    corruption, external edits, selection-only no-save, reset/undo, and relaunch simulations.
  - Backpressure: F narrowed to `SettingsWorkspaceCoordinatorTests` and
    `AppSpecificHUDModelTests`; B; D.

- [x] **2.2: Add an independent Global HUD keyboard route and unambiguous trigger events.**
  - Depends on: 1.1. External gates: none.
  - Owns: `Services/TriggerService.swift`, `Views/TriggersSettingsView.swift`; new
    `Utilities/HUDTriggerRouting.swift` and `../MousePlusTests/HUDTriggerRoutingTests.swift`;
    related trigger/accessibility assertions in `WorkspaceAccessibilityTests.swift` only.
  - Work: retain existing keyboard/mouse bindings as Contextual, add a second keyboard monitor for
    Global, and carry route plus stable physical-source identity on down/move/up events. Keep
    Hold-release and Tap-toggle semantics. Stop/reconfigure every monitor deterministically.
  - Work: add a native AppKit-backed “Global HUD Shortcut” row in the existing Triggers pane,
    unbound by default with its own mode control. Reject an exact contextual-keyboard collision with
    a visible reason and retain the previously saved Global binding; other established conflict
    behavior remains unchanged.
  - Interface: route/source-aware trigger event stream and pure binding-collision policy consumed by
    Task 3.1. No AppDelegate edits in this task.
  - Success: trigger configuration compatibility, event routing, monitor reconfiguration, duplicate
    rejection, Settings save/live-apply, and accessible native control metadata satisfy AC10,
    AC14–AC15, and the trigger portion of AC17.
  - Backpressure: F narrowed to `HUDTriggerRoutingTests`, `ConfigurationServiceTests`, and
    `WorkspaceAccessibilityTests`; B; D.

### Wave 3 — Runtime and Settings integration (parallel on disjoint files)

- [x] **3.1: Resolve, show, and safely switch Contextual/Global HUD invocations.**
  - Depends on: 1.1 and 2.2. External gates: none.
  - Owns: `MousePlusApp.swift`, `ViewModels/RingViewModel.swift`,
    `Controllers/RingWindowController.swift` only if a minimal anchored refresh seam is required;
    new `../MousePlusTests/AppSpecificHUDRuntimeTests.swift`; relevant additions to
    `RingViewModelHUDTests.swift` and `DismissMonitorTests.swift`.
  - Work: capture one immutable PID/bundle-ID/name snapshot before panel display, resolve from the
    already-loaded configuration, and load resolved actions with global presentation settings. Keep
    the profile and action target frozen for an invocation; saved configuration updates affect the
    next invocation without mutating an already-visible action layout.
  - Work: introduce a pure/testable invocation-ownership state machine. The other route replaces the
    layout in the visible panel at the same anchor, resets selection/outer state, transfers release
    ownership, and does not replay full summon motion. An old release is ignored. Same-route
    Tap-toggle dismissal and hold-release commit behavior remain intact; unavailable Contextual
    profiles safely resolve to Global.
  - Work: preserve App Switcher dynamic icons/full-circle geometry, expansion epochs, native mouse-up,
    Settings-center callbacks, outside/Escape dismissal, and action-result routing.
  - Interface: exposes stable resolved-context presentation to Task 4.1 and complete runtime routing
    behavior to Wave 5.
  - Success: AC6–AC14 and runtime portions of AC16/AC18 pass under exact match, fallback, rapid route
    switching, stale release, app activation, configuration live-apply, and reopen tests.
  - Backpressure: F narrowed to `AppSpecificHUDRuntimeTests`, `RingViewModelHUDTests`,
    `DismissMonitorTests`, and existing runtime interaction tests discovered in `MousePlusTests`; B; D.

- [x] **3.2: Add profile management above the existing Menu Items editor.**
  - Depends on: 2.1. External gates: none; placement was approved through the specification and must
    still be checked in the rendered minimum-size Settings window.
  - Owns: `Views/MenuEditor/MenuItemsPane.swift`, `Views/MenuEditor/AppPickerSheet.swift` only for
    reusable exclusion/missing-app behavior, `Views/AppKitControls/AppKitControls.swift` only if the
    existing popup wrapper lacks the required API, and profile UI additions to
    `WorkspaceAccessibilityTests.swift` after Task 2.2's changes are integrated.
  - Work: add one compact profile bar directly above `MenuEditorWorkspace`: native profile selector
    with Global first, Add App HUD…, and app-only Delete. Reuse the installed-app picker, select an
    existing duplicate instead of overwriting it, identify missing apps by stored bundle ID, and use
    an AppKit-native destructive confirmation. Clearly state that a new profile is copied once and
    then edited independently.
  - Work: ensure switching selection alone neither dirties configuration nor loses an in-progress
    serialized edit. Preview, selected-item routing, Test Action, reset/recovery, and visible save
    status operate on the named profile. Global cannot be deleted. Update the existing restore
    warning so it accurately states that recovery also replaces app profiles and customization.
  - Interface: completes Settings profile management without adding a destination, writer, split
    view, or raw SwiftUI interactive control.
  - Success: AC2–AC5 and AC17 pass through the actual native controls; minimum-size layout, keyboard
    traversal, identifiers, labels, duplicate choice, deletion, missing app, and save/relaunch state
    are verified.
  - Backpressure: F narrowed to `SettingsWorkspaceCoordinatorTests`,
    `WorkspaceAccessibilityTests`, and `AppKitControlsTests`; B; inspect the real Settings pane.

### Wave 4 — Native context presentation (serial shared view seam)

- [x] **4.1: Present the resolved context in the native center Settings control.**
  - Depends on: 3.1. External gates: none.
  - Owns: `Views/Components/HUDCenterSettingsControl.swift`, `Views/RingMenuView.swift`,
    `../MousePlusTests/HUDCenterSettingsTests.swift`, and center-specific additions to
    `AppSpecificHUDRuntimeTests.swift` after Task 3.1 is integrated.
  - Work: show the resolved app icon/name or Global identity while retaining one native Settings
    action, its current frame/hit target, drag arbitration, and stable accessibility identifier. Use
    a small gear affordance without adding a second action/node. Editor/opening previews that suppress
    the center remain isolated and query no live app icons.
  - Work: update the accessible label with the active context. Context replacement is immediate and
    does not replay the full opening style; under Reduce Motion it introduces no spatial animation.
    Tune only the compact icon/gear composition during live review, not its semantics or target size.
  - Interface: completes the user-visible `ResolvedHUDProfile` presentation consumed by Wave 5.
  - Success: AC16 and AC18 pass; center click/drag, early AXPress, opening concealment, stable AX frame,
    and preview isolation regressions remain green.
  - Backpressure: F narrowed to `HUDCenterSettingsTests`, `AppSpecificHUDRuntimeTests`,
    `HUDOpeningMotionTests`, and `HUDOpeningPreviewTests`; B; hosted native AX/frame inspection.

### Wave 5 — Integration and adversarial verification

- [x] **5.1: Close automated, compatibility, review, and fresh-build gates.**
  - Depends on: 3.1, 3.2, and 4.1. External gates: none for automated work; E1 remains separate.
  - Owns: all affected source/tests for concrete integration fixes; this plan, spec status/evidence,
    project state/tasks, and the eventual session record. Shared writes and Xcode resources are
    serialized by the coordinator.
  - Work: map every AC1–AC18 claim to a focused or existing regression; inspect actual test discovery
    and result counts. Review tolerant/raw profile preservation, fresh-base merges, reset/restore,
    same-binding rejection, event ownership, rapid switching, live-apply freezing, App Switcher
    state, panel anchoring, action target PID, center AX semantics, opening-motion isolation, and idle
    task/observer cleanup. Fix findings and rerun affected checks.
  - Work: run F, T, B, and D. Treat Xcode as authoritative over isolated SourceKit diagnostics. Do
    not claim visuals, BetterMouse delivery, or user acceptance from unit tests.
  - Success: all automated AC1–AC18 coverage and existing scheme tests pass with no unexpected skips;
    Debug build succeeds; documentation matches evidence; no unresolved review finding remains.
  - Backpressure: F + T + B + D; record exact counts/artifact path only after the commands run.

### Wave 5 automated evidence map

| Criteria | Regression evidence |
|---|---|
| AC1 | `AppSpecificHUDModelTests.testLegacyConfigurationKeepsGlobalLayoutAndAddsNoProfile`, `testExplicitNullMiddleRetainsLegacySampleFallback` |
| AC2 | `SettingsWorkspaceCoordinatorTests.testCreateCopiesCurrentGlobalThenProfilesEditIndependentlyAcrossReload`, `testGlobalUnknownItemFieldsSurviveSaveAndCreateByCopy` |
| AC3 | `SettingsWorkspaceCoordinatorTests.testAppEditUsesGlobalCustomizationWithoutWritingOtherActionProfiles`, `testFreshBaseRejectsConcurrentTypedEditToLocallyEditedProfile` |
| AC4 | Save-failure/close-barrier, raw recovery snapshot, and opaque collection/entry recovery regressions in `SettingsWorkspaceCoordinatorTests` |
| AC5 | `SettingsWorkspaceCoordinatorTests.testDeleteSelectedAppFallsBackToGlobalAndSurvivesReload` |
| AC6 | Exact-match/frozen-value model regression and `AppSpecificHUDRuntimeTests.testCommittedActionsUseFrozenInvocationPIDAndReplacementOwnerPID` |
| AC7 | Deterministic fallback-reason model regression and complete Global runtime fallback regression |
| AC8 | `AppSpecificHUDRuntimeTests.testConfigurationChangesDoNotMutateLoadedInvocationButNextLoadUsesThem` and frozen action-PID regression |
| AC9 | Pure `Configuration.resolveHUD` model tests plus runtime loading from an injected resolved snapshot; no persistence dependency exists on the summon path |
| AC10 | Global-route bypass model and runtime regressions |
| AC11–AC12 | Other-route ownership transfer, interaction-state clearing, and production panel replacement regressions |
| AC13 | Runtime ownership, native generation, cancellation-owner, and held-monitor reconfiguration regressions |
| AC14 | `AppSpecificHUDRuntimeTests.testSameRouteTapToggleDismissesWhileOtherRouteTapReplaces` |
| AC15 | `HUDTriggerRoutingTests` exact/symmetric collision, visible warning, retained save, effective-monitor, and held-cancellation regressions |
| AC16 | `HUDCenterSettingsTests` native action/frame/drag suite and production replacement center regression |
| AC17 | Coordinator profile-selection/non-dirty/recovery suite and native profile-bar accessibility regression |
| AC18 | Reduce Motion policy matrix plus replacement opening-isolation and immediate native center interaction regressions |

## External Checks

- [ ] **E1: Signed-live Finder and Global HUD acceptance.**
  - Depends on: 5.1.
  - Requires: user availability, configured Accessibility/keystroke permissions, Finder, one
    unconfigured app such as TextEdit, and distinct Contextual/Global shortcuts. Continue using the
    supported BetterMouse-to-keyboard route; direct MousePlus mouse acceptance remains separately
    deferred and cannot be claimed here.
  - Owns: signed artifact and signature evidence, exact launch/process-path evidence, user-observed
    acceptance results, and documentation updates. Use an isolated DerivedData path; never alter the
    user's live configuration outside the requested Settings actions.
  - Gates: AC19, the live portions of AC11–AC18, and overall feature completion. While unavailable,
    automated implementation may be complete but the plan and feature remain acceptance-pending.
  - Flow: create a Finder HUD from Global; change at least one inner and middle action; confirm visible
    save; exercise Finder Contextual, Finder Global, visible in-place switching both directions,
    stale Hold-release isolation, same-route Tap-toggle dismissal, center context/Settings/drag,
    Reduce Motion, unconfigured-app fallback, action targeting, quit/relaunch persistence, deletion,
    and post-delete fallback. Confirm a duplicate Global shortcut is rejected before restoring the
    chosen distinct binding.
  - Success / verification: fresh Debug build and strict deep signature verification pass; all old
    MousePlus instances exit gracefully; launch the exact fresh artifact and verify its running
    executable path; the user confirms the flow without stale commits, mixed profiles, target drift,
    lost settings, or accessibility/control regressions.

## Operational Learnings

- Existing Global `inner`/`middle` fields are compatibility-critical; profile support extends rather
  than renames or nests them.
- App-profile identity must be a bundle identifier, while PID remains invocation-local action context.
- Trigger route and physical source are different concepts; release ownership must survive two
  independently configured routes.
- A complete app action layout does not imply complete per-app presentation. Item-level overrides
  travel with their items; menu/ring presentation and behavior remain Global.

## Blocked Tasks

None at planning time. E1 is an explicit external acceptance gate, not an implementation blocker.

## Execution Log

| Wave / task IDs | Assignments or serial reason | Validation / evidence | Commits or exception | Remaining gates / next action or stop reason |
|---|---|---|---|---|
| Wave 1 / 1.1 | Serial foundation under the coordinator; independent data-integrity review after implementation. | 34 focused model/service tests pass; authoritative Debug build succeeds; `git diff --check` and changed-file security scan pass. Review findings covering opaque collection loss, nested future fields, self resolution, and duplicate IDs were fixed; final re-review found no remaining issue. | `54ce97f` | Wave 2 Tasks 2.1 and 2.2 are ready and independent; E1 remains the final external gate. |
| Wave 2 / 2.1, 2.2 | Parallel implementation with disjoint Settings-coordinator and trigger-route ownership; coordinator integrated review fixes and serialized Xcode/Git work. | 90 focused tests pass with 0 failures/skips; authoritative Debug build, `git diff --check`, and changed-file credential scan pass. Review fixes closed fresh-base/opaque profile preservation, recovery fidelity, exact modifier/release pairing, symmetric collision validation, and native accessible warning behavior; final independent re-review found no blockers. Fresh artifact relaunched from DerivedData as PID 87647. | `54a8ce8`, `a6914a6`, `2b94bca` | Wave 3 Tasks 3.1 and 3.2 are ready and independent. Task 3.2 must correct the expanded restore-warning scope; E1 remains the final external gate. |
| Wave 3 / 3.1, 3.2 | Parallel implementation with disjoint runtime and Menu Items ownership; coordinator integrated review fixes and serialized Xcode/Git work. | 113 focused regressions pass with no failures/skips; the final 11-test runtime class also passes after auxiliary-trigger adoption. Authoritative Debug build, `git diff --check`, and changed-file credential scan pass. Review closed save-timing wording, opaque-profile recovery/replacement, duplicate-name ambiguity, stale release/drag isolation, and new-trigger adoption; final re-review found no important residual issue. Fresh artifact relaunched from DerivedData as PID 86795. The real 1120×712 Menu Items pane shows the native profile bar and explanations without clipping; native AX/control tests cover identifiers and keyboard choice behavior. The user reports the app-aware HUD system works in the fresh build. | `d445388`, `9e71e28` | Wave 4 Task 4.1 is ready; E1 remains the final external gate, including its explicit transition/persistence flow. |
| Wave 4 / 4.1 | Serial native center/RingMenuView seam under the coordinator; independent AppKit/SwiftUI review after implementation and after fixes. | 45 focused center/runtime/opening regressions pass with no failures/skips; hosted and production-controller checks preserve the exact 40×40 AX frame and full-button hit target during app-to-Global replacement. Authoritative Debug build, `git diff --check`, and changed-file credential scan pass. Review fixes preserved adaptive icon rendering and made the decorative gear badge click-through; final re-review found no remaining important issue. Fresh artifact relaunched from DerivedData as PID 54738. | `6d0f391` | Wave 5 Task 5.1 is ready for complete integration/adversarial verification; E1 remains the final external signed-live gate. |
| Wave 5 / 5.1 | Serial cross-cutting integration under the coordinator; independent persistence and runtime adversarial reviews, followed by fix re-reviews. | AC1–AC18 mapped above. Final F: 158 passed, 0 failed/skipped. Final T: 377 passed, 0 failed/skipped. B and D pass; changed-file credential scan found no credential material. Review fixes cover lossless Global raw fields and recovery, same-profile concurrency, noncanonical selection, async App Switcher isolation, frozen action PID, selective held-trigger reconfiguration/cancellation, native replacement center/drag, and legacy null compatibility. Developer ID build artifact launched as PID 13881; strict deep verification reached `CSSMERR_TP_NOT_TRUSTED` on macOS 27 beta, so E1 retains signature trust as a live gate. | `a8d7db8` | Run E1 signed-live Finder/Global acceptance; do not claim AC19 yet. |

---
*Keep active while required work or acceptance is incomplete. On completion, archive with execution
evidence and update incoming links before retiring the active copy.*
