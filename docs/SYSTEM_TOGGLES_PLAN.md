# System Toggles — Implementation Plan

**Status:** Planned (2026-09-04). HUD action track; last in the recommended build order
(`docs/HUD_ACTIONS_PLAN.md` §"Recommended build order" — most permission/UX surface of the five
actions). Ring-UI feature — does not depend on the HID++ decision (#17).

**Relationship to `docs/HUD_ACTIONS_PLAN.md`.** That doc specs this as **Feature D** (§233–273)
and already settles the hard research questions (which toggles are reliably doable without a
private API, exact mechanisms, permissions). This plan turns that spec into execute-ready phases.
**Unlike Feature A (menu mirror) and Feature C (app switcher), this feature needs none of the
shared §1.2/§1.3 machinery** (async dynamic `expand()`, `IconSource`) — every toggle is a
self-contained, one-shot action fired directly from a static inner-ring wedge, exactly like
`.sendKeystroke`/`.custom` today. It is the simplest of the four remaining actions to wire.

**Ground truth (verified 2026-09-04 — corrects the 2026-05-30 HUD plan sketch, which predates the
current `ActionService` shape):**
- `ActionType.systemToggle` already exists as a case (`Models/ActionType.swift`) but is routed to a
  no-op in `ActionService.execute`'s catch-all (`Services/ActionService.swift:121`:
  `case .menuBar, .systemToggle, .screenshot, .unavailable: return ActionExecutionResult(validation: validation)`).
  It is **not** in `ActionType.selectableCases`, so the editor cannot offer it yet either.
- `ActionService` is a DI-friendly `actor` composed of small injected protocols
  (`ActionProcessRunning`, `ActionWorkspace`, `ActionKeystrokeSending`, `ActionWindowSnapping` —
  `Services/ActionService.swift:14–90`), each backed by a `System*` production struct and a
  test double. **New toggle execution must follow this same protocol-injection pattern**, not a
  bespoke path — add `ActionSystemToggling` alongside the existing four.
- `PermissionsService` (`Services/PermissionsService.swift`) already owns the Accessibility (AX)
  TCC flow (`isGranted`, `promptAccessibility()`, `openAccessibilitySettings()`, `startPolling()`).
  Toggles needing AX (lock screen, per the HUD plan's CGEvent approach) **reuse this unchanged** —
  do not build a second permission flow.
- `SystemActionProcessRunner` (`Services/ActionService.swift:18–36`) already spawns `/bin/zsh -c
  <command>` for `.custom`. Toggles must **not** reuse this path for `osascript` calls — the HUD
  plan is explicit that `Process` → `/usr/bin/osascript` directly (no shell) is required so TCC
  attributes the Automation prompt correctly and no shell-injection surface is introduced by
  string-interpolating toggle arguments into a `zsh -c` command.
- `KeystrokeService`/`ActionKeystrokeSending` (`Services/ActionService.swift:61–65`) already posts
  `CGEvent`s for `.sendKeystroke` — the lock-screen toggle's `CGEvent ⌃⌘Q` reuses this exact
  mechanism (see §2).

---

## 1. Scope (v1 set, per the HUD plan — unchanged, do not add)

| Toggle | Mechanism | Permission |
|---|---|---|
| Dark/Light mode | `osascript` → System Events `set dark mode to not dark mode` | Automation (System Events) |
| Display sleep | `pmset displaysleepnow` (direct `Process`, no `osascript`) | none |
| Screen saver | `osascript` → `start current screen saver` | Automation |
| Volume up/down/set, Mute toggle | `osascript 'set volume …'` | none (standard addition, no app scripted) |
| Lock screen | CGEvent `⌃⌘Q` | Accessibility (already granted for `.sendKeystroke`) |
| Empty Trash (confirm-gated) | `osascript` → `tell Finder to empty` | Automation |

**Explicitly deferred, do not build:** DND/Focus (no public toggle; the `ncprefs`/`controlcenter`
+ `killall` hack is broken post-Monterey), Brightness (only private
`DisplayServicesSetBrightness`, App-Store-fatal), Logout/Restart/Shutdown (destructive, low value
in a quick menu). Re-litigating these is out of scope for this plan.

---

## 2. `SystemToggleService`

```swift
enum SystemToggle: String, Codable, CaseIterable {
    case toggleDarkMode, displaySleep, screenSaver
    case volumeUp, volumeDown, volumeMute
    case lockScreen, emptyTrash

    var displayName: String { … }
    var systemImage: String { … }        // e.g. moon.stars, zzz, sparkles, speaker.wave.2,
                                          // speaker.slash, lock, trash — inner-ring symbol-only
    var requiresConfirmation: Bool { self == .emptyTrash }   // confirm-gated, default on
    var requiredPermission: TogglePermission {               // .none | .automation | .accessibility
        switch self {
        case .displaySleep, .volumeUp, .volumeDown, .volumeMute: .none
        case .lockScreen: .accessibility
        default: .automation
        }
    }
}

protocol ActionSystemToggling: Sendable {
    func perform(_ toggle: SystemToggle, arg: String?) async throws
}

actor SystemToggleService: ActionSystemToggling {
    func perform(_ toggle: SystemToggle, arg: String?) async throws
}
```
- **AppleScript dispatch — `Process` → `/usr/bin/osascript`, never `NSAppleScript`.** The HUD plan
  is explicit on why: `NSAppleScript` must run on (and blocks) the main thread, which is wrong from
  an `actor`; out-of-process `osascript` keeps execution off-main and TCC still attributes the
  prompt to MousePlus. Build the script string from a **fixed, non-interpolated template per
  toggle** (e.g. `"tell application \"System Events\" to tell appearance preferences to set dark
  mode to not dark mode"`) — volume's numeric argument (`arg`) is the only interpolated value, and
  it must be validated as an integer 0–100 before formatting, closing the shell-injection surface
  the HUD plan's mechanism choice exists to avoid. (Contrast with `.custom`, which is inherently
  free-form shell by design — toggles are a **curated enum**, not arbitrary text, specifically so
  this validation is possible.)
