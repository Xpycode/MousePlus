# Session History

## Active Project
**MousePlus** (formerly PointerActions, renamed 2026-04-26) — Radial quick-access menu for macOS

## Current Status
→ See [PROJECT_STATE.md](../PROJECT_STATE.md)

## Sessions

| Date | Focus | Outcome | Log |
|------|-------|---------|-----|
| 2026-05-30-b | Triggers settings tab (W4) | ✅ Built & verified live. New `TriggersSettingsView` (keyboard + mouse binding rows, Record/Clear, per-binding hold-release/tap-toggle picker, permission banner, 4s interception-timeout warning) + `TriggerRecorderService` (one-shot recorder) + `KeyCodeNames`. Swapped dead "Hotkey" tab → "Triggers"; `TriggersConfig: Equatable`. **Wiring-bug fix:** app booted the hardcoded F5+middle default regardless of saved config — `setupTriggers` now starts from `configuration.triggers` and a new `AppDelegate.applyTriggers` hook + load-completion push saved/edited triggers into the live `TriggerService` (rebind, no restart). Fixes in verification: recorder stripped `.function` flag (was breaking mouse→F-key injection), Identify Input minimize restored (`.floating`→`.normal`), temp "Settings…" button added to Identify Input (M1 Max menu-bar-icon workaround). Verified: rebind to F4 with no restart, persisted across quit+relaunch, F4 opens the ring. Process lesson: launch `TARGET_BUILD_DIR`, not `find\|head` (had been launching a stale ad-hoc build). On branch `feature/triggers-settings-tab` | [→](2026-05-30-b.md) |
| 2026-05-30-a | Execute concentric ring menu UI plan (`/execute`, 5 waves) | ✅ COMPLETE & verified live. Replaced circles-in-a-ring with a concentric wedge menu: inner symbol ring + middle labeled ring on locked shared spokes, on-demand outer ring as a localized arc, Blender-style angle hit-testing, branch dimming, Esc/click-outside dismissal. 12 tasks / 5 waves, each wave build-gated green; new files `AnnularWedge`, `WedgeView`, `RadialGeometry`, `DismissMonitor`; rewrote `RingViewModel`/`RingMenuView`/`RingWindowController`; `Configuration` inner/middle split + `AppearanceConfig` band-radius/dim/keepSpokeLit + Ring Appearance settings tab. Three bugs caught in live verification & fixed: app quit on last-window-close (`applicationShouldTerminateAfterLastWindowClosed`), Esc not dismissing (needed a local key monitor), F5/voice-key collision (temp test trigger). git initialized this session (baseline on `main` + per-wave commits on a feature branch + fixes), merged `--no-ff` to `main`, branch deleted | [→](2026-05-30-a.md) |
| 2026-05-02-a | MX4 capture on M4 Pro + Inspector schema-v3 fixes | M4 Pro signing bootstrapped (`Debug.local.xcconfig`). Inspector bumped to schema v3: `fireCounts` in JSON, per-device live-capture buffers (cap 80→10000), raw-report cap (40→1000), `matchAllDevices` provenance. MX4 BLE snapshot captured with match-all on: 5/7 page-9 buttons fire on raw HID (L/R/M + 2 sides), buttons 6/7 silent; vendor pipe is page 0xFF43 (vs 3S's 0xFF03) and emits HID++ traffic *without* divert (six vendor cookies fired) — directly contradicts session-e's "firmware-withholds" finding for the MX3S. Raw reports still empty on standard mouse interface; vendor-only interface needs a separate capture. HID++ decision (#17) still deferred pending capture #3 | [→](2026-05-02-a.md) |
| 2026-05-01-a | State recovery post-restart + HID++ option 2 scoping | Mac restart lost several sessions; reconciled "code shipped, docs lag" pattern (task #19 already done in tree — `HIDDeviceSnapshot.rawReports` field + `[HID++ pipe]` suffix in inspector picker — but PROJECT_STATE.md still flagged it open). Scoped option 2 (HID++ 2.0 host-side) for the pending #17 decision: file plan `HIDPlusPlus.swift` + `HIDPlusPlusFeatures.swift` + `HIDMouseButtonMonitor.swift` (~250 LoC), actor-per-device surface exposing `enumerateFeatures()` / `divertButton(controlID:)` / `var buttonEvents: AsyncStream<HIDPlusButton>`; 5-phase breakdown with LoC + per-phase risks (Bolt-receiver vs BLE divergence, Logi Options+ coexistence, no exclusive HID open, per-product controlID variance MX3/3S/4). HID++ strategy decision (#17) explicitly deferred (user exhausted). MX3S BLE snapshot fixture (`hid-046d-b034-1x2-2026-04-29.json`) missing on this machine — needs copy from M1 Max into `docs/fixtures/` for offline controlID derivation | [→](2026-05-01-a.md) |
| 2026-04-29-e | Plan A review + execute IOHIDDeviceInspector end-to-end | Inspector built (multi-pair + match-all matching, value-callback + raw input reports, snapshot save). Three IOKit dispatch-queue asserts surfaced and fixed (Open-before-Activate, no register-nil post-Activate, pre-Activate input-report registration). MX Master 3S BLE snapshot captured: device DECLARES the HID++ pipe but firmware emits zero events for DPI/thumb/gesture without HID++ activation — earlier "macOS filters vendor reports" hypothesis disproven. Decision pending on plan B strategy (accept / implement HID++ / coexist with Options+) | [→](2026-04-29-e.md) |
| 2026-04-29-d | W3 verification on M1 Max + IOHIDManager pivot | Per-machine xcconfig pattern (`Debug.local.xcconfig`, `#include?`) unblocks cross-Mac builds; standard mouse buttons fire, MX Master extras silent under NSEvent → architectural pivot to IOHIDManager (likely retires v1.1 CGEventTap plan); menu bar icon mystery deferred behind auto-open-Identify-Input workaround | [→](2026-04-29-d.md) |
| 2026-04-29-c | Post-reboot resume + venue pivot | DriverKit confirmed gone via `systemextensionsctl`; clean build + launch; W3 verification deferred to a Karabiner-never-installed second Mac (cleaner baseline than post-uninstall remote machine) | [→](2026-04-29-c.md) |
| 2026-04-29-b | W3 mouse-button monitor + Identify Input window + Karabiner discovery | Tap-toggle wired; mouse pipeline verified for buttons 0/1/2; buttons 3+ blocked by Karabiner DriverKit; v1.1 CGEventTap upgrade planned; pause for user reboot after Karabiner uninstall | [→](2026-04-29-b.md) |
| 2026-04-29-a | W1 trigger refactor — permissions unblocker | ⌘⌃M test trigger fires ring; AX permission gate + onboarding sheet wired; original blocker dead | [→](2026-04-29-a.md) |
| 2026-04-26-a | Resume + rename PointerActions → MousePlus | Project renamed/relocated, git initialised, distribution + pricing decided | [→](2026-04-26-a.md) |
| 2026-01-12-a | Create Xcode project | Menu bar app running, Settings works, hotkey not working | [→](2026-01-12-a.md) |
| 2026-01-09-a | Discovery interview | Core requirements defined, decisions logged | [→](2026-01-09-a.md) |

---

## Session Log Template

When starting a new session, create a file: `sessions/YYYY-MM-DD-[a|b|c].md`

```markdown
# Session: [Date] [a/b/c]

## Goal
[What we're trying to accomplish]

## Context
- Previous session: [link or summary]
- Current phase: [discovery|planning|implementation|polish|shipping]

## Progress

### Completed
- [x] [What got done]

### In Progress
- [ ] [What's being worked on]

### Discovered
- [New things learned]

### Decisions Made
- [Decision] → logged in decisions.md

### Blockers
- [Anything blocking progress]

## Next Session
- [What to do next]

## Notes
[Anything else worth remembering]
```

---
*One log per session. Link from here.*
