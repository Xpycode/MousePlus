# First-run trigger onboarding — live acceptance

**Status:** Fresh-install testing deferred by the user on November 7. Remaining
configured-account E1 checks await evidence. Daily-account remediation
was accepted November 7 and does not establish fresh-install/permission behavior.

**Current candidate (November 7):** `/private/tmp/MousePlus-onboarding-20261107/MousePlus.app`,
version 0.1.0 (1), copied from the user-accepted fixed-header Release build.
Current GUI-only instructions: `/private/tmp/MousePlus-onboarding-20261107/READ-ME-FIRST.txt`.
The September preflight below is historical evidence, not the current candidate.

**Original September candidate (historical):** `/private/tmp/MousePlus-onboarding-20260926/MousePlus.app`.
Developer ID team `FDMSRXXN73`; strict deep signature verification passed, hardened runtime enabled.
Debug and Release builds passed on macOS 27.2 (arm64). Candidate not installed or launched;
production app remains running. A separate live test environment has not yet been selected.

**Preflight on 2026-09-27 (M4 Pro MacBook Pro, macOS 27.2):** The staged candidate is
`com.xpycode.MousePlus`, version 0.1.0 (1), arm64, Developer ID team `FDMSRXXN73`, with
hardened runtime. Strict deep signature verification outside the tool sandbox passed: valid on
disk and satisfies its designated requirement. Verification inside the sandbox reported
`CSSMERR_TP_NOT_TRUSTED`; the unrestricted check resolved that discrepancy. The candidate has
not been launched here. The current account has an existing MousePlus configuration, so the
fresh-configuration checks need an isolation method; a separate account is one option.
Input hardware and initial Accessibility state remain to be recorded in the live session.

**GUI-only test-account handoff:** `READ-ME-FIRST.txt` is beside the staged app in
`/private/tmp/MousePlus-onboarding-20260926/`. Its maintained source is
[first-run-trigger-onboarding-test-account-handoff.md](first-run-trigger-onboarding-test-account-handoff.md).
The test account does not need Codex or access to this repository. Results return through
`/Users/Shared/MousePlus-onboarding-results.txt` and are not accepted until reviewed here.

Use the signed candidate after automated validation and review. Record the app path, version,
signature identity, Mac/macOS version, input hardware, configuration isolation method, and
permission state before testing. Preserve the daily-use installation and its configuration.
For a genuinely fresh permission grant, use a separate test account/environment; do not reset
the production Accessibility database.

| Scenario | Expected result | Result / evidence |
|---|---|---|
| Fresh configuration, Accessibility absent | Permission setup appears; no ring shortcut is silently assigned | Deferred by user, 2026-11-07; untested |
| Grant permission, then continue | Triggers pane opens with recording guidance; one setup window flow | Deferred with fresh-install testing, 2026-11-07; untested |
| Fresh configuration, Accessibility already granted | Triggers opens directly after load | Deferred by user, 2026-11-07; untested |
| Existing ring trigger on launch | No automatic trigger setup; binding/mode preserved | PASS — user report 2026-11-07 after configured relaunch; no onboarding, binding/mode unchanged |
| Record keyboard shortcut | Saved binding appears with correct mode instructions | PASS — user report 2026-11-08: re-recorded existing shortcut using keyboard; binding displayed, mode unchanged, guidance matches |
| Record supported physical mouse button | Saved binding appears; direct device route identified | PASS after fix — November 10 user confirms direct mouse trigger works in Warp after consuming-tap build; prior tab-switch leak resolved. Exact button number and mode unspecified. |
| Cancel recording / timeout | Old binding retained; timeout recovery guidance remains accessible | PASS — user reports 2026-11-07: mouse-recorder timeout preserves binding and shows recovery guidance; keyboard recording cancels with Escape, retaining binding/mode and working trigger. |
| Hold-release over another app | Ring opens on hold; Escape cancels before release without executing an action | PASS — user report 2026-11-08 over Finder via BetterMouse-to-keyboard |
| Tap-toggle over another app | Ring opens on tap; Escape dismisses without action | PASS — user report 2026-11-08 over Finder via BetterMouse-to-keyboard |
| Close with no trigger, relaunch | No immediate reopening loop; setup returns on next launch | Deferred with fresh-install testing, 2026-11-07; untested |
| Save and relaunch | Same binding/mode works across apps | PASS — configured relaunch PASS by user report 2026-11-07: existing binding/mode preserved and works over Finder, Escape dismisses. November 8: re-recorded existing shortcut and BetterMouse invocation/Escape in another app passed (app unspecified). November 10: changed-binding relaunch persistence PASS by user report: different shortcut opened the HUD before and after normal quit/reopen, and binding/mode were retained. |
| Restore permission for configured user | Existing bindings remain; no forced re-recording | FAIL — 2026-11-13: revoking permission still allowed direct mouse HUD invocation; outside-click dismissal failed, followed by broad input unresponsiveness after hiding. Exposé restored clicking. Reproduced by user; permission now ON. Do not repeat on daily account. Cause of system-wide symptoms not yet established. |
| Customized/cleared Settings shortcut | Guidance describes actual route; menu-bar access remains | PASS — user report 2026-11-10 for no-shortcut guidance and reopening through menu-bar Settings; whether shortcut was already empty or cleared was unspecified |
| Keyboard navigation | Controls and status readable; focus order usable; native button activation and Escape preserved | PASS — user PASS 2026-11-07 for visible Tab/Shift-Tab focus order, Space activating Record, Escape cancellation and unchanged working binding/mode. November 10: Return does not start Record; Space does. Record uses an ordinary NSButton with no Return default action; expected native behavior, prior Return-to-record instruction was incorrect. |