- **`pmset displaysleepnow`** and lock screen's `CGEvent` do not go through `osascript` — direct
  `Process` for the former (no scripting, no TCC), reuse of `ActionKeystrokeSending`'s CGEvent
  posting mechanism for the latter (already Accessibility-gated via the existing `.sendKeystroke`
  permission surface — same `PermissionsService.isGranted` check, no new prompt path).
- **No system volume HUD appears** for `set volume` (confirmed by the HUD plan) — MousePlus must
  show its own brief on-screen confirmation after a volume toggle fires (§4).
- **Empty Trash is destructive** — gated behind a Settings-level confirmation toggle, **default
  on** (i.e. confirm by default), per the HUD plan.
- **Cold `osascript` spawn is ~50–150ms** — acceptable for one-shot inner-ring actions; no caching
  or warm-process pooling needed.

---

## 3. Permission pre-priming (§1.4 pattern from the HUD plan, reused verbatim)

**Pre-prime in Settings, never mid-gesture** — a TCC consent dialog popping mid hold-release
gesture loses the gesture and silently fails. Two permission classes:
- **Accessibility** (lock screen only): already covered end-to-end by `PermissionsService` — no
  new code, just gate the lock-screen toggle's editor entry on `PermissionsService.isGranted`
  exactly as `.sendKeystroke` items presumably already are.
- **Automation (System Events / Finder):** **new** — macOS prompts for Automation permission the
  *first time* an `osascript` targets a given app (System Events, Finder), scoped per-target-app,
  separate from the Accessibility TCC bucket `PermissionsService` tracks. There is no equivalent
  polling API (`AXIsProcessTrusted`-style) for Automation; the standard approach is to fire a
  harmless no-op `osascript` probe (e.g. `tell application "System Events" to get name`) when the
  user first adds an Automation-requiring toggle in Settings, catching the
  `errAEEventNotPermitted` (-1743) failure to detect "denied" vs. "not yet asked" vs. "granted".
  Surface this in the same calm, pre-gesture Settings context as Accessibility.

---

## 4. Ring placement, editor, and feedback

