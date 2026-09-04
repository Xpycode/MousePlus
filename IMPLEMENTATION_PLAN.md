# Implementation Plan

> Reorganize HUD customization into scope-specific tabs and add independently configurable, readable labels without changing existing configurations by default.

## Goal

Replace the stacked Menu/ring control groups with Menu, Inner, Middle, and Outer tabs, clarify inheritance wording, and add per-ring label visibility and orientation that render consistently in preview and the live HUD.

## Acceptance Criteria

- [ ] The Menu & Rings inspector contains a native AppKit segmented control with Menu, Inner, Middle, and Outer tabs; changing tabs does not change the selected menu item or active editing band.
- [ ] Menu owns shared defaults, Inner and Middle own their layout plus appearance overrides, and Outer owns visibility plus appearance overrides; controls appear in only the scope that owns them.
- [ ] Menu-level colors say “Default,” while ring- and item-level controls say “Inherit,” with concise help text explaining item → ring → menu → application-default resolution.
- [ ] Inner, Middle, and Outer labels can each be shown or hidden; compatibility defaults preserve the current HUD (Inner hidden, Middle and Outer shown).
- [ ] Labels support upright, radial, and tangential orientation with per-ring inheritance from a menu default; radial and tangential text automatically flips when needed so it is never upside down.
- [ ] Label visibility and orientation use the same resolved geometry in preview and runtime, do not rotate icons or expand affordances, and do not create or remove accessibility names.
- [ ] Missing, partial, and invalid persisted fields decode safely; canonical values round-trip through save, reset/undo, backup restore, merge, and relaunch without disturbing items or unknown actions.
- [ ] Focused tests, the complete unit target, a clean signed Debug build, and user-driven light/dark verification pass.

## Specs and Evidence

- `specs/sustained-use-hud-redesign.md` — completed customization foundation and inheritance rules
- `docs/PROJECT_STATE.md` — backlog scope and current project state
- `docs/sessions/2026-09-04.md` — signed baseline: 217 tests and the completed HUD lifecycle gate

## UI Placement Proposal (confirmed 2026-09-04)

Keep the existing top-level **Menu & Rings / Selected Item** inspector switch. Inside **Menu & Rings**, replace the three vertically stacked group boxes with a second native segmented control: **Menu / Inner / Middle / Outer**.

- **Menu:** default icon direction, default label direction, default wedge color, default icon color, and the inheritance explanation.
- **Inner:** slot mode/count, rotation, icon direction override, label visibility, label direction override, wedge color, and icon color.
- **Middle:** the same ring-owned controls as Inner.
- **Outer:** outer-item visibility, label visibility, icon direction override, label direction override, wedge color, and icon color. Outer has no independent slot count or rotation because its arc geometry belongs to the expanded middle parent.

Use the existing `AppKitSegmentedControl`, `AppKitSlider`, `AppKitCountControl`, and `AppKitColorWell`; add no raw SwiftUI interactive controls. The inspector remains fixed-width within the existing non-resizable `HStack`, so no new split view is introduced.

---

## Tasks

### Wave 1 — Persistence and pure presentation policy

- [x] **1.1: Add tolerant label customization fields and compatibility defaults** → `01_Project/MousePlus/Models/HUDCustomization.swift`, `01_Project/MousePlusTests/HUDCustomizationCodingTests.swift`, configuration fixtures
  - Add a label-orientation type plus menu default and per-ring overrides; add explicit per-ring label visibility.
  - Preserve current behavior for old files: Inner labels hidden, Middle and Outer labels shown, all labels upright.
  - Success: missing/partial/unknown values preserve valid siblings, canonical values round-trip, and reset defaults remain compatible.
  - Backpressure: focused `HUDCustomizationCodingTests` and `ConfigurationServiceTests` migration/round-trip cases.

- [x] **1.2: Define label visibility and readable rotation as pure resolved presentation** → `01_Project/MousePlus/Views/Components/LabelPresentationPolicy.swift` (new, alongside `OrientedHUDIcon.swift`/`WedgeView.swift`), focused tests
  - Resolve menu → ring label orientation independently from icon orientation; normalize angles and auto-flip radial/tangential text into a readable half-plane.
  - Keep accessibility labels independent from whether the visual caption is hidden.
  - Success: boundary-angle matrices prove labels never render upside down and icon/chevron transforms remain unchanged.
  - Backpressure: focused `WedgePresentationTests` covering all orientations, wrap boundaries, and visibility states.

### Wave 2 — Scope-specific inspector tabs

