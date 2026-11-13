# First-Run Trigger Onboarding — Implementation Plan

**Created:** 2026-09-26
**Status:** Implementation validated; signed live acceptance E1 pending

## Goal and specification

Guide an unconfigured user into Settings → Triggers, reuse recording and persistence, and explain
how to try the saved binding. See the [specification](../../specs/first-run-trigger-onboarding.md).

Planning carries forward the proposed existing-pane flow, no default ring trigger, reminder once
per launch while unconfigured, and no persisted tutorial-completion flag. These are planning
assumptions, not separately recorded answers to the earlier preference questions.

## Acceptance criteria

- [ ] Missing permission leads through permission setup to Triggers for unconfigured users.
- [ ] Already-granted permission and empty bindings open Triggers only after configuration loads.
- [ ] Existing bindings and modes survive setup and relaunch unchanged.
- [ ] Guidance reflects successfully saved state; cancelled recording and errors do not imply readiness.
- [ ] Missing and unreadable configuration have different outcomes; load errors never cause default overwrites.
- [ ] Signed live recording, cross-app invocation, dismissal, relaunch, and accessibility checks pass.

The specification contains detailed Given/When/Then cases. None are verified yet.

## Gap analysis

Already present: permission window/polling, recorder and collision handling, AppKit trigger controls,
atomic persistence, coordinator retry/close barrier, live application after saving, and menu-bar and
keyboard access to Settings. Reuse these components.

Missing: explicit Triggers opening route, load-aware launch policy, and inline setup guidance.
`AppDelegate.loadConfiguration()` suppresses errors with `try?`, although
`ConfigurationService.loadResult()` already distinguishes missing files from unreadable files.
Permission continuation opens generic Settings, initially showing General.

## Execution schedule and ownership

- Scope: user requested execution of the complete plan on 2026-09-26. Fresh-context task delegation
  and local validated commits follow Directions. Production-data changes, installs, and releases
  remain outside automatic execution. Work branch: `feature/first-run-trigger-onboarding`.
- Coordinator owns tracking, shared build/test execution, and project membership integration.
  Xcode uses synchronized groups: verify discovery before editing the project file.
- Dependencies: 1.1 → {2.1, 2.2} → 3.1 → 4.1 → E1. No cycles or missing prerequisites.
- Wave 2 tasks have exclusive source/test ownership and may run independently under execution rules.
  Other waves establish or verify a shared boundary and therefore each contain one task.
- Run builds/tests serially in this checkout. No task owns production user data.

### Contract established by Task 1.1

Use a small testable policy driven by configuration load and permission state. Loading is not
empty configuration; failure is not first run. Outputs distinguish waiting, permission setup,
trigger setup, configured, and load failure. A per-launch latch prevents duplicate presentation
and immediate reopen after closing. When the permission window is visible, its explicit Continue
action transfers to Settings once loading completes; do not open Settings behind it automatically.

Ring eligibility matches runtime slot types: contextual keyboard, mouse button, or non-colliding
Global HUD keyboard binding. Open Settings never qualifies. Reuse existing collision logic.
Readiness means configured, not proven physical delivery. Guidance for the selected trigger must
come from successfully loaded/saved state rather than an in-flight or failed edit.

## Tasks

Source paths below are relative to `01_Project/MousePlus/`; test paths to `01_Project/MousePlusTests/`.

### Wave 1 — establish policy

- [x] **1.1: Model eligibility and launch ordering**
  - Dependencies / external gates: none.
  - Owns: new `Utilities/TriggerOnboardingPolicy.swift` and `TriggerOnboardingPolicyTests.swift`.
  - Interface: the policy contract above; record exact accepted types before Wave 2.
  - Success: tests cover both permission/load arrival orders, load error, empty bindings,
    Settings-only, Global-only, wrong-slot binding types, configured users, and once-per-launch routing.
  - Backpressure: focused test command below selecting `TriggerOnboardingPolicyTests`.

### Wave 2 — independent consumers

- [x] **2.1: Route startup and permission continuation**
  - Depends on: 1.1. External gates: none.
  - Owns: `MousePlusApp.swift`, `Controllers/OnboardingWindowController.swift`,
    `Views/PermissionOnboardingView.swift`, new `TriggerOnboardingLaunchTests.swift`.
  - Interface: explicit Triggers route; load outcome reaches the launch policy; continuation can
    wait for load without dropping the user's request.
  - Success: empty successful load opens Triggers once; configured users keep their bindings;
    load failure exposes existing Settings recovery/error handling without saving defaults.
    No duplicate monitors; preserve the app-hosted test guard against real event taps/TCC prompts.
  - Replace touched permission-view controls with AppKit wrappers, preserving default/cancel keys.
    Any shared wrapper extension belongs to coordinator integration rather than concurrent edits.
  - Backpressure: launch and `ApplicationLifecycleAccessTests`; authoritative Debug build.

