# Permission-loss and stuck-input remediation — Implementation Plan

**Created:** 2026-11-13
**Status:** Planned; execution not requested.
**Progress:** 0/7 implementation and verification tasks complete; external gate E1 open.
Unchecked tasks are pending unless explicitly blocked. This plan owns task status/evidence.

## Goal and evidence

When runtime permission or input infrastructure becomes unavailable, MousePlus must stop
intercepting input, cancel the HUD without executing a selection, and retain saved settings.
This mitigates confirmed lifecycle gaps; it does not establish or promise a cure for the
unexplained system-wide input failure reported on November 13.

Source journey: configured trigger → permission/capability check → live HUD → permission loss
or tap failure → suspended runtime, hidden HUD, cancelled capture, native input passed through.
Restored permission → Settings reports restart required → user quits/relaunches → fresh preflight
and fresh monitors. No restoration of a held gesture or replay of queued events.

Evidence: [investigation](permission-loss-investigation.md),
[original incident](../sessions/2026-11-13.md), and
[onboarding plan](first-run-trigger-onboarding-implementation.md).
Original onboarding E1 remains FAILED/open; its completed implementation is preserved.

## Scope and constraints

- Planning only authorized now. No source implementation, builds, tests, app control or commits
  were performed to prepare this plan. Preserve existing dirty source and documentation changes.
- No further live permission-toggle tests, on any account. VoiceOver excluded. Fresh-install
  acceptance remains deferred. No TCC reset, simulated physical input, competing-app installation,
  forced quit, focus manipulation or automatic restart.
- Proposed recovery policy: first runtime trust loss or event-tap disable latches suspension for
  this process. Do not automatically re-enable/recreate taps. Require a normal restart after
  permission restoration. A timeout is an infrastructure fault, not proof of permission denial;
  record its distinct reason. This deliberately trades availability for bounded recovery.
- Keep the existing first-grant onboarding flow. A grant after runtime suspension must not be
  mistaken for first grant. Configuration edits save normally but cannot restart suspended input.
- No new Input Monitoring permission request unless inspected API requirements establish necessity.
  AX trust, listen-event access, posting access and actual monitor installation are distinct facts.
- Keep existing menu-bar Settings/Quit routes; no new emergency global shortcut or watchdog helper.
  A main-run-loop timer cannot protect against a hung main thread; do not make that guarantee.

## Acceptance criteria

- Ongoing non-prompting trust observation catches loss after an initial grant, including with
  Settings closed. Proposed sampling interval: 500 ms while running, plus synchronous admission
  checks before starting monitors/HUD/capture. This is a target, not a real-time guarantee.
- Loss/fault sets suspension and advances a generation before teardown. Every old queued event,
  recorder completion and native release is rejected after suspension. Pending HUD actions whose
  external side effect has not begun are cancelled; already-started effects cannot be undone,
  and exact owned synthetic key-up cleanup remains best-effort.
- Teardown is idempotent: disable/invalidate owned taps, remove monitors, clear pressed ownership,
  cancel captures, invalidate native callbacks and hide/reset HUD without a commit.
- Events arriving after suspension pass through; no global release-all or synthetic replay of
  swallowed physical downs. Clear internal ownership even if a matching up never arrives.
- Synthetic keys already posted retain only their exact owned best-effort key-up cleanup;
  posting denial means delivery cannot be guaranteed. Never manufacture releases for other input.
- Restored permission/config-save/repeated callbacks cannot rearm in-process. Fresh launch with
  permission and valid config starts one set of monitors. Startup denial opens existing setup.
- Permission/fault status is consistent in Settings; existing menu-bar Settings/Quit remain usable.
- Fake-based validation and review pass; actual OS focus/input recovery remains unverified until
  suitable separately authorized evidence exists. No real revocation test is scheduled here.

## Interfaces and execution schedule

Paths below are under `01_Project/MousePlus/`; tests under `01_Project/MousePlusTests/`.
Coordinator owns tracking, build resources and any project membership changes. Builds/tests serial.
Use Directions `commands/execute.md` on later execution, with fresh agent task packets.

P1 establishes a shared runtime capability/suspension contract: reason, monotonic generation,
non-prompting snapshot, admission check, idempotent cancellation registration and effect ordering.
P2/P3 consume it without editing its implementation. Runtime cancellation registrations must be
released with their owners; callback lifetimes must not retain views or resurrect stopped sessions.
Permission polling cannot be stopped merely because an onboarding view disappears.