- **Best fit: inner-ring, symbol-only quick toggles** (per the HUD plan) — no submenu expansion
  needed; each toggle is a direct-commit leaf, structurally identical to the existing
  `sampleInnerItems` (`Models/RingMenuItem.swift:107–132`, e.g. Copy/Paste/Spotlight today).
- **Editor:** add `.systemToggle` to `ActionType.selectableCases`; the Menu Items editor's action
  picker needs a toggle-specific sub-picker (choose which `SystemToggle`) analogous to however
  `.appSwitch` currently picks a bundle ID or `.sendKeystroke` records a chord — reuse that
  picker-composition pattern rather than inventing a new editor affordance.
- **Feedback ("HUD echo"):** volume toggles need a transient on-screen confirmation since macOS
  shows none for scripted volume changes. Scope this to a small, reusable "toast" surface —
  check whether the existing action-result routing (`actionResultRouter.routeRuntimeResult`,
  `RingViewModel.swift:307`) already has an affordance for transient success feedback before
  building a new one; if it does, extend it with a toggle-specific echo (e.g. current volume %)
  rather than adding a parallel notification path.
- **Empty Trash confirmation:** a native confirmation alert on commit, gated by the Settings-level
  "confirm before emptying Trash" toggle (default on) — not a blocking modal mid-gesture; fire it
  after the ring closes, matching the dismiss-before-action ordering already established for
  Screenshots (§1.5 of the HUD plan) so the confirmation dialog isn't fighting the closing panel.

---

## 5. Phased implementation

Build-gated: `xcodebuild -workspace 01_Project/MousePlus.xcworkspace -scheme MousePlus -configuration Debug build`

### Phase 0 — Model + service (parallel-friendly, no cross-feature deps)

| Wave | # | Task | Target file | Done when |
|---|---|------|-------------|-----------|
| **W1** | T1 | `SystemToggle` enum + `TogglePermission` (§2): raw values, display name, symbol, `requiresConfirmation`, `requiredPermission`. | `Models/SystemToggle.swift` (new) | Builds; `CaseIterable` covers exactly the v1 set (§1) |
| | T2 | `ActionSystemToggling` protocol + `actor SystemToggleService` implementing all eight toggles via `osascript`/`pmset`/CGEvent per §2's mechanism table. Volume `arg` validated as integer 0–100 before templating (no raw interpolation). | `Services/SystemToggleService.swift` (new) | Builds; a debug harness firing each toggle produces the expected system effect on a real Mac (manual, one pass) |
| **W2** (needs W1) | T3 | Wire `SystemToggleService` into `ActionService` (new injected `systemToggleService: any ActionSystemToggling` param, matching the existing four-protocol init pattern at `Services/ActionService.swift:80–90`); replace the `.systemToggle` arm in the catch-all switch (`:121`) with real dispatch: resolve `SystemToggle(rawValue: item.actionData)`, call `perform(_:arg:)`. | `Services/ActionService.swift` | Builds; switch exhaustive; `.systemToggle` no longer falls into the no-op catch-all |
| | T4 | Add `.systemToggle` to `ActionType.selectableCases`. | `Models/ActionType.swift` | Builds; toggle actions are choosable in the editor's action-type picker |

### Phase 1 — Permission pre-priming (needs Phase 0; can start in parallel with editor UI)