- [x] **2.2: Add inline setup and saved-trigger guidance**
  - Depends on: 1.1. External gates: none for development; E1 verifies placement live.
  - Owns: `Views/TriggersSettingsView.swift`, `ViewModels/SettingsWorkspaceCoordinator.swift`,
    new `TriggerOnboardingGuidanceTests.swift`, relevant additions to `SettingsWorkspaceCoordinatorTests.swift`.
  - Placement: after permission notices and before Keyboard Trigger (baseline line 61). Reuse
    Record/Clear/mode controls; no duplicate recorder, writer, or separate wizard.
  - Interface: if necessary, expose a read-only durable trigger snapshot from the coordinator.
    Preserve serialized whole-configuration persistence and live apply after successful saving.
  - Success: explain recording when empty; show actual saved binding and mode-specific trial/Escape
    instructions after saving. Failed/pending saves do not claim new readiness. Retain collision and
    interception guidance. Settings access help reflects customized or cleared shortcuts.
  - Backpressure: guidance/coordinator tests for failed save, retry, rapid edits and clearing the last
    binding; Debug build. Keep normal configured-user guidance concise.

### Wave 3 — integration

- [x] **3.1: Integrate and run automated regressions**
  - Depends on: 2.1, 2.2. External gates: none.
  - Owns: new `TriggerOnboardingIntegrationTests.swift`; narrow fixes to earlier files after
    their prior ownership ends; shared wrapper/project changes only if required.
  - Success: no false setup from provisional defaults, duplicate routing or monitors; saved state
    precedes readiness/live apply; corrupt files remain intact; cancel/timeout retain bindings.
    Verify new test discovery and all applicable regressions, not merely process exit status.
  - Backpressure: complete focused command below and Debug build; use isolated fixtures and fake
    permission/monitor dependencies, not real permission prompts.

### Wave 4 — review

- [x] **4.1: Review lifecycle and persistence behavior**
  - Depends on: 3.1. External gates: none.
  - Owns: review evidence in this plan; fixes return to the relevant implementation owner.
  - Success: review permission ordering, loading errors, stale save completion, close/reopen,
    monitor lifetime, focus and accessibility. Resolve material findings and rerun affected checks.
    Use independent review as required by the execution workflow; disclose unavailable capabilities.
  - Backpressure: recorded file-specific findings, dispositions, and validation of fixes.

## Acceptance-blocking remediation — November 7, 2026

The October 29 handoff identified a Settings saving stall and two confirmed color-well
bugs. The November 7 continuation authorizes remediation before resuming E1; E1 remains
open and no previous acceptance evidence is promoted.

- [x] **R1: Make editor persistence independent of pane rendering.** Owns
  `MenuEditorModel.swift`, `SettingsWorkspaceCoordinator.swift`, and coordinator tests.
  Success: direct binding edits schedule saves; owner-driven loads do not; close waits
  for edits received during an in-flight save. Validate focused model/coordinator tests.
- [x] **R2: Correct inherited color-well behavior.** Owns `AppKitControls.swift` and
  its tests. Success: opening a chooser never writes its seed; inherited display reflects
  current context; retired wells detach from the color panel. Validate detached native
  control tests; actual chooser interaction remains a manual acceptance check.

R1 and R2 are independent; fresh agents own their separate files. The coordinator owns
builds, test execution, integration and records; a third fresh agent reviews the fixes.
R1/R2 automated validation: 74 focused tests passed on November 7. Native chooser
and end-to-end Settings/live-HUD confirmation remain unperformed under E1.

These source fixes address reproducible failure paths, not a proven retrospective cause
of the October 29 incident: the November 7 last-day log query returned no matching records.

## External checks

