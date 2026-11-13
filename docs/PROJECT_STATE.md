# Project State

**Last updated:** 2026-11-13

## Identity

- **Project:** MousePlus (formerly PointerActions; started 2026-01-09)
- **Purpose:** A pointer-anchored radial menu for macOS, summoned by mouse button or keyboard shortcut, with configurable actions and submenus.
- **Distribution:** Public GPLv3 project; direct download first, Mac App Store feasibility later.
- **Repository:** https://github.com/Xpycode/MousePlus

## Now

- **Phase:** Build — permission-loss remediation executing; Waves 1–4 complete. <!-- Phase changed: 2026-11-13 -->
- **Focus:** Permission-loss remediation revision 2: remove all taps and self-relaunch on loss, decided by user. Detection by TCC notification plus tap probe. Permission reported ON; no further live permission-toggle tests.
- **Blocker:** Onboarding E1 permission restoration FAILED November 13. The input hang matches documented macOS behaviour for a live active tap in an untrusted process; a runtime shutdown path (R3) is implemented, fake-validated and independently reviewed (no blocker; three should-fix items open for R6), still unverified under real revocation. Fresh-install deferred; VoiceOver excluded. Settings dragging remains unresolved.
- **Next:** Wave 5: R6 resolves review findings S1 (invalidate all ports before any tap-disable IPC), S2 (deadline on flush/launch), S3 (test the AppDelegate latch guards) and decides notes N1, N3–N7. No live permission toggles; VoiceOver excluded.
- **Execution:** [Permission-loss remediation, revision 2](plans/permission-loss-implementation.md) — Waves 1–4 complete (R0–R5; 117/117 headless tests, Debug build succeeded, no launch; review found no blocker, 3 should-fix); Wave 5 (R6) ready. E1 open; onboarding E1 remains FAILED/open. Evidence: [Wave 4 report](plans/permission-loss-wave4-report.md). Current handoff: [2026-11-13 Wave 4 Resume](sessions/2026-11-13.md#wave-4-resume).

## Recent

- **2026-11-13 Wave 4 (R4, R5):** 117 headless tests pass and the Debug build succeeds (not launched). The independent review found no blocker: every tap is registered, torn down before any wait and refused after loss. It raised three should-fix items for R6 and kept all four deferred items deferred. A suspended-state cue went to the backlog. Not pushed.

- **2026-11-13 Wave 3 (R3):** Loss now removes every tap at once, blocks new ones, closes the HUD, saves settings and relaunches (at most once a minute; otherwise stays alive without taps). 117 headless tests pass, test build succeeded, no launch. Not pushed.

- **2026-11-13 G1 + Wave 2 (R1, R2):** Checkpointed all uncommitted work, merged `main` (code identical; doc conflicts kept newer versions), pushed. Added the permission-loss watcher and a registry that can remove every input tap at once; taps no longer silently re-enable and the keyboard fallback is gone. 93 headless tests pass, test build succeeded, no launch. Wave 2 commits not pushed.

- **2026-11-13 Wave 1 (R0):** Headless SwiftPM harness added (`01_Project/Package.swift`, `scripts/test-input-safety.sh`, `docs/testing/input-safety-harness.md`); 43 tests pass, isolated build-only check succeeded, no launch. Committed in the G1 checkpoint.

- **2026-11-13 planning and review:** Remediation plan created with three agents, then reviewed with three more plus direct source reads. Hang found documented (Apple forums 844416, 735204); plan rewritten as revision 2 with self-relaunch on loss. Documents only; no source, build, tests or app control.

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
- **Selected plan:** Permission-loss remediation revision 2: 6/7 implementation/verification tasks complete (R0–R5), G1 passed, E1 open. Prior onboarding: 7/7 implementation/remediation tasks complete, E1 FAILED/open. Six backlog items preserved.

## Risks and Backlog

- Fresh installs ship without a default trigger; onboarding is implemented, with signed live acceptance required before public-release testing.
- Onboarding VoiceOver live acceptance is deferred by user request and remains untested; it is tracked with the Opening Styles accessibility backlog item.
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
- First-run trigger onboarding specification: `../specs/first-run-trigger-onboarding.md`
- First-run trigger onboarding implementation plan: `plans/first-run-trigger-onboarding-implementation.md`
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
