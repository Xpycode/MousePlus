# First-Run Trigger Onboarding

**Status:** Implemented and automatically validated; signed live acceptance pending
**Created:** 2026-09-26
**Last Updated:** 2026-09-26

**Planning:** [Implementation plan](../docs/plans/first-run-trigger-onboarding-implementation.md)
prepared after the user's request to continue. The subsequent request to execute authorizes the
proposed flow and scope; no separate preference answers were received.

## Problem Statement

New users receive no ring trigger by design. Permission onboarding currently ends with
“Open Settings,” which opens the default General pane rather than Triggers. When Accessibility
is already granted, startup does not present setup at all. A new user can therefore launch
MousePlus successfully without learning how to open its ring.

This affects clean installs and existing installations with no configured ring trigger.
Today users must discover Settings → Triggers and record a binding themselves.

## Proposed Solution

Guide users from permission setup directly to the existing trigger recorder, then explain how
to try their saved trigger. Retain the existing decision to ship without a default ring trigger.

### Key capabilities

1. Decide whether setup is needed only after configuration loading finishes.
2. Open Settings → Triggers when permission is granted and no ring trigger is configured.
3. Explain recording and hold-release/tap-toggle using the existing controls and persistence path.
4. Distinguish a saved binding from a trigger that the user has actually tried successfully.
5. Allow closing setup and returning through the menu-bar Settings command or configured Settings shortcut.

### Proposed user flow

1. Launch and load configuration. If Accessibility is missing, show the existing permission window.
2. After permission is granted, “Choose a Trigger” opens Settings with Triggers selected when
   no ring binding exists. Existing configured users retain a normal route back to Settings.
3. At the top of Triggers, below permission notices and above “Keyboard Trigger,” show
   “Choose how to open MousePlus” with concise guidance to record a keyboard shortcut or mouse button.
   Keep the existing recorder rows and mode controls; do not introduce a second recorder.
4. After a successful save/live apply, show the selected binding and mode-specific instructions
   in the same guidance area. Ask the user to try it over another app, keeping the pointer away
   from actionable slices, and press Escape to dismiss. Recording alone is not described as a
   successful real-world trigger test.
5. Closing Settings leaves the app available from its menu-bar icon. Proposed policy: if all ring
   bindings are still empty, show setup again on the next launch, at most once per launch.
   If a ring binding exists, do not automatically reopen trigger setup.

The default Open Settings shortcut remains ⌥⌘,; help must reflect a customized or cleared binding
rather than promise that this default always works. Global HUD and Open Settings rows remain
available but are not required steps for a new user.

## Acceptance Criteria

Implementation and automated evidence are recorded in the linked plan. The end-to-end product
criteria below remain unchecked until signed live acceptance; test results do not establish real
permission, physical input, or accessibility behavior.

### Core functionality

- [ ] Given no configuration file and no Accessibility grant, when MousePlus launches, then the
  permission window appears and no default ring binding is assigned.
- [ ] Given permission onboarding and no saved ring trigger, when permission is granted and the
  user continues, then Settings opens with Triggers selected and recording guidance visible.
- [ ] Given Accessibility is already granted and all ring bindings are empty, when configuration
  finishes loading at launch, then Settings → Triggers opens once with setup guidance.
- [ ] Given an existing ring binding, when configuration loads at launch, then trigger setup
  does not automatically open and the binding and selected mode remain unchanged.
- [ ] Given a recorded keyboard or mouse binding, when saving succeeds, then the normal runtime
  receives the saved configuration and the guidance explains how to try that binding's mode.
- [ ] Given a saved trigger and permission, when the user invokes it over another app and then
  presses Escape without selecting an action, then the ring opens and dismisses without executing an action.
- [ ] Given a saved trigger, when the app relaunches, then the same binding and mode remain usable.

### Edge cases

- [ ] Given a slow configuration load containing a saved trigger, when startup begins, then
  temporary default values do not cause an incorrect setup window to open.
- [ ] Given only a valid Global HUD shortcut is configured, when startup evaluates setup, then
  the app treats that shortcut as a ring entry point; Open Settings alone does not qualify.
- [ ] Given recording is cancelled or times out, when the recorder returns, then existing
  bindings remain unchanged and setup does not report success.
- [ ] Given a mouse button intercepted by other software, when recording times out, then the
  existing interception guidance remains available and the user can choose keyboard recording.
- [ ] Given setup was closed without recording, when the user opens Settings from the menu bar,
  then Triggers remains accessible; on the next launch the proposed setup reminder returns.
- [ ] Given the last ring trigger is cleared deliberately, when the edit saves, then the empty-state
  guidance returns in Triggers without opening another window during that session.
