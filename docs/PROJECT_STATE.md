# Project State

**Last updated:** 2026-09-04

## Identity

- **Project:** MousePlus (formerly PointerActions; started 2026-01-09)
- **Purpose:** A pointer-anchored radial menu for macOS, summoned by mouse button or keyboard shortcut, with configurable actions and submenus.
- **Distribution:** Public GPLv3 project; direct download first, Mac App Store feasibility later.
- **Repository:** https://github.com/Xpycode/MousePlus

## Now

- **Phase:** App Switcher v1 implemented and signed-live verified; evaluating focused v2 concepts. <!-- Phase changed: 2026-09-04 -->
- **Focus:** App Switcher (`APP_SWITCHER_PLAN.md` / `IMPLEMENTATION_PLAN.md`) — running apps now occupy a pointer-aligned full-circle outer ring; names/icons, activation, label visibility, and the new layout are live-confirmed. MRU ordering and rapid re-pointing remain to verify.
- **Blocker:** Advanced Logitech-button support is paused until raw MX4/MX3S captures resolve the HID++ strategy decision. `APP_CHROME_SETTINGS_PLAN.md`'s Leave-a-Tip button still needs a tip-jar platform/URL from the user.
- **Next:** Verify the remaining v1 MRU and rapid re-point checks, then decide whether the next scoped App Switcher increment should add windows, search/filtering, grouping/paging, recent apps, or app-specific actions.

## Recent

- **2026-09-04:** Prototyped and live-verified a full-circle running-app switcher aligned to the Apps wedge; fixed the test-run handoff by relaunching the exact rebuilt bundle, and confirmed outer labels can be disabled.
- **2026-09-04:** Fixed tap-toggle commits at the native AppKit mouse-up boundary; the full 249-test suite and signed build pass, and the user confirmed both static and dynamic Safari activation.
- **2026-09-04:** Clarified dynamic Apps editing: the inspector now shows a read-only running-app source, hides inactive preserved children, centralizes outer-item creation under Menu & Rings, and keeps Move/Delete together at the bottom. Signed builds pass; the live HUD screenshot confirms real app names/icons.
- **2026-09-04:** Restored App Switcher behavior for returning-user configurations with a narrow, lossless schema migration; fixed dynamic Apps commit availability and a Settings-preview Reveal bug that could replace Apps children with Snap children. The full suite and clean signed build pass, and the user confirmed the Apps/Snap preview sequence. Also logged the Action choice-grid design decision; live-HUD App Switcher verification remains.
- **2026-09-04:** Verified two Settings complaints were stale-build artifacts, identified the persistent band toolbar and Reveal traversal as intentional UX awaiting user decisions, then received and implemented both decisions.

## Progress

- **Unified Settings workspace:** 8/8 waves complete; automated, adversarial, accessibility, signed-build, and user-driven checks passed.
- **Send Keystroke:** Complete; automated coverage and signed live verification passed.
- **Ring UI:** Complete and live-verified.
- **Ring-controls reorganization (Menu/Inner/Middle/Outer tabs + per-ring labels):** 4/4 waves complete; automated, adversarial, signed-build, and user-driven checks passed.
- **HUD actions:** Window snapping and keystroke delivery work; App Switcher names/icons, activation, full-circle layout, and label visibility are live-confirmed, with MRU/re-point checks outstanding; menu-bar mirror, system toggles, and screenshots remain.
- **Trigger backend:** Keyboard and standard mouse paths work; advanced Logitech HID++ support remains undecided.
- **Task tracker:** no active sprint; 22/23 tracked items complete overall (96%).

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
- Active App Switcher execution plan: `../IMPLEMENTATION_PLAN.md`
- HUD action roadmap: `HUD_ACTIONS_PLAN.md`
- App menu-bar mirror (Feature A) implementation plan: `APP_COMMANDS_PLAN.md`
- Dynamic app switcher (Feature C) implementation plan: `APP_SWITCHER_PLAN.md`
- System toggles (Feature D) implementation plan: `SYSTEM_TOGGLES_PLAN.md`
- Help/Feedback/Tip/Appearance Settings plan: `APP_CHROME_SETTINGS_PLAN.md`
- Send Keystroke implementation record: `SEND_KEYSTROKE_PLAN.md`
- Menu-editor findings and deferred risks: `MENU_EDITOR_REVIEW.md`
- HID captures and evidence: `fixtures/`
