# Implementation Plan

> Focused Wave 7 remediation plan. Supersedes the completed Waves 1–6 HUD plan after signed live testing exposed runtime interaction and presentation defects.

## Goal

Close the sustained-use HUD redesign by fixing every failure found during signed user-driven verification while preserving direct mouse triggering, action safety, persistence, accessibility, and the passing automated baseline.

## Acceptance Criteria

- [ ] Move Earlier and Move Later wrap circularly at both ends without losing selection or changing item identity.
- [ ] A configured outside click dismisses the HUD everywhere outside its circular footprint, including transparent corners of the square panel; disabling the preference preserves the HUD.
- [ ] Preview selection is visually distinct from runtime hover, and an unhovered custom wedge/icon renders equivalently in preview and the live HUD.
- [ ] Always, Reveal, and Hidden create visibly and behaviorally distinct outer-ring states; Hidden draws no outer backing and cannot expand a parent.
- [ ] Reveal latches only for an expanded submenu after the pointer enters the inner region and then travels outward.
- [ ] In tap-toggle mode, dragging the center beyond a small threshold moves the current HUD without selecting or executing an action; a click still opens Menu Items Settings. Hold-release behavior remains unchanged.
- [ ] The user has a visible, reliable way to quit MousePlus even if the status icon is unavailable, and the signed development build can be relaunched without losing configuration.
- [ ] All narrow tests, the full test target, a signed Debug build, and a repeated user-driven verification pass succeed.

## Specs and Evidence

- `specs/sustained-use-hud-redesign.md` — existing HUD behavior and acceptance criteria
- `docs/sessions/2026-09-03.md` — original Wave 7 handoff
- Signed live findings, 2026-09-03 — circular reorder, outside dismissal, preview/runtime color mismatch, outer visibility, movement, and lifecycle access

---

## Tasks

### Wave 1 — Deterministic model and policy fixes

- [ ] **1.1: Make top-level reordering circular** → `01_Project/MousePlus/ViewModels/MenuEditorModel.swift`, `01_Project/MousePlusTests/MenuEditorModelRegressionTests.swift`
  - Replace edge clamping with modulo wrap for non-empty arrays; preserve the selected UUID and reject offsets that cannot resolve safely.
  - Success: first→Earlier moves to last, last→Later moves to first, repeated moves complete multiple revolutions, and selection follows the same item.
  - Backpressure: focused `MenuEditorModelRegressionTests` covering both bands, both directions, one-item arrays, and repeated wrap.

- [ ] **1.2: Define outer-ring policy as one pure state transition** → `01_Project/MousePlus/ViewModels/RingViewModel.swift`, `01_Project/MousePlus/Views/AppKitControls/HUDPreviewInteractionView.swift`, related tests
  - Share the same eligibility and reveal-latch rules between runtime and preview: no parent/no items = absent; Always = visible after expansion; Reveal = visible only after the inner-to-outer traversal; Hidden = absent and unavailable.
  - Success: runtime and preview produce identical visibility for the same policy, expansion, pointer history, and item state.
  - Backpressure: focused `RingViewModelHUDTests` and `HUDPreviewInteractionTests` state-transition matrices.

### Wave 2 — Runtime geometry and preview fidelity

- [ ] **2.1: Make outside-click dismissal circular and complete** → `01_Project/MousePlus/Services/DismissMonitor.swift`, `01_Project/MousePlus/Controllers/RingWindowController.swift`, `01_Project/MousePlus/MousePlusApp.swift`, tests
  - Keep the global monitor for clicks delivered to other apps; add a local panel click path that converts the event into panel coordinates and dismisses only when distance from HUD center exceeds `r3`.
  - Preserve wedge clicks, center clicks, trigger events, and the `dismissOnClickOutside` preference.
  - Success: desktop/other-app clicks and transparent-corner clicks dismiss; points inside the circular HUD do not; monitors are removed on every close path.
  - Backpressure: pure geometry boundary tests plus monitor/controller lifecycle tests and signed corner-click verification.

- [ ] **2.2: Render only the outer surface allowed by policy** → `01_Project/MousePlus/Views/RingMenuView.swift`, `01_Project/MousePlus/Views/Components/WedgeView.swift`, presentation tests
  - Draw the persistent material/background only through `r2`; add the localized outer backing and wedges only when `isOuterRingVisible` is true.
  - Success: Hidden has no visible `r2…r3` surface, Reveal adds it only after its latch, and Always shows it after a submenu parent expands.
  - Backpressure: `WedgePresentationTests`, accessibility snapshots, and signed screenshots for all three policies.

