# Session History

## Active Project
**MousePlus** (formerly PointerActions, renamed 2026-04-26) — Radial quick-access menu for macOS

## Current Status
→ See [PROJECT_STATE.md](../PROJECT_STATE.md)

## Sessions

| Date | Focus | Outcome | Log |
|------|-------|---------|-----|
| 2026-09-05 | HUD Opening Styles and trigger diagnosis | Fixed reproduced post-mount center drift; 303 tests pass. BetterMouse mapping must keep suppressing Warp tab navigation. Physical native-trigger and remaining visual/accessibility acceptance stay open. | [→](2026-09-05.md) |
| 2026-09-04 | Execute HUD Motion v1 Wave 3 | Added summon fade and safe outer-branch crossfades; immediate commit/dismissal preserved. All 48 focused tests and Debug build pass. Next: Wave 4 native motion controls; live checks remain in Wave 5. | [→](2026-09-04.md) |
| 2026-09-04 | Investigate HUD animation feasibility | Confirmed the overlay can support restrained role-based motion; recorded safe effects, rejected disruptive ones, and established immediate interaction with Reduce Motion-aware presentation. Next: plan Motion v1. | [→](2026-09-04.md) |
| 2026-09-04 | Close the remaining App Switcher v1 live checks | A fresh signed build passed; the user confirmed recent-usage ordering and clean rapid Apps↔Snap re-pointing with no stale icons. App Switcher v1 is complete; HUD-animation feasibility was captured for later. | [→](2026-09-04.md) |
| 2026-09-04 | Live-verify App Switcher activation and prototype a richer circular layout | Routed tap-toggle commits through native AppKit mouse-up, then added and live-verified a pointer-aligned full-circle running-app ring with optional labels. Build and 249 tests pass. Next: MRU/re-point checks, then scope the next switcher increment. | [→](2026-09-04.md) |
| 2026-09-04 | Clarify dynamic Apps and clean up Selected Item controls | Confirmed live running-app names/icons; made Apps read-only in the inspector, hid preserved inactive children, centralized outer-item creation, and moved Delete to the footer. Signed builds pass. Next: verify activation, MRU, rapid re-pointing; review label crowding. | [→](2026-09-04.md) |
| 2026-09-04 | Decide Action selector UX and fix App Switcher Settings preview | Logged the Action choice-grid decision; migrated legacy Apps configs losslessly; fixed dynamic-parent commit and preview Reveal overwriting the clicked branch. Full suite and signed build pass; user confirmed the Apps/Snap sequence. Next: live-HUD Apps verification. | [→](2026-09-04.md) |
| 2026-09-04 | Resolve Reveal and Menu Items editor UX decisions | Reveal now supports direct entry; the left toolbar was removed and per-ring add actions moved into setup tabs, stabilizing the preview. Automated suite passed; live App Switcher verification remains. | [→](2026-09-04.md) |
| 2026-09-04 | Execute the App Switcher plan (Waves 1–4) via wave-based subagents | Landed `DynamicSource`/`IconSource` model types, an async epoch-guarded `RingViewModel.expand()` with `WedgeView`/`RingMenuView` icon-source plumbing, a new `AppSwitcherService` actor (self-tracked MRU, capped at 12), and then wired the service into `.runningApps` (epoch-guarded fetch + populate, sample "Apps" wedge switched over, editor-preview placeholder). Fixed a cross-cutting `hasSubItems` gap the wedge-drop would have silently broken. Each wave built clean and was committed separately (`feat(wave-1..4)`). Next: Wave 5 (closure gate — full suite + signed live verification). | [→](2026-09-04.md) |
| 2026-09-04 | Spec the app switcher, system toggles, and a Help/Feedback/Tip/Appearance Settings tab | Wrote full phased implementation plans (`APP_SWITCHER_PLAN.md`, `SYSTEM_TOGGLES_PLAN.md`, `APP_CHROME_SETTINGS_PLAN.md`), reconciled against current `ActionService`/`RingViewModel` code, correcting stale assumptions in the older HUD plan sketch. No code changes; docs-only, uncommitted. Next: execute one of the three plans, or pick up screenshots. | [→](2026-09-04.md) |
| 2026-09-04 | Implement and verify the menu-bar Restart MousePlus command | Added and signed-live-verified a flush → fresh-instance launch → terminate lifecycle barrier with regression tests; committed and pushed the clean branch. Next: screenshots HUD action. | [→](2026-09-04.md) |
| 2026-09-04 | Close the signed HUD redesign, then plan and execute the full ring-controls reorganization (Waves 1–4) | The redesign passed all live checks with 217 tests green and was committed. Planned and confirmed Menu/Inner/Middle/Outer tab ownership, landed Wave 1 (tolerant per-ring label model plus a pure readable-rotation presentation policy), Wave 2 (native Menu/Inner/Middle/Outer segmented inspector), Wave 3 (wired label visibility/orientation into live HUD and preview, proved the fields survive every Settings write path), and Wave 4 (adversarial review fixed a wedge-caption width bug; signed Debug build quit/relaunched live and confirmed working). 235/235 tests pass; ring-controls reorganization complete. Logged a "Restart MousePlus" menu-bar item to the backlog. | [→](2026-09-04.md) |
| 2026-09-03 | Execute, live-verify, and remediate the sustained-use HUD redesign | Reorder and dismissal passed live; a macOS 27 Window Snap crash was fixed and retested with 207 tests green. Color verification remains; clearer root “Default” wording is logged for the next UI-design pass. | [→](2026-09-03.md) |
| 2026-09-02 | Close Send Keystroke, plan the sustained-use HUD redesign, and execute Waves 1–4 | Runtime and editor integration now support independent rings, safe commits, durable customization, native controls, item colors, and a non-executing preview; the full unit target and signed Debug build pass. Next: `/execute wave 5`. | [→](2026-09-02.md) |
| 2026-09-01 | Unified Settings completion, merge, and repository repair | All 8 waves and the live gate passed; the verified real history now owns local and GitHub main, with the displaced April history preserved on a backup branch. Audit confirmed Send Keystroke is implemented; next is its remaining signed live checklist. | [→](2026-09-01.md) |
| 2026-08-10 | Plan ③ Send-Keystroke (3-agent research) + git false-alarm triage | ✅ **`SEND_KEYSTROKE_PLAN.md` written** (7 tasks / 4 waves): `ActionType.sendKeystroke`, payload `"keyCode:modifiers"`, private CGEventSource + explicit flags on down+up + `.cghidEventTap` so other apps' global hotkeys fire (QSP ⌃⌥⌘Q); editor row reuses `TriggerRecorderService`; Mission Control = `open -b com.apple.exposelauncher`; inner Copy/Paste/Spotlight defaults become real; permission gate resolved empirically via `CGPreflightPostEventAccess()`. Also resolved the pre-flight "origin/main 4 ahead" warning as a **false alarm** — `origin/main` is an orphaned pre-re-init April history; local `main` fully contained in the branch; replace `origin/main` deliberately at merge time. Clean build + launch for T12; the 4 regression checks still pending. Next: T12 → merge → cut `feature/send-keystroke` → `/execute` | [→](2026-08-10.md) |
| 2026-07-12 | Reconcile the stalled working tree — commit + push, clean-build, live-verify | ✅ **Committed the two build-verified-but-uncommitted batches as clean feature-separated commits** on `feature/menu-editor` and pushed: `fd0d04b` menu-editor Wave 5 data-loss fixes + `5b6dc77` app-shell ⌥⌘, Settings hotkey. Disjoint .swift files → `git add <path>` split them (no per-hunk); shared narrative docs rode the later commit. Clean build (stable signing, TCC preserved) → **live-verify ① ⌥⌘, opens Settings = PASS**; ② menu-editor regressions **deferred**. Investigated **QuickStatsPanel** tile integration: LSUIElement, no URL scheme/CLI → only its Carbon global hotkey ⌃⌥⌘Q, so needs a **send-keystroke** action (③) or an osascript `custom`-action stopgap. Next: finish live-verify ② → `--no-ff` merge to `main`. | [→](2026-07-12.md) |
| 2026-07-08 | App-shell access — kill Identify-Input auto-open + global Settings hotkey | ✅ **Built & build-verified (UNCOMMITTED, live-verify pending).** Removed the launch-time Identify-Input auto-open → now via **Settings ▸ General ▸ Diagnostics** + menu bar. New global **⌥⌘,** "Open Settings" hotkey (`TriggersConfig.openSettings`, rebindable in Triggers), armed by a dedicated `KeyboardTriggerMonitor`; `TriggersConfig` made **decode-tolerant** so the new key can't break old configs (synthesized-`Codable` `keyNotFound` trap). Snag: user pressed plain ⌘, (it's ⌥⌘,) + wanted Settings *from the HUD* → diagnosed live config (inner ring = empty `custom` no-ops; only Snap/Apps expand). Next: `ActionType.openSettings` (Settings wedge) + ③ Send-Keystroke. Disjoint files from the menu-editor tree. | [→](2026-07-08.md) |
| 2026-07-07 | Menu editor code review — bugs, enhancements, feature-gap audit | ✅ **7 bugs found & fixed, build-verified** (manual read + independent review-agent pass + all 89 curated SF Symbols runtime-validated). Criticals: preview "+ add" ghost stole the last wedge's clicks on the default 4/4 config; corrupt `config.json` silently overwritten with defaults by autosave → new `LoadState` save gate + alert. Also: per-band spoke cap, fresh-disk-read merge base (Settings edits no longer reverted), close→reopen race, stale `actionData` on type switch, single observation chain, lazy app-picker icons. Findings + feature-gap backlog → `MENU_EDITOR_REVIEW.md`. T11 nearly closed; open: symbol-validation save-gate design choice, then T12. Env: fixed M4 Pro signing (wrong Mac's cert SHA in `Debug.local.xcconfig`). Branch pushed to origin (first upstream). **Part 2 (Wave 5 close):** T11 resolved = **persist-with-placeholder + defensive render** (`SFSymbol.resolved()` at every icon draw site → no blank wedge from the editor, a hand-edited config, or an older build; `ea4a2fc`); **editor relaid side-by-side** (draggable `HSplitView`, ring left / form right, window min 900×600; `ca223b5`). Both build-verified + live. **Part 3 (Fable adversarial panel):** ran a 4-lens Fable-5 review (correctness / invariants / persistence / SwiftUI-identity) over the same diff hunting for MISSES → **15 new findings**; cross-lens agreement + a code read confirmed a real **data-loss race** the first pass (and one Fable lens) cleared: `refreshFromDisk` treated a *cancelled* debounce task as a completed save → reopen-mid-debounce reverted edits. Fixed clusters **A** (load/save path — deterministic flush, bail-on-corrupt, surface write errors), **B** (normalize direct `.windowSnap` payloads so a de-subitem'd wedge can't no-op behind a "Left" label + outer-band cap), **D** (T11 miss at `RingPreviewSelector:220`) — kills 5 data-loss paths + F7/F8/F11/F15, build-verified. 6 deferred as logged risks (incl. F5: Settings writers still wipe corrupt config). All in `MENU_EDITOR_REVIEW.md` §7. **Uncommitted** — T12 gates the commit. Remaining: T12 live verify, then `--no-ff` merge | [→](2026-07-07.md) |
| 2026-06-02 | Menu Items editor — review checkpoint (Waves 1–4) | ✅ Clean-build + run for visual review. Confirmed editor **Waves 1–4** are committed on `feature/menu-editor` (`19bbab6`→`822b360`, built 2026-05-31 but **never logged** — captured here retroactively); working tree clean; only **Wave 5** (T11 invariants + T12 live verify) remains. Clean-build cycle (`killall` → wipe DerivedData → `xcodebuild` Debug → **BUILD SUCCEEDED** → `open`). Launch path: **Settings → "Menu Items" → "Open Menu Editor…"** (`MenuEditorWindowController`, min 560×620). What's built: live click-to-select ring preview + detail form, SF-Symbol grid (validated, no blank wedges) + App picker (bundle ID), action-type-aware data, per-middle sub-items, add/remove/reorder, debounced 400ms autosave → live-apply + close-flush, Reset-to-Defaults. No code changes; awaiting user review feedback to fold into Wave 5 | [→](2026-06-02.md) |

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