**Deferred by user request on 2026-09-27:** VoiceOver live acceptance for onboarding is not an
E1 completion gate. Its labels, focus order, and operability remain untested and are tracked in
`docs/TASKS.md` for a later accessibility pass. Do not describe them as passed.

Do not count BetterMouse-to-keyboard success as direct physical mouse coverage. If a button is
intercepted, verify the warning and keyboard fallback and record that device path as unverified.
Actual action execution and keystroke-posting permission are not prerequisites for ring setup.

Overall completion remains blocked until every required row passes or the user explicitly changes
the acceptance scope. Record failures concretely and route fixes back to the active implementation plan.

## November 7 continuation boundary

User chose “Defer fresh-install testing.” No fresh-account or permission checks were run.
The current candidate is staged with GUI-only instructions for later use; strict deep
signature verification passed and its executable SHA-256 matches the accepted source build.
No daily configuration or permission changes were made. Remaining configured-account
checks are independent: current trigger invocation/Escape, recording cancellation/timeout,
configured relaunch persistence and keyboard navigation. Direct physical mouse input and
permission restoration remain unverified; do not infer passes from earlier menu-item recorder checks.

## Current-trigger acceptance — November 7

User reported PASS for: activate Finder, invoke the ring with the usual configured trigger,
keep the pointer in the center, and press Escape (before release if using hold-release).
The ring dismissed without executing an action. This verifies the user's current route/mode;
the input device and mode were not identified, so do not count this as both-mode or direct
physical-mouse coverage. Remaining next check: trigger-recorder cancellation and timeout,
then configured relaunch persistence and keyboard navigation. Fresh-install rows stay deferred.

## Mouse-recorder timeout acceptance — November 7

User reported PASS after starting mouse-button recording and waiting about four seconds
without input: recording stopped, previous binding remained unchanged, recovery guidance
appeared, and the usual trigger still opened the ring with Escape dismissal. This does not
establish physical mouse capture or cancellation. Next: configured relaunch, then keyboard
navigation; cancellation still needs confirmation. E1 remains open and deferrals unchanged.

## Configured-relaunch acceptance — November 7

User reported PASS after normal quit and reopening the specified title-header Release
artifact: no onboarding appeared, existing binding/mode remained unchanged, and the usual
trigger worked over Finder with Escape dismissal. This confirms existing-configuration
relaunch; it does not establish a newly recorded binding or additional app/device coverage.
Next: keyboard navigation. Cancellation remains unconfirmed; E1 remains open.

## Keyboard navigation and cancellation — November 7

User reported “Otherwise pass” for visible Tab/Shift-Tab focus, Space activation of
keyboard Record, Escape cancellation, retained binding/mode and working usual trigger.
Return behavior was not part of that batch. Separately reported Settings header/sidebar
color mismatch and inability to drag the Settings window; those chrome defects require
remediation and fresh visual/drag acceptance, without invalidating the trigger evidence.

## Settings chrome acceptance — November 8

The corrected MousePlus screenshot confirms continuous sidebar color behind the traffic
lights and centered content-pane title. User explicitly confirmed title-area dragging
works. Chrome remediation is accepted. Earlier unrelated app screenshots are not evidence
for MousePlus. This closes the chrome defects only; E1 and its existing deferrals remain.

## Both trigger modes — November 8

User reported “both pass” for Hold-release and Tap-toggle over Finder, with Escape
dismissal and no action execution. Input route was not supplied; direct physical mouse
coverage is not inferred. The instructions included restoring the original mode. E1
remains open, with fresh-install and VoiceOver deferrals unchanged.

November 8 route clarification: user confirmed BetterMouse mapping for both-mode
acceptance. These passes cover BetterMouse-to-keyboard, not direct physical mouse capture.

## Keyboard recording and additional app — November 8

User reported PASS for re-recording the existing keyboard shortcut using physical keys,
seeing the saved binding with unchanged mode and matching guidance, then invoking via
BetterMouse in another app and dismissing with Escape. The other app was not identified
(Safari was offered as an example). This does not prove changed-binding persistence after
relaunch or direct physical mouse capture. E1 remains open.

November 8 Global preview/tree follow-up: user reports PASS for Menu Items → Global
and editor/live ring parity in the profile-tree build. New-tree app-profile switching/
deletion was not exercised. Settings shortcut/menu-bar guidance remains unconfirmed.

## Settings access and drag recovery — November 10

User reported that moving works after the requested restart and that the Settings path
passes the no-shortcut/menu-bar guidance batch. No claim is made about a newly customized
shortcut. Dragging had recurred as a failure in the same latest build; restart recovery
does not establish a permanent fix. E1 remains open with existing deferrals preserved.

November 10 sidebar regression acceptance: user passed Safari creation, independent
label edit, Global/Safari switching and Safari deletion with correct Global fallback/
preview. Separate app-picker XPC/name presentation finding is being corrected.