- [x] **2.1: Replace stacked customization groups with Menu/Inner/Middle/Outer tabs** → `01_Project/MousePlus/Views/MenuEditor/HUDCustomizationControls.swift`, `01_Project/MousePlus/Views/AppKitControls/AppKitControls.swift`, `01_Project/MousePlusTests/AppKitControlsTests.swift`
  - Implement the confirmed placement proposal with stable tab state, scope-owned control content, and unambiguous accessibility identifiers.
  - Rename only menu-root color choices to “Default”; retain “Inherit” for ring/item overrides and add concise hierarchy help.
  - Success: every control appears under exactly one owner tab, switching tabs preserves selection/active band, and keyboard/VoiceOver can identify and change each segment.
  - Backpressure: focused `AppKitControlsTests`, `WorkspaceAccessibilityTests`, and a source audit excluding forbidden SwiftUI controls.

### Wave 3 — Runtime, preview, and persistence integration

- [x] **3.1: Render per-ring label visibility and readable orientation everywhere** → `01_Project/MousePlus/ViewModels/RingViewModel.swift`, `01_Project/MousePlus/Views/RingMenuView.swift`, `01_Project/MousePlus/Views/Components/WedgeView.swift`, `01_Project/MousePlus/Views/MenuEditor/RingPreviewSelector.swift`, related tests
  - Feed the same resolved label policy to runtime and preview for Inner, Middle, and Outer wedges.
  - Rotate only the caption around its own center; icons and expand affordances retain their independently resolved presentation.
  - Success: preview/runtime parity holds for all rings, hidden labels leave icons centered sensibly, and visual visibility never erases accessibility names.
  - Backpressure: focused `RingViewModelHUDTests`, `HUDPreviewInteractionTests`, `WedgePresentationTests`, and accessibility cases.

- [ ] **3.2: Preserve the new values across every Settings write path** → `01_Project/MousePlus/ViewModels/MenuEditorModel.swift`, `01_Project/MousePlus/ViewModels/SettingsWorkspaceCoordinator.swift`, persistence/integration tests
  - Verify edit, debounce save, fresh-base merge, retry, reset/undo, durable backup restore, live apply, and relaunch paths carry all new fields.
  - Success: concurrent unrelated edits and recovery operations cannot revert label settings or lose unknown action data.
  - Backpressure: focused `MenuEditorModelRegressionTests`, `SettingsWorkspaceCoordinatorTests`, and `HUDCustomizationIntegrationTests`.

### Wave 4 — Closure gate

- [ ] **4.1: Run focused adversarial and automated verification** → complete change set
  - Review tab-state identity, compact-width label truncation, migration defaults, orientation discontinuities near flip boundaries, empty labels, submenu expansion, hidden labels, VoiceOver naming, and reset/merge races.
  - Success: no unresolved high-severity finding; every affected focused suite and the complete unit target pass.
  - Backpressure: focused suites, full MousePlus test target, forbidden-control audit, and `git diff --check`.

- [ ] **4.2: Run clean signed live verification and close documentation** → complete application, `docs/PROJECT_STATE.md`, `docs/TASKS.md`, session log
  - Verify all four tabs at minimum window width, light/dark preview and runtime parity, each ring’s show/hide behavior, readable radial/tangential labels around a full circle, persistence after immediate Quit, and trigger re-arming.
  - Success: signed user confirmation is recorded and tracker/spec/state claims agree.
  - Backpressure: clean signed Debug build plus user-driven screenshots and quit/relaunch verification.

---

## Operational Learnings

- Current Inner captions are suppressed structurally with `symbolOnly`; label controls require a resolved presentation policy rather than scattering additional band checks.
- `model.activeBand` controls item insertion and selection. The new customization tab must own separate UI state so viewing Middle settings cannot silently retarget Add or item editing.
- Outer items inherit their geometry from the expanded Middle parent, so the Outer tab must not imply independent slot-count or rotation ownership.

## Blocked Tasks

- None. The placement proposal is confirmed; Wave 2 UI implementation may proceed once Wave 1 lands.

---

## Execution Log

| Wave | Started | Completed | Commits |
|------|---------|-----------|---------|
| 1 | 2026-09-04 | 2026-09-04 | `feat(wave-1): add label orientation model and pure presentation policy` |
| 2 | 2026-09-04 | 2026-09-04 | `feat(wave-2): add Menu/Inner/Middle/Outer HUD customization tabs` |
| 3 | 2026-09-04 | | `feat(wave-3): wire per-ring label visibility and orientation into runtime and preview` (3.1 only; 3.2 remains) |
| 4 | | | |

---
*Delete this file when all tasks complete. Archive the outcome in the session log.*
