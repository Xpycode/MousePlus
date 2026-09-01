# IMPLEMENTATION_PLAN — Unified Settings Workspace

**Created:** 2026-09-01
**Status:** READY
**Funnel stage:** plan ✓ → build
**Source of truth:** `specs/unified-settings-workspace.md` (approved 2026-09-01)

## Goal

Replace MousePlus's compact tabbed preferences and separate Menu Editor with one resizable sidebar workspace where every supported ring action can be edited, durably saved, tested, and diagnosed without risking configuration loss.

## Acceptance Criteria

- [ ] General, Triggers, Ring Appearance, and Menu Items live in one resizable `SettingsSidebarShell` workspace; Menu Items embeds the ring preview and identity-based editor with no second editor window.
- [ ] One workspace coordinator owns load, dirty, debounce, flush, merge, backup, reset, restore, live-apply, and visible Loading/Saving/Saved/Failed state across all panes.
- [ ] Decode or write failure never overwrites the existing configuration, never live-applies an unsaved edit, and cannot lose dirty in-memory edits on close without explicit Discard.
- [ ] Unknown action raw values round-trip losslessly and appear unavailable; incompatible action payloads reset safely and invalid symbols stay visible through the placeholder resolver.
- [ ] Send Keystroke records one key plus modifiers inline through ShortcutKit, persists one canonical payload, migrates legacy shortcut data, and executes identically from Test Action and the live ring.
- [ ] Test Action flushes before execution, validates through the same contract as runtime, identifies contextual targets, and reports real completion/failure rather than dispatch-only success.
- [ ] Reset Menu Items creates a durable atomic backup, supports session Undo and post-relaunch Restore, and never affects triggers, appearance, or behavior.
- [ ] Live-ring execution failures use a brief non-activating error HUD with a route to the relevant Settings item; successful actions remain silent.
- [ ] Full Keyboard Access and VoiceOver can reach and understand all specified workspace controls and states.
- [ ] Automated model/persistence/action tests pass, followed by the reduced T12 live smoke test.

## Specs

- `specs/unified-settings-workspace.md` — approved product, safety, interaction, recovery, and accessibility contract.
- `docs/MENU_EDITOR_REVIEW.md` — existing editor invariants and regression cases F1/F5/F6/F7/F8/F15.
- `docs/SEND_KEYSTROKE_PLAN.md` — researched CGEvent recipe; this plan supersedes its recorder, migration, and error-surfacing sequence where the approved spec differs.

## Verified Gap Analysis

| Area | Exists | Delta |
|---|---|---|
| Settings shell | Fixed `460 × 460` `TabView` | Pinned sidebar shell, larger resizable scene, direct Menu Items pane |
| Menu editor | Identity-based side-by-side editor in its own controller | Embed composition, add persistent chrome/status/Test/Reset, retire launcher/controller |
| Persistence | Four service instances; fallback-default and `try?` writers remain | One serialized coordinator, explicit states, flush barrier, backup/restore, save-before-live-apply |
| Action model | Unknown raw values collapse to `.custom` | Lossless unknown representation, `sendKeystroke`, explicit supported/unavailable choices |
| Shortcut data | Dead `keyboardShortcut`; no package dependency | Canonical tolerant payload, legacy migration, exact ShortcutKit pin |
| Actions | Partial execution; malformed payloads no-op; ring uses `try?` | Shared validation/result, awaited command exit, keystroke service, context and error routes |
| UI controls | App panes/editor use raw SwiftUI controls | AppKit wrappers; only approved shared shell/recorder exceptions |
| Tests | Placeholder UI test; test plan references missing feature package | Real unit target, injected seams/fixtures, focused tests and final live gate |
| Dependency | No SPM products; needed package work is dirty | Commit/push required package scope, then pin immutable revision |

## Global Backpressure

```bash
BUILD="xcodebuild -workspace 01_Project/MousePlus.xcworkspace -scheme MousePlus -configuration Debug build"
TEST="xcodebuild test -workspace 01_Project/MousePlus.xcworkspace -scheme MousePlus -testPlan MousePlus"
```

Run `BUILD` after every implementation task. Tasks with tests also run their focused `TEST` selection; each wave ends with full `TEST`. No task advances with warnings introduced by that task.

## Tasks

### Wave 0 — Dependency and test gates (sequential prerequisites)

