# Project State

**Last updated:** 2026-11-27

## Identity

- **Project:** MousePlus (formerly PointerActions; started 2026-01-09)
- **Purpose:** A pointer-anchored radial menu for macOS, summoned by mouse button or keyboard shortcut, with configurable actions and submenus.
- **Distribution:** Public GPLv3 project; direct download first, Mac App Store feasibility later.
- **Repository:** https://github.com/Xpycode/MousePlus

## Now

- **Phase:** Implementation. <!-- Phase changed: 2026-09-11 -->
- **Focus:** Backlog selection. No active implementation plan.
- **Next:** Choose among the 11 [backlog entries](TASKS.md#backlog). The first is to reproduce Safari missing from the Add App HUD picker.
- **M4 Pro cleanup:** Another Atlas session is using the helper. The disposable MousePlus profile and test apps are recorded in the current handoff.
- **Current handoff:** [2026-11-27 Resume](sessions/2026-11-27.md#resume)

## Recent

- **2026-11-27:** Packaged the Radial Fan icon, verified Accessibility across signed builds and recovered the global Settings shortcut. Repaired the recurring preview mismatch and verified the Global and Finder profiles in Atlas. Verified Calculator Copy from Global and Calculator’s own profile after fixing Test Action targeting. Fixed the truncated profile heading and symbol name at minimum width. Verified that a Global rename preserves externally stored hidden and order IDs. Restoring a missing Global ring now reconnects its customized app items.
- **2026-11-26:** The signed baseline still requested access at close. On retry, macOS showed a separate permission alert while the file picker's Open button remained disabled.
- **2026-11-25:** The installed MousePlus baseline passed signature verification in the helper. System Settings still disabled Open when the user selected it.
- **2026-11-24:** Added Use Global inner/middle ring to app profiles. Verified both switches in Settings and passed 94 focused tests.
- **2026-11-22 (night):** You accepted App HUD inheritance live in Safari, so it is complete. Copy first failed because Safari's old copy had no keystroke; Revert to Global fixed it. The item editor buttons now fit on one row, and the spec gained a per-ring "Use Global ring" switch.

## Progress

- **Unified Settings workspace:** 8/8 waves complete; automated, adversarial, accessibility, signed-build, and user-driven checks passed.
- **Send Keystroke:** Complete; automated coverage and signed live verification passed.
- **Ring UI:** Complete and live-verified.
- **Ring-controls reorganization (Menu/Inner/Middle/Outer tabs + per-ring labels):** 4/4 waves complete; automated, adversarial, signed-build, and user-driven checks passed.
- **HUD actions:** Window snapping and App Switcher v1 are verified, including MRU order and rapid re-point safety. Calculator received Copy from both Settings profiles in [the signed helper check](sessions/2026-11-27.md#test-action-recipients). Menu-bar mirror, system toggles and screenshots remain open.
- **HUD Motion v1:** 5/5 waves complete; automated checks and independent review passed, with overall signed-live acceptance from the user.
- **HUD Opening Styles:** 7/7 tasks complete and signed-live verified on the supported BetterMouse-to-keyboard route. VoiceOver, direct MousePlus mouse triggering and the broad device/geometry performance matrix are deferred before release and remain untested.
- **App-specific HUDs:** 5/5 implementation waves and signed-live Finder/Global acceptance complete on the supported BetterMouse-to-keyboard route.
- **Trigger backend:** Keyboard and standard mouse paths work (the mouse trigger button is now consumed, not passed to other apps); advanced Logitech HID++ support remains undecided.
- **App HUD inheritance:** complete; 11/11 tasks, Atlas and user live acceptance passed. [Use Global ring](plans/use-global-ring.md) complete, 4/4 tasks.
- **Task tracker:** 11 open backlog entries, including visual design exploration and permission setup improvements. No active plan.

## Risks and Backlog

- Fresh installs ship without a default trigger; onboarding is required before clean-install or public-release testing.
- Capture the alternate MX4 vendor interface and re-capture the MX3S with the current inspector before choosing accept-limitation, HID++ implementation, or Options+ coexistence. OpenLogi's code and fixtures cover both mice; see `OPENLOGI_REFERENCE.md` (BetterMouse coexistence still untested).
- The menu-bar status icon and General Settings Quit fallback are signed-live verified on the M1 Max.
- Settings writers may still replace a corrupt configuration with defaults; the full deferred-risk list is in `MENU_EDITOR_REVIEW.md`.
- Consider screenshots next if onboarding is deferred; it is the smallest unfinished HUD action and establishes dismiss-before-action behavior.
- Longer-term work includes the menu-bar mirror, recent-app switcher, system toggles, app-aware command rings, and alternative menu layouts.
- HUD motion must remain presentation-only: rapid pointer interaction, native mouse-up commits, action timing, and accessibility semantics cannot depend on animation completion.

## Infrastructure

- **Build:** `xcodebuild -workspace 01_Project/MousePlus.xcworkspace -scheme MousePlus -configuration Debug build`
- **Signing:** Stable per-machine Debug identity on the M1 Max. On the M4 Pro, `01_Project/Config/Debug.local.xcconfig` selects the restored Developer ID Application identity for team `FDMSRXXN73` and disables Debug base-entitlement injection.
- **Runtime:** Non-sandboxed AppKit/SwiftUI menu-bar app using an `NSPanel`, global event monitoring, Accessibility APIs, JSON configuration, and UserDefaults settings.
- **Packages:** Adopts GlobalEventMonitors and ShortcutKit; contributes source patterns for GlobalEventMonitors and PermissionsService. See `PACKAGE-NOTES.md`.

## Detail (read only if needed)

- Product and engineering rationale: `decisions.md`
- Session history and handoffs: `sessions/_index.md`
- Current tracker and backlog: `TASKS.md`
- App-specific HUD signed-live completion: `sessions/2026-09-17.md`
- Unified Settings specification: `../specs/unified-settings-workspace.md`
- App HUD inheritance specification (incl. Use Global ring addendum): `../specs/app-hud-inheritance.md`
- Completed App HUD inheritance plan: `plans/app-hud-inheritance-implementation.md`
- Sustained-use HUD redesign specification: `../specs/sustained-use-hud-redesign.md`
- HUD action roadmap: `HUD_ACTIONS_PLAN.md`
- App menu-bar mirror (Feature A) implementation plan: `APP_COMMANDS_PLAN.md`
- Dynamic app switcher (Feature C) implementation plan: `APP_SWITCHER_PLAN.md`
- HUD Motion v1 completion and pre-clear handoff: `sessions/2026-09-05.md`
- Completed opening-styles implementation plan: `plans/hud-opening-styles-implementation.md`
- Opening-styles behavior, preview, and acceptance criteria: `../specs/hud-opening-styles.md`
- App-specific HUD behavior, fallback, switching, and acceptance criteria: `../specs/app-specific-huds.md`
- Completed app-specific HUD implementation plan: `plans/app-specific-huds-implementation.md`
- System toggles (Feature D) implementation plan: `SYSTEM_TOGGLES_PLAN.md`
- Help/Feedback/Tip/Appearance Settings plan: `APP_CHROME_SETTINGS_PLAN.md`
- Send Keystroke implementation record: `SEND_KEYSTROKE_PLAN.md`
- Menu-editor findings and deferred risks: `MENU_EDITOR_REVIEW.md`
- HID captures and evidence: `fixtures/`
- HID++ diversion, haptics and ring ideas from OpenLogi: `OPENLOGI_REFERENCE.md`
