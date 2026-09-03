# Implementation Plan — Sustained-Use HUD Redesign

> **Persists across sessions.** Execute in dependency order and update checkboxes as tasks pass. Regenerate if the architecture changes materially rather than layering exceptions onto this plan.

## Goal

Turn MousePlus into a safe, live HUD experimentation surface with center Settings access, independent ring geometry, configurable outer-ring visibility, inheritable orientation and colors, and backward-compatible persistence.

## Acceptance Criteria

- [ ] The runtime HUD opens the menu editor from a dedicated center Settings control without executing a configured action in either trigger mode.
- [ ] Inner and middle rings support independent auto/fixed slot counts and angular offsets; invisible fixed slots preserve spacing but have no render, hit, or accessibility target.
- [ ] Outer-ring visibility supports always visible, reveal beyond the inner ring, and always hidden; conditional reveal latches for one invocation.
- [ ] Upright, radial, and tangential icon orientation resolves through menu defaults and optional per-ring overrides.
- [ ] Wedge and icon colors resolve application → menu → ring → item, round-trip as sRGB RGBA, and retain verified icon/label contrast.
- [ ] Small fixed choices use native compact segmented controls; longer/dynamic choices keep an appropriate popup or purpose-built control.
- [ ] The editor preview updates immediately, reproduces runtime geometry and reveal behavior, supports safe selection/hover, and cannot execute actions.
- [ ] Pre-redesign, partial, malformed-new-field, and current configurations load without losing unrelated data; compatibility defaults reproduce current behavior.
- [ ] Automated tests, accessibility checks, a clean Debug build, and signed live verification pass on macOS 14+.

## Specs

- `specs/sustained-use-hud-redesign.md` — approved behavior, boundaries, and detailed Given/When/Then criteria.
- `specs/unified-settings-workspace.md` — persistence, close barrier, recovery, and Settings workspace contracts that remain in force.

## Resolved Planning Decisions

1. **Contrast:** use WCAG 2.2 relative luminance without rounding. Meaningful icons, controls, and state indicators require at least **3:1** against adjacent colors; small wedge labels require **4.5:1**. Resolve the requested color first, then choose a deterministic black/white application fallback when the threshold fails. Preserve the requested value in configuration so future edits do not destroy user intent.
2. **Color persistence:** convert selected `NSColor` values to sRGB, then persist explicit red, green, blue, and alpha components as bounded numbers. A failed color-space conversion rejects the edit and retains the previous value.
3. **Conditional outer reveal:** start each invocation unrevealed; a center-relative radius transition from `≤ r1` to `> r1` reveals an available outer ring. The state latches until `reset()`/close. A pointer starting outside `r1` must first enter `≤ r1` before a later outward crossing can reveal, preventing instant reveal from a stale/outlying pointer location.
4. **Always-hidden submenus:** keep submenu data and the parent's appearance, suppress the expand affordance and commit path, expose the parent as unavailable with “Submenu hidden by HUD setting,” and show an inline Settings warning with a route to change visibility. Never execute the parent's marker action as a fallback.
5. **Preview interaction architecture:** replace the preview's per-wedge SwiftUI `Button` overlays with one AppKit-backed interaction surface that calls the same pure geometry/hit-test API as runtime. This removes duplicated hit regions, conforms to project UI rules, and enforces a non-executing preview path.
6. **Control selection:** use `NSSegmentedControl` for two-to-four short fixed options when labels fit; use `NSPopUpButton` for longer/dynamic lists, `NSStepper` plus `NSTextField` for fixed slot counts, `NSSlider` for angular offsets, and `NSColorWell` for colors.

## Current Delta

- `Configuration` has tolerant decoding, but only global appearance fields; `RingMenuItem` has no color overrides and the editor only merges item arrays.
- `RadialGeometry`, `RingViewModel`, `RingMenuView`, and `RingPreviewSelector` assume one shared inner/middle spoke count and zero angular offset.
- Placeholder wedges visibly render faint fills and are represented in shared geometry; the new fixed-slot contract requires completely invisible, inert empty positions.
- Outer arcs exist only after expanding a middle parent; invocation-level always/conditional/hidden policy does not exist.
- `WedgeView` hard-codes default/accent colors and upright icons.
- The editor already has a live render model, AppKit sliders/segmented controls, debounced autosave, recovery, and live apply; these should be extended rather than replaced.
- `RingPreviewSelector` currently uses SwiftUI buttons as annular hit targets, which conflicts with project UI conventions and duplicates renderer geometry.
- `AppDelegate.showSettings()` and routed Settings selection already exist, so the center control needs a narrow callback rather than a second window-opening mechanism.

