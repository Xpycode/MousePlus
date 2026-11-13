# Permission loss and stuck input — investigation

2026-11-13. Read-only source investigation and primary-source web research with three agents:
input/runtime audit, independent panel/action review, and comparable-app research. No live tests,
permission changes, builds, source changes or app control. VoiceOver excluded.

## Findings and confidence

Confirmed in current source:

- `PermissionsService` is grant/onboarding oriented; polling ends on grant. AppDelegate and
  onboarding retain granted/runtime-applied state without a loss transition. Triggers Settings
  owns another service and forwards grants only.
- `TriggerService.stop()` does not clear active sources or invalidate buffered AsyncStream events.
  `updateConfig()` starts a stopped service. AppDelegate trigger dispatch/runtime config/HUD opening
  lack authoritative runtime admission. Stop alone therefore cannot establish suspension.
- Mouse and keyboard triggers and keystroke capture automatically re-enable disabled event taps.
  Shared keyboard capture events erase timeout versus user-input disable distinctions. Keyboard
  tap failure can fall back to local/global monitoring; suspension must prohibit that fallback.
- Existing tap teardown already disables/invalidates ports and removes sources; preserve it.
  View-owned trigger and action recorders require shared cancellation registration/injection.
- `DismissMonitor` considers any registration token sufficient and cannot report partial failure.
  `closeRing` is a useful non-committing cleanup path, but does not stop triggers or pending actions.
- `RingWindowController.hide()` orders out/releases references; native callbacks need explicit
  invalidation. No explicit modal session or focus capture was found. The floating nonactivating
  panel has `hidesOnDeactivate = false`; monitor failure can explain a stranded visible HUD.
- `RingViewModel.commitActive()` launches an untracked action task. Ordinary commit-driven close
  must allow its intended action; safety suspension needs a separate cancellation boundary.
- `KeystrokeService` preflights before a 50 ms delay. It already attempts matching synthetic key-up
  on cancellation after down. Preserve this limited cleanup; preflight is not delivery confirmation.

Not established: the broad cross-device input-loss root cause. The auxiliary mouse tap masks only
other-button events, not all keyboard/primary-click input. Exposé recovery does not prove panel,
TCC or WindowServer causality. No event trace establishes which path failed. Input starvation,
focus state and interrupted sequences remain hypotheses, not diagnoses.

## Comparable apps and platform sources

Sources inspected by research agent on 2026-11-13. Repository branch links can change; retain this
summary as scoped evidence, not a promise about all versions or a matching reproduction.

