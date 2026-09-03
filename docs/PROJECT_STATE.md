# Project State

**Last updated:** 2026-09-03

## Identity

- **Project:** MousePlus (formerly PointerActions; started 2026-01-09)
- **Purpose:** A pointer-anchored radial menu for macOS, summoned by mouse button or keyboard shortcut, with configurable actions and submenus.
- **Distribution:** Public GPLv3 project; direct download first, Mac App Store feasibility later.
- **Repository:** https://github.com/Xpycode/MousePlus

## Now

- **Phase:** HUD redesign live-verification remediation planned. <!-- Phase changed: 2026-09-03 -->
- **Focus:** Fix signed-test failures in circular reorder, dismissal, preview fidelity, outer visibility, movement, and lifecycle access.
- **Blocker:** Advanced Logitech-button support is paused until raw MX4/MX3S captures resolve the HID++ strategy decision.
- **Next:** Confirm the proposed center-drag and General-pane Quit placements, then execute `IMPLEMENTATION_PLAN.md` Wave 1.

## Recent

- **2026-09-03:** Signed user testing confirmed direct MousePlus mouse binding works without the BetterMouse shortcut beep, and exposed six closure issues: reorder does not wrap, transparent-corner clicks do not dismiss, preview selection distorts color comparison, outer visibility leaves misleading geometry, HUD movement lacks a safe interaction, and quitting is inaccessible when the status item is invisible. A focused four-wave remediation plan now replaces the completed implementation plan.
- **2026-09-03:** Live Wave 7 review reshaped Menu Items into a compact tabbed inspector, made deletion and action testing discoverable, preserved wedge selection, removed ambiguous preview-add hotspots, and deferred clearer per-ring/label controls.
- **2026-09-03:** Wrapped HUD redesign Waves 5–6 with atomic reset/recovery, complete accessibility and migration coverage, shared runtime presentation resolution, and a clean 180-test/build gate.
- **2026-09-02:** Completed HUD redesign Wave 6; five migration fixtures and editor-to-runtime coverage now validate canonical persistence, unknown actions, geometry, visibility, orientation, colors, retry behavior, and preview safety. The clean gate passed 180/180 tests and a Debug build with no new HUD warnings or forbidden controls.
- **2026-09-02:** Completed HUD redesign Wave 5; reset/undo/backup restore now atomically preserve full HUD customization, and runtime/editor accessibility exposes configured visible wedges while omitting empty and policy-hidden positions. The 24 focused tests and signed Debug build passed.

## Progress

- **Unified Settings workspace:** 8/8 waves complete; automated, adversarial, accessibility, signed-build, and user-driven checks passed.
- **Send Keystroke:** Complete; automated coverage and signed live verification passed.
- **Ring UI:** Complete and live-verified.
- **HUD actions:** Window snapping and keystroke delivery work; menu-bar mirror, app switching, system toggles, and screenshots remain.
- **Trigger backend:** Keyboard and standard mouse paths work; advanced Logitech HID++ support remains undecided.
- **Task tracker:** 0/4 current sprint; 12/17 tracked items complete overall (71%).

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

Confirm the Wave 3 UI placements, then continue at `IMPLEMENTATION_PLAN.md` Wave 1. Preserve the passing redesign contracts and clean automated baseline while fixing the signed-test findings before repeating user-driven verification.