## Backpressure Baseline

Use these exact gates unless a task names a narrower one:

```bash
xcodebuild -workspace 01_Project/MousePlus.xcworkspace -scheme MousePlus -configuration Debug build
xcodebuild test -workspace 01_Project/MousePlus.xcworkspace -scheme MousePlus -destination 'platform=macOS'
```

All source is under `01_Project/MousePlus/`; Xcode synchronized groups should auto-register new Swift files.

---

## Tasks

### Wave 1 — Contracts and Pure Foundations (parallel)

- [x] **1.1: Add tolerant HUD customization configuration and migration defaults** → `Models/Configuration.swift`, new `Models/HUDCustomization.swift`, `Models/RingMenuItem.swift`, `MousePlusTests/ConfigurationServiceTests.swift`, new `MousePlusTests/HUDCustomizationCodingTests.swift`
  - Define `SlotCountMode`, `OuterRingVisibility`, `IconOrientation`, per-band layout/appearance overrides, and optional item wedge/icon colors.
  - Compatibility defaults reproduce today's shared item-derived spoke count, zero offsets, upright icons, current application colors, and current outer behavior.
  - Validate/clamp only malformed new fields; preserve unrelated configuration and unknown action values.
  - Success: legacy, partial, canonical, and invalid-new-field fixtures decode and round-trip without data loss.
  - Backpressure: `xcodebuild test -workspace 01_Project/MousePlus.xcworkspace -scheme MousePlus -destination 'platform=macOS' -only-testing:MousePlusTests/HUDCustomizationCodingTests -only-testing:MousePlusTests/ConfigurationServiceTests`

- [x] **1.2: Replace shared-spoke math with explicit per-band geometry inputs** → `Utilities/RadialGeometry.swift`, new `MousePlusTests/RadialGeometryTests.swift`
  - Introduce a small value type containing effective slot count and normalized angular offset for each top-level band.
  - Make wedge angles, centroids, hit testing, and outer-parent arc calculations consume the correct band's geometry.
  - Preserve existing coordinate convention and boundary behavior where new settings do not apply.
  - Success: asymmetric counts/offsets, wraparound, boundary points, outer-parent alignment, and invisible empty indices pass deterministic tests.
  - Backpressure: `xcodebuild test -workspace 01_Project/MousePlus.xcworkspace -scheme MousePlus -destination 'platform=macOS' -only-testing:MousePlusTests/RadialGeometryTests`

- [x] **1.3: Add sRGB color persistence and contrast resolution utilities** → new `Models/HUDColor.swift`, new `Utilities/HUDColorResolver.swift`, new `MousePlusTests/HUDColorResolverTests.swift`
  - Encode bounded sRGB RGBA components; bridge to/from `NSColor` through `.sRGB` conversion.
  - Implement WCAG relative luminance and unrounded contrast ratio.
  - Resolve application/menu/ring/item inheritance separately for wedge and icon; keep requested and rendered colors distinct.
  - Apply deterministic black/white fallback at 3:1 for icons and 4.5:1 for small labels.
  - Success: reference luminance pairs, alpha compositing over the final wedge, inheritance order, failed conversion, and fallback choices pass tests.
  - Backpressure: `xcodebuild test -workspace 01_Project/MousePlus.xcworkspace -scheme MousePlus -destination 'platform=macOS' -only-testing:MousePlusTests/HUDColorResolverTests`

- [x] **1.4: Extend reusable AppKit controls for the new Settings inputs** → `Views/AppKitControls/AppKitControls.swift`, new `MousePlusTests/AppKitControlsTests.swift`
  - Add an `NSColorWell` wrapper with explicit inherit/custom state, plus a compact `NSTextField` + `NSStepper` count control.
  - Harden `AppKitSegmentedControl` sizing, tooltips, selected-state accessibility, and keyboard behavior for short fixed choices.
  - Do not introduce raw SwiftUI interactive controls.
  - Success: bindings update in both directions, disabled/inherit state is visible, identifiers are stable, and the app builds on the macOS 14 target.
  - Backpressure: narrow control tests, then Debug build.

### Wave 2 — Runtime State and Rendering Primitives (depends on Wave 1; tasks parallel after contracts land)

