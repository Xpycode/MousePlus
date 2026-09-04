# Project State

**Last updated:** 2026-09-04

## Identity

- **Project:** MousePlus (formerly PointerActions; started 2026-01-09)
- **Purpose:** A pointer-anchored radial menu for macOS, summoned by mouse button or keyboard shortcut, with configurable actions and submenus.
- **Distribution:** Public GPLv3 project; direct download first, Mac App Store feasibility later.
- **Repository:** https://github.com/Xpycode/MousePlus

## Now

- **Phase:** App Switcher v1 complete and signed-live verified; selecting the next focused increment. <!-- Phase changed: 2026-09-04 -->
- **Focus:** App Switcher v1 is closed: the pointer-aligned full-circle running-app ring, names/icons, activation, label visibility, MRU ordering, and rapid Apps↔Snap re-pointing are all live-confirmed.
- **Blocker:** Advanced Logitech-button support is paused until raw MX4/MX3S captures resolve the HID++ strategy decision. `APP_CHROME_SETTINGS_PLAN.md`'s Leave-a-Tip button still needs a tip-jar platform/URL from the user.
- **Next:** Scope the next App Switcher increment from windows, search/filtering, grouping/paging, recent apps, app-specific actions, or a keyboard/pointer hybrid; keep the separate HUD-animation feasibility study in the backlog.

## Recent

- **2026-09-04:** Closed App Switcher v1 after a fresh signed build: the user confirmed recent-usage ordering and clean rapid Apps↔Snap re-pointing with no stale app icons. Captured a later investigation into feasible and unsuitable HUD animations.
- **2026-09-04:** Prototyped and live-verified a full-circle running-app switcher aligned to the Apps wedge; fixed the test-run handoff by relaunching the exact rebuilt bundle, and confirmed outer labels can be disabled.
- **2026-09-04:** Fixed tap-toggle commits at the native AppKit mouse-up boundary; the full 249-test suite and signed build pass, and the user confirmed both static and dynamic Safari activation.
- **2026-09-04:** Clarified dynamic Apps editing: the inspector now shows a read-only running-app source, hides inactive preserved children, centralizes outer-item creation under Menu & Rings, and keeps Move/Delete together at the bottom. Signed builds pass; the live HUD screenshot confirms real app names/icons.
- **2026-09-04:** Restored App Switcher behavior for returning-user configurations with a narrow, lossless schema migration; fixed dynamic Apps commit availability and a Settings-preview Reveal bug that could replace Apps children with Snap children. The full suite and clean signed build pass, and the user confirmed the Apps/Snap preview sequence. Also logged the Action choice-grid design decision; live-HUD App Switcher verification remains.

## Progress

- **Unified Settings workspace:** 8/8 waves complete; automated, adversarial, accessibility, signed-build, and user-driven checks passed.
- **Send Keystroke:** Complete; automated coverage and signed live verification passed.
- **Ring UI:** Complete and live-verified.
- **Ring-controls reorganization (Menu/Inner/Middle/Outer tabs + per-ring labels):** 4/4 waves complete; automated, adversarial, signed-build, and user-driven checks passed.
- **HUD actions:** Window snapping and keystroke delivery work; App Switcher v1 is complete and signed-live verified, including MRU order and rapid re-point safety; menu-bar mirror, system toggles, and screenshots remain.
- **Trigger backend:** Keyboard and standard mouse paths work; advanced Logitech HID++ support remains undecided.
- **Task tracker:** no active sprint; 22/24 tracked items complete overall (92%).

## Risks and Backlog

- Fresh installs ship without a default trigger; onboarding is required before clean-install or public-release testing.
- Capture the alternate MX4 vendor interface and re-capture the MX3S with the current inspector before choosing accept-limitation, HID++ implementation, or Options+ coexistence.
- The menu-bar status icon and General Settings Quit fallback are signed-live verified on the M1 Max.
- Settings writers may still replace a corrupt configuration with defaults; the full deferred-risk list is in `MENU_EDITOR_REVIEW.md`.
- Consider screenshots next if onboarding is deferred; it is the smallest unfinished HUD action and establishes dismiss-before-action behavior.
- Longer-term work includes the menu-bar mirror, recent-app switcher, system toggles, app-aware command rings, and alternative menu layouts.
- Investigate what HUD animations are viable in the non-activating AppKit/SwiftUI overlay, including interaction, performance, and accessibility constraints, before choosing an animation direction.

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
- System toggles (Feature D) implementation plan: `SYSTEM_TOGGLES_PLAN.md`
- Help/Feedback/Tip/Appearance Settings plan: `APP_CHROME_SETTINGS_PLAN.md`
- Send Keystroke implementation record: `SEND_KEYSTROKE_PLAN.md`
- Menu-editor findings and deferred risks: `MENU_EDITOR_REVIEW.md`
- HID captures and evidence: `fixtures/`