| Source | Observed evidence | Consequence for this plan |
|---|---|---|
| [Apple tapEnable](https://developer.apple.com/documentation/coregraphics/cgevent/tapenable(tap:enable:)) | Tap disable may follow unresponsiveness or a user request; re-enable is available. | Disable is not proof of revocation; preserve distinct reasons. Automatic re-enable is optional. |
| [Hammerspoon source](https://raw.githubusercontent.com/Hammerspoon/hammerspoon/master/extensions/eventtap/libeventtap.m) | Re-enables timeout/user-input disable; stop disables, invalidates and releases tap/source. Invalid callback ownership passes through, but Lua errors suppress events. | Reuse complete teardown principle, not unconditional re-enable or a claim of universal fail-open behavior. |
| [Hammerspoon documentation](https://www.hammerspoon.org/docs/hs.eventtap) | Secure Input prevents keyboard interception and has separate status. | Missing keyboard events alone do not diagnose TCC loss; never bypass Secure Input. |
| [Mac Mouse Fix issue 2065](https://github.com/noah-nuebling/mac-mouse-fix/issues/2065) | Open user report describes physical clicks suppressed while replacement posts are rejected; reporter proposes a circuit breaker. | Relevant failure pattern only: not confirmed shipped mitigation, maintainer diagnosis, or proof of MousePlus cause. |
| [BetterMouse official troubleshooting](https://better-mouse.com/) | Requires Accessibility, says Input Monitoring is unnecessary; discusses conflicts and permission troubleshooting. | No documented runtime-loss safeguard found. Do not import permission-reset/toggle instructions into this plan. |
| [Karabiner release notes](https://github.com/pqrs-org/Karabiner-Elements/releases) | 16.3.0 addresses stuck modifiers with CGEventTap fallback; 16.0.0 missed capture events; 15.7.0 pending modifier release. | Interrupted down/up sequences merit explicit tests. These are different bugs and architecture, not proof of a common cause. |
| [Karabiner architecture](https://github.com/pqrs-org/Karabiner-Elements/blob/main/DEVELOPMENT.md) | Capture, AX observation and privileged posting are separate operations. | Keep capabilities distinct; do not add a privileged helper or HID rewrite for this bounded fix. |
| [Apple listen preflight](https://developer.apple.com/documentation/coregraphics/cgpreflightlisteneventaccess()) and [post preflight](https://developer.apple.com/documentation/coregraphics/cgpreflightposteventaccess()) | Separate public capability APIs. | Neither establishes guaranteed immediate freshness or delivered-event acknowledgement. |

The comparison does not establish a universal macOS 27 fix. Preserve the user's reported
“Device Control and Data Access” UI wording; avoid depending on OS marketing labels in policy.

## Proposed engineering decisions

Use a single runtime safety boundary, generation invalidation and fail-open callbacks. Continue
non-prompting trust observation after startup. On detected trust loss, failed required installation
or disabled tap, latch suspension and cancel without committing. Restart after restoration is the
proposed recovery policy; do not silently rearm. This is our conservative design choice, not an
Apple requirement or a claim that every comparable app follows it.

No physical-event replay, global release-all, private focus APIs, automatic app relaunch or watchdog
helper. Only already-posted owned synthetic downs retain best-effort matching release. A main-thread
poll has scheduling limits and does not protect against main-thread hangs or stale OS trust state.

Review disagreements: the input audit suggested fresh monitor rebuilding on restoration as an
option. The selected proposal requires restart instead, reducing rearm races until real recovery
is established. The panel reviewer confirmed ordinary commit close must remain distinct from
permission-safety cancellation. No evidence supported speculative focus manipulation.

See [implementation plan](permission-loss-implementation.md) for task ownership and validation.

## Review addendum (2026-11-13)

Plan review with three agents and direct reads. Where this addendum conflicts with the text above,
the addendum holds. The engineering decisions above are superseded by plan revision 2.

**The failure is documented macOS behaviour.**

| Source | Evidence |
|---|---|
| [Apple Developer Forums 844416](https://developer.apple.com/forums/thread/844416), September 2026, FB24619068 | Session-level, head-insert, `.defaultTap` on the main run loop, callback returning every event unchanged. Disabling or deleting the Accessibility entry makes keyboard and mouse unresponsive system-wide on Sequoia, Tahoe and macOS 27. No tap-disabled callback observed first. Poster's log reading: WindowServer's post/listen check for the tap owner is denied and delivery stalls. Apple DTS asked for a sysdiagnose; no mechanism or supported handling given. |
| [Apple Developer Forums 735204](https://developer.apple.com/forums/thread/735204), 2023 | Default tap, permission turned off while running: "left & right click are blocked". Listen-only does not reproduce. `AXIsProcessTrusted()` "continues to return true" when the entry is removed instead of toggled; `CGPreflightPostEventAccess` does not update in a running process. DTS: "the best option there is to accept the quit and relaunch". Accepted workaround: probe by creating a throwaway default tap; nil means no access. |
| [alt-tab-macos `SystemPermissions.swift`](https://github.com/lwouis/alt-tab-macos/blob/master/src/macos/SystemPermissions.swift) | Triggered by Darwin notification `com.apple.tcc.access.changed`; notes that `AXIsProcessTrusted` answers from an in-process cache refreshed by a notification posted before tccd writes. On loss after startup: restarts itself. |
| [LinearMouse `GlobalEventTapWatchdog.swift`](https://github.com/linearmouse/linearmouse/blob/main/LinearMouse/EventTap/GlobalEventTapWatchdog.swift) | 10-second timer; throwaway default-tap probe on a utility queue because "permission APIs can report a cached grant after access has been revoked"; on failure restarts itself. |
| [Handy issue 1281](https://github.com/cjpais/Handy/issues/1281) | One report that quitting the owning process restores input immediately. Not independently confirmed. |

Read through a summarising fetcher, not byte-verified. Not found: source for Mac Mouse Fix, Loop,
Karabiner-Elements or Maccy revocation handling; any explanation of the Exposé recovery; any proof
that in-process teardown or relaunch always beats the hang.

**Corrections to the findings above.**

- "Not established: the broad cross-device input-loss root cause" no longer stands as written. The
  tap configuration at `MouseButtonTriggerMonitor.swift:24` and `KeystrokeCaptureRecorder.swift:131`
  matches the documented reproduction, and that reproduction does not depend on the event mask.
- The mask argument also omitted the keyboard taps. Up to three run at once (contextual trigger,
  global shortcut, Settings hotkey at `MousePlusApp.swift:819`), each seeing every key event.
- `PermissionsService` does observe a true-to-false flip while its poll is running
  (`PermissionsService.swift:41-43`); polling stops only on a false-to-true flip. Nothing acts on it.
- `KeyboardTriggerMonitor` does not re-enable a disabled tap while a shortcut is being recorded:
  the recording guard returns before the `.tapDisabled` case.
- Tap callbacks all run on the main run loop (`CFRunLoopGetMain()`), so there is no off-main
  callback race; the exposure is the delay before the loss is noticed.
- Input paths the original audit did not assign: `InputRecorderService`,
  `InputRecorderWindowController`, `Services/HID/IOHIDDeviceInspector.swift` (which calls
  `IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)`), `PostEventPermissionsState`.
- Remote packages `ShortcutKit` and `MacUIKitSettings` were not inspected for input code.
