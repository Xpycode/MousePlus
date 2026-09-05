# Project State

**Last updated:** 2026-09-05

## Identity

- **Project:** MousePlus (formerly PointerActions; started 2026-01-09)
- **Purpose:** A pointer-anchored radial menu for macOS, summoned by mouse button or keyboard shortcut, with configurable actions and submenus.
- **Distribution:** Public GPLv3 project; direct download first, Mac App Store feasibility later.
- **Repository:** https://github.com/Xpycode/MousePlus

## Now

- **Phase:** HUD Opening Styles implementation; Wave 5 verification in progress. <!-- Phase changed: 2026-09-05 -->
- **Focus:** User confirms the selected opening animation works through the keyboard shortcut and through BetterMouse mapped to that shortcut. Direct MousePlus mouse-button triggering still has a reported fade-only failure; failing live traces show hover settlement before replay.
- **Blocker:** Native mouse-trigger opening acceptance remains open; BetterMouse → keyboard shortcut is a user-verified working setup. Unrelated: advanced Logitech support awaits raw captures/strategy, and Leave-a-Tip awaits a platform/URL.
- **Next:** Preserve the working BetterMouse → ⌃⌥⌘M setup with MousePlus's direct mouse binding disabled. If resuming native-trigger remediation, compare its initial pointer/hover coordinates with the working keyboard path; do not change playback without evidence. Task 5.1 remains open for native-trigger and remaining visual/accessibility checks. Fresh runnable builds are automatically quit/relaunched under the user's new global preference.

## Recent

- **2026-09-05:** User confirms keyboard-triggered animation works and BetterMouse mapping the mouse button to that shortcut also works. Recorded the preferred working setup; direct mouse-trigger failure remains open. Live diagnostics distinguish full stagger playback from hover cancellation before replay.
- **2026-09-05:** User still reports a fade in the real HUD. Found that custom Debug config omitted the Swift DEBUG condition, so the first diagnostic build contained no trace owner. Enabled DEBUG, verified trace strings and strict signature, gracefully quit the old copy and launched the corrected build. Global quit/relaunch preference saved in Codex instructions.
- **2026-09-05:** Added full-renderer playback/interruption regressions and bounded Debug runtime diagnostics. 53 focused tests pass; centered live-interaction test and isolated stagger material captures show selected playback. A fixed-position test false alarm was legitimate pointer hover, not a proven mount defect. User live reproduction remains open.
- **2026-09-05:** User reports the concealed-mount build is flash-free but only fades in again. Recorded the selected-animation regression and the gap in hosted frame tests; no further code fix during pre-clear logging.
- **2026-09-05:** Implemented concealed, non-playing runtime mounting with guarded replay and early-interruption protection. The regression failed before the playback fix; all 51 focused tests now pass, including real-panel lifecycle coverage. Fresh Debug build and strict Developer ID signature verification pass; user visual acceptance remains pending.

## Progress

- **Unified Settings workspace:** 8/8 waves complete; automated, adversarial, accessibility, signed-build, and user-driven checks passed.
- **Send Keystroke:** Complete; automated coverage and signed live verification passed.
- **Ring UI:** Complete and live-verified.
- **Ring-controls reorganization (Menu/Inner/Middle/Outer tabs + per-ring labels):** 4/4 waves complete; automated, adversarial, signed-build, and user-driven checks passed.
- **HUD actions:** Window snapping and keystroke delivery work; App Switcher v1 is complete and signed-live verified, including MRU order and rapid re-point safety; menu-bar mirror, system toggles, and screenshots remain.
- **HUD Motion v1:** 5/5 waves complete; automated checks and independent review passed, with overall signed-live acceptance from the user.
- **HUD Opening Styles:** Wave 5 verification in progress; 6/7 implementation tasks complete. Selected runtime animation is user-verified through keyboard and BetterMouse-to-keyboard triggering; direct native mouse-trigger and remaining accessibility acceptance are open.
- **Trigger backend:** Keyboard and standard mouse paths work; advanced Logitech HID++ support remains undecided.
- **Task tracker:** 0/1 current sprint tasks complete; 35/37 tracked items complete overall (95%), with one backlog item.

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
- HUD Motion v1 completion and pre-clear handoff: `sessions/2026-09-05.md`
- Current opening-styles implementation plan: `../IMPLEMENTATION_PLAN.md`
- Opening-styles behavior, preview, and acceptance criteria: `../specs/hud-opening-styles.md`
- System toggles (Feature D) implementation plan: `SYSTEM_TOGGLES_PLAN.md`
- Help/Feedback/Tip/Appearance Settings plan: `APP_CHROME_SETTINGS_PLAN.md`
- Send Keystroke implementation record: `SEND_KEYSTROKE_PLAN.md`
- Menu-editor findings and deferred risks: `MENU_EDITOR_REVIEW.md`
- HID captures and evidence: `fixtures/`