- [x] **0.1 Stabilize the shared-package source** → `/Users/sim/ProgrammingProjects/1-macOS/zPackages/Sources/{MacUIKitSettings,ShortcutKit}`, package tests
  - Success: the approved shell, recorder, layout-aware shortcut, candidate callback, commit gate, conflicts, sticky candidate, and teardown behavior are committed and pushed on a clean revision; unrelated dirty package work is excluded.
  - Backpressure: `swift test --package-path /Users/sim/ProgrammingProjects/1-macOS/zPackages --filter 'MacUIKitSettingsTests|ShortcutKitTests'`; record exact revision.

- [x] **0.2 Pin package products into MousePlus** → `01_Project/MousePlus.xcodeproj/project.pbxproj`, SwiftPM resolution
  - Depends on: 0.1
  - Success: `MacUIKitSettings` and `ShortcutKit` resolve from the zPackages GitHub repository at the exact clean revision; no local-path or floating-branch dependency remains.
  - Backpressure: resolve packages, verify resolved revision, then cold and cached `BUILD`.

- [x] **0.3 Add a real unit-test target** → Xcode project, `MousePlus.xctestplan`, new `01_Project/MousePlusTests/`
  - Depends on: 0.2
  - Success: `MousePlusTests` can `@testable import MousePlus`; the stale missing `MousePlusFeatureTests` entry is replaced; a sentinel test executes.
  - Backpressure: `TEST -only-testing:MousePlusTests` executes at least one passing test.

### Wave 1 — Model, keystroke, and control foundations (parallel after Wave 0)

- [x] **1.1 Preserve action types losslessly** → `Models/ActionType.swift`, `ActionDataEditor.swift`, `MousePlusTests/ActionTypeCodingTests.swift`
  - Success: known cases include `sendKeystroke`; unknown strings decode unavailable and re-encode unchanged; selectable supported cases are separate from all decodable values.
  - Backpressure: round-trip tests cover known, legacy `clipboard`, and arbitrary future values; `BUILD`.

- [x] **1.2 Define canonical keystroke payload and migration** → new `Models/KeystrokePayload.swift`, `RingMenuItem.swift`, payload tests
  - Success: payload represents key+modifiers or an unresolved legacy string; non-empty `keyboardShortcut` migrates only without canonical data; new encodes omit the legacy field and never guess an executable chord.
  - Backpressure: fixtures cover canonical, masking, canonical-wins, parseable/unresolved legacy, missing field, nested sub-items; `BUILD`.

- [x] **1.3 Implement injectable keystroke posting** → new `KeystrokeService.swift`, `CGEventPosting.swift`, service tests
  - Success: private source posts down/up with explicit flags to `.cghidEventTap`, approved delays, and post-event preflight; injected poster/clock verifies behavior without real input.
  - Backpressure: tests assert permission failure, event order, flags, tap, cancellation; `BUILD`.

- [x] **1.4 Add app-owned AppKit control wrappers** → new `Views/AppKitControls/`
  - Success: wrappers cover buttons, checkbox, popup, segmented control, slider, single/multiline fields, and selectable rows with enabled/focus/accessibility bindings.
  - Backpressure: wrapper harness compiles; coordinator callbacks remain main-thread safe; `BUILD`.

### Wave 2 — Safe persistence boundary (sequential core)

- [x] **2.1 Make configuration storage injectable and recoverable** → new `ConfigurationStore.swift`, `ConfigurationService.swift`, filesystem tests
  - Depends on: Wave 1 models
  - Success: production/temp stores share APIs; missing-file defaults differ from decode failure; save is atomic; backup is created beside config without destroying the previous backup first; restore/discovery are explicit.
  - Backpressure: tests cover absent, valid, corrupt, unwritable, backup-replacement failure, restore; `BUILD`.

- [x] **2.2 Build the workspace configuration coordinator** → new `SettingsWorkspaceCoordinator.swift`, coordinator tests
  - Depends on: 2.1
  - Success: one observable coordinator owns configuration/editor model, load/save state, dirty fields, serialized debounce/flush, retry, and post-save live apply; cancelled debounce is never called saved; every save revalidates a decoded base.
  - Backpressure: deterministic tests cover rapid edits, teardown, overlapping panes, mid-session corruption, failed write/retry, no-op close, live-apply-after-success; `BUILD`.

- [x] **2.3 Add reset, restore, and close-barrier state machines** → coordinator, new `SettingsWorkspaceState.swift`, tests
  - Depends on: 2.2
  - Success: Reset changes menu items only after backup; Undo/Restore use normal save; failed close flush exposes Retry/Discard/Cancel and cannot dismiss otherwise.
  - Backpressure: transition tests cover every acceptance branch and relaunch; `BUILD`.

