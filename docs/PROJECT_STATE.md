# Project State

**Last updated:** 2026-09-04

## Identity

- **Project:** MousePlus (formerly PointerActions; started 2026-01-09)
- **Purpose:** A pointer-anchored radial menu for macOS, summoned by mouse button or keyboard shortcut, with configurable actions and submenus.
- **Distribution:** Public GPLv3 project; direct download first, Mac App Store feasibility later.
- **Repository:** https://github.com/Xpycode/MousePlus

## Now

- **Phase:** Ring-controls reorganization underway; Wave 3 (runtime/preview wiring + persistence verification) is complete on top of Wave 1's label model and Wave 2's inspector tabs. Wave 4's adversarial/automated review (Task 4.1) is also complete. <!-- Phase changed: 2026-09-04 -->
- **Focus:** Wave 4's remaining signed-live closure gate.
- **Blocker:** Advanced Logitech-button support is paused until raw MX4/MX3S captures resolve the HID++ strategy decision.
- **Next:** Task 4.2 — clean signed live verification and close documentation.

## Recent

- **2026-09-04:** Completed Task 4.1: adversarial review of the complete Wave 1–3 change set (tab-state identity, compact-width truncation, migration defaults, flip-boundary orientation, empty labels, submenu expansion, hidden-label centering, VoiceOver naming, reset/merge races) found and fixed one SHOULD_FIX — `WedgeView`'s caption had no width cap, letting a long Inner-ring label (newly toggleable) overlap neighboring wedges; fixed with a chord-width cap plus truncation/scale-down fallback. One low-severity dead-code suggestion was left as non-blocking. Full MousePlus test target and `git diff --check` clean; no forbidden raw SwiftUI controls introduced.
- **2026-09-04:** Completed Task 3.2: added explicit label-field (`labelVisible`/`labelOrientation`) coverage to every Settings write path — in-editor edit + merge, debounced/failed-save retry, fresh-base merge against a concurrent external edit, reset/undo, durable backup restore, live apply, and relaunch (reload) — confirming a failed save or an unrelated concurrent edit can never revert a label setting. Extended `MenuEditorModelRegressionTests`, `SettingsWorkspaceCoordinatorTests` (including a new fresh-base-merge test and a strengthened `customizedHUDConfiguration` fixture), and `HUDCustomizationIntegrationTests`; no production code changes were needed since `hudCustomization` was already threaded through every path as one unit. 235/235 tests pass; a clean Debug build succeeded. Wave 3 is complete.
- **2026-09-04:** Completed Task 3.1: `RingViewModel` gained `labelOrientation(for:)`/`isLabelVisible(for:)` mirroring the existing icon-orientation inheritance, and `WedgeView` now resolves caption visibility and readable rotation from `LabelPresentation` instead of a per-band `symbolOnly` flag — so any ring's label can be shown or hidden and rotated independently of its icon. `RingMenuView` feeds the same resolved policy to Inner, Middle, and Outer wedges; `RingPreviewSelector` gets it for free by rendering through the same `RingMenuView`. 233/233 tests pass (232 prior + 1 new compatibility-default test), plus 2 new assertions extending an existing integration test; a clean Debug build succeeded and no `symbolOnly` references remain.
- **2026-09-04:** Completed Wave 2: replaced the stacked Menu/ring/Outer customization groups with a native Menu/Inner/Middle/Outer segmented-tab inspector, owned by local UI state so browsing a ring's settings never retargets the Menu Items band or selection. Outer-ring visibility moved from the Menu group into its own Outer tab; each scope now also exposes label visibility and label direction controls (previously model-only since Wave 1), menu-root colors read "Default" while ring/item overrides keep "Inherit" (`AppKitColorWell` gained an `inheritTitle` parameter), and a hierarchy help line explains item → ring → menu → application-default resolution. 232/232 focused-plus-full unit tests pass; a source audit found no raw SwiftUI interactive controls.
- **2026-09-04:** Completed Wave 1: `HUDCustomization` gained a tolerant `LabelOrientation` model with per-ring overrides and compatibility defaults (inner hidden, middle/outer shown, upright), and a new pure `LabelPresentationPolicy` resolves per-ring label visibility and auto-flipping readable rotation independent of icon presentation. 230/231 tests pass (the one failure is a local UI-automation runner timeout, unrelated to the change).
- **2026-09-04:** Confirmed the Menu/Inner/Middle/Outer tab ownership proposal in `IMPLEMENTATION_PLAN.md`, unblocking Wave 2.
- **2026-09-04:** Planned the next HUD increment: four scope-specific customization tabs, clearer Default/Inherit semantics, and backward-compatible per-ring label visibility and readable orientation across preview and runtime.
- **2026-09-04:** Closed the sustained-use HUD redesign. A clean signed build passed the full live checklist: immediate Quit persisted the changed configuration, relaunch re-armed triggers, and the visible menu-bar status item and its Quit command worked. The full 217-test suite remains green.
- **2026-09-03:** Final signed testing passed reorder and outside dismissal, then exposed and remediated a macOS 27 Window Snap crash caused by background window mutation; all 207 tests and the signed snap retest pass. Color verification remains incomplete, and clearer color-inheritance wording is logged for the next UI-design pass.
- **2026-09-03:** Completed remediation Wave 3: tap-toggle HUDs now move from the native center control after a 4 pt threshold while clicks still open Settings, moved panels clamp to the active screen, General Settings exposes a native Quit MousePlus button, and the menu-bar image has explicit template sizing and accessibility metadata. All 11 combined focused tests passed; signed drag/click and quit/relaunch verification remain in Wave 4.
- **2026-09-03:** Completed remediation Wave 2: transparent panel corners now dismiss against the circular HUD boundary, hidden outer rings leave no backing surface, and preview selection is visually separate from hover without changing configured colors. All 48 combined focused tests passed; signed visual verification remains in the final gate.

