# Permission-loss remediation — Implementation Plan (revision 2)

**Created:** 2026-11-13. **Revised:** 2026-11-13 after plan review.
**Status:** Executing — Waves 1–2 (R0, R1, R2) complete 2026-11-13; G1 passed; Wave 3 (R3) ready.
**Progress:** 3/7 implementation and verification tasks complete; external acceptance E1 open.
**Task states:** unchecked = pending unless a gate is named. This plan owns task status/evidence.
Revision 1 (latch until manual restart, tasks P1–P7) is retained unchanged as
[permission-loss-implementation.v1-superseded.md](permission-loss-implementation.v1-superseded.md).

## Goal and evidence

When MousePlus loses its Accessibility-type permission while running, it removes every event tap
it owns, closes the HUD without committing, and relaunches itself into the existing
permission-setup path. Saved settings are preserved.

Revision 1 treated the November 13 input failure as unexplained. The review found it documented:
a live session-level, head-insert, `.defaultTap` owned by a process that loses trust hangs keyboard
and mouse input system-wide, independent of the tap's mask or callback behaviour. Sources and
corrections: [investigation, review addendum](permission-loss-investigation.md#review-addendum-2026-11-13).
The hazard is therefore the *existence* of our taps after loss, not what our callbacks return.

Source journey: running with trust → loss detected (TCC change notification, tap probe, or trust
read) → synchronous teardown of all taps, monitors and HUD → settings flush → new app instance →
old process terminates → new instance starts untrusted and shows the existing permission setup.

Related: [original incident](../sessions/2026-11-13.md),
[onboarding plan](first-run-trigger-onboarding-implementation.md) (its E1 remains FAILED/open),
[decision record](../decisions.md).

## Decisions and their status

| Choice | Status |
|---|---|
| Self-relaunch on loss, replacing latch-until-manual-restart | **Decided by user, 2026-11-13** |
| Authoritative detection: TCC change notification + throwaway tap probe, trust read as backstop | Review recommendation; adopted here pending plan approval |
| Tap disable is not fatal: probe first, resume only if still trusted | Review recommendation; adopted here pending plan approval |
| Separate harness task before any source work | Review recommendation; adopted here pending plan approval |
| Generation counters, pending-action cancellation, dismissal-monitor readiness, Settings banner rewording (revision 1 P2–P4 parts) | Deferred; re-evaluated in R5 |

## Scope and constraints

- Planning only is authorized now. No source edit, build, test, app control or commit was performed
  to prepare this revision. Preserve existing dirty source and documentation changes.
- **User limits, unchanged:** no live permission-toggle tests on any account; VoiceOver excluded;
  fresh-install acceptance deferred. No TCC reset, simulated physical input, competing-app
  installation or forced quit.
- Self-relaunch is application behaviour. It does not extend agent app-control permission:
  validation in this plan is headless tests plus a build-only check, with no launch handoff.
- Relaunch is bounded: at most one safety relaunch per 60 seconds (persisted timestamp). A second
  loss inside that window, a failed settings flush or a failed launch leaves the process alive
  with all taps removed and no in-process re-arm. The existing menu-bar Restart and Quit remain.
- No new UI. The relaunched instance uses the existing startup-denied path
  (`TriggerOnboardingLaunch` → `showPermissionOnboarding`, `MousePlusApp.swift:338`), which also
  shows the system permission prompt as any untrusted launch does today.
- The first-grant onboarding flow and `PermissionsService` are not modified.
- Undocumented dependency, accepted knowingly: the Darwin notification
  `com.apple.tcc.access.changed`. It is a trigger only; the probe and trust read still decide.
- No private TCC API, no privileged helper, no global release-all, no replay of swallowed input.

## Acceptance criteria

- Loss is detected with Settings closed, including removal of the entry (where `AXIsProcessTrusted`
  can stay stale-true). The probe runs off the main thread; a probe that does not return within its
  deadline counts as loss, so a hung probe cannot block the run loop servicing live taps.
- On loss, before any `await`: every live event tap in the process is disabled and invalidated
  (trigger monitors, Settings hotkey, both recorders), NSEvent monitors owned by triggers and
  dismissal are removed, pressed ownership is cleared and the HUD closes through the
  non-committing `closeRing` path. Teardown is idempotent and fires once.
- After teardown: pending settings are flushed, a new instance is launched, the old process
  terminates. Within the rate-limit window, or if flush or launch fails, the process stays alive
  suspended: no tap, no re-arm from configuration saves, permission grants or queued events.
- A tap-disable event never re-enables by itself. The owner clears pressed state, cancels a held
  invocation, and reports upward. Trust read false or probe false → loss path. Probe true →
  resume. More than three disables in ten seconds → loss path (a relaunch gives fresh taps).
- Tap-install failure for the keyboard trigger no longer falls back to NSEvent monitors
  (`KeyboardTriggerMonitor.swift:43-60`); it reports the failure and requests a probe.
- Healthy operation is unchanged: matching down/up pairs are still consumed, commits execute once,
  rebinding still cancels a held source.
- Trust transitions, notification arrivals, probe results and latency, tap-disable type, teardown
  and the relaunch decision are logged (OSLog, one category), so a recurrence leaves a trace.
- Headless validation and independent review pass. Behaviour under real revocation stays
  unverified until E1; no claim of a verified fix is made from fakes.

## Execution schedule and ownership

Paths are under `01_Project/MousePlus/`; tests under `01_Project/MousePlusTests/`.
Coordinator owns tracking, the package manifest after R0, build resources and any project
membership changes. Builds and test runs are serial. Use master `commands/execute.md` with fresh
task packets when execution is requested.

Dependency graph: R0 → {R1, R2} → R3 → {R4, R5} → R6 → E1. G1 gates R2 and R3 only.
R1/R2 and R4/R5 have disjoint ownership and no mutual prerequisites. R2 does not consume R1: tap
owners report faults through callbacks and R3 connects them to the monitor. No cycles.

Interfaces fixed before dispatch:

- `RuntimeTrustMonitor` (R1): `start(onLoss:)`, synchronous `trustReadIsFalse`,
  `requestProbe(reason:) async -> Bool`; loss callback fires at most once.
- `InputTapRegistry` (R2): every system tap registers on start and unregisters on stop;
  `teardownAll()` is synchronous and main-actor.
- Fault reporting (R2): tap owners expose `onDisabled(reason)` and `onInstallFailed`, plus an
  explicit `resume()`; `TriggerService` forwards them and yields the existing `.cancel(source:)`.
- `RuntimeSafetyCoordinator` (R3): owns the monitor and takes injected effects (teardown, flush,
  launch, terminate, clock, defaults), so integration is testable without `AppDelegate`, which
  shares a file with `@main` and cannot be compiled headless.

## Tasks

### Wave 1 — harness (single task: everything later validates through it)

- [x] **R0: Committed headless test harness** — done 2026-11-13 (commit deferred to G1; see log)
  - Depends on / external gates: none. Adds files only.
  - Owns: proposed `01_Project/Package.swift` (module `MousePlus`, explicit source lists over the
    sources in place, no copies or stubs), `scripts/test-input-safety.sh`, a short coverage note.
  - Context: the November 10 run used `swift test --package-path build/mouse-trigger-20261110/Headless`
    with copied sources and a stub (gitignored). The hosted XCTest target already has a launch
    guard (`MousePlusApp.swift:315`) but stays app-hosted under master `34_testing.md`.
  - Success: the script runs the existing monitor tests that are headless-safe and names the ones
    excluded because they reach unseamed NSEvent monitors
    (`MouseButtonTriggerMonitorTests.swift:58,71`). Scratch and cache paths are redirected under
    `build/`. Manifest placement is confirmed not to change the app build.
  - Backpressure: `scripts/test-input-safety.sh --all` (inspect before first run); authoritative
    `xcodebuild -workspace 01_Project/MousePlus.xcworkspace -scheme MousePlus -configuration Debug build`,
    build only, after inspecting startup/build hooks per `34_testing.md`.
  - Stop/replan: if the manifest cannot sit beside the project without affecting the app build,
    stop and report options; do not move production sources in this task.

### Wave 2 — sensor and tap layer (parallel, disjoint)

- [x] **R1: Runtime trust monitor** — done 2026-11-13, commit `b7db89d` (see Wave 2 log)
  - Depends on: R0. External gates: none (new files only).
  - Owns: new `Services/RuntimeTrustMonitor.swift`, new `RuntimeTrustMonitorTests.swift`.
  - Interface: as fixed above. Injectable trust reader, probe, notification source and clock.
    Production probe: create a session-level `.defaultTap` with a narrow mask, never attach it to
    a run loop, invalidate it in the same call; nil means no access. Runs on a utility queue.
  - Proposed cadence, to be fixed in this task: probe on each TCC notification and on request;
    `AXIsProcessTrusted` read every 500 ms; backstop probe every 5 s.
  - Success: loss by notification, by backstop, by stale-true trust with failing probe, by probe
    deadline; coalesced notification bursts; single loss callback; nothing prompts.
  - Backpressure: `scripts/test-input-safety.sh --suite RuntimeTrustMonitorTests`.

- [x] **R2: Tap registry, fault reporting, no silent re-enable or fallback** — done 2026-11-13,
  commit `1c2c24c` (see Wave 2 log)
  - Depends on: R0. External gates: G1.
  - Owns: new `Services/InputTapRegistry.swift`, `Services/MouseButtonTriggerMonitor.swift`,
    `KeystrokeCaptureRecorder.swift`, `KeyboardTriggerMonitor.swift`, `TriggerService.swift`,
    `TriggerRecorderService.swift`; their tests, new where absent.
  - Success: both system tap classes register and unregister; `teardownAll()` leaves no enabled
    port. Disable (timeout and user-input kept distinct) clears pressed state, yields `.cancel`,
    reports upward and does not re-enable; `resume()` re-enables. Recorders cancel the recording
    on disable. Keyboard install failure reports and installs no NSEvent fallback.
    `TriggerService.stop()` clears active sources; `updateConfig` no longer starts a stopped
    service. Recorder static flags are cleared on teardown. Add the NSEvent seam
    `TriggerRecorderService` needs so its tests run headless, and re-admit the two R0 exclusions.
  - Backpressure: harness suites for mouse, keyboard, trigger service, both recorders, registry.

### Wave 3 — integration (single task: one owner for the shared app file)

- [ ] **R3: Loss path, bounded relaunch and suspended fallback**
  - Depends on: R1, R2. External gates: G1.
  - Owns: new `Services/RuntimeSafetyCoordinator.swift`, `MousePlusApp.swift`, new
    `RuntimeSafetyCoordinatorTests.swift`.
  - Success: the monitor starts when runtime is applied (trust plus loaded configuration) and
    stays up with Settings closed. Loss runs teardown synchronously, then the existing
    `performApplicationRestart` route (`MousePlusApp.swift:409`), subject to the 60-second limit.
    Suspended state blocks `applyRuntimeConfiguration`, `handleTriggerEvent`, `showRing` and
    `applySettingsHotkey`. Tap faults route to probe-then-resume or loss, with the burst rule.
    Logging as specified. `AppDelegate` only wires closures.
  - Audit and record, no edits expected: `InputRecorderService`, `InputRecorderWindowController`
    and `Services/HID/IOHIDDeviceInspector.swift` use passive monitors or HID, own no event tap,
    and end with the process. If the audit finds an active tap, add it to the registry here.
  - Backpressure: coordinator suite with fakes covering loss at idle, visible HUD, held trigger,
    active recording, during flush; rate-limited second loss; failed flush; failed launch; late
    queued events; configuration save while suspended. Then the build-only command from R0.

### Wave 4 — verification and review (parallel, disjoint)

- [ ] **R4: Full headless matrix and authoritative build**
  - Depends on: R3. External gates: none.
  - Owns: validation report only.
  - Success: all harness suites pass; related onboarding, routing, recorder and keystroke
    regressions run where the harness supports them, with gaps listed instead of substituting
    app-hosted runs. Build-only succeeds. No launch handoff.
  - Backpressure: `scripts/test-input-safety.sh --all`; the build command above.

- [ ] **R5: Independent lifecycle review and deferred-scope decision**
  - Depends on: R3. External gates: none.
  - Owns: review report only; findings return to the owning task.
  - Success: independently trace every tap creation and re-enable site to the registry, the
    teardown-before-await ordering, the relaunch loop guard and the suspended guards. Give a
    reasoned keep-or-drop recommendation for each deferred revision 1 item. No agreement-only pass.
  - Backpressure: file-specific findings with dispositions and affected tests.

### Wave 5 — close implementation evidence

- [ ] **R6: Resolve findings and prepare bounded handoff**
  - Depends on: R4, R5. External gates: none.
  - Owns: serial corrective edits to earlier task files, final evidence and tracking.
  - Success: material findings resolved and affected checks rerun; artifact identity and exact
    tested scope recorded; "implemented and fake-validated" kept separate from "verified under
    real revocation". Neither this plan's E1 nor onboarding E1 is marked passed from fakes.
  - Backpressure: affected harness suites and build if source changed.

## Gates and external acceptance

- [x] **G1: Checkpoint and base decision (user) — gates R2 and R3** — passed 2026-11-13: user chose
  checkpoint + merge. Checkpoint `bc39d95`, merge of `origin/main` `25f3cc1` (code merged clean and
  identical to checkpoint; six doc conflicts took this branch's newer versions), harness 43/43 after
  merge, branch pushed with remote equality verified.
  - R2 and R3 edit files that already carry uncommitted changes (`MouseButtonTriggerMonitor`,
    `KeystrokeCaptureRecorder`, `TriggerRecorderService`, `MousePlusApp`). The branch has one
    unpushed commit and is three commits behind `origin/main`, including `c5b8e61` (isolate
    permission-sensitive test startup). Without a checkpoint this work cannot be rolled back
    separately. Decision needed: commit the current tree as a checkpoint and merge or rebase
    `origin/main` first, or proceed on the dirty tree knowingly. R0 and R1 are not gated.

- [ ] **E1: Real macOS acceptance — open**
  - Depends on: R6; requires separately authorized user-operated acceptance.
  - Part A, proposed, no toggles: launch with permission already ON, one mouse and one keyboard
    invocation and dismissal, one cancelled recording, Settings and Quit. Stop on the first
    abnormal input response.
  - Part B, **not authorized under the current no-toggle limit**: one revocation with the fix in
    place. If the limit is ever lifted, the safe shape is the test account, an SSH session open
    from the other Mac, and a timed kill of the app armed before the toggle; one report states
    that ending the owning process restores input immediately.
  - Incident closure and the failed onboarding row need Part B, or an explicit user decision to
    accept the residual risk on fake evidence plus Part A. Neither is assumed here.

## Mapping from revision 1

| Revision 1 | Revision 2 |
|---|---|
| P1 suspension contract + harness | Split: R0 harness, R1 sensor. Generation contract deferred. |
| P2 fail-open interception, capture cancellation | R2, narrowed to tap lifetime, fault reporting, fallback removal. |
| P3 HUD/native callback and pending-action cancellation | Deferred to R5's decision; HUD closes through existing `closeRing` in R3. |
| P4 lifecycle wiring and Settings banner | R3 without UI; banner unchanged. |
| P5, P6, P7 | R4, R5, R6. |
| E1 | E1, split into Part A and unauthorized Part B, with closure condition stated. |

## Known limits

- No source shows that in-process teardown or self-relaunch always wins the race against the
  hang; alt-tab-macos and LinearMouse ship relaunch-on-loss, which is the strongest available
  precedent. The Exposé recovery in the incident is unexplained by any source.
- In the suspended fallback there is no new visible cue beyond what exists today.
- The relaunch shows the system permission prompt, as any untrusted launch does.

## Execution log

### G1 — checkpoint and base (2026-11-13, M1 Max)

- **User decision:** checkpoint + merge. Checkpoint `bc39d95` (55 paths, explicit staging);
  merge of `origin/main` `25f3cc1`: code auto-merged and identical to the checkpoint tree; six doc
  conflicts resolved to this branch's newer versions. Harness 43/43 after merge; pushed, remote equal.

### Wave 2 — R1, R2 (2026-11-13, M1 Max)

- **Assignment:** two fresh-context developer agents in parallel, each in its own temporary git
  worktree under the session scratchpad (outside Syncthing), because the harness compiles one
  module and concurrent edits in one checkout would break each other's runs. Coordinator reviewed
  both diffs, committed each on its temp branch, cherry-picked onto `fix/hud-live-remediation`,
  resolved the expected list conflicts (`Package.swift`, harness script, harness note), then
  removed both worktrees and branches after verifying full content carry-over.
- **R1 (`b7db89d`):** `Services/RuntimeTrustMonitor.swift` + 12 tests. `@MainActor`; `start(onLoss:)`
  (no reason argument; `lossReason` exposed afterwards), `stop()`, `trustReadIsFalse`,
  `requestProbe(reason:) async -> Bool` (concurrent requests share one probe). Constants: trust read
  0.5 s, backstop probe 5 s, probe deadline 1 s, notification coalescing 0.1 s trailing. Monitor
  stops itself before the loss callback; never re-arms. OSLog `com.xpycode.MousePlus`/`RuntimeSafety`.
  Coordinator corrections: probe comment no longer claims the throwaway tap is never enabled;
  `DarwinTCCNotificationSource.name` made `nonisolated` (deinit isolation warning).
- **R2 (`1c2c24c`):** `Services/InputTapRegistry.swift` (`InputTapDisableReason`, `InputTapHandle`,
  `SystemEventTapHandle`, `InputTapFactory`, `InputTapRegistry.shared`, synchronous idempotent
  `teardownAll()`). Mouse/keyboard monitors and keystroke recorder: disable clears pressed state,
  cancels, reports `onDisabled(reason)`, never re-enables; explicit `resume()`; keyboard NSEvent
  fallback deleted, install failure reports `onInstallFailed`. `TriggerService` forwards faults,
  yields `.cancel` for held sources on disable and on `stop()` (stop-yield is an addition beyond the
  spec), `updateConfig` keeps a stopped service stopped. `TriggerRecorderService` NSEvent seam +
  `teardown()` clearing static flags; `KeystrokeCaptureRecorder.teardown()`. Tests split:
  `KeystrokeCaptureEditorTests` (AppDelegate/editor, app-hosted only). Both R0 exclusions
  re-admitted; `SKIPPED_TESTS` removed. One assertion in `HUDTriggerRoutingTests.swift` (outside
  ownership) updated so it compiles against the new `.tapDisabled(reason)`; no behaviour change.
- **Validation (coordinator, integrated tree):** `scripts/test-input-safety.sh --all` →
  `Executed 93 tests, with 0 failures`. `xcodebuild -workspace 01_Project/MousePlus.xcworkspace
  -scheme MousePlus -configuration Debug -derivedDataPath build/wave2-build-check build-for-testing`
  → `TEST BUILD SUCCEEDED`, no warnings in touched files; app-hosted tests compiled, not run. No
  launch, no handoff. Xcode uses synchronized folders, so no project membership edits were needed.
- **Carried to R3:** wire `triggerService.onDisabled`/`onInstallFailed` to the monitor
  (probe-then-resume or loss, burst rule); loss path must call `InputTapRegistry.shared.teardownAll()`
  **and** `triggerService.stop()` plus both recorder `teardown()`s — after `teardownAll()` alone the
  service still believes it is running and a configuration change would install new taps. The
  `.cancel` yielded by `stop()` arrives asynchronously, so suspended `handleTriggerEvent` must
  ignore it safely. The monitor does no trust check inside `start`; the first read is at 0.5 s.
- **Carried to R5 review:** (1) the probe tap is enabled from `tapCreate` until invalidation
  (microseconds; `otherMouseUp` only) — assess whether that window matters; (2)
  `DarwinTCCNotificationSource` hands a raw pointer to a main-queue block, so a notification queued
  just before the source is released could touch freed memory (the monitor owns the source for its
  lifetime); (3) `SystemEventTapHandle` create/invalidate is verified by reading only; (4)
  `SystemKeystrokeCaptureTap.stop()` can run from inside its own callback on disable; (5) whether
  `TriggerService.stop()` should yield `.cancel`.
- **Commit:** R1 and R2 as separate commits (above); plan/state update committed separately.
  Not pushed (push not authorized for this wave).
- **Next:** Wave 3, R3 (single task; owns `MousePlusApp.swift`).

### Wave 1 — R0 (2026-11-13, M1 Max)

- **Assignment:** one fresh-context developer agent (single-task wave); coordinator reviewed the
  diff and reran every check itself.
- **Created (untracked):** `01_Project/Package.swift` (module `MousePlus`, tools 6.0, Swift 5 mode,
  macOS 14, explicit in-place sources, no copies/stubs, no package dependencies),
  `scripts/test-input-safety.sh` (`--all`, `--suite`, `--list`; scratch, cache, config, security
  and clang module cache under `build/test-input-safety/`), coverage note
  [`docs/testing/input-safety-harness.md`](../testing/input-safety-harness.md). No existing file edited.
- **Module closure:** 12 Models files, `HUDColorResolver`, `HUDMotionPolicy`, `RadialGeometry`,
  `MouseButtonTriggerMonitor`, `TriggerRecorderService`. Suites: ActionTypeCoding (4),
  HUDColorResolver (7), HUDCustomizationCoding (8), HUDMotionPolicy (4), KeystrokePayloadCoding (7),
  MouseButtonTriggerMonitor (3 of 5), RadialGeometry (10).
- **Validation (coordinator):** `scripts/test-input-safety.sh --all` → `Executed 43 tests, with 0
  failures`; both skipped tests absent from the log; no `01_Project/.build` or `.swiftpm`.
  `xcodebuild -workspace 01_Project/MousePlus.xcworkspace -scheme MousePlus -configuration Debug
  -derivedDataPath build/r0-build-check build` (Xcode 27.2, 27B5019j) → `BUILD SUCCEEDED`, no
  `Package.swift` mention in the log; `git status` unchanged by the build. Build only: no launch,
  no handoff. A first attempt exited 137 with no output before compiling and did not recur on retry.
  Isolated derived-data path chosen so a DerivedData copy the user may run is not replaced.
- **Safety inspection:** included tests have no setUp/tearDown; no live tap, CGEvent posting,
  Accessibility prompt, UserDefaults, Application Support, pasteboard or process use. The two
  `TriggerRecorderService.record` tests (live NSEvent monitors) are compiled but `--skip`ped.
- **Exclusions handed to later tasks:** `KeystrokeCaptureRecorderTests` (references `AppDelegate`
  and SwiftUI/MacUIKitSettings editor types; R2 owns this file and must split or seam it);
  `HUDTriggerRoutingTests`, `KeyboardTriggerMonitor` and `TriggerService` closure not yet in the
  harness (R2 adds them). Note for R2: `testReenablesTapAndStopsCleanly` encodes today's silent
  re-enable and must change with the "no silent re-enable" criterion.
- **Commit exception:** not committed. The manifest lists files that are untracked or modified in
  the uncommitted tree (for example `MouseButtonTriggerMonitorTests.swift`), so an R0-only commit on
  `HEAD` would not build. It belongs with the G1 checkpoint.
- **Next:** Wave 2. R1 ready (new files only). R2 blocked on G1 (user: checkpoint commit and
  merge/rebase of `origin/main`, or proceed dirty knowingly).

### Planning

Planning, revision 1: code-audit, panel-review and web-research agents; independent document review.
Planning, revision 2 (2026-11-13): plan review with three agents (source-claim and coverage audit,
platform research, harness feasibility) plus direct reads of the trigger, tap, dismissal, panel and
launch source. Four primary sources re-read directly. Dependency and ownership check: no cycles,
no shared ownership inside a wave, G1 and E1 gates named. Document work only.
