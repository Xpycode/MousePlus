# Send-Keystroke Plan — ③ First-Class Keystroke Action for Ring Wedges

**Status:** planned 2026-08-10 (3-agent research: codebase map + Apple-docs verify + OSS-practice survey).
**Branch:** cut `feature/send-keystroke` from `main` **after** `feature/menu-editor` merges — the editor
UI arm (T5) edits `ActionDataEditor.swift`, which lives on that branch.
**Estimated effort:** ~1–1.5 dev-days.

Naming pinned: **`ActionType.sendKeystroke`** (raw `"sendKeystroke"`). Supersedes the drifting names
in older docs — `.keyStroke` (sessions/2026-07-08.md), `.keyShortcut` (APP_COMMANDS_PLAN.md §3). Those
docs stand, but this spelling wins.

---

## 0. Goal & current reality

A wedge action that synthesizes a keyboard shortcut (keyCode + modifiers) system-wide, so a ring
wedge can fire another app's global hotkey (headline case: QuickStatsPanel's ⌃⌥⌘Q) or send a
plain chord (⌘C, ⌘V, ⌘Space) to the frontmost app.

**Today:**
- No CGEvent/event-posting code exists anywhere in the repo (verified by grep) — everything is
  observe-only NSEvent monitors + AX + NSWorkspace.
- The stopgap is a `.custom` wedge shelling to `osascript … System Events keystroke` (works, ugly,
  spawns a process per press, needs Automation-TCC on first run).
- The four inner-ring default wedges (Copy / Paste / Mission Control / Spotlight,
  `RingMenuItem.sampleInnerItems`, `RingMenuItem.swift:39-47`) are `.custom` with empty
  `actionData` — confirmed no-ops. This feature makes them real.
- The ring panel is **non-activating** (`RingWindowController.swift:96`), so the user's app keeps
  focus while the ring is up — a fired keystroke naturally lands on the app below (verified live
  2026-07-08).

**Reusable seams (from the codebase map):**
- `ActionType` decode-tolerant `init(from:)` (`ActionType.swift:49-61`) — unknown raw values decode
  to `.custom` no-op, so the new case degrades safely on older builds (same as the `clipboard` drop).
- `ActionService.execute` switch (`ActionService.swift:24-47`) + `ActionContext.frontmostPID`
  captured at ring-open (`MousePlusApp.swift:227-229`).
- `TriggerRecorderService` (`Services/TriggerRecorderService.swift`) — one-shot @MainActor recorder,
  already strips `.function`/`.capsLock` to chord modifiers (⌃⌥⇧⌘). Returns a `TriggerBinding`
  whose `mode` is a placeholder — callers ignore it here.
- `KeyCodeNames.key(_:)` / `.modifiers(_:)` (`Utilities/KeyCodeNames.swift`) for display.
- `ActionDataEditor.dataControl` switch (`ActionDataEditor.swift:43-57`) — the exact insertion point
  for the editor arm; `TriggersSettingsView.bindingRow` (`:92-137`) is the recorder-row reference.
- `MenuEditorModel.normalizingTypeSwitch` + `defaultActionData(for:)` (`MenuEditorModel.swift:355-371`)
  already reset stale payloads on action-type switch; `.sendKeystroke` defaults to `""` (unbound).

**Deliberately NOT reused:** `RingMenuItem.keyboardShortcut: String?` — exists but is never read
anywhere (display-oriented leftover). Overloading it would fork the payload contract; the payload
lives in `actionData` like every other case. Leave the field alone.

---

## 1. Data model

`actionData = "<keyCode>:<modifiers>"` — e.g. `"12:1835008"` (⌃⌥⌘Q). Format proposed in
sessions/2026-07-08.md:68, now pinned.

- `keyCode` = `UInt16` virtual key code, `modifiers` = **`NSEvent.ModifierFlags.rawValue`** (`UInt`)
  restricted to the chord mask (⌃ 1<<18, ⌥ 1<<19, ⇧ 1<<17, ⌘ 1<<20) — exactly what
  `TriggerRecorderService` emits and what `TriggersConfig` already persists. **Not** `CGEventFlags`;
  the service maps at the posting boundary (`.control→.maskControl`, `.option→.maskAlternate`,
  `.shift→.maskShift`, `.command→.maskCommand`).
