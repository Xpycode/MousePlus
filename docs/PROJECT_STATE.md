# Project State

**Last updated:** 2026-09-26

## Identity

- **Project:** MousePlus (formerly PointerActions; started 2026-01-09)
- **Purpose:** A pointer-anchored radial menu for macOS, summoned by mouse button or keyboard shortcut, with configurable actions and submenus.
- **Distribution:** Public GPLv3 project; direct download first, Mac App Store feasibility later.
- **Repository:** https://github.com/Xpycode/MousePlus

## Now

- **Phase:** Implementation — next task selection. <!-- Phase changed: 2026-09-11 -->
- **Focus:** Ready to choose the next task on main; the accepted installed MousePlus build remains running.
- **Blocker:** None for this acceptance task. The original system-dialog loop cause remains unestablished.
- **Next:** Recommended: scope first-run trigger onboarding before clean-install release testing. No implementation plan is approved yet.

## Recent

- **2026-09-26:** Verified plain/modifier recording, fixed preview dimensions, and passed 11 focused tests. Cleared a stuck macOS permission dialog; corrected signed build passed user-confirmed permission, trigger, and preview/layout acceptance. Changes merged and pushed to main.
- **2026-09-25:** Exported a Developer ID-signed Release 0.1.0 (1) from the current working tree; Apple accepted notarization, and the stapled ZIP passed signature and Gatekeeper checks. Local artifact only.
- **2026-09-17:** App-specific HUD acceptance passed through post-delete relaunch; a signed Release 0.1.0 (1) build was installed and launched from `/Applications` on M1-Max.
- **2026-09-13:** Signed-live Finder/Global checks passed through action targeting; saved the remaining persistence/deletion handoff and quit the test build for session close.
- **2026-09-13:** Made unused slot backing transparent by default with a persisted complete-ring option, kept empty regions inert, and stabilized the hidden-submenu warning layout; 134 focused regressions and the Debug build pass, and both appearances are signed-live accepted.

## Progress

- **Unified Settings workspace:** 8/8 waves complete; automated, adversarial, accessibility, signed-build, and user-driven checks passed.
- **Send Keystroke:** Complete; automated coverage and signed live verification passed.
- **Ring UI:** Complete and live-verified.
- **Ring-controls reorganization (Menu/Inner/Middle/Outer tabs + per-ring labels):** 4/4 waves complete; automated, adversarial, signed-build, and user-driven checks passed.
- **HUD actions:** Window snapping and keystroke delivery work; App Switcher v1 is complete and signed-live verified, including MRU order and rapid re-point safety; menu-bar mirror, system toggles, and screenshots remain.
- **HUD Motion v1:** 5/5 waves complete; automated checks and independent review passed, with overall signed-live acceptance from the user.
- **HUD Opening Styles:** 7/7 tasks complete and signed-live verified on the supported BetterMouse-to-keyboard route. VoiceOver, direct MousePlus mouse triggering and the broad device/geometry performance matrix are deferred before release and remain untested.
- **App-specific HUDs:** 5/5 implementation waves and signed-live Finder/Global acceptance complete on the supported BetterMouse-to-keyboard route.
- **Trigger backend:** Keyboard and standard mouse paths work; advanced Logitech HID++ support remains undecided.
- **Task tracker:** no current sprint tasks; 44/49 tracked items complete overall (90%), with five backlog items.

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
- App-specific HUD signed-live completion: `sessions/2026-09-17.md`
- Unified Settings specification: `../specs/unified-settings-workspace.md`
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