### Wave 3 — Shared action contract and feedback plumbing (parallel after Waves 1–2)

- [x] **3.1 Define validation and execution results** → new `ActionValidation.swift`, `ActionExecutionResult.swift`, tests
  - Success: editor/runtime share validation for containers, supported payloads, unresolved legacy, known unavailable, unknown unavailable, and missing context; every invalid result has user-facing text.
  - Backpressure: table-driven validation tests; `BUILD`.

- [x] **3.2 Upgrade ActionService completion semantics** → `ActionService.swift`, new injected process/workspace seams, tests
  - Depends on: 1.3, 3.1
  - Success: service validates, invokes keystrokes, awaits command exit/non-zero status, checks app activation/launch, and returns structured results without UI coupling.
  - Backpressure: tests cover launch error, non-zero exit, activation failure, unavailable/invalid payload, permission denial; `BUILD`.

- [x] **3.3 Capture a safe Settings test target** → new `SettingsActionContextProvider.swift`, `MousePlusApp.swift`, tests
  - Success: external app is recorded before Settings activation and refreshed after focus round-trip; target name/PID/current screens or an unavailable reason are exposed; MousePlus is excluded.
  - Backpressure: tests cover first open, focus return, terminated/stale target, MousePlus-only state; `BUILD`.

- [x] **3.4 Add presentation-neutral result routing** → new `ActionResultRouter.swift`, tests
  - Success: Settings retains per-item Test results; runtime failures emit message+settings route; runtime successes emit nothing.
  - Backpressure: async routing/replacement/dismissal tests; `BUILD`.

### Wave 4 — Unified workspace and pane migration

- [x] **4.1 Replace TabView with approved sidebar shell** → `SettingsView.swift`, new `SettingsSection.swift`, `MousePlusApp.swift`
  - Depends on: 0.2, 2.2, 1.4
  - Success: four panes appear in order through `SettingsSidebarShell(searchable: false)`; General is initial; selection lives for the scene; minimum size fits shell+editor; primary layout uses `HSplitView`, never `NavigationSplitView`.
  - Backpressure: `BUILD`; launched keyboard/mouse navigation at minimum and larger sizes.

- [x] **4.2 Migrate General, Triggers, and Ring Appearance** → new Settings pane files, `TriggersSettingsView.swift`, remove superseded code
  - Depends on: 4.1
  - Success: panes bind through coordinator, use AppKit wrappers, preserve recorder/permission behavior, and contain no independent config service/fallback writer/debounce/live apply.
  - Backpressure: integration tests; writer `rg` audit; `BUILD`; live rebind/appearance check.

- [x] **4.3 Embed Menu Items workspace** → `MenuEditorView.swift`, `RingPreviewSelector.swift`, `SlotEditorForm.swift`, new `MenuItemsPane.swift`
  - Depends on: 4.1
  - Success: preview/form share draggable split; chrome remains visible; detail alone scrolls; selection stays UUID-based; pane minima work within shell.
  - Backpressure: F7/F8/F15 plus identity regression tests; `BUILD`; resize/selection check.

- [x] **4.4 Retire the second editor path** → `MousePlusApp.swift`, Settings files, delete `MenuEditorWindowController.swift`
  - Depends on: 4.3
  - Success: no product path launches another editor; persistence ownership lives only in coordinator.
  - Backpressure: `rg "MenuEditorWindowController|showMenuEditor|Open Menu Editor"` has no product references; `BUILD`.

### Wave 5 — Editor actions, Test Action, recovery, accessibility

- [x] **5.1 Migrate editor controls and unavailable actions** → editor views, symbol/app pickers
  - Depends on: 1.1, 1.4, 3.1, 4.3
  - Success: supported types alone are selectable; unavailable types stay visible/lossless; model invariants handle payload switches; app controls use wrappers; invalid symbols persist and announce placeholder.
  - Backpressure: switch/round-trip tests; forbidden-control audit with shared exceptions only; `BUILD`.

- [x] **5.2 Integrate ShortcutKit recording** → `ActionDataEditor.swift`, new `KeystrokePayload+ShortcutKit.swift`, tests
  - Depends on: 0.2, 1.2, 5.1
  - Success: sticky layout-aware candidate; Save/Cancel/Clear affect selected item only; teardown preserves committed data; ordinary conflicts warn; proven unusable/reserved conflicts block visibly; no trigger registration.
  - Backpressure: adapter/conflict and package tests; `BUILD`; manual record/cancel/section-switch.