- [ ] **E1: Signed live onboarding acceptance**
  - Depends on: 4.1.
  - Requires: signed build, deliberate isolated configuration environment, and user availability
    for OS permission interaction, physical input, and foreground app checks.
  - Owns: acceptance evidence, spec verification marks, and project completion update.
  - Gates: live presentation, cross-app invocation, physical mouse capture, permission behavior,
    keyboard access and overall completion. VoiceOver live acceptance is deferred by user request
    on 2026-09-27 and remains untested in the backlog. Does not block Tasks 1.1–4.1.
  - Verify: fresh configuration with permission missing; pre-granted permission; configured user;
    permission restore; cancel/timeout; keyboard and supported physical mouse recording; both modes;
    Escape dismissal without action execution; close/reopen; relaunch persistence and keyboard focus.
  - An intercepted vendor button must show recovery guidance and permit keyboard fallback.
    Keyboard remapping does not prove direct physical mouse support.
  - Do not remove production configuration or reset production TCC for routine tests. Document
    the environment and every untested row. Installation/foreground actions follow execution scope.
  - While unavailable: finish automation/review and prepare the acceptance record; keep E1 unchecked
    and distinguish implemented behavior from live-accepted behavior. No public distribution.

## Backpressure commands

Run from the project root during execution. Earlier tasks select only their applicable test classes.

```bash
xcodebuild -workspace 01_Project/MousePlus.xcworkspace \
  -scheme MousePlus -configuration Debug build

xcodebuild -workspace 01_Project/MousePlus.xcworkspace \
  -scheme MousePlus -configuration Debug -destination 'platform=macOS' test \
  -only-testing:MousePlusTests/TriggerOnboardingPolicyTests \
  -only-testing:MousePlusTests/TriggerOnboardingLaunchTests \
  -only-testing:MousePlusTests/TriggerOnboardingGuidanceTests \
  -only-testing:MousePlusTests/TriggerOnboardingIntegrationTests \
  -only-testing:MousePlusTests/ApplicationLifecycleAccessTests \
  -only-testing:MousePlusTests/SettingsWorkspaceCoordinatorTests \
  -only-testing:MousePlusTests/ConfigurationServiceTests \
  -only-testing:MousePlusTests/HUDTriggerRoutingTests \
  -only-testing:MousePlusTests/DismissMonitorTests
```

Preserve actual result locations/counts during execution. Do not repeat unaffected broad suites.

## Operational learnings

No execution findings yet. Startup's provisional defaults must not be mistaken for a completed load.

## Blocked tasks

E1 awaits an isolation method for fresh-configuration and fresh-permission scenarios plus
user-driven signed live checks. The daily-use account has existing configuration, so launching
the candidate there would not establish fresh-install behavior. VoiceOver is deferred and is not
an E1 gate. Tasks 1.1–4.1 are validated. The installed daily-use app remains unchanged.

## Execution log

| Wave / task IDs | Assignments or serial reason | Validation / evidence | Commits or exception | Remaining gates / next action |
|---|---|---|---|---|
| 1.1 | Fresh agent `onboarding_policy`; coordinator validation | 11 policy tests passed; baseline Debug build passed | `9de0183` | Policy interface accepted before Wave 2 |
| 2.1, 2.2 | Fresh agents `onboarding_launch` / `onboarding_guidance`; disjoint ownership | Integrated focused suite passed 128 tests. A test fixture MainActor annotation was corrected before passing run | `29b34e5`, `7e9dc01` | Integration/review followed |
| 3.1 | Coordinator integration; native key equivalents and Settings permission-grant bridge | 24 affected tests passed after grant bridge correction; Debug build passed | `8a791db` | Review followed |
| 4.1 | Fresh independent reviewer `onboarding_review`; fixes by coordinator and guidance agent | Two P2 recovery findings resolved; 63 affected tests and final 5 integration tests passed; final Debug build passed; reviewer reports no remaining findings | `4e3514a` | E1 is unperformed |
| E1 preflight | Coordinator only; physical input and permission checks require the user | Candidate bundle and version identified; strict deep signature verification passed outside tool sandbox on M4 Pro/macOS 27.2; current account configuration exists | Documentation-only; no app launched | Isolate fresh-configuration and fresh-permission rows, then perform required live checks; E1 remains unchecked |
| E1 manual handoff | Coordinator prepared GUI-only instructions for the test account | Candidate and handoff are readable in the same `/private/tmp` folder; repository source and staged copy match | Documentation-only; no app launched | Sign out of daily account, run the handoff in the test account, return results via `/Users/Shared/`; E1 remains unchecked |

Evidence logs: `/tmp/mouseplus-onboarding-policy-tests.log`,
`/tmp/mouseplus-onboarding-integration-tests.log`, `/tmp/mouseplus-onboarding-recovery-tests.log`,
`/tmp/mouseplus-onboarding-review-fix-tests.log`, `/tmp/mouseplus-onboarding-backup-race-tests.log`,
`/tmp/mouseplus-onboarding-final-build.log`. The counts overlap; do not add them together.