Dependency graph: P1 → {P2, P3} → P4 → {P5, P6} → P7 → E1.
P2/P3 and P5/P6 have disjoint ownership. Other waves are serial because they establish or integrate
shared contracts. No missing dependencies or cycles. E1 does not block implementation tasks.

## Tasks

### Wave 1 — shared safety boundary

- [ ] **P1: Runtime suspension policy and headless validation harness**
  - Depends on / external gates: none.
  - Owns: `Services/PermissionsService.swift`, new `Services/RuntimeInputSafety.swift`, new
    `RuntimeInputSafetyTests.swift`, proposed `scripts/test-input-safety.sh` and isolated harness
    manifest/fixtures. No application wiring yet.
  - Interface: injectable trust provider/clock, startup-waiting/running/suspended state, reason and
    generation, cancellation registry; distinguish restored trust from permission to resume.
  - Success: loss after grant, startup denied/granted, repeated transitions, delayed poll,
    cancellation ownership, teardown ordering and restart-only latch tested with fakes. Define
    production probe cost and callback-safe admission before P2/P3; no blocking prompt in a tap.
  - Backpressure: proposed `scripts/test-input-safety.sh --suite RuntimeInputSafetyTests`.
    Script must be created and inspected first; no such command is currently claimed to exist.
    Harness must compile real production sources with fake OS boundaries, isolated files/defaults,
    no app entry point, real taps, event posting, permission prompt or production configuration.

### Wave 2 — independent input and presentation outcomes

- [ ] **P2: Fail-open interception and capture cancellation**
  - Depends on: P1. External gates: none.
  - Owns: `Services/MouseButtonTriggerMonitor.swift`, `KeyboardTriggerMonitor.swift`,
    `KeystrokeCaptureRecorder.swift`, `TriggerRecorderService.swift`, `TriggerService.swift`;
    corresponding monitor/recorder/service test files, new tests where absent.
  - Interface: generation-tagged trigger delivery; stop clears ownership; configuration update
    does not implicitly restart suspended service; explicit fault callback with disable reason.
  - Success: loss between down/up, missing up, rebind, stale callbacks, failed tap installation,
    timeout/user-input disable and repeated stop all pass through safely and report cancellation.
    Preserve suppression of healthy matching down/up sequences. No automatic tap re-enable.
    Preserve original disable reason in the shared keyboard event representation.
  - Backpressure: harness suites for mouse/keyboard/trigger service and both recorders; include
    fakes delivering callbacks after stop and verifying zero re-enable/consume calls when suspended.

- [ ] **P3: Cancel HUD/native callbacks and pending input actions**
  - Depends on: P1. External gates: none.
  - Owns: `Controllers/RingWindowController.swift`, `Services/DismissMonitor.swift`,
    `ViewModels/RingViewModel.swift`, `Services/ActionService.swift`, `KeystrokeService.swift`,
    `CGEventPosting.swift`; corresponding dismissal/native-ownership/action/keystroke tests.
  - Interface: explicit cancel-without-commit, callback generation invalidation, monitor installation
    readiness/failure, pending HUD action cancellation; no changes to AppDelegate in this task.
    Safety cancellation must be distinct from ordinary commit-driven close, which must still
    execute its intended action. Paired tests: healthy commit closes then executes once; safety
    suspension before the external effect executes zero times.
  - Success: retained native callbacks cannot commit after hide; partial monitor install rolls back;
    cancel invalidates pending action launch before its external side effect. Recheck posting access
    after pre-delay and immediately before down; cancellation after owned down attempts only its up.
    Already executed external actions cannot be undone. Clear tracking/callback ownership before
    releasing the panel; do not add private focus APIs or global focus recovery hacks.
  - Backpressure: fake panel/monitor/action/poster tests for hide twice, callbacks after hide,
    denied posting, cancellation during both delays, and no commit on loss. Native AppKit focus
    behavior remains outside headless claims.

### Wave 3 — integrate runtime and existing recovery surface