- [x] **5.3 Add flush-before-Test Action** → new `TestActionControl.swift`, `MenuItemsPane.swift`, coordinator/router
  - Depends on: 2.2, 3.2–3.4, 5.1
  - Success: validation/context disable reasons appear; dirty edits flush first; save failure prevents execution; contextual target is named; results persist until edit/retry/dismiss.
  - Backpressure: ordering/failure integration tests; `BUILD`; live app/custom/snap tests.

- [x] **5.4 Add status, reset/undo/restore, and close UI** → new `WorkspaceStatusView.swift`, `CloseBarrier.swift`, Menu Items and Settings window bridge
  - Depends on: 2.3, 1.4
  - Success: all visible states render text; reset names scope/backup; Undo/Restore are discoverable; Retry/Discard/Cancel gates close.
  - Backpressure: UI-state tests; temporary corrupt/unwritable harness (not real config); `BUILD`.

- [x] **5.5 Complete workspace accessibility** → Settings/editor views, wrappers, new UI tests
  - Depends on: 4.1–5.4
  - Success: identifiers/labels expose wedge band/position/label/action/selection; state isn't color-only; every required operation is keyboard reachable with focus.
  - Backpressure: UI tests plus manual Full Keyboard Access/VoiceOver audit; `BUILD`.

### Wave 6 — Runtime integration

- [x] **6.1 Consolidate post-save live apply** → `MousePlusApp.swift`, coordinator
  - Depends on: Waves 4–5
  - Success: one post-save callback updates full runtime configuration, rings, appearance, triggers, and Settings hotkey; old field callbacks are removed; failure changes nothing live.
  - Backpressure: runtime snapshot tests; obsolete-bridge `rg`; `BUILD`.

- [x] **6.2 Wire live-ring results and error HUD** → `RingViewModel.swift`, router, new `ActionErrorHUDController.swift`, app delegate
  - Depends on: 3.2, 3.4
  - Success: no `try?` execution; failures show brief non-activating HUD with AppKit Open Settings route; success silent; ring dismissal unchanged.
  - Backpressure: router/controller tests; swallowed-error `rg`; `BUILD`; live unavailable/denied check.

- [x] **6.3 Make default inner actions real** → `RingMenuItem.swift`
  - Depends on: 1.2, 3.2
  - Success: fresh defaults use keystrokes for Copy/Paste/Spotlight and approved Mission Control command; saved configs are not reseeded.
  - Backpressure: default fixture tests; `BUILD`; temporary fresh-config smoke.

### Wave 7 — Final gates

- [ ] **7.1 Run full automated and static gates** → whole project
  - Depends on: Waves 0–6
  - Success: package/unit/UI tests, clean build, fixture round-trips, package revision, and control/reference searches pass without new warnings.
  - Backpressure: clean DerivedData build then full `TEST`; archive output in session log.

- [ ] **7.2 Adversarial safety/accessibility review** → implementation diff and acceptance matrix
  - Depends on: 7.1
  - Success: persistence races, forward compatibility, action side effects/context, view identity/lifecycle, keyboard/VoiceOver, and pin reproducibility are independently reviewed; findings fixed or user-accepted.
  - Backpressure: focused regressions, full `TEST`, `BUILD`.

- [ ] **7.3 Reduced T12 user-driven live smoke** → signed Debug app
  - Depends on: 7.2
  - Success: open workspace, edit/save item, record/test keystroke, reopen for persistence, invoke live ring, confirm no second editor; spot-check F1/F7/F8/F15 and close choices.
  - Backpressure: user confirmation/session log; merge/push only through explicit repository-history procedure.

## UI Constraints Checklist

- [x] `SettingsSidebarShell`/`HSplitView`; no `NavigationSplitView` or Tahoe sidebar.
- [x] Menu Items uses `HSplitView` because divider is user-resizable.
- [x] Shared shell and ShortcutKit recorder are the only approved narrow interactive-control exceptions.
- [x] App-owned controls migrate through AppKit wrappers.
- [x] Placement is approved: General → Triggers → Ring Appearance → Menu Items.
- [x] Live placement/binding checks exist before final T12.

## Risks and Mitigations