### Review findings and disposition

- P2: a file repaired before Settings first loads could appear saved while runtime stayed stopped
  after startup load failure. Added a narrow loaded-Settings recovery bridge, restricted to
  failed/waiting startup and preserving newer saved configurations. The production Settings load
  entry has an integration regression with a real isolated configuration file.
- P2: the backup check at the end of load can yield after controls become editable. A dirty snapshot
  must not be forwarded as recovered durable configuration. Added a dirty-fields guard and a bounded
  delayed-backup test which verifies both pending and failed saves remain unapplied.
- Additional integration correction: Settings has a separate permission service; its granted state
  now reaches the launch adapter even when the original permission window was closed.
- All tests use injected effects/isolated persistence; they do not prove physical input, TCC grant
  behavior, visible focus, or VoiceOver acceptance. Use the [live checklist](first-run-trigger-onboarding-acceptance.md).

### Acceptance candidate and stop boundary

Release candidate: `/private/tmp/MousePlus-onboarding-20260926/MousePlus.app`.
Developer ID team `FDMSRXXN73`; strict deep signature verification passed; hardened runtime enabled.
Release log: `/tmp/mouseplus-onboarding-release-build.log`. Built on macOS 27.2, arm64.
Not installed, launched, notarized, or published in this execution. Only the existing installed
MousePlus process remained at final process check. E1 is the only remaining task and requires live
user interaction; no other ready implementation work remains. No push or merge performed.

### November 7 remediation evidence

- R1: fresh agent `persistence`; R2: fresh agent `color_well`; independent read-only
  reviewer `review`. Coordinator inspected integration and ran the authorized app-hosted tests.
- Final focused run: 74 tests, zero failures; Debug, macOS, serialized test execution.
  Classes: SettingsWorkspaceCoordinatorTests, MenuEditorModelRegressionTests, AppKitControlsTests.
  Result: `/private/tmp/MousePlus-settings-20261107/FocusedTests-final.xcresult`.
  Log: `/private/tmp/MousePlus-settings-20261107-tests-final.log`.
- Initial run: 72/73 passed; new fixture accidentally recorded the existing Copy shortcut.
  Corrected fixture to a different shortcut and asserted a real mutation; no product workaround.
- Review initially questioned same-color item retargeting; finding retracted after confirming
  existing `.id(model.selection)`. Added defensive native-well teardown and detached test.
- Commit exception: fixes overlap substantial pre-existing uncommitted onboarding/diagnostic work
  on `fix/hud-live-remediation`; the October handoff records unreconciled other-Mac history.
  Preserve the checkout; no commit, fetch, merge or push in this remediation run.