- [x] **2.1: Teach `RingViewModel` effective geometry and invocation reveal policy** → `ViewModels/RingViewModel.swift`, new `MousePlusTests/RingViewModelHUDTests.swift`
  - Load customization values, derive valid effective auto/fixed counts, track center-entry/outward-crossing state, and reset reveal state on every close/open.
  - Enforce always-visible/conditional/hidden outer policy and suppress submenu-only commits while hidden.
  - Success: both trigger-neutral state transitions, invalid fixed counts, reveal latching, stale outside-pointer entry, hidden submenus, and reset behavior pass without executing actions.
  - Backpressure: `xcodebuild test -workspace 01_Project/MousePlus.xcworkspace -scheme MousePlus -destination 'platform=macOS' -only-testing:MousePlusTests/RingViewModelHUDTests`

- [x] **2.2: Make wedges render resolved colors and icon orientation** → `Views/Components/WedgeView.swift`, new `Views/Components/OrientedHUDIcon.swift`, new `MousePlusTests/WedgePresentationTests.swift`
  - Pass resolved presentation values into the view instead of reading hard-coded colors.
  - Compute upright/radial/tangential transforms from the final normalized wedge midpoint.
  - Keep labels upright; preserve selection, hover, dimmed, disabled, and off-branch distinctions under custom colors.
  - Success: pure presentation snapshots/values cover inheritance results, orientations in all quadrants, and state contrast.
  - Backpressure: narrow presentation tests, then Debug build.

- [x] **2.3: Add a dedicated center Settings control and callback contract** → new `Views/Components/HUDCenterSettingsControl.swift`, `ViewModels/RingViewModel.swift`, `MousePlusApp.swift`, new `MousePlusTests/HUDCenterSettingsTests.swift`
  - Use an AppKit-backed control with stable accessibility metadata.
  - Route through the existing `AppDelegate.showSettings()` mechanism to the Menu Items section; dismiss/reset the HUD first.
  - Ensure hold-release cannot commit the previously active wedge after Settings activation.
  - Success: center activation requests one close and one routed Settings open, with zero action-service calls in both trigger modes.
  - Backpressure: narrow center Settings tests, then Debug build.

### Wave 3 — Runtime Integration (sequential)

- [x] **3.1: Render independent top-level rings and truly invisible fixed slots** → `Views/RingMenuView.swift`, `Views/Components/WedgeView.swift`, `Utilities/RadialGeometry.swift`
  - Iterate each top-level ring's own effective count and offset.
  - Omit empty fixed positions from visual and accessibility trees while retaining their angles in geometry.
  - Align outer arcs with the rotated middle parent and selected visibility policy.
  - Depends on: 1.2, 2.1, 2.2.
  - Success: asymmetric layouts render without shared divider assumptions or placeholder artifacts; renderer and pure geometry use identical inputs.
  - Backpressure: RadialGeometry + RingViewModel + presentation tests, then Debug build.

- [x] **3.2: Integrate runtime hit testing, expansion, and action safety** → `ViewModels/RingViewModel.swift`, `Views/RingMenuView.swift`, `MousePlusApp.swift`, `MousePlusTests/MousePlusTests.swift`
  - Feed every pointer event through per-band geometry and reveal tracking before selection.
  - Make invisible positions inert; keep outer expansion/collapse and direct action execution correct with rotated/asymmetric bands.
  - Make hidden submenu parents visibly/accessibly unavailable without falling through to their marker action.
  - Depends on: 3.1.
  - Success: hold-release and tap-toggle tests cover center, empty positions, direct items, expanded outer items, hidden parents, Escape, and close/reset.
  - Backpressure: all runtime/model tests, then Debug build.

### Wave 4 — Editor State and Controls

- [x] **4.1: Extend editor working state and coordinator merge/live-apply paths** → `ViewModels/MenuEditorModel.swift`, `ViewModels/SettingsWorkspaceCoordinator.swift`, `MousePlusTests/MenuEditorModelRegressionTests.swift`, `MousePlusTests/SettingsWorkspaceCoordinatorTests.swift`
  - Let editor-owned customization and item overrides load, mutate, merge, debounce-save, recover, and live-apply without selection loss.
  - Preserve field-generation protection and fresh-base safe-save behavior.
  - Depends on: 1.1.
  - Success: edits survive concurrent field changes, failed save/retry, close barrier, backup restore, and reload.
  - Backpressure: coordinator + editor-model test classes.