- [ ] **2.3: Separate editor selection from runtime hover presentation** → `01_Project/MousePlus/Views/MenuEditor/RingPreviewSelector.swift`, `01_Project/MousePlus/Views/RingMenuView.swift`, `01_Project/MousePlus/Views/Components/WedgeView.swift`, color/presentation tests
  - Keep persistent editor selection as a neutral outline/marker; drive accent/emphasis only from actual preview hover. Resolve semantic application colors once through the shared presentation path.
  - Success: the selected item remains discoverable without washing its configured color, and unhovered preview/live pixels use the same resolved wedge/icon colors.
  - Backpressure: pure state/color tests plus side-by-side signed screenshot comparison in light and dark appearances.

### Wave 3 — Movement and lifecycle access (UI confirmation gate)

- [ ] **3.1: Add thresholded center dragging for tap-toggle HUDs** → `01_Project/MousePlus/Views/Components/HUDCenterSettingsControl.swift`, `01_Project/MousePlus/Controllers/RingWindowController.swift`, `01_Project/MousePlus/Views/RingMenuView.swift`, tests
  - Proposed interaction: the existing center Settings control remains the sole affordance; a click opens Settings, while movement beyond 4 pt becomes a panel drag. Enable dragging only for tap-toggle invocations and clamp the moved panel to the active screen.
  - UI gate: confirm this interaction before implementation; do not add a raw SwiftUI control.
  - Success: click and drag are mutually exclusive, drag never executes a wedge, coordinate-space hit testing remains correct after movement, and hold-release remains pointer-anchored.
  - Backpressure: gesture-state unit tests, screen-clamp tests, and signed drag/click verification.

- [ ] **3.2: Provide a visible quit path and verify status-item rendering** → `01_Project/MousePlus/Views/GeneralSettingsPane.swift`, `01_Project/MousePlus/Controllers/MenuBarController.swift`, `01_Project/MousePlus/MousePlusApp.swift`, tests
  - Proposed placement: native AppKit “Quit MousePlus” button in General, following existing `AppKitButton` wiring; retain the menu command and make the template status image explicit and correctly sized.
  - UI gate: confirm General-pane placement before implementation.
  - Success: Quit works from General and the menu when visible; a signed relaunch preserves configuration and re-arms triggers.
  - Backpressure: callback tests, UI accessibility identifiers, signed quit/relaunch verification, and persisted JSON comparison.

### Wave 4 — Regression gate and feature closure

- [ ] **4.1: Run focused adversarial review** → all changed source/tests/spec/docs
  - Review array wrap identity, exact `r3` boundaries, monitor teardown, stale selection after dismissal, reveal reset per invocation, color contrast under selection/dimming, drag-vs-click arbitration, multi-display clamping, and quit during pending save.
  - Success: two focused passes leave no unresolved high-severity finding.
  - Backpressure: rerun every affected narrow suite after fixes.

- [ ] **4.2: Run the clean automated and signed live gates** → complete application
  - Run the full unit target and signed Debug build from clean derived data, then repeat the user-driven checklist with both trigger modes.
  - Verify no preview action executes, no mouse-trigger beep returns, settings survive quit/relaunch, and old configuration migration remains canonical.
  - Success: all acceptance criteria have recorded evidence and the sustained-use HUD specification can be marked Complete.
  - Backpressure: full tests + signed Debug build + persisted JSON inspection + user-driven screenshots.

- [ ] **4.3: Close documentation and tracker state** → `specs/sustained-use-hud-redesign.md`, `docs/PROJECT_STATE.md`, `docs/TASKS.md`, `docs/sessions/2026-09-03.md`
  - Record fixes, verification evidence, remaining deferred ring/label controls, and any non-blocking risks.
  - Success: plan, spec, tracker, and project-state claims agree; completed work is ready to archive.
  - Backpressure: checkbox/count audit and clean `git diff --check`.

---

## Operational Learnings

- A borderless circular HUD still owns a square AppKit window; global-only monitoring cannot observe clicks delivered to transparent parts of that window.
- Editor selection and runtime pointer selection are different states and must not share highlight presentation.
- Outer-ring visibility must control both hit testing and visible backing geometry; hiding wedges alone leaves a misleading ring.
- HUD relocation needs explicit gesture arbitration because a zero-distance drag already drives hold-release wedge selection.

## Blocked Tasks

- Wave 3 UI implementation waits for confirmation of the proposed center-drag interaction and General-pane Quit placement, per the UI Changes Protocol.

---

## Execution Log

| Wave | Started | Completed | Commits |
|------|---------|-----------|---------|
| 1 | | | |
| 2 | | | |
| 3 | | | |
| 4 | | | |