- [ ] Given a configured user whose permission was revoked, when permission is restored, then
  saved bindings remain intact and the user is not required to record them again.

### Error and accessibility states

- [ ] Given unreadable or malformed existing configuration, when startup loading fails, then the
  app exposes a recovery/error state instead of treating it as a clean install or saving defaults over it.
- [ ] Given a failed save, when recording completes, then the UI does not claim the trigger is
  saved or ready; retry uses the existing coordinator error and close-barrier behavior.
- [ ] Given keyboard navigation, when the user traverses setup, then guidance, recorder controls,
  selected binding, and mode have understandable labels and focus order.

VoiceOver live acceptance for this onboarding flow is deferred by user request on 2026-09-27.
It remains untested and is tracked in `docs/TASKS.md` for a later accessibility pass.
- [ ] Given permission remains denied, when setup is closed or revisited, then it does not
  claim readiness or repeatedly issue permission prompts from render/poll callbacks.

## Technical Considerations

### Existing wiring and proposed placement

| Location | Existing behavior | Proposed change |
|---|---|---|
| `01_Project/MousePlus/Views/TriggersSettingsView.swift`, `body`, before Keyboard Trigger (currently line 61) | Recorder outcomes feed `coordinator.edit([.triggers])`; Record/Clear use AppKit wrappers | Add conditional setup guidance after permission notices; reuse rows, collision validation, and modes |
| `01_Project/MousePlus/Views/PermissionOnboardingView.swift`, `grantedState` (currently line 56) | “Open Settings” invokes `onDone` | For unconfigured users, label the next step “Choose a Trigger”; use native AppKit wrappers for touched controls |
| `01_Project/MousePlus/MousePlusApp.swift`, app settings selection and delegate launch/load paths | Defaults to General; configuration loads asynchronously; permission completion calls generic Settings opening | Add an explicit Triggers route and evaluate setup only after a successful load; handle permission/config arrival in either order |
| `01_Project/MousePlus/ViewModels/SettingsWorkspaceCoordinator.swift` | Serialized save, error state, close barrier, live apply after successful persistence | Reuse as the sole writer for recorded triggers; do not create an onboarding writer |

Use `ConfigurationService.loadResult()` to distinguish a missing file from an unreadable existing
file. Do not infer a clean install from `try?` falling back to in-memory defaults. Define readiness
from valid supported ring bindings, not the Settings shortcut or a separate “onboarding complete”
flag. The precise predicate and error presentation must be established in the implementation plan.

Use the existing permission service and monitor lifecycle. This feature must not add a new
permission requirement, start duplicate monitors, or request keystroke-posting permission merely
to finish trigger setup. Handle startup routing once per launch and preserve the app's no-Dock-icon
behavior. Do not refactor general HUD invocation behavior as part of onboarding.

All new or changed interactive controls use AppKit wrappers under the project conventions.
The current permission view contains SwiftUI Buttons; replacements for touched controls belong
in implementation scope. The Triggers pane already provides appropriate native controls.

### Validation scope

During implementation, test startup ordering, setup eligibility, saved/failed state transitions,
and routing. Reuse trigger/coordinator coverage for recording and persistence; add regression
coverage only where this flow changes behavior. Run the authoritative Debug build and relevant
tests, followed by signed live checks for clean-install setup, already-granted permission,
keyboard/mouse recording, cancellation, relaunch, and accessibility. Use isolated configuration
fixtures and a deliberate signed acceptance environment; do not erase the user's production
configuration or reset system permissions as routine test setup.

## Out of Scope

- Assigning a default ring shortcut or changing trigger semantics.
- A separate multi-page wizard, automated tutorial ring, or persisted tutorial-completion tracking.
- Global detection of shortcuts owned by other applications.
- New HID++ support, vendor remapping integrations, or broader device compatibility work.
- Menu/action onboarding, public release packaging, or broad configuration-recovery redesign.
- Requiring action execution or keystroke posting to prove a ring trigger works.

## Open Questions

| Question | Status | Proposed answer |
|---|---|---|
| Keep no default ring trigger? | Resolved by existing decision and execution scope | Yes; preserve the 2026-04-29 D1 decision unless explicitly changed |
| Placement and flow? | Resolved by execution scope | Existing Settings → Triggers guidance, following permission setup |
| Repeat setup on launch after closing with no trigger? | Resolved by execution scope | Yes, once per launch; no persistent skip flag in v1 |
| Must in-app tutorial completion be tracked? | Resolved by execution scope | No; successful save enables usage instructions, real trigger testing is a live acceptance check |

## Related

- [Project state](../docs/PROJECT_STATE.md)
- [Trigger model and persistence decisions](../docs/decisions.md)
- [Current task tracker](../docs/TASKS.md)