- [x] **4.2: Add menu and per-ring layout/orientation/color controls** → new `Views/MenuEditor/HUDCustomizationControls.swift`, `Views/MenuEditor/MenuEditorView.swift`, `Views/MenuEditor/MenuItemsPane.swift`
  - Place controls beside the existing preview/editor workspace without changing its fixed-width pane behavior.
  - Use segmented controls for three-state visibility, auto/fixed mode, and orientation; use stepper/text for counts, sliders for offsets, and color wells with inherit controls.
  - Show the hidden-submenu warning and a direct control route; disable fixed-count values below item count non-destructively.
  - Depends on: 1.4, 4.1.
  - Success: every control has stable accessibility metadata, current selection is visible, and no forbidden SwiftUI control is introduced.
  - Backpressure: workspace/accessibility tests, `rg` forbidden-control review in changed files, then Debug build.

- [x] **4.3: Add per-item wedge/icon color overrides** → `Views/MenuEditor/SlotEditorForm.swift`, `Models/RingMenuItem.swift`, `ViewModels/MenuEditorModel.swift`
  - Add independent inherit/custom controls using the shared AppKit color well.
  - Display requested color plus a non-destructive notice when the renderer substitutes a contrast-safe output.
  - Depends on: 1.3, 1.4, 4.1.
  - Success: item override → ring → menu fallback updates immediately and survives rapid selection changes without cross-item writes.
  - Backpressure: editor regression + color resolver tests, then Debug build.

- [x] **4.4: Replace preview overlay buttons with one safe AppKit interaction surface** → `Views/MenuEditor/RingPreviewSelector.swift`, new `Views/AppKitControls/HUDPreviewInteractionView.swift`, new `MousePlusTests/HUDPreviewInteractionTests.swift`
  - Share runtime geometry and reveal state, map pointer movement/clicks to editor selection/add operations, and omit action execution dependencies entirely.
  - Support hover, conditional reveal/latch, outer selection, center Settings visualization, invisible slots, and fit-to-canvas scaling.
  - Remove raw SwiftUI `Button` hit targets from the preview.
  - Depends on: 2.1, 3.1, 4.1.
  - Success: injected interaction tests prove correct selection and zero external/action effects across every band and empty region.
  - Backpressure: preview interaction + geometry + editor-model tests, then Debug build.

### Wave 5 — Persistence, Reset, and Accessibility Integration

- [x] **5.1: Define reset/backup behavior for customization and inherited item colors** → `ViewModels/SettingsWorkspaceCoordinator.swift`, `Views/MenuEditor/MenuEditorView.swift`, `MousePlusTests/SettingsWorkspaceCoordinatorTests.swift`
  - Expand the existing Menu Items reset confirmation to state exactly which HUD customization values reset, create the same durable backup first, and keep triggers/general behavior untouched.
  - Ensure undo and backup restore include layout and color overrides atomically.
  - Depends on: Wave 4.
  - Success: reset, undo, restore, failed backup, failed save, and close barrier retain a recoverable full pre-reset HUD state.
  - Backpressure: coordinator tests, then Debug build.

- [x] **5.2: Complete accessibility presentation and navigation** → `Views/RingMenuView.swift`, `Views/MenuEditor/RingPreviewSelector.swift`, `Views/MenuEditor/HUDCustomizationControls.swift`, `MousePlusTests/WorkspaceAccessibilityTests.swift`
  - Expose center Settings, selected segments, visible configured wedges, unavailable hidden-submenu parents, and preview selection.
  - Prove invisible fixed positions and hidden outer items do not appear in the accessibility tree.
  - Depends on: Waves 3–4.
  - Success: keyboard/Full Keyboard Access and VoiceOver-oriented tests cover names, values, identifiers, selected/unavailable state, and absence rules.
  - Backpressure: `xcodebuild test -workspace 01_Project/MousePlus.xcworkspace -scheme MousePlus -destination 'platform=macOS' -only-testing:MousePlusTests/WorkspaceAccessibilityTests`

### Wave 6 — Automated Integration Gates

- [x] **6.1: Add end-to-end migration fixtures and canonical JSON round trips** → `MousePlusTests/ConfigurationServiceTests.swift`, `MousePlusTests/Fixtures/`
  - Cover current production shape, pre-inner/middle legacy shape, partial new shape, corrupt individual new values, and fully customized shape.
  - Success: compatibility appearance is asserted from resolved render inputs, not only decoded field equality; unknown action payloads survive.
  - Backpressure: configuration + HUD coding test classes.

