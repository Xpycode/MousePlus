# Project State

**Last updated:** 2026-09-03

## Identity

- **Project:** MousePlus (formerly PointerActions; started 2026-01-09)
- **Purpose:** A pointer-anchored radial menu for macOS, summoned by mouse button or keyboard shortcut, with configurable actions and submenus.
- **Distribution:** Public GPLv3 project; direct download first, Mac App Store feasibility later.
- **Repository:** https://github.com/Xpycode/MousePlus

## Now

- **Phase:** HUD redesign live-verification remediation in progress. <!-- Phase changed: 2026-09-03 -->
- **Focus:** Add confirmed tap-toggle HUD movement and visible lifecycle controls in remediation Wave 3.
- **Blocker:** Advanced Logitech-button support is paused until raw MX4/MX3S captures resolve the HID++ strategy decision.
- **Next:** Execute `IMPLEMENTATION_PLAN.md` Wave 3, starting with thresholded center dragging.

## Recent

- **2026-09-03:** Completed remediation Wave 2: transparent panel corners now dismiss against the circular HUD boundary, hidden outer rings leave no backing surface, and preview selection is visually separate from hover without changing configured colors. All 48 combined focused tests passed; signed visual verification remains in the final gate.
- **2026-09-03:** Completed remediation Wave 1: top-level reordering now wraps circularly while preserving item identity, and runtime/preview share one tested outer-ring eligibility and reveal policy. All 35 focused tests passed; center-drag movement and General-pane Quit placements are confirmed for Wave 3.
- **2026-09-03:** Signed user testing confirmed direct MousePlus mouse binding works without the BetterMouse shortcut beep, and exposed six closure issues: reorder does not wrap, transparent-corner clicks do not dismiss, preview selection distorts color comparison, outer visibility leaves misleading geometry, HUD movement lacks a safe interaction, and quitting is inaccessible when the status item is invisible. A focused four-wave remediation plan now replaces the completed implementation plan.
- **2026-09-03:** Live Wave 7 review reshaped Menu Items into a compact tabbed inspector, made deletion and action testing discoverable, preserved wedge selection, removed ambiguous preview-add hotspots, and deferred clearer per-ring/label controls.
- **2026-09-03:** Wrapped HUD redesign Waves 5–6 with atomic reset/recovery, complete accessibility and migration coverage, shared runtime presentation resolution, and a clean 180-test/build gate.

## Progress

- **Unified Settings workspace:** 8/8 waves complete; automated, adversarial, accessibility, signed-build, and user-driven checks passed.
- **Send Keystroke:** Complete; automated coverage and signed live verification passed.
- **Ring UI:** Complete and live-verified.
- **HUD actions:** Window snapping and keystroke delivery work; menu-bar mirror, app switching, system toggles, and screenshots remain.
- **Trigger backend:** Keyboard and standard mouse paths work; advanced Logitech HID++ support remains undecided.
- **Task tracker:** 0/2 current sprint; 14/17 tracked items complete overall (82%).

## Risks and Backlog

- Fresh installs ship without a default trigger; onboarding is required before clean-install or public-release testing.
- Capture the alternate MX4 vendor interface and re-capture the MX3S with the current inspector before choosing accept-limitation, HID++ implementation, or Options+ coexistence.
- The menu-bar status icon remains invisible on the M1 Max; the global Settings shortcut is the current workaround.
- Settings writers may still replace a corrupt configuration with defaults; the full deferred-risk list is in `MENU_EDITOR_REVIEW.md`.
- Consider screenshots next if onboarding is deferred; it is the smallest unfinished HUD action and establishes dismiss-before-action behavior.
- Longer-term work includes the menu-bar mirror, recent-app switcher, system toggles, app-aware command rings, and alternative menu layouts.
- Clarify HUD customization scope with Menu/Inner/Middle/Outer subtabs; add per-ring label visibility and optional readable label orientation.

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

Continue at `IMPLEMENTATION_PLAN.md` Wave 3. Preserve the passing redesign contracts and Wave 1–2 focused baselines while adding movement and lifecycle access before repeated user-driven verification.