- **Dirty package checkout:** commit only required package scope and pin immutable revision before imports.
- **Unknown action destruction:** lossless representation and fixtures land before coordinator writes.
- **Legacy shortcut ambiguity:** unparseable strings become unresolved canonical payloads requiring re-recording; never guessed or discarded.
- **Cross-pane lost updates:** one coordinator serializes writes; tests overlap menu/trigger/appearance edits.
- **Close-time loss:** coordinator gates close with three explicit choices.
- **Wrong app targeted:** provider excludes MousePlus and names target before test.
- **Synthetic-input/TCC risk:** injected tests post nothing real; signed live gate probes permissions and held modifiers.
- **Focus-stealing HUD:** non-activating controller; only explicit Open Settings activates.
- **Large migration:** each wave ends green; old editor remains usable until task 4.4.

## Operational Learnings

- Current test plan references missing `MousePlusFeatureTests`; repair topology before trusting feature tests.
- MacUIKitSettings exists at current zPackages HEAD, but required ShortcutKit behavior is dirty; current HEAD is not the integration revision.
- MousePlus currently links no SPM products.
- Approved spec supersedes the older Send Keystroke plan on recorder, legacy migration, and errors.

## Blocked Tasks

- Wave 0.1 blocker resolved 2026-09-01: fetched the canonical remote history, fast-forwarded the hash-identical synchronized checkout, and verified clean revision `b4ad72a5dd84666e875b19afadd6de13b93fabcb` with 125 focused tests passing.

## Execution Log

| Wave | Started | Completed | Commits / evidence |
|---|---|---|---|
| 0 | 2026-09-01 | 2026-09-01 | 0.1: clean pushed zPackages revision `b4ad72a5dd84666e875b19afadd6de13b93fabcb`, focused tests 125/125. 0.2: exact pin + cold/cached builds, commit `369ba7e`. 0.3: real unit target + sentinel, commit `63c9433`. Full unit/UI plan passed with ad-hoc signing. |
| 1 | 2026-09-01 | 2026-09-01 | 1.1 `34ec954`; 1.2 `0916596`; 1.3 `507f0c7`; 1.4 `7546235`. Unsigned Debug build and full MousePlus test plan passed (18 unit tests + 1 UI test); signed build unavailable because this machine lacks the configured certificate. |
| 2 | 2026-09-01 | 2026-09-01 | 2.1 `9dd165b`; 2.2 `5a5d2ae`; 2.3 `711fb9d`. Focused Wave 2 persistence/coordinator/state suites passed 21/21; independent workspace build remained blocked by the sandboxed Xcode/CoreSimulator workspace-detection failure. |
| 3 | 2026-09-01 | 2026-09-01 | 3.1 `76df64e`; 3.2 `a29eed7`; 3.3 `53bcc32`; 3.4 `183bb5f`. Shared validation/results, awaited and injectable action execution, safe Settings target capture, and presentation-neutral routing landed. Focused Wave 3 suites passed 17/17; full plan passed 55 unit tests + 1 UI test; unsigned Debug build succeeded. |
| 4 | 2026-09-01 | 2026-09-01 | 4.1 `79f51bc`; 4.2 `5c105cc`; 4.3 `2a2e720`; 4.4 `4c53d3b`. Unified resizable sidebar, coordinator-backed panes, embedded UUID-safe Menu Items workspace, and standalone-editor retirement landed. F7/F8/F15 + identity regressions passed 5/5; full plan passed 60 unit tests + 1 UI test; unsigned Debug build and writer/reference audits succeeded. Live resize, keyboard navigation, and rebind/appearance checks remain in the final user-driven gate. |
| 5 | 2026-09-01 | 2026-09-01 | 5.1 `7441c25`; 5.2 `ba4a67b`; 5.3 `c15a3ab`; 5.4 `917273a`; 5.5 `4312801`. Editor controls/unavailable values, inline ShortcutKit recording, flush-before-Test, visible persistence/recovery/close states, and accessibility semantics landed. Full MousePlus unit/UI test plan and unsigned Debug build passed; live recorder, Full Keyboard Access, and VoiceOver checks remain in the final user-driven gate. |
| 6 | 2026-09-01 | 2026-09-01 | Consolidated durable full-snapshot live apply; live-ring failures now route to a four-second non-activating HUD with exact Menu Items routing; fresh Copy/Paste/Spotlight/Mission Control defaults execute real actions. Full unsigned MousePlus test plan and Debug build passed; obsolete-bridge and swallowed-error searches clean. |
| 7 | | | |

---
*Plan: 29 tasks across 8 waves. Regenerate if architecture or approved scope changes.*