- [x] **6.2: Add editor-to-runtime integration tests** → new `MousePlusTests/HUDCustomizationIntegrationTests.swift`
  - Exercise control binding → editor model → coordinator merge → encode/decode → live `RingViewModel` → geometry/presentation resolution.
  - Include asymmetric rings, rotations, each visibility mode, all orientation inheritance levels, colors, empty positions, save failure/retry, and preview suppression.
  - Success: each spec capability has at least one automated path and each error/edge criterion is mapped in test names.
  - Backpressure: the new integration test class.

- [x] **6.3: Run full clean automated gate and audit the UI constraints** → whole workspace
  - Run full tests and Debug build from a clean derived-data location.
  - Search changed UI files for forbidden raw SwiftUI controls; manually inspect any toolbar exception.
  - Confirm no warnings, flaky timing assumptions, or test-only production branches.
  - Depends on: 6.1, 6.2.
  - Success: all tests/builds pass and the constraint audit is recorded in the execution log.
  - Backpressure: full commands in “Backpressure Baseline.”

### Wave 7 — Signed Live Verification and Review

- [ ] **7.1: Live-verify the complete user flow in a signed build** → runtime app + `specs/sustained-use-hud-redesign.md`
  - Preserve the stable signing identity so Accessibility permission survives rebuilds.
  - Verify center Settings under hold-release and tap-toggle; live editor updates; asymmetric auto/fixed rings; invisible slots; rotation alignment; all outer modes; orientation; inheritance; color contrast; save/relaunch; and an old configuration migration.
  - Use user-driven input for final verification; do not use synthetic clicks/keystrokes as proof of behavior.
  - Success: every acceptance criterion is checked with outcome/evidence and no configured action fires from preview or center Settings.
  - Backpressure: signed app behavior plus persisted JSON inspection after relaunch.

- [ ] **7.2: Run adversarial review and close the feature** → changed source/tests/spec/docs
  - Review geometry boundaries, release-with-stale-selection, corrupt config recovery, inheritance cycles/ambiguity, contrast under alpha/dimming, Full Keyboard Access, large radii scaling, and unknown action preservation.
  - Fix findings, rerun affected narrow tests, then rerun the full gate.
  - Mark verified spec criteria, update project state, and record deferred risks without expanding scope.
  - Depends on: 7.1.
  - Success: two focused review passes find no unresolved high-severity issue and the spec is ready for Complete status.
  - Backpressure: full test suite + Debug build + targeted signed recheck for any runtime fix.

---

## Source Verification

- W3C WCAG 2.2, non-text contrast: https://www.w3.org/WAI/WCAG22/understanding/non-text-contrast.html
- Apple `NSSegmentedControl`: https://developer.apple.com/documentation/appkit/nssegmentedcontrol
- Apple `NSColorWell`: https://developer.apple.com/documentation/appkit/nscolorwell
- Apple `NSColor.usingColorSpace(_:)`: https://developer.apple.com/documentation/appkit/nscolor/usingcolorspace(_:)
- Apple `NSTrackingArea`: https://developer.apple.com/documentation/appkit/nstrackingarea

## Operational Learnings

- Keep geometry, rendering, runtime hit testing, preview selection, and accessibility positions on one explicit per-band geometry value; duplicated angle calculations caused the current preview overlay debt.
- Store requested colors and derive accessible render colors. Replacing persisted user colors with fallbacks would make inheritance and later editing lossy.
- Invocation reveal state belongs in `RingViewModel.reset()` lifecycle, never in persisted configuration.

## Blocked Tasks

None. Logitech HID++ remains a separate project blocker and does not block this plan.

## Execution Log

| Wave | Started | Completed | Commits |
|------|---------|-----------|---------|
| 1 | | | |
| 2 | | | |
| 3 | 2026-09-02 | 2026-09-02 | Uncommitted with Waves 1–2 |
| 4 | 2026-09-02 | 2026-09-02 | Uncommitted with Waves 1–3 |
| 5 | 2026-09-02 | 2026-09-02 | Uncommitted with Waves 1–4 |
| 6 | 2026-09-02 | 2026-09-02 | Uncommitted with Waves 1–5 |
| 7 | | | |

Wave 6 gate: 180/180 tests passed and the Debug build succeeded from fresh derived-data directories. The changed-UI audit found only four permitted confirmation-dialog `Button` actions, with no raw Settings/preview controls. No new HUD/Wave 6 warnings, flaky timing dependencies, or test-only production branches were found; remaining warnings are pre-existing Xcode/project warnings.

---

*Plan created 2026-09-02. Execute with `/execute`; do not begin later waves before their dependencies pass.*