- [ ] **P4: Wire one suspension lifecycle through launch, settings and all entry points**
  - Depends on: P2, P3. External gates: plan's proposed UI placement accepted before UI edits.
  - Owns: `MousePlusApp.swift`, `Views/TriggersSettingsView.swift`,
    `Views/MenuEditor/ActionDataEditor.swift`, `ViewModels/SettingsWorkspaceCoordinator.swift`,
    `Controllers/OnboardingWindowController.swift`, `Views/PermissionOnboardingView.swift`,
    `Utilities/TriggerOnboardingPolicy.swift`, `ViewModels/TestActionController.swift`;
    launch/onboarding/guidance/integration and TestActionController tests.
  - Interface: single app-owned runtime safety service injected into views/capture owners;
    saved configuration is independent of runtime admission. Keep first-run policy separate from
    suspension. Close via existing `closeRing`, never `hideRing(commitHovered: true)`.
  - Success: all contextual/global triggers, Settings shortcut, native commits, recorders and test
    actions honor admission. Queued streams and config-save callbacks cannot bypass the latch.
    Test Action revalidates admission/generation after awaiting configuration flush and immediately
    before an external effect. Ordinary Settings and Quit remain local routes. No recurring modal
    prompts or automatic restart.
  - Proposed UI: reuse `TriggersSettingsView.permissionBanner` (current line 219), shown from the
    top of its existing Form, with suspension/restart wording even after trust returns. Keep its
    AppKit Open System Settings button. Existing shared state supplies status; remove independent
    grant-only authority. No new control or pane. Before implementation confirm this placement per
    master `36_ui-changes-protocol.md`; backend P1–P3 are independent of this UI gate.
  - Backpressure: headless launch/save/race integration suites plus build command below.
    Audit Identify Input diagnostics for registration/stop; if it owns a separate long-lived input
    path, integrate its service/controller serially here and record exact added ownership.

### Wave 4 — independent regression and adversarial review

- [ ] **P5: Verify integrated fake fault matrix and authoritative build**
  - Depends on: P4. External gates: none for inspected headless checks/build-only operation.
  - Owns: new `RuntimeInputSafetyIntegrationTests.swift`; validation report/results only.
  - Success: loss at idle/visible HUD/held trigger/active capture/pending action; restoration,
    config save during suspension, repeated disable, late event and launch-order races covered.
    Run existing related onboarding, routing, persistence, recorder and keystroke regressions when
    safely supported by the harness. Record coverage gaps instead of substituting app-hosted tests.
  - Backpressure: `scripts/test-input-safety.sh --all` once implemented/inspected; authoritative
    `xcodebuild -workspace 01_Project/MousePlus.xcworkspace -scheme MousePlus -configuration Debug build`.
    Inspect startup/build hooks first per master `34_testing.md`. Existing XCTest target uses
    TEST_HOST, so ordinary `xcodebuild test` is not a headless substitute. No launch handoff as part
    of this plan's validation; app control remains separately scoped.

- [ ] **P6: Independent lifecycle and input-ownership review**
  - Depends on: P4. External gates: none.
  - Owns: review report only; source findings return to responsible task owner after parallel work.
  - Success: independently trace all input/action entry points, partial install, async generation
    checks, cancellation registry lifetimes, down/up semantics, recovery latch, poll limitations,
    configuration preservation and local Settings/Quit reachability. Classify root-cause hypotheses.
  - Backpressure: file-specific findings/dispositions and affected tests; no agreement-only pass.

### Wave 5 — close implementation evidence, preserve real-OS limit

- [ ] **P7: Resolve review findings and prepare bounded handoff**
  - Depends on: P5, P6. External gates: none.
  - Owns: serial corrective edits to prior task files, final validation/evidence/tracking.
  - Success: resolve material findings, rerun affected checks, document artifact identity and exact
    tested scope. Separate mitigation validated from broad-input root cause unknown. Do not mark
    onboarding E1 or this plan's E1 passed from fake events.
  - Backpressure: affected harness suites and build if source changed; evidence/links review.

## External acceptance

- [ ] **E1: Real macOS normal-operation and recovery evidence — blocked/deferred**
  - Depends on: P7; requires separately authorized user-operated acceptance and appropriate evidence.
  - Owns: acceptance report. Gates real OS focus/input recovery and overall incident closure.
  - A later finite non-toggle smoke batch may cover launch with permission already ON, one mouse
    invocation/dismissal, one keyboard invocation/dismissal, cancelled capture and Settings/Quit.
    Stop on the first abnormal input response. This is proposed scope, not a present instruction.
  - No permission toggles, VoiceOver or forced reproduction. Normal smoke cannot prove behavior
    under real TCC revocation. That claim remains explicitly unverified; no test-account loophole
    or automatic future permission request is scheduled. Existing failed onboarding row remains.
  - While unavailable: complete P1–P7 and retain exact automated limits; no claim of full fix.

## Execution log

No implementation assignments or validation passes yet. Planning used code-audit, panel-review
and web-research agents. Research evidence and disagreements are recorded in the investigation.

Planning review: independent reviewer identified ordinary-close cancellation, the Settings Test
Action flush race, and overly broad pending-action wording; all three were incorporated before
plan handoff. This was a document review, not implementation validation.