## Progress

- **Unified Settings workspace:** 8/8 waves complete; automated, adversarial, accessibility, signed-build, and user-driven checks passed.
- **Send Keystroke:** Complete; automated coverage and signed live verification passed.
- **Ring UI:** Complete and live-verified.
- **HUD actions:** Window snapping and keystroke delivery work; menu-bar mirror, app switching, system toggles, and screenshots remain.
- **Trigger backend:** Keyboard and standard mouse paths work; advanced Logitech HID++ support remains undecided.
- **Task tracker:** 0/1 current sprint; 21/22 tracked items complete overall (95%).

## Risks and Backlog

- Fresh installs ship without a default trigger; onboarding is required before clean-install or public-release testing.
- Capture the alternate MX4 vendor interface and re-capture the MX3S with the current inspector before choosing accept-limitation, HID++ implementation, or Options+ coexistence.
- The menu-bar status icon and General Settings Quit fallback are signed-live verified on the M1 Max.
- Settings writers may still replace a corrupt configuration with defaults; the full deferred-risk list is in `MENU_EDITOR_REVIEW.md`.
- Consider screenshots next if onboarding is deferred; it is the smallest unfinished HUD action and establishes dismiss-before-action behavior.
- Longer-term work includes the menu-bar mirror, recent-app switcher, system toggles, app-aware command rings, and alternative menu layouts.

## Infrastructure

- **Build:** `xcodebuild -workspace 01_Project/MousePlus.xcworkspace -scheme MousePlus -configuration Debug build`
- **Signing:** Stable per-machine Debug identities are configured on both development Macs so Accessibility permission survives rebuilds.
- **Runtime:** Non-sandboxed AppKit/SwiftUI menu-bar app using an `NSPanel`, global event monitoring, Accessibility APIs, JSON configuration, and UserDefaults settings.
- **Packages:** Adopts GlobalEventMonitors and ShortcutKit; contributes source patterns for GlobalEventMonitors and PermissionsService. See `PACKAGE-NOTES.md`.

## Detail (read only if needed)

- Product and engineering rationale: `decisions.md`
- Session history and handoffs: `sessions/_index.md`
- Current tracker and backlog: `TASKS.md`
- Unified Settings specification: `../specs/unified-settings-workspace.md`
- Sustained-use HUD redesign specification: `../specs/sustained-use-hud-redesign.md`
- Sustained-use HUD redesign implementation plan: `../IMPLEMENTATION_PLAN.md`
- HUD action roadmap: `HUD_ACTIONS_PLAN.md`
- Send Keystroke implementation record: `SEND_KEYSTROKE_PLAN.md`
- Menu-editor findings and deferred risks: `MENU_EDITOR_REVIEW.md`
- HID captures and evidence: `fixtures/`

## Resume

The ring-controls reorganization is tracked in `IMPLEMENTATION_PLAN.md`. Waves 1–3 (label model, inspector tabs, and runtime/preview/persistence integration) are complete; Wave 4 (adversarial/automated review and signed-live closure) is next.