- E1 remains open. Current handoff: [November 7 Resume](../sessions/2026-11-07.md#resume).

Release remediation artifact: `/private/tmp/MousePlus-settings-20261107/DerivedData/Build/Products/Release/MousePlus.app`.
Build and strict Developer ID verification passed; not launched or installed. See current handoff
for finite manual checks.

User subsequently reported all three November 7 remediation checks passed (record/clear
persistence, chooser inheritance, and inherited color/context display). R1/R2 live
acceptance is complete; onboarding E1 remains open. Title placement is a separate
user-approved visual follow-up recorded in the current session.

### November 7 fresh-install deferral

User explicitly deferred fresh-install testing. Fresh permission setup, permission continuation,
fresh/pre-granted launch and unconfigured relaunch remain untested and deferred in the acceptance
record. E1 stays open for remaining configured-account evidence; deferral is not a pass.
Latest candidate and GUI handoff staged in `/private/tmp/MousePlus-onboarding-20261107/`.
Signature verified; executable hash matches the title-header build. No account switch,
production configuration modification, permission reset or extra launch performed.

November 7 final user evidence: usual configured trigger invokes over Finder and Escape
dismisses without action (PASS). Exact mode/device unspecified; both-mode and direct-mouse
coverage are not inferred. E1 remains open; next is recorder cancellation/timeout.

November 7 follow-up: user reports mouse-recorder timeout recovery PASS (old binding
retained, guidance visible, usual trigger still works with Escape dismissal). Cancellation
remains unconfirmed. Next: configured relaunch and keyboard navigation. E1 stays open.

November 7 configured-relaunch follow-up: user reports PASS for normal quit/reopen,
no onboarding, unchanged existing binding/mode and invocation over Finder with Escape
dismissal. New-binding persistence and broader cross-app coverage are not inferred.
Next: keyboard navigation; cancellation remains unconfirmed. E1 stays open.

November 7 keyboard follow-up: user passed Tab/Shift-Tab focus, Space activation of
Record, Escape cancellation and retained working binding/mode. Return was not tested.
User reported header/sidebar color mismatch and non-draggable Settings window; local
chrome remediation is authorized and requires a fresh build and live acceptance.

Chrome correction built and strict-signature verified; fresh persistent Release artifact
launched as PID 76249 after graceful old-instance exit. See current session for artifact
identity. Header drag/color live acceptance remains open; no new automated UI tests.

November 8: Settings chrome remediation accepted. MousePlus screenshot confirms header/
sidebar appearance; user explicitly confirms title-area dragging works. E1 remains open
with prior deferrals and unverified scenarios preserved. Current handoff: November 8 session.

November 8: user passed Hold-release and Tap-toggle invocation over Finder with Escape
dismissal and no action execution. Input route unspecified; direct mouse coverage is
not established. E1 and existing deferrals remain open.

November 8 route clarification: both trigger modes passed via the user’s BetterMouse
mapping (BetterMouse-to-keyboard). Direct physical mouse triggering remains unverified.

November 8: user passed re-recording the existing keyboard shortcut, retained mode and
matching guidance, plus BetterMouse invocation/Escape in another unspecified app.
Changed-binding relaunch persistence is not inferred; E1 remains open.

November 8 new user finding: after deleting Safari HUD, Settings showed default sample
layout while live Global matched saved Global data. Preview initialization/profile identity
and sidebar profile tree updated; fresh live parity/tree acceptance required. No production
config edits. Settings-shortcut guidance check remains unconfirmed; E1 stays open.

November 8 Global preview/tree follow-up: user reports PASS for Menu Items → Global
and editor/live ring parity in the profile-tree build. New-tree app-profile switching/
deletion was not exercised. Settings shortcut/menu-bar guidance remains unconfirmed.

November 10: Settings menu-bar access/no-shortcut guidance passed by user report. Latest
profile-tree build had become non-draggable; user-requested graceful restart restored
dragging. No code change; recurrence root cause remains unresolved. E1 remains open.

November 10: user passed new-sidebar app-HUD creation, independent editing, switching,
and deletion fallback to Global with editor/live parity. App picker exposed XPC services
and crowded name rows; corrected discovery filtering and row text, live acceptance pending.

November 10 follow-up: screenshot of “safa” confirms readable real-app names with no XPC
helpers. User passed recording a different keyboard trigger, invoking the HUD, normal
quit/reopen, and retained working binding/mode. Changed-binding relaunch persistence is
accepted. E1 remains open for direct mouse input, permission restoration and Return behavior;
fresh-install and VoiceOver checks remain deferred.

November 10 direct-mouse finding: user reports MousePlus-bound mouse button switches Warp
tabs without BetterMouse. MouseButtonTriggerMonitor used passive NSEvent observers; replaced
with active session tap consuming matched down/drag/up. Recorder capture passes through,
unrelated buttons remain untouched, tap failure has no passive double-action fallback. Five
focused headless tests pass; signed Release build/verification pass; launched new candidate.
Live Warp suppression/hold-release checks remain pending. Return on ordinary Record NSButton
is not a default action; user confirms Space activates it, expected native behavior. Previous
Return-to-record instruction was incorrect. VoiceOver explicitly excluded from this pass.

November 10 Warp retest: user confirms “that worked” after direct-mouse fix handoff.
Mouse trigger suppression accepted on the tested route; no exact button or mode inferred.
Permission restoration remains the configured-account acceptance item. VoiceOver excluded.

### November 13 blocker: permission revocation and input failure

E1 permission-restoration acceptance FAILED: user reproduced continued mouse-trigger HUD
invocation after revocation, broken dismissal and broad input unresponsiveness; Exposé
restored clicking. Permission is now ON. Missing runtime revocation/shutdown handling is
confirmed; exact cause of system-wide symptoms is not yet established. November 10 routing
tests do not cover OS permission/focus behavior. No new source remedy or tests November 13.
Next session: investigate if necessary, then plan with agents and web research, including
similar apps' failure reports and lifecycle handling. No further daily-account revocation
reproduction. Current handoff: [November 13 Resume](../sessions/2026-11-13.md#resume).
