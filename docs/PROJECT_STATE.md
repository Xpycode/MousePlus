# Project State

**Last updated:** 2026-11-22

## Identity

- **Project:** MousePlus (formerly PointerActions; started 2026-01-09)
- **Purpose:** A pointer-anchored radial menu for macOS, summoned by mouse button or keyboard shortcut, with configurable actions and submenus.
- **Distribution:** Public GPLv3 project; direct download first, Mac App Store feasibility later.
- **Repository:** https://github.com/Xpycode/MousePlus

## Now

- **Phase:** Implementation — next task selection. <!-- Phase changed: 2026-09-11 -->
- **Focus:** App HUD inheritance — spec approved (`../specs/app-hud-inheritance.md`), plan ready: [`plans/app-hud-inheritance-implementation.md`](plans/app-hud-inheritance-implementation.md) (11 tasks, 5 waves + 2 acceptance checks).
- **Execution:** [plan](plans/app-hud-inheritance-implementation.md) all 11 tasks, review (5.2) and Atlas check (E1) done; awaiting E2, your live acceptance in Safari/Finder (unsigned build means re-granting Accessibility).
- **Blocker:** No signing certificates on the M4 Pro; every unsigned rebuild loses its Accessibility permission and must be re-added by hand.
- **Next:** E2 live acceptance; then archive the plan; local signing certificate once the 99-AUTH folder is on this Mac.
- **Current handoff:** [2026-11-22 Resume (execution)](sessions/2026-11-22.md#resume-execution)

## Recent

- **2026-11-22 (evening):** Built App HUD inheritance end to end. App menus now follow Global unless you customize, hide or reorder an item, and existing App HUDs convert without visible change. 250 of 251 focused tests pass (the failure was already broken), the review was clean, and the Settings screens passed the hidden-desktop check. Your live acceptance is next; 7 commits are not pushed yet.
- **2026-11-22 (later):** Wrote and approved the App HUD inheritance spec (app menus follow Global unless customized, hidden or reordered) and an 11-task plan, using a code survey and web research on how other apps handle overrides.
- **2026-11-22:** The mouse trigger button no longer also acts in other apps (Warp tab switching); Global menu saves no longer overwrite outside changes; Test Action sends keystrokes to the app you came from. User-verified and committed. Decided app menus will inherit from Global.
- **2026-11-21:** Key labels now follow the keyboard layout; precautionary fix for the stale preview; fixed ring keystrokes going to MousePlus instead of the app underneath (ring panel no longer takes keyboard focus; user-accepted in Safari with Settings closed and open). Committed.
- **2026-11-18:** Fresh clone and unsigned build on the reset M4 Pro; found a stale Menu Items preview and US-only key labels while setting it up.

## Progress

- **Unified Settings workspace:** 8/8 waves complete; automated, adversarial, accessibility, signed-build, and user-driven checks passed.
- **Send Keystroke:** Complete; automated coverage and signed live verification passed.
- **Ring UI:** Complete and live-verified.
- **Ring-controls reorganization (Menu/Inner/Middle/Outer tabs + per-ring labels):** 4/4 waves complete; automated, adversarial, signed-build, and user-driven checks passed.
- **HUD actions:** Window snapping and keystroke delivery work; App Switcher v1 is complete and signed-live verified, including MRU order and rapid re-point safety; menu-bar mirror, system toggles, and screenshots remain.
- **HUD Motion v1:** 5/5 waves complete; automated checks and independent review passed, with overall signed-live acceptance from the user.
- **HUD Opening Styles:** 7/7 tasks complete and signed-live verified on the supported BetterMouse-to-keyboard route. VoiceOver, direct MousePlus mouse triggering and the broad device/geometry performance matrix are deferred before release and remain untested.
- **App-specific HUDs:** 5/5 implementation waves and signed-live Finder/Global acceptance complete on the supported BetterMouse-to-keyboard route.
- **Trigger backend:** Keyboard and standard mouse paths work (the mouse trigger button is now consumed, not passed to other apps); advanced Logitech HID++ support remains undecided.
- **App HUD inheritance:** spec approved; 11/11 tasks, E1 passed; E2 user acceptance pending.
- **Task tracker:** no current sprint tasks; 9 backlog items, one of them a precautionary fix awaiting a recurrence check.

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
- **Signing:** Stable per-machine Debug identity on the M1 Max. The M4 Pro was reset and has no certificates (2026-11-18); recreate `Config/Debug.local.xcconfig` after adding one.
- **Runtime:** Non-sandboxed AppKit/SwiftUI menu-bar app using an `NSPanel`, global event monitoring, Accessibility APIs, JSON configuration, and UserDefaults settings.
- **Packages:** Adopts GlobalEventMonitors and ShortcutKit; contributes source patterns for GlobalEventMonitors and PermissionsService. See `PACKAGE-NOTES.md`.

## Detail (read only if needed)

- Product and engineering rationale: `decisions.md`
- Session history and handoffs: `sessions/_index.md`
- Current tracker and backlog: `TASKS.md`
- App-specific HUD signed-live completion: `sessions/2026-09-17.md`
- Unified Settings specification: `../specs/unified-settings-workspace.md`
- App HUD inheritance specification (draft): `../specs/app-hud-inheritance.md`
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