- Empty string = unbound → runtime no-op (mirrors `.custom`'s empty-command guard).
- Malformed string → no-op, tolerant parse (mirrors the `SnapZone(rawValue:)` guard pattern at
  `ActionService.swift:52`).
- Codec lives as a tiny `struct KeystrokePayload { let keyCode: UInt16; let modifiers: UInt }`
  with `init?(actionData:)` + `var actionData: String` — one place, used by service and editor.
- We do **not** touch `TriggerBinding` — its synthesized Codable is decode-brittle (any case change
  breaks configs); the payload string keeps keystroke data out of that blast radius.

---

## 2. `KeystrokeService` — the posting recipe (research-verified)

New `Services/KeystrokeService.swift`, `actor` (house pattern, mirrors `WindowService`), owned by
`ActionService` like `windowService`.

```
actor KeystrokeService {
    func send(_ payload: KeystrokePayload) async throws
}
```

Recipe — each line is a researched decision, see §6 for sources:

1. **Private event source**: one `CGEventSource(stateID: .privateState)` created lazily and kept.
   (Hammerspoon's choice; the modern spelling of skhd's deprecated
   `CGEnableEventStateCombining(false)` defense against the user's physically-held modifiers.)
2. **Explicit flags on BOTH events**: build keyDown + keyUp via
   `CGEvent(keyboardEventSource:virtualKey:keyDown:)`, then set `.flags` to the mapped chord on
   **both** — even when the chord is empty (set `[]` explicitly). Contamination bites events whose
   flags were never set; an explicitly-flagged event carries exactly those flags. No separate
   modifier keyDown/keyUp events (flags-on-event is the right school for "send a chord"; the
   left-side-modifier limitation is irrelevant here).
3. **Post to `.cghidEventTap`**: HID-level posting flows through the same path as hardware, so
   *other apps'* Carbon `RegisterEventHotKey` hotkeys fire — the QSP requirement. Session-wide, not
   `postToPid` (targeted posting bypasses global-hotkey matching; per-app targeting is a possible
   later option, not v1).
4. **Timing**: ~50 ms pre-delay before the keyDown (lets the panel's `orderOut` land — the minimal
   stand-in for the unbuilt §1.5 dismiss-before-action seam, without touching `commitActive`
   ordering for the other action types), then keyDown → 10 ms → keyUp. (OSS floor is 1 ms between
   posts; Hammerspoon's default down→up gap is a conservative 200 ms; 10 ms is plenty for hotkey
   matching.) `Task.sleep`, all inside the actor = serial by construction.
5. **Permission gate**: `CGPreflightPostEventAccess()` first; on `false` throw
   `KeystrokeError.postEventAccessDenied` (and the Settings-side row calls
   `CGRequestPostEventAccess()` — see T6). We do **not** assume the existing Accessibility grant
   covers it; see risk R2.

---

## 3. Wiring

- **`ActionType`** (`ActionType.swift`): `case sendKeystroke` + `displayName` "Send Keystroke" +
  `systemImage` "keyboard". Rides the existing tolerant decode unchanged.
- **`ActionService.execute`**: new arm — parse `KeystrokePayload(actionData:)`, guard else return
  (no-op), `try await keystrokeService.send(payload)`. Context not needed (session-wide posting);
  `frontmostPID` stays untouched for a future targeted mode.
- **Errors**: today the caller discards everything (`try? await` at `RingViewModel.swift:139`).
  Unchanged in v1 — logged as risk R6, not this feature's job to build error surfacing.
- **`MenuEditorModel`**: nothing — `defaultActionData(for:)` already returns `""` for
  non-windowSnap types, and `normalizingTypeSwitch` handles the type-switch reset generically.

---

## 4. Editor UI (`ActionDataEditor`)

New arm at the `dataControl` switch (`ActionDataEditor.swift:52`), removing `.sendKeystroke` from
the coming-soon group:

- **Row** modeled on `TriggersSettingsView.bindingRow` (`:92-137`): current chord as text
  (`KeyCodeNames.modifiers(_:)` + `.key(_:)`, e.g. "Ctrl+Opt+Cmd+Q"), **Record** button (swaps to
  "Press keys… (Cancel)" while armed), **Clear** button. Empty payload displays "Not set" +
  caption warning (mirrors `customControl`'s empty-command warning).
- **Recorder**: `@State private var recorder = TriggerRecorderService()` alongside
  `showingAppPicker`; consume via `.onChange(of: recorder.outcome)`; on
  `.captured(.keyboard(keyCode, modifiers, _))` write
  `item.actionData = KeystrokePayload(keyCode:modifiers:).actionData` — the placeholder `mode` and
  mouse-button case are ignored. Cancel/timeout → no write.
- **Teardown**: `ActionDataEditor` has no lifecycle hooks today; add `.onDisappear { recorder.cancel() }`
  so a half-armed recorder can't outlive the row (type-switch or selection change mid-recording).
- Known recorder caveats accepted: Escape cancels recording (can't record Escape — fine, Escape
  dismisses the ring anyway); recording swallows the chord only via the *local* monitor (fine
  inside the editor window).

---

## 5. Inner-ring defaults become real (`RingMenuItem.sampleInnerItems`)

| Wedge | New action | Payload |
|---|---|---|
| Copy | `.sendKeystroke` | `"8:1048576"` (⌘C — kVK_ANSI_C=8, ⌘=1<<20) |
| Paste | `.sendKeystroke` | `"9:1048576"` (⌘V) |
| Mission Control | `.custom` | `open -b com.apple.exposelauncher` — **not a keystroke**; no public keycode reaches it (Karabiner-only HID territory). The bundle-launch trick is the OSS consensus. |
| Spotlight | `.sendKeystroke` | `"49:1048576"` (⌘Space) — fragile if the user remapped Spotlight; accepted, it's just a default. |

⚠️ **Saved-config-wins trap** (hit twice before — PROJECT_STATE "Verify gap found"): editing samples
reaches only fresh installs. Returning users (i.e. the user) get these via the Menu Editor or a
one-time offer to re-seed the inner ring. Verify wave must not "test" the samples through a stale
live config.

**Out of scope (v2+):** media/system keys (volume, brightness, play — the `NX_SYSDEFINED`
subtype-8 `NSEvent.otherEvent` trick); per-app targeted posting (`postToPid`); separate
modifier-key-event mode for apps that track physical modifier transitions.

---

## 6. Research basis (what was verified, 2026-08-10)

- **Apple docs** (apple-docs/sosumi MCP): `CGEvent(keyboardEventSource:virtualKey:keyDown:)` +
  `.flags` is current and non-deprecated on macOS 14/15; tap-location semantics; `.privateState`
  source semantics; `CGPreflightPostEventAccess`/`CGRequestPostEventAccess`; Secure Event Input
  blocks event *taps*, not posting (TN2150).
- **Hammerspoon** (`libeventtap_event.m`): flags-on-both-events school; private source after
  finding HID/session/private indistinguishable (#2104); posts to session tap; `usleep(1000)`
  after every post; NX_SYSDEFINED for media keys; Mission Control via CoreDock notification.
- **skhd** (`synthesize.c`): the contamination problem and its (deprecated) fix
  `CGEnableEventStateCombining(false)`; zeroed flags as defense.
- **espanso** (`native.mm`): query-and-release of physically-held modifiers via
  `CGEventSourceKeyState(.hidSystemState, code)` — the escalation path if R1 bites; main-thread
  serialization; `kCGHIDEventTap`.
- **Karabiner** (`DEVELOPMENT.md`): the CGEventPost ceiling — Fn/Globe behaviors and
  mission_control/spotlight consumer keys unreachable without a virtual HID driver. Defines what
  we don't attempt.
- **Tahoe warning** (nick-liu.com write-up): WindowServer drops synthetic modifier-bearing events
  from ad-hoc-signed binaries *before* hotkey matching; TCC buckets `kTCCServicePostEvent`
  separately from Accessibility and Input Monitoring. Our stable Developer-signing path (memory:
  `tcc-adhoc-signing`) is the sanctioned side of that gate — one more reason never to ship ad-hoc.

---

## 7. Wave-based build plan (build-gated, `/execute`-ready)

Backpressure for every task: `xcodebuild -workspace 01_Project/MousePlus.xcworkspace -scheme
MousePlus -configuration Debug build` green. Same-file tasks never share a wave.

**Wave 1 — foundations (parallel, no deps)**
- **T1 · Model.** `ActionType.sendKeystroke` (+`displayName`/`systemImage` arms) and
  `KeystrokePayload` codec (new `Models/KeystrokePayload.swift`: parse/format, chord-mask clamp,
  NSEvent→CGEventFlags mapping helper). Done = builds; decode of `"sendKeystroke"` and of garbage
  both safe by construction of the existing tolerant init.
- **T2 · Service.** `Services/KeystrokeService.swift` per §2 (actor, private source, explicit flags
  both events, `.cghidEventTap`, 50 ms/10 ms timing, preflight gate, `KeystrokeError`). Compiles
  standalone; not yet called.

**Wave 2 — wiring (after W1)**
- **T3 · ActionService arm.** `case .sendKeystroke` in `execute`, tolerant-parse guard, owned
  `keystrokeService`. Done = a hand-edited `config.json` wedge with `"12:1835008"` fires ⌃⌥⌘Q
  (dev smoke check only; formal verify is W4).

**Wave 3 — UI + defaults (after W2; T4/T5 touch different files, parallel-safe)**
- **T4 · Editor arm.** `ActionDataEditor` recorder row per §4 (+ `.onDisappear` teardown). Done =
  record → chord text renders → autosave persists payload → live ring fires it.
- **T5 · Inner defaults.** `sampleInnerItems` per §5 table. Done = fresh-install path
  (delete `config.json`) shows a working Copy/Paste/Mission-Control/Spotlight inner ring.
- **T6 · Permission row.** Reuse the `TriggersSettingsView.permissionBanner` pattern: a
  "Keystroke posting" status row in Settings ▸ Triggers driven by `CGPreflightPostEventAccess()`,
  button calling `CGRequestPostEventAccess()`. Pre-prime in Settings, never mid-gesture
  (HUD_ACTIONS_PLAN §1.4 rule). Skip the row entirely if R2 testing shows the existing
  Accessibility grant already satisfies preflight on both Macs.

**Wave 4 — user-driven live verify (no synthetic *verification* input; the feature itself posting
events is the thing under test, exercised by real user gestures)**
- **T7 · Verify checklist.** ① QSP wedge fires ⌃⌥⌘Q (QuickStatsPanel toggles) — the headline case,
  proves other-app global hotkeys. ② Copy/Paste round-trip in TextEdit via the ring. ③ Spotlight
  wedge opens Spotlight. ④ **Contamination probe:** trigger the ring in *hold-release* mode (chord
  physically held through commit) and fire a bare ⌘V wedge — paste must not become ⌃⌥⌘V. If it
  does → escalate to espanso query-and-release (R1). ⑤ Editor flow: record, clear, re-record,
  type-switch away/back (payload resets), quit+relaunch persistence. ⑥ Permission first-run: note
  whether a new TCC prompt appeared (feeds R2 + T6 skip decision). Then log §8 decisions in
  `decisions.md`, merge `--no-ff`.

---

## 8. Decisions to log in `decisions.md` (when built)

1. Naming: `ActionType.sendKeystroke`; payload `"keyCode:modifiers"` (NSEvent raw flags) in
   `actionData`; `TriggerBinding` and `RingMenuItem.keyboardShortcut` deliberately untouched.
2. Posting recipe: private CGEventSource + explicit flags on down *and* up + `.cghidEventTap`
   session-wide (not `postToPid`) + 50 ms/10 ms timing — and why (contamination defense; global
   hotkeys of other apps must fire).
3. Mission Control = `open -b com.apple.exposelauncher` custom action, not a keystroke; media keys
   (NX_SYSDEFINED) deferred to v2.
4. Permission stance: preflight-probe at fire time, pre-prime row in Settings (or the T6-skip
   finding, whichever verification shows).

## 9. Risks & mitigations

- **R1 — Held-modifier contamination.** User's ⌃⌥⌘ physically down at commit (hold-release mode)
  bleeds into the synthetic chord. Mitigated by private source + explicit flags on both events
  (consensus fix); T7-④ probes it; escalation = espanso-style query-and-release
  (`CGEventSourceKeyState`) per held modifier before posting.
- **R2 — Which TCC bucket gates posting.** Sources conflict (docs-scout said Input Monitoring; the
  Tahoe write-up shows `kTCCServicePostEvent` is its own bucket, historically satisfied alongside
  Accessibility). Resolved empirically: `CGPreflightPostEventAccess()` is the oracle, T7-⑥ records
  the answer per Mac, T6 ships or is skipped accordingly. Worst case = one extra one-time prompt.
- **R3 — Spotlight default breaks if the user remapped ⌘Space.** Accepted; it's an editable default.
- **R4 — Secure Input.** A focused password field doesn't block our *posting* (TN2150: it blocks
  taps/listening), but the target app may ignore injected events; not our bug. No mitigation.
- **R5 — Panel-teardown race.** §1.5 seam remains unbuilt; the 50 ms pre-delay is a stand-in scoped
  to keystrokes only. If verify shows the ring swallowing the event, build the real seam
  (`requestClose()` → `await Task.yield()`) as specced in HUD_ACTIONS_PLAN §1.5.
- **R6 — Errors invisible.** `try?` at `RingViewModel.swift:139` swallows `postEventAccessDenied`
  → a denied permission looks like a dead wedge. Pre-existing, out of scope; the T6 Settings row is
  the compensating control. Log as accepted risk.
- **R7 — Ad-hoc builds silently dead on Tahoe.** WindowServer drops synthetic modifier events from
  unsigned/ad-hoc binaries. Already mitigated by the stable-signing discipline (memory
  `tcc-adhoc-signing`); noted so a future "works on my Mac, dead on a test build" report finds this.

## References

- Codebase map, Apple-docs verification, and OSS survey: 3-agent research run 2026-08-10 (sources
  inline in §6).
- `docs/HUD_ACTIONS_PLAN.md` §1.4 (permission pre-priming), §1.5 (dismiss seam).
- `docs/APP_COMMANDS_PLAN.md` §3.2 (`.keyShortcut` secondary path — superseded naming).
- `docs/sessions/2026-07-08.md`, `2026-07-12.md` (origin of ③).
