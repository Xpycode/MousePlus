# Permission-loss remediation — Wave 4 report (R4 validation, R5 review)

**Date:** 2026-11-13, M1 Max. **Plan:** [permission-loss-implementation.md](permission-loss-implementation.md).
**Tree:** `fix/hud-live-remediation` at `7b91e39` (R3 code `4898e28`), clean.
Report-only wave: no source edits, no launch, no app-hosted tests.

## R4 — full headless matrix and authoritative build

- `scripts/test-input-safety.sh --all` → exit 0, `Executed 117 tests, with 0 failures`. 14 suites
  passed: ActionTypeCoding, HUDColorResolver, HUDCustomizationCoding, HUDMotionPolicy,
  InputTapRegistry, KeyboardTriggerMonitor, KeystrokeCaptureRecorder (headless subset),
  KeystrokePayloadCoding, MouseButtonTriggerMonitor, RadialGeometry, RuntimeSafetyCoordinator (24),
  RuntimeTrustMonitor (12), TriggerRecorderService, TriggerService. Log: `build/wave4/harness-all.log`.
- `xcodebuild -workspace 01_Project/MousePlus.xcworkspace -scheme MousePlus -configuration Debug
  -derivedDataPath build/wave4-build-check build` → exit 0, `BUILD SUCCEEDED`, no warnings in the
  touched files. No shell-script build phases in the project. Log: `build/wave4/xcodebuild.log`.
- Artifact (not launched, not handed off):
  `/Users/sim/ProgrammingProjects/1-macOS/MousePlus/build/wave4-build-check/Build/Products/Debug/MousePlus.app`,
  `com.xpycode.MousePlus` 0.1.0 (1), team `FDMSRXXN73`.
- Observed, not touched: the running MousePlus process is the older
  `build/mouse-trigger-20261110/Release/MousePlus.app`, which predates this fix.

### Related regressions not covered by the harness (gaps, no app-hosted substitution)

| Suite | Why not headless today |
|---|---|
| TriggerOnboardingGuidanceTests, TriggerOnboardingPolicyTests, PostEventPermissionsStateTests | Reference only their own types; candidates for cheap admission (closure not yet audited) |
| HUDTriggerRoutingTests | Needs ConfigurationService, SettingsWorkspaceCoordinator closure |
| TriggerOnboardingIntegrationTests, TriggerOnboardingLaunchTests, ApplicationLifecycleAccessTests, DismissMonitorTests, KeystrokeCaptureEditorTests | Reference `AppDelegate` (shares a file with `@main`) |
| KeystrokeShortcutKitAdapterTests | Imports ShortcutKit (manifest has no package dependencies) |
| MousePlusTests (keystroke permission tests) and the other ~25 suites | Not audited for headless closure |

## R5 — independent lifecycle review

Fresh-context reviewer agent, read-only. Coordinator spot-checked S1 and S2 against source.
**Verdict:** no blocker. Only two `CGEvent.tapCreate` sites exist (`SystemEventTapHandle.create`,
the trust probe); every live tap is registered, torn down on loss and refused after seal. No path
was found that creates or re-enables a tap, or shows the HUD, while latched (Settings save,
permission grant, flush-time live apply, tap callbacks, queued main-queue work, `resume()` paths).
Every loss entry reaches `handleLoss`, which tears down before its first `await`; single-fire holds.

### Findings → R6

| ID | Severity | Where | Finding | Proposed fix / test |
|---|---|---|---|---|
| S1 | should-fix (OS behaviour unverified) | `InputTapRegistry.swift:131-139`, `:54-64` | `teardownAll` calls `tapEnable(false)` (WindowServer IPC) twice per handle before `CFMachPortInvalidate`. If that IPC blocks while WindowServer is wedged, later taps are never invalidated. | Two-pass teardown: remove sources and invalidate every port first, drop or defer `tapEnable(false)`. `InputTapRegistryTests`: call-order fake. |
| S2 | should-fix | `RuntimeSafetyCoordinator.swift:114-138` | Hung flush or `openApplication` completion strands the process in `.relaunching` with no timeout (safe, no taps, but stuck). | Deadline around flush and launch; on expiry suspend, restore timestamp on launch timeout. Coordinator tests with never-completing effects. |
| S3 | should-fix | `MousePlusApp.swift:504, 562, 572, 868` | The four AppDelegate latch guards are the only barrier against re-arming after loss and are untested. | Injectable coordinator plus read-only probes; latched-only tests (app-hosted file; no headless home today). |
| N1 | note | `MousePlusApp.swift:567` | Monitoring starts only from `applyRuntimeConfiguration`; a recorder tap can exist with no passive sensing if config load failed. | Start monitoring at end of launch or on first registration. Low priority. |
| N2 | note | coordinator | Loss with zero live taps still relaunches. | Reviewer recommends leaving as is. |
| N3 | note | `RuntimeTrustMonitor` | Notification path waits 100 ms + probe; an immediate `trustTick()` on notification is a free speed-up. | Optional. |
| N4 | note (OS behaviour unverified) | `RuntimeTrustMonitor` probe | A nil probe while trusted (inactive session, fast user switching) would loop one relaunch per 60 s. | Require probe false **and** trust read false on backstop/notification paths; keep probe-only for fault-routed paths. `RuntimeTrustMonitorTests`. |
| N5 | note | probe | Probe is not seal-gated (harmless; invalidated at once). | One-line guard. |
| N6 | note | `RuntimeSafetyCoordinator.swift:128` | Timestamp write right before terminate. | Optional `synchronize()`. |
| N7 | note | `MouseButtonTriggerMonitor` / `SystemKeystrokeCaptureTap` callbacks | `stop()` nils `handler` while it executes; safe in practice, not by contract. | Bind `let h = tap.handler` before calling. |

### Carried-concern dispositions

- (a) Probe tap live from create to invalidate: accept (microseconds, every 5 s, `otherMouseUp` only).
- (b) Raw pointer in the Darwin notification block: real but low (source lives as long as
  `AppDelegate`); fix with a weak box if the file is touched.
- (c) `SystemEventTapHandle` create/invalidate: correct and idempotent; ordering is S1.
- (d) `stop()` inside own callback: safe in practice; N7.
- (e) `TriggerService.stop()` yielding `.cancel`: keep (dropped by the latch during loss).
- (f) Recorder disable while not recording: moot; a recorder tap exists only while recording.
- (g) Rate-limited loss leaves only menu-bar Restart: acceptable for safety; UX gap.
- (h) Permanent seal: accept, by design.
- (i) AppDelegate guards untested: S3.

### Deferred revision-1 items

- **Generation counters:** keep deferred. Disable clears pressed state and yields `.cancel`; stale
  `.up` needs `isPressed`; loss drops queued events via the latch. No surviving scenario found.
- **Pending-action cancellation:** keep deferred. A committed action finishing after loss was
  user-intended and fails harmlessly without trust; it creates no tap.
- **Dismissal-monitor readiness:** keep deferred. Passive NSEvent monitors, closed by `closeRing`.
- **Settings banner rewording:** keep deferred. Reviewer suggests a later status-item cue when
  latched ("paused: permission lost, choose Restart"); that is new UI and needs the UI-changes
  protocol and user approval, so it goes to the backlog, not R6.

Production wiring (Darwin source, scheduler, `probeNow`, registry handle) remains fakes-only and
unverified under real revocation (E1).
