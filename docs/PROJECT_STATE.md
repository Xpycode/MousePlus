# Project State

## Quick Facts
- **Project:** MousePlus (renamed from PointerActions on 2026-04-26)
- **Started:** 2026-01-09 (as PointerActions)
- **Current Phase:** implementation. **Three parallel tracks:** (1) *Trigger/HID backend* — Waves 1+2 done, W3 architecture done, plan A (`IOHIDDeviceInspector`) built, plan B blocked on the HID++ strategy decision (#17); (2) *Ring UI redesign* — concentric wedge menu **✅ COMPLETE & verified live 2026-05-30** (`IMPLEMENTATION_PLAN.md`, 12 tasks / 5 waves), merged to `main`; (3) *HUD actions backend* — **NEW, specced 2026-05-30-c** (`HUD_ACTIONS_PLAN.md`). The ring *renders* but its `ActionService` is mostly stubs (only `appSwitch` + `custom` fire; `clipboard`/`menuBar` are `break` cases; several default wedges are empty no-ops). Five real action types specced: menu-bar mirror, window snapping, app switcher, system toggles, screenshots. Not yet built.
- **Last Session:** 2026-05-31-a (**Trigger fix, verified live.** Diagnosed the "HUD flashes for a fraction of a second on middle-click" report as **not a bug** — button 2 is `holdRelease`, so a quick tap with no drag commits the center dead zone and closes instantly. User opted to drive the ring from a **modifier chord mapped to a mouse button in BetterMouse** rather than fix native mouse-button binding. F4 fired, but the **Logitech keyboard firmware rewrites fn+F4 → F12** before macOS sees it, so bare/fn function keys are unusable. Switched to **`⌃⌥⌘M`** (doesn't ride the fn-row → firmware can't remap it): pre-wrote `config.json` keyboard binding `keyCode 118`/`mods 8388608` → `keyCode 46`/`mods 1835008`, still `tapToggle` (quit-edit-relaunch; saved JSON always wins over `TriggersConfig.default` at load). Also changed `KeyCodeNames.modifiers()` to render **text** (`Ctrl+Opt+Cmd+M`) instead of the cramped `⌃⌥⌘` glyphs. Clean build, committed `e59e4be`, merged `--no-ff` `cc96736`, branch deleted. **Verified: both the keyboard chord and the BetterMouse-mapped button open the ring.** Saved memory `trigger-modifier-chord-strategy`.) Previous: 2026-05-30-c (**Planning/research, no code.** Audited the action backend and found the ring is a polished shell on a stub `ActionService`. Fanned out 5 source-verified research agents — `menuanywhere`, `Rectangle`, live `man screencapture`, Apple docs — and wrote `docs/HUD_ACTIONS_PLAN.md`: proper task specs for **menu-bar mirror** (radial top-level → native NSMenu handoff; `AccessibilityService` is `@MainActor`), **window snapping** (own middle wedge → outer arc of 8 directions; `actor WindowService`; Rectangle's `AXEnhancedUserInterface` + size→pos→size hacks; y-flip about the *primary* screen's `frame.maxY`), **app switcher** (self-tracked MRU via `didActivateApplicationNotification`; `IconSource` enum for real app icons, NSImage never in the Codable model), **system toggles** (dedicated `ActionType.systemToggle` + curated enum; `Process`→osascript not NSAppleScript; CGEvent ⌃⌘Q lock; DND+brightness deferred), **screenshots** (interactive `screencapture -i/-U` only = no Screen-Recording TCC). Plus a **shared foundation** layer (extend `ActionType`, async `expand()` w/ stale-guard, `IconSource`, one Accessibility-TCC flow, dismiss-before-action seam at `RingViewModel.swift:132`) and a build order (foundation → snap → screenshots → mirror → switcher → toggles, ≈10–13 dev-days). Decided to **drop `ActionType.clipboard`** (defer to the user's separate ClipSmart/Aloft app). Key product finding: 3 of 5 features are **sandbox-incompatible** → reinforces direct distribution. 7 decisions logged to `decisions.md`. No build, nothing merged.) Previous: 2026-05-30-b (Built the **Triggers settings tab (W4)** on branch `feature/triggers-settings-tab`. New `TriggersSettingsView` — keyboard + mouse binding rows, Record/Clear, per-binding hold-release/tap-toggle picker, Accessibility permission banner, 4s interception-timeout warning — backed by new `TriggerRecorderService` (one-shot recorder, strips `.function`/lock flags to chord modifiers only) and `KeyCodeNames` display helpers. Swapped the dead "Hotkey" tab → "Triggers"; `TriggersConfig: Equatable`. **Fixed a latent wiring bug:** the app booted the hardcoded F5+middle-click default no matter what was saved — `setupTriggers` now starts from `configuration.triggers`, and a new `AppDelegate.applyTriggers` hook + load-completion call push saved/edited triggers into the live `TriggerService` (rebind takes effect with no restart). Verified live by the user: rebind to F4 with no restart, persisted across quit+relaunch, F4 opens the ring. Side-fixes: Identify Input window minimize restored (`.floating`→`.normal`), temp "Settings…" button added to Identify Input as an M1 Max menu-bar-icon workaround. Process lesson logged: launch `xcodebuild -showBuildSettings → TARGET_BUILD_DIR`, never `find DerivedData | head` — had been relaunching a stale ad-hoc build with lost TCC; deleted the two stale DerivedData dirs. **Merged `--no-ff` to `main` (d430d68); branch deleted.** Previous: 2026-05-30-a — concentric ring menu via `/execute` — all 5 waves build-gated green, full interactive flow verified live: trigger, concentric render, expand→outer arc, hold-to-select, click-outside + Esc dismissal. New files `AnnularWedge`/`WedgeView`/`RadialGeometry`/`DismissMonitor`; rewrote `RingViewModel`/`RingMenuView`/`RingWindowController`; `Configuration` inner/middle split + `AppearanceConfig` band-radius/dim/keepSpokeLit + Ring Appearance settings tab. Three bugs caught in verification & fixed: app quit on last-window-close (`applicationShouldTerminateAfterLastWindowClosed`), Esc not dismissing (needed a local key monitor), F5/voice-key collision. git initialized — baseline on `main` + per-wave commits, merged `--no-ff`, feature branch deleted.)
- **Repo:** https://github.com/Xpycode/MousePlus (public, GPLv3)
- **Build:** ✅ clean on both Macs under `xcodebuild -workspace 01_Project/MousePlus.xcworkspace -scheme MousePlus -configuration Debug build` (M4 Pro + M1 Max both have `Debug.local.xcconfig` bootstrapped)

## 📦 Packages
> Shared packages ↔ this app — see `docs/PACKAGE-NOTES.md` (catalog: zPackages/docs/PACKAGE-CATALOG.md).
> **Adopt:** GlobalEventMonitors, ShortcutKit · **Source for:** GlobalEventMonitors, PermissionsService

## One-Liner

Radial quick-access menu summoned by mouse-button or hotkey — app switching, clipboard, menu bar access, and custom actions in a beautiful ring interface. Designed to complement BetterMouse; built for MX Master 3s/4 owners but works with any mouse or trackpad.

## Current Focus

**Ring UI redesign ✅ DONE — but the ring's *actions* are mostly stubs.** The concentric wedge menu *renders* and is verified live, but `ActionService` only executes `appSwitch` + `custom`; `clipboard`/`menuBar` are `break` stubs and several default wedges are empty no-ops. Two open work tracks:

- **HUD actions backend (NEW, `HUD_ACTIONS_PLAN.md`, specced 2026-05-30-c):** make the ring actually *do* things. Five specced action types + a shared foundation layer. **Recommended next build:** the §1 shared foundation, then **Feature B (window snapping)** — most radial-native, self-contained, lowest risk. Not blocked by the HID track. ≈10–13 dev-days for all five at v1. Three of the five are sandbox-incompatible (reinforces direct distribution). 7 decisions logged 2026-05-30-c.
- **HID/trigger backend:** (a) the HID++ strategy decision (#17, gated on MX4 capture #3); (b) Triggers settings tab is ✅ done (W4, 2026-05-30-b). **Working trigger as of 2026-05-31-a:** `⌃⌥⌘M` (tap-toggle), mapped from a mouse button via **BetterMouse** — a modifier chord chosen because the Logitech keyboard firmware remaps F-keys (fn+F4→F12). The side-by-side test default in `TriggersConfig.default` still ships until onboarding (D1) forces a choice.

Also still open: the M1 Max menu-bar-icon mystery (the "Identify Input" auto-open is a workaround).

---

**Plan A — `IOHIDDeviceInspector` ✅ done (session-e), bumped to schema v3 (session 2026-05-02-a).** Side panel in Identify Input that enumerates HID devices via IOHIDManager (multi-pair matching + a "match all" toggle), lists elements with live-fire counters, captures raw input reports for vendor pipes, and saves per-device snapshots as JSON. v3 schema adds per-element accumulated `fireCounts` (the authoritative "did this element ever fire" signal — supersedes the lossy `liveCaptures` ring), per-device live-capture buffers, and `matchAllDevices` provenance.

**Per-product variance confirmed.** The MX Master 4 BLE snapshot (M4 Pro, session 2026-05-02-a) shows the vendor pipe lives on page `0xFF43` (not `0xFF03` like the 3S) and emits HID++ traffic *without* an explicit divert from us — six vendor cookies fired during a normal capture session, with five of seven page-9 buttons (L/R/M + both side buttons) firing under raw HID. Buttons 6/7 (likely DPI / gesture / thumb / wheel-mode) declared but silent on the consumer page; their HID++ representation should land in capture #3 (vendor-only interface, not yet captured).

**Session-e's "firmware-withheld" conclusion for the MX3S is now suspect.** That snapshot was taken with schema v2 (no fire counts in JSON, global 80-entry live-capture ring) — same lossy machinery that almost masked the MX4's working buttons in capture #1 today. A re-capture of the MX3S on the M1 Max with v3 Inspector is needed before treating "MX3S firmware withholds without divert" as ground truth.

**Decision point before plan B can start (#17, still pending):**

1. **Accept the limitation** — document "silent buttons require Logi Options+ running." Cheap, but undercuts the "made for MX Master" pitch.
2. **Implement HID++ 2.0 host-side** (~250 lines, scoped session 2026-05-01-a): featureID lookup, divert per controlID, parse incoming `0x11` reports. Path that `logiops` (Linux) and `Mouser` (macOS) take. No Options+ dependency. **Strengthened by the MX4 evidence** — the wire is alive on the MX4 without us doing anything, so we'd be decoding rather than negotiating from zero.
3. **Coexist with Options+** — read events Options+ has already enabled. Fragile because Options+ also consumes presses for its own remapping.

Recommendation: option 2, with a stronger basis than after session-e. **Decision still gated on capture #3** (alternate MX4 interface for raw report bytes) so we know what we'd be decoding before committing.

Wave status:
- **W1 ✅** Permission plumbing, onboarding sheet, key-repeat-guarded `showRing`, static Info.plist, stable Debug signing (M4 Pro + M1 Max bootstrapped)
- **W2 ✅** `HotkeyService` → `TriggerService` refactor with `TriggerBinding` enum + unified `AsyncStream<TriggerEvent>`
- **W3 architecture ✅** `MouseButtonTriggerMonitor` body + tap-toggle wired + `hideRing(commitHovered:)` + `toggleRing()`
- **W3 backend rewrite ⏳** plan A ✅ (`IOHIDDeviceInspector`, schema v3 as of 2026-05-02-a); plan B blocked on HID++ strategy decision
- **W3 verify ⏳** Lock W3 default to user's preferred MX Master button after B is in
- **W4 ⏳** Rewrite Settings → "Triggers" tab embedding `InputRecorderView`-style recorder per binding, per-binding mode toggle, permission banner, interception-detection warning
- **W5 ⏳** Onboarding + polish

The 5-wave plan: W1 ✅ → W2 ✅ → **W3 (architecture ✅, backend rewrite + verify ⏳)** → W4 → W5.

**Bonus already in tree from W3:** the **"Identify Input" window** — `InputRecorderService` + `InputRecorderView` + `InputRecorderWindowController`. Now auto-opens at launch (temporary workaround for the M1 Max menu-bar-icon mystery; will revert when the menu bar bug is fixed). Will also host the IOHIDDeviceInspector panel.

### Ring UI redesign track (planned 2026-05-30)

Parallel to the HID work and not blocked by it. The user re-imagined the menu as a **concentric wedge ("pie") menu**: inner symbol ring + middle labeled ring sharing locked spokes, plus an on-demand outer ring that expands as a localized arc from a parent wedge, with focus-dimming of inactive branches. Full spec + 12-task/5-wave breakdown in `IMPLEMENTATION_PLAN.md`; design rationale in `decisions.md` (2026-05-30 "Ring UI: Concentric Wedge Menu"). Replaces the current circles-in-a-ring `RingMenuView`; reuses triggers, NSPanel, `RingMenuItem`, `ActionService` untouched.

**Status (2026-05-30): ✅ COMPLETE — T1–T12 built & verified live.** All 5 wave build-gates passed (`xcodebuild -workspace 01_Project/MousePlus.xcworkspace -scheme MousePlus -configuration Debug build`); the user verified the full interactive flow (trigger Fn+F5, concentric render, expand → outer arc, hold-to-select, click-outside + Esc dismissal). Two integration bugs found & fixed during verification: (1) app quit when the last window (auto-opened "Identify Input") closed — added `applicationShouldTerminateAfterLastWindowClosed -> false` + made that window minimizable; (2) Esc didn't dismiss — `DismissMonitor` needed a *local* key monitor (global-only can't see Escape when our panel holds focus). Trigger swapped to F5 (Fn+F5 directly, or map a mouse button to F5; bare F5 collides with the system/Perplexity voice key). Lives on branch `feature/concentric-ring-menu` (git initialized 2026-05-30: baseline on `main`, then one commit per wave + the three fixes). New files: `Views/Components/{AnnularWedge,WedgeView}.swift`, `Utilities/RadialGeometry.swift`, `Services/DismissMonitor.swift`. Rewrote `RingViewModel` (angle hit-test API + commit/expand/collapse), `RingMenuView` (concentric ZStack + localized-arc expansion + branch dimming; old `RingItemView` deleted), `RingWindowController` (fixed square panel, `acceptsFirstMouse`, multi-display clamp). Split `Configuration` into `inner`/`middle` (legacy `items`→`middle` decode shim) and extended `AppearanceConfig` with band radii / dimOpacity / keepSpokeLit (new "Ring Appearance" settings tab). Commit repointed to `commitActive()`; Escape/click-outside dismissal via `DismissMonitor`. **Remaining = T12 interactive verify** (open→hover→expand→select→dismiss); `/preview` can't render this multi-file macOS view (standalone/iOS-sim only), so it must be exercised by hand. Watch the §6 risks: flipped-clockwise wedge orientation, NSPanel first-click swallow, and whether `onContinuousHover`/drag selection tracks the cursor during a global mouse-button hold on the non-activating panel. Build-time refinements logged in `decisions.md` (2026-05-30 entries).

## Key Decisions Made

See `decisions.md` for full rationale.

**Product:**
- **HUD actions (2026-05-30-c, `HUD_ACTIONS_PLAN.md` + 7 entries in `decisions.md`):** drop `ActionType.clipboard` (defer to the user's separate ClipSmart/Aloft app); menu mirror = radial top-level → native NSMenu handoff; window snap = own wedge → 8-direction arc; app switcher = self-tracked MRU + `IconSource` real icons; system toggles = curated enum (DND/brightness deferred — no reliable API); screenshots = interactive `screencapture` only (no TCC). Product consequence: menu-mirror / window-snap / system-toggles are **sandbox-incompatible** → reinforces direct distribution.
- Two-level menu depth (ring → sub-ring) — **extended 2026-05-30** to three concentric rings (inner + middle + one expansion), still hard-capped at depth 3
- **Ring UI = concentric wedge menu (2026-05-30):** inner symbol ring + middle labeled ring (locked spokes `N=min(8,max(inner,middle))`, independent action sets), on-demand outer ring as a localized arc; Blender-style angle hit-testing; inactive branches dim to 0.30 but stay clickable. See `decisions.md`.
- Both trigger methods (hold+release AND tap+click)
- User-selectable animation (instant vs animated)
- All dismiss methods (click outside, Escape, release hotkey)
- **Trigger model (2026-04-29):** Both keyboard shortcut and mouse button supported in v1; mouse-button is the premium path; ships with no default — user picks during onboarding (D1)
- **Tap-to-toggle semantics (2026-04-29):** click a slice to confirm; not a second tap of the trigger (D2)

**Technical:**
- NSPanel + SwiftUI for ring overlay
- **Keyboard trigger:** `NSEvent.addGlobalMonitorForEvents`
- **Mouse-button trigger (2026-04-29-d):** pivoting to **IOHIDManager** — NSEvent silently drops MX Master 3S extras (thumb, wheel-mode, DPI, micro-buttons). See `decisions.md` "Mouse-Button Trigger Backend: IOHIDManager". Likely retires the v1.1 CGEventTap upgrade.
- **Silent-button root cause (2026-04-29-e) — *suspect, pending v3 re-capture*:** session-e concluded that the MX Master 3S firmware withholds DPI/thumb/gesture events until a HID++ `ReprogrammableKeysV4` divert is issued. That conclusion was drawn from a schema-v2 snapshot whose lossy 80-entry global ring buffer almost masked the MX Master 4's working buttons in capture #1 of session 2026-05-02-a. A v3 re-capture of the MX3S on the M1 Max is needed before treating "MX3S is firmware-silent" as established fact.
- **Per-product variance (2026-05-02-a):** MX3S vendor pipe = page `0xFF03`, MX4 vendor pipe = page `0xFF43`. MX4 emits HID++ traffic on the vendor pipe by default (six vendor cookies fire under match-all + Options+ quit); MX3S does not (per the suspect session-e snapshot). Plan B's HID++ implementation must discover the vendor page per-device, not hard-code one.
- **Inspector schema v3 (2026-05-02-a):** adds `fireCounts: [HIDFireCount]` (per-element accumulated counts, the authoritative "did this fire?" signal) and `matchAllDevices: Bool?` (capture-time provenance). Replaces the global 80-entry `lastFires` ring with `lastFiresByDevice` capped at 10 000 per device; raw-report cap 40 → 1 000 per device. Old v2 snapshots still decode (new fields default-or-optional).
- **IOKit dispatch-queue lifecycle constraints (2026-04-29-e):** documented in `IOHIDDeviceInspector.swift`. Open before Activate (not after); never `Register*Callback(mgr, nil, nil)` post-Activate (use `Cancel`); per-device input-report registration must happen pre-Activate via `IOHIDManagerCopyDevices` or it asserts on hot-plug arrivals. Match-all uses `IOHIDManagerSetDeviceMatching(mgr, nil)` despite the TN2187 phrasing — empty dict isn't equivalent.
- AXUIElement API for menu bar access
- JSON for config, UserDefaults for settings
- **Non-sandboxed (2026-04-29):** required for global event monitors; aligns with GPLv3 + direct-distribution path
- **Static Info.plist (2026-04-29):** at `01_Project/Info.plist`, outside any synced folder; `GENERATE_INFOPLIST_FILE = NO` because `INFOPLIST_KEY_*` doesn't cover arbitrary TCC keys
- **Recorder UI strategy (2026-04-29):** vendored, not via SPM `KeyboardShortcuts` (D3) — visual parity with the mouse recorder we have to hand-roll anyway
- **Per-machine signing (2026-04-29-d, M4 Pro bootstrapped 2026-05-02-a):** `Debug.xcconfig` shared/tracked; sibling `Debug.local.xcconfig` (gitignored, `.stignore`'d) holds `CODE_SIGN_IDENTITY` per-machine; `#include?` makes it optional. Both Macs now bootstrapped (M1 Max in session-d, M4 Pro in 2026-05-02-a using cert SHA-1 `2D26CB12…0631AA`). See `decisions.md`.

**Distribution / Brand / Legal (decided 2026-04-26):**
- Distribution: direct download primary, MAS evaluated later (caveat: GPLv3 vs MAS terms)
- Pricing: free or ~€5 one-time, no subscription, no phone-home
- License: GPLv3
- Repo: public at github.com/Xpycode/MousePlus

## Action Types (v1)

1. **App Switcher** - as sub-menu
2. **Clipboard** - copy, paste, clipboard manager integration
3. **Menu Bar Access** - show current app's menu with search
4. **Custom Commands** - open app, run shortcut

## Blockers

- **Product decision (#17) still blocks plan B**, but better-informed now. Three options in Current Focus (accept / implement HID++ / coexist). Recommendation strengthened to option 2 by the MX4 evidence: the wire is alive without us doing anything, so we'd be decoding rather than negotiating from zero. Decision now gated on capture #3 (alternate MX4 interface for raw report bytes) so we know what we'd be decoding before committing.
- **Open mystery (not blocking):** menu-bar status item invisible on M1 Max despite same source that produces a working item on the M4 Pro. App runs cleanly, `LSUIElement = true` confirmed in built `Info.plist`, `MenuBarController.statusItem` symbols present in binary, `circle.hexagongrid` SF Symbol renders in System Settings. No crash, no stderr. Worked around via auto-opening Identify Input on launch (clearly-marked temporary workaround in `AppDelegate`). Investigate once IOHIDManager work lands — suspects: notch-position quirk, isTemplate / wallpaper rendering, status-item-dispatch difference under M1 Max's macOS variant.
- **Open question (re-opened 2026-05-02-a):** was the MX3S session-e snapshot a true "firmware-silent" finding or an artifact of the schema-v2 lossy ring buffer? The MX4 capture in session 2026-05-02-a almost produced the same false negative for the MX4 before we found the bug. Resolution: re-capture MX3S on M1 Max with v3 Inspector before treating "MX3S firmware withholds" as ground truth.

## Next Actions

1. [x] Map discovery to architecture
2. [x] Create Xcode project with proper structure
3. [x] Rename PointerActions → MousePlus (2026-04-26)
4. [x] Confirm clean build under new name
5. [x] Push to public GitHub (Xpycode/MousePlus, GPLv3)
6. [x] Decide trigger model (2026-04-29: keyboard + mouse button, mouse premium, no default)
7. [x] Add Accessibility entitlement + sandbox decision (2026-04-29: non-sandboxed; usage strings in static Info.plist)
8. [x] Confirm hotkey events arrive (2026-04-29: ⌘⌃M test trigger fires ring end-to-end)
9. [x] Get ring menu visible at the cursor (2026-04-29: works; key-repeat duplicate-panel bug also fixed)
10. [x] **W2:** Refactor `HotkeyService` → `TriggerService` with protocol-based monitor split + `TriggerBinding` enum + config migration shim (2026-04-29)
11. [x] **Stable Debug signing** to preserve TCC across rebuilds (2026-04-29-a: Apple Development cert SHA-1 + Team `H56HM4MMZS` in Debug.xcconfig)
12. [x] **W3:** `MouseButtonTriggerMonitor` body + tap-toggle interpretation (2026-04-29-b)
13. [x] **Identify Input window** — diagnostic + foundation for W4 recorder (2026-04-29-b: menu bar → "Identify Input...")
14. [~] **W3 partial verify on M1 Max (2026-04-29-d):** standard mouse buttons (incl. back/forward side buttons) fire under NSEvent. MX Master 3S extras silent → triggered the IOHIDManager pivot below.
15. [x] **Per-machine signing pattern (2026-04-29-d):** `Debug.local.xcconfig`, `#include?` from base, gitignored + `.stignore`'d. (M4 Pro still needs its own local file created on next sync — see `decisions.md`.)
16. [x] **W3 backend pivot — A: `IOHIDDeviceInspector`** (2026-04-29-e) — built end-to-end. Multi-pair matching + match-all toggle, value callbacks, raw input reports, JSON snapshot save. Used to capture the MX Master 3S BLE snapshot that *disproved* the consumer-page hypothesis.
17. [ ] **Decision: HID++ strategy for silent buttons** — accept limitation / implement HID++ host-side / coexist with Options+. Now gated on item 17b (capture #3) so the decision is made with raw-byte evidence in hand. Blocks item 18. See Current Focus + Blockers.
17a. [x] **Inspector schema v3 (2026-05-02-a):** added `fireCounts` to JSON, replaced global 80-entry live-capture ring with per-device 10 000-entry buffers, raw-report cap 40 → 1 000, added `matchAllDevices` provenance. Old v2 fixtures still decode. Bumped because session-e's MX3S conclusions were drawn from v2 data that the MX4 capture in this session showed to be lossy enough to mislead.
17b. [ ] **MX4 capture #3 — alternate (vendor-only) interface.** With "Match all" on, pick the second MX4 row in the Inspector picker (likely primary `0xFF43`). Mash silent buttons (DPI, gesture/thumb, wheel-mode toggle) plus standard buttons for cross-reference. Save into `docs/fixtures/`. Goal: populate `rawReports` with `0x11` HID++ payloads so item 17 can be decided with decode-feasibility evidence rather than inference.
17c. [ ] **MX3S re-capture on M1 Max with v3 Inspector.** Verify or refute session-e's "firmware-withholds" conclusion. Save into `docs/fixtures/`. If the MX3S also emits HID++ traffic by default like the MX4, the strategy decision changes shape (decoding-only path becomes viable for both products without divert).
17d. [ ] **Fixture cleanup.** Delete obsolete schema-v2 MX4 snapshot at repo root; move v3 MX4 + future captures into `docs/fixtures/`; add a short README in that folder describing schema versions and what each fixture proves.
18. [ ] **W3 backend pivot — B: `HIDMouseButtonMonitor`** — replace NSEvent body of `MouseButtonTriggerMonitor`; map HID usages → `TriggerBinding.mouseButton(Int)`. If item 17 picks HID++: a `HIDPlusPlus` service feeds button presses into B without B knowing the wire format. Verify hold-release + tap-toggle modes against thumb button + wheel-mode button + side buttons.
19. [x] **Inspector follow-ups (small, 2026-04-29-e):** `HIDDeviceSnapshot.rawReports` field shipped (schemaVersion → 2; populated by `IOHIDDeviceInspector.snapshot(for:)`); `[HID++ pipe]` suffix surfaced in `HIDInspectorPanel` device picker via `inspector.hasVendorPipe(_:)` (elements scanned for usagePage ≥ 0xFF00). Reconciled from working tree on 2026-05-01 after lost-sessions restart; clean build confirmed.
20. [ ] **Lock W3 default** to user's preferred MX Master button once B works.
21. [x] **W4 (2026-05-30-b):** Settings → **Triggers tab** built & verified live — `TriggersSettingsView` (keyboard + mouse rows, Record/Clear, per-binding mode picker, permission banner, 4s interception-timeout warning), new `TriggerRecorderService` + `KeyCodeNames`. Also fixed the wiring bug where saved triggers were ignored at launch (`AppDelegate.applyTriggers` hook + start-from-`configuration.triggers`). Merged to `main` (d430d68). Follow-ups: re-record any pre-fix F-key binding (old `.function` flag); onboarding (W5) should force a choice and drop the temp test default.
22. [ ] **Investigate menu-bar-icon mystery on M1 Max** (background, post-W3); revert auto-open-Identify-Input workaround when fixed.
23. [ ] **W5:** First-launch onboarding flow walking user from zero to a working trigger; "Test your trigger" step.
24. [ ] **Ring UI redesign — concentric wedge menu** (planned 2026-05-30, `IMPLEMENTATION_PLAN.md`, 12 tasks / 5 waves). Supersedes the old "refine ring visuals" line. Parallel track to HID work; run via `/execute` (Wave 1: `AnnularWedge` + `RadialGeometry` + config split).
25. [~] **HUD actions backend — superseded by `HUD_ACTIONS_PLAN.md` (2026-05-30-c).** The ring renders but `ActionService` is mostly stubs. Five action types specced (menu mirror, window snap, app switcher, system toggles, screenshots) + a shared foundation. Sub-tasks:
   - 25a. [ ] **§1 Shared foundation** (~1–1.5d): extend `ActionType` (add windowSnap/systemToggle/screenshot, drop clipboard); async `RingViewModel.expand()` w/ stale-guard; `IconSource` enum + `WedgeView` render change; one reusable Accessibility-TCC status/prompt flow; dismiss-before-action seam.
   - 25b. [ ] **Feature B — Window snapping** (~2d, recommended first feature): `actor WindowService`, `SnapZone` enum, own middle wedge → 8-direction outer arc. Rectangle's enhanced-UI + size→pos→size hacks; primary-screen y-flip.
   - 25c. [ ] **Feature E — Screenshots** (~0.5–1d): `ScreenshotService` + `ShotMode`, interactive `screencapture` modes (no TCC), dismiss-ring-first.
   - 25d. [ ] **Feature A — Menu-bar mirror** (~1.5–2d): `@MainActor AccessibilityService`, top-level radial → native NSMenu handoff. Port from menuanywhere. Implements the existing `.menuBar` case.
   - 25e. [ ] **Feature C — App switcher** (~1.5–2d): `actor AppSwitcherService`, self-tracked MRU, real app icons via `IconSource`.
   - 25f. [ ] **Feature D — System toggles** (~3.5–4d): `actor SystemToggleService`, curated `SystemToggle` enum, Settings picker + TCC pre-priming. DND/brightness deferred.
26. [~] **v1.1 CGEventTap plan:** likely subsumed by IOHIDManager pivot (item 18). Confirm during W3 backend work; retire if unneeded. Memory key `karabiner-driverkit-mouse-interception` still relevant as a known-coexistence concern.
27. [ ] **App-aware command rings + menu-bar palette** (planned 2026-05-30, `APP_COMMANDS_PLAN.md`). App-specific curated shortcuts in RING 3, paginated overflow, and a center-hub search palette (Paletro-class) over the frontmost app's AX menu bar, with pin-from-search self-curation; conditional Liquid Glass (macOS 26) + `.ultraThinMaterial` fallback (min target stays 14). Builds on `HUD_ACTIONS_PLAN.md` Feature A's shared `AccessibilityService` — Phase 0 (AX engine) also kills the long-standing `ActionType.menuBar` stub and is independently valuable. Ring-UI track; not blocked by the HID++ decision (#17). 5-agent research + Tahoe-adoption basis logged in `decisions.md` (2026-05-30 "App-Aware Command Rings"). **Now `/execute`-ready (2026-05-30):** all 5 phases fleshed into build-gated waves in `APP_COMMANDS_PLAN.md` §4 (P0–P4, ~4 waves each, IMPLEMENTATION_PLAN.md format) — same-file conflicts kept out of shared waves, per-phase reuse notes (P0 reuses existing `PermissionsService` for the AX-TCC flow, so no new permission plumbing), naming pinned to §3.2 `DynamicSource`, verify waves honor the no-synthetic-input rule. **Recommended start: Phase 0** (AX engine; reuses `PermissionsService`; kills the `.menuBar` stub; no UI). **Phase 4 (Liquid Glass) is hard-gated** on the macOS 26 SDK to compile *and* macOS 26 hardware to verify — sequence it last / defer.

---
*Updated automatically by Claude during sessions*