| # | Task | Target file | Done when |
|---|------|-------------|-----------|
| T5 | Automation-probe helper (§3): a harmless `osascript` no-op against System Events/Finder, run when a toggle requiring `.automation` is first added in Settings; classify granted / denied / not-yet-asked from the exit status and `errAEEventNotPermitted`. Surface a calm pre-prime UI element (reuse `PermissionsService`'s status-row visual language, but this is a distinct permission bucket — do not conflate with `isGranted`). | `Services/AutomationPermissionProbe.swift` (new) or an extension on the Settings toggle-picker view | Builds; adding a System-Events-backed toggle in Settings triggers the OS Automation prompt exactly once, in Settings, never mid-gesture |
| T6 | Lock-screen toggle gates its editor entry on `PermissionsService.isGranted` (reuse, no new prompt). | wherever `.sendKeystroke` already gates on this | Builds; lock-screen toggle is unselectable/prompts correctly when AX isn't granted |

### Phase 2 — Editor UI + feedback (needs Phase 0)

| Wave | # | Task | Target file | Done when |
|---|---|------|-------------|-----------|
| **W1** | T7 | Toggle sub-picker in the Menu Items editor's action-type flow (choose which `SystemToggle`), composed the same way the `.appSwitch` bundle picker or `.sendKeystroke` recorder is composed today. | Menu Items editor views (wherever `.appSwitch`'s picker lives) | Builds; user can create/save an inner-ring item with `actionType: .systemToggle, actionData: <SystemToggle.rawValue>` |
| | T8 | Empty-Trash confirmation setting (default on) in General/relevant Settings pane; commit path checks the setting and fires a post-close confirmation alert (dismiss-before-action ordering, §4) before calling `SystemToggleService.perform(.emptyTrash)`. | Settings pane + `ActionService` or `RingViewModel` commit path | Builds; committing Empty Trash with confirmation on shows an alert after the ring closes; declining does not empty the trash |
| **W2** (needs W1) | T9 | Volume HUD echo: after a volume toggle completes, show a transient on-screen confirmation (extend the existing action-result routing if it supports transient success feedback; otherwise scope a minimal toast). | wherever `actionResultRouter` lives | Builds; a volume toggle shows a brief confirmation since macOS shows none |

### Phase 3 — Verification

| # | Task | Done when |
|---|------|-----------|
| T10 | Seed one toggle of each permission class (`.none`: display sleep; `.automation`: dark mode; `.accessibility`: lock screen) as sample inner-ring items. Launch signed build; **user presses their trigger** (no synthetic input) and commits each. Confirm: display sleep engages, dark mode flips with a first-run Automation prompt then silently on repeat, lock screen locks via CGEvent. | All three permission classes verified live on hardware |
| T11 | Empty Trash: verify the confirm-gated path (declining truly no-ops) and the direct path with confirmation disabled. Volume: verify the HUD echo appears and the volume actually changes. | Destructive-action gating and feedback both verified |

**Net deliverables:** `Models/SystemToggle.swift`, `Services/SystemToggleService.swift`,
`Services/AutomationPermissionProbe.swift` (new); `Services/ActionService.swift`,
`Models/ActionType.swift`, Menu Items editor views, a Settings pane, `RingViewModel`/result-router
(edited).

---

## 6. Risks

- **TCC prompts mid-gesture** — closed by pre-priming in Settings (§3); if a user somehow reaches
  an unprimed Automation toggle from the ring, the resulting silent failure must surface a clear
  "grant Automation permission in Settings" result via the existing action-result routing rather
  than failing invisibly.
- **`set volume` shows no system HUD** — closed by the echo in Phase 2 W2; without it, a volume
  toggle is indistinguishable from a silent no-op to the user.
- **Automation permission has no polling API** (unlike Accessibility) — the probe-and-classify
  approach in §3 is a workaround, not a guarantee; document that a user who denies the OS prompt
  must be told to re-enable it manually in System Settings → Privacy & Security → Automation
  (there is no deep-link URL scheme for Automation the way `PermissionsService.openAccessibilitySettings()`
  has one for Accessibility — verify this during T5 and surface a plain-text path instead if so).
- **Empty Trash is irreversible** — confirm-gated by default is a hard requirement, not a nice-to-have.

## 7. Decisions to log in `decisions.md`

- System toggles are a curated `enum`, not arbitrary shell (`.custom` already covers free-form
  commands) — this is what makes validating the one interpolated argument (volume level) tractable
  and closes the injection surface a naive `.custom`-reuse approach would reopen.
- `Process` → `osascript`, never `NSAppleScript` — off-main, correct TCC attribution, matches the
  actor-based `ActionService` architecture.
- Lock screen uses `CGEvent ⌃⌘Q`, reusing the existing `.sendKeystroke`/Accessibility permission
  surface — not the private `SACLockScreenImmediate` API.
- DND/Focus and Brightness toggles are out of scope indefinitely (no reliable public API); revisit
  only if Apple ships one.
- Empty Trash defaults to confirm-on; this is a product safety decision, not just a UX default.
