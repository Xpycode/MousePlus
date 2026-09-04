# Project State

**Last updated:** 2026-09-04

## Identity

- **Project:** MousePlus (formerly PointerActions; started 2026-01-09)
- **Purpose:** A pointer-anchored radial menu for macOS, summoned by mouse button or keyboard shortcut, with configurable actions and submenus.
- **Distribution:** Public GPLv3 project; direct download first, Mac App Store feasibility later.
- **Repository:** https://github.com/Xpycode/MousePlus

## Now

- **Phase:** HUD Motion v1 implementation; Wave 1 of 5 complete. <!-- Phase changed: 2026-09-04 -->
- **Focus:** Wave 1 added migration-safe role-based motion persistence and a pure Reduce Motion-aware presentation policy. Wave 2 will scope hover/dimming animation and outer-ring reveals to visual presentation only.
- **Blocker:** Advanced Logitech-button support is paused until raw MX4/MX3S captures resolve the HID++ strategy decision. `APP_CHROME_SETTINGS_PLAN.md`'s Leave-a-Tip button still needs a tip-jar platform/URL from the user.
- **Next:** Execute Wave 2: replace blanket springs with scoped hover/dimming feedback and add localized/full-circle outer-ring reveal presentations.

## Recent

- **2026-09-04:** Completed HUD Motion v1 Wave 1: legacy animation settings migrate losslessly into independently tolerant role styles, and a pure policy resolves master/style/duration/Reduce Motion combinations without touching interaction state. All 21 focused tests pass.
- **2026-09-04:** Audited HUD animation feasibility and created a five-wave Motion v1 plan for safe semantic effects, role-specific Settings controls, accessibility, and signed live verification.
- **2026-09-04:** Closed App Switcher v1 after a fresh signed build: the user confirmed recent-usage ordering and clean rapid Apps↔Snap re-pointing with no stale app icons. Captured a later investigation into feasible and unsuitable HUD animations.
- **2026-09-04:** Prototyped and live-verified a full-circle running-app switcher aligned to the Apps wedge; fixed the test-run handoff by relaunching the exact rebuilt bundle, and confirmed outer labels can be disabled.
- **2026-09-04:** Fixed tap-toggle commits at the native AppKit mouse-up boundary; the full 249-test suite and signed build pass, and the user confirmed both static and dynamic Safari activation.
- **2026-09-04:** Clarified dynamic Apps editing: the inspector now shows a read-only running-app source, hides inactive preserved children, centralizes outer-item creation under Menu & Rings, and keeps Move/Delete together at the bottom. Signed builds pass; the live HUD screenshot confirms real app names/icons.

## Progress

- **Unified Settings workspace:** 8/8 waves complete; automated, adversarial, accessibility, signed-build, and user-driven checks passed.
- **Send Keystroke:** Complete; automated coverage and signed live verification passed.
- **Ring UI:** Complete and live-verified.
- **Ring-controls reorganization (Menu/Inner/Middle/Outer tabs + per-ring labels):** 4/4 waves complete; automated, adversarial, signed-build, and user-driven checks passed.
- **HUD actions:** Window snapping and keystroke delivery work; App Switcher v1 is complete and signed-live verified, including MRU order and rapid re-point safety; menu-bar mirror, system toggles, and screenshots remain.
- **Trigger backend:** Keyboard and standard mouse paths work; advanced Logitech HID++ support remains undecided.
- **Task tracker:** 2/7 current sprint tasks complete; 24/30 tracked items complete overall (80%).

## Risks and Backlog

- Fresh installs ship without a default trigger; onboarding is required before clean-install or public-release testing.
- Capture the alternate MX4 vendor interface and re-capture the MX3S with the current inspector before choosing accept-limitation, HID++ implementation, or Options+ coexistence.
- The menu-bar status icon and General Settings Quit fallback are signed-live verified on the M1 Max.
- Settings writers may still replace a corrupt configuration with defaults; the full deferred-risk list is in `MENU_EDITOR_REVIEW.md`.
- Consider screenshots next if onboarding is deferred; it is the smallest unfinished HUD action and establishes dismiss-before-action behavior.
- Longer-term work includes the menu-bar mirror, recent-app switcher, system toggles, app-aware command rings, and alternative menu layouts.
- HUD motion must remain presentation-only: rapid pointer interaction, native mouse-up commits, action timing, and accessibility semantics cannot depend on animation completion.

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
- HUD action roadmap: `HUD_ACTIONS_PLAN.md`
- App menu-bar mirror (Feature A) implementation plan: `APP_COMMANDS_PLAN.md`
- Dynamic app switcher (Feature C) implementation plan: `APP_SWITCHER_PLAN.md`
- Current HUD Motion v1 implementation plan: `../IMPLEMENTATION_PLAN.md`
- System toggles (Feature D) implementation plan: `SYSTEM_TOGGLES_PLAN.md`
- Help/Feedback/Tip/Appearance Settings plan: `APP_CHROME_SETTINGS_PLAN.md`
- Send Keystroke implementation record: `SEND_KEYSTROKE_PLAN.md`
- Menu-editor findings and deferred risks: `MENU_EDITOR_REVIEW.md`
- HID captures and evidence: `fixtures/`
