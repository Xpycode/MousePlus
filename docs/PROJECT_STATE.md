# Project State

**Last updated:** 2026-09-02

## Identity

- **Project:** MousePlus (formerly PointerActions; started 2026-01-09)
- **Purpose:** A pointer-anchored radial menu for macOS, summoned by mouse button or keyboard shortcut, with configurable actions and submenus.
- **Distribution:** Public GPLv3 project; direct download first, Mac App Store feasibility later.
- **Repository:** https://github.com/Xpycode/MousePlus

## Now

- **Phase:** Implementation.
- **Focus:** Send Keystroke and the unified Settings workspace are complete and live-verified; choose onboarding or the next unfinished HUD action as the next feature.
- **Blocker:** Advanced Logitech-button support is paused until raw MX4/MX3S captures resolve the HID++ strategy decision.
- **Next:** Build first-launch onboarding because fresh installs currently have no configured trigger and must discover Settings manually.

## Recent

- **2026-09-02:** Completed Send Keystroke; recording now consumes the captured shortcut, delivery to QuickStatsPanel passed signed live testing, and editor selection behavior was fixed.
- **2026-09-01:** Completed and verified all eight unified Settings waves, repaired the repository handoff, and preserved the displaced historical branch.
- **2026-08-10:** Planned Send Keystroke and confirmed that the apparent remote-history mismatch was an obsolete pre-reinitialization history, not missing work.
- **2026-07-12:** Committed and pushed the menu-editor safety fixes and Settings hotkey, verified the Settings shortcut, and identified keystroke delivery as the path to QuickStatsPanel integration.
- **2026-07-08:** Removed the launch-time diagnostic window, added a global Settings shortcut, and made trigger configuration tolerant of older saved files.

## Progress

- **Unified Settings workspace:** 8/8 waves complete; automated, adversarial, accessibility, signed-build, and user-driven checks passed.
- **Send Keystroke:** Complete; automated coverage and signed live verification passed.
- **Ring UI:** Complete and live-verified.
- **HUD actions:** Window snapping and keystroke delivery work; menu-bar mirror, app switching, system toggles, and screenshots remain.
- **Trigger backend:** Keyboard and standard mouse paths work; advanced Logitech HID++ support remains undecided.
- **Task tracker:** 0/0 current sprint; 7/8 tracked items complete overall.

## Risks and Backlog

- Fresh installs ship without a default trigger; onboarding is required before clean-install or public-release testing.
- Capture the alternate MX4 vendor interface and re-capture the MX3S with the current inspector before choosing accept-limitation, HID++ implementation, or Options+ coexistence.
- The menu-bar status icon remains invisible on the M1 Max; the global Settings shortcut is the current workaround.
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
- HUD action roadmap: `HUD_ACTIONS_PLAN.md`
- Send Keystroke implementation record: `SEND_KEYSTROKE_PLAN.md`
- Menu-editor findings and deferred risks: `MENU_EDITOR_REVIEW.md`
- HID captures and evidence: `fixtures/`

## Resume

Start with onboarding unless priorities have changed. Confirm the working tree and current branch, create or refresh the implementation plan, then preserve the stable signed-build path for live trigger testing. If returning to HID work, collect the two pending device captures before making the HID++ decision.
