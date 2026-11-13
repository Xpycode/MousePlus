# Session History

## Active Project
**MousePlus** (formerly PointerActions, renamed 2026-04-26) — Radial quick-access menu for macOS

## Current Status
→ See [PROJECT_STATE.md](../PROJECT_STATE.md)

## Sessions

| Date | Focus | Outcome | Log |
|------|-------|---------|-----|
| 2026-11-13 | Permission-loss investigation, remediation plan and plan review | Incident E1 failed. Plan review found the hang documented (Apple forums 844416, 735204); user decided self-relaunch on loss. Plan revision 2: seven tasks, five waves. Wave 1 executed: R0 headless harness, 43 tests pass, build-only succeeded, uncommitted. Next: R1 ready, R2 blocked on G1. No live permission toggles; VoiceOver excluded. | [Log](2026-11-13.md) |
| 2026-11-10 | Settings acceptance and mouse-trigger suppression | Picker and changed-shortcut persistence passed. Direct mouse leaked clicks to Warp; consuming-tap fix tested, signed and launched, live retest pending. Native Space/Return behavior clarified; E1 open. | [Log](2026-11-10.md) |
| 2026-11-08 | Settings acceptance and HUD preview/tree correction | Correct MousePlus screenshot confirms header/sidebar appearance; title-area dragging, both trigger modes over Finder, keyboard recording and an additional cross-app check passed. Global preview parity and sidebar HUD tree accepted; app-profile switching/deletion through the new tree remains untested. Onboarding acceptance remains open. | [Log](2026-11-08.md) |
| 2026-11-07 | Settings fixes, title layout and onboarding acceptance | Persistence/colors/title and current trigger/Escape accepted; 74 tests passed. Fresh-install checks deferred. Latest signed build left running. Mouse-recorder timeout and configured relaunch passed. Keyboard focus/cancellation passed. Header color/dragging remediation pending live acceptance. | [Log](2026-11-07.md) |
| 2026-10-29 | Recorder failure and wedge-color discrepancy diagnosis | Fresh working-tree build fixed the trigger recorder and is installed at /Applications. Menu-editor keystroke captures succeed but edits stopped reaching the saved config; two color-well bugs confirmed. A diagnostic build is running to name the drop point. Next: reproduce, read SettingsWorkspace logs, fix drop and color-well bugs. | [Log](2026-10-29.md) |
| 2026-10-03 | Save pre-clear onboarding handoff | Candidate present; GUI-only handoff restored beside it. No shared results or live acceptance evidence yet. Next: run test-account checks, return results, and review E1. | [Log](2026-10-03.md) |
| 2026-09-27 | Prepare signed onboarding acceptance | Candidate verified and GUI-only test-account handoff staged; no launch or live checks yet. VoiceOver deferred. Next: run handoff, save results in `/Users/Shared/`, and review E1. | [Log](2026-09-27.md) |
| 2026-09-26 | Recorder recovery and trigger onboarding | Earlier recorder fix merged; onboarding implemented on a local feature branch. Tests, builds, signing and review pass; signed candidate staged. Next: live onboarding acceptance. | [Log](2026-09-26.md) |
| 2026-09-25 | Export a notarized MousePlus app | Release 0.1.0 (1) archived with Developer ID and hardened runtime; Apple accepted notarization. Stapled ZIP passed extraction, signature, and Gatekeeper checks. Local artifact only; next: acceptance testing and release prerequisites. | [→](2026-09-25.md) |
| 2026-09-17 | Complete Finder/Global acceptance and install a versioned build | E1/AC19 passed and the plan was archived. Developer ID-signed Release 0.1.0 (1) was installed and launched from `/Applications` on M1-Max; local build is unnotarized. | [→](2026-09-17.md) |
| 2026-09-13 | HUD appearance options and Finder/Global live acceptance | Transparent/complete backing accepted; recorded 134 tests. Fresh signed build and live checks through action targeting pass. Next: relaunch persistence, deletion, and post-delete fallback. Test app quit; commit/push requested for all pending work. | [→](2026-09-13.md) |
| 2026-09-11 | Close Opening Styles, plan app-specific HUDs, and execute Waves 1–5 | E1 setup/collision acceptance passed: no trigger beep, duplicate retains the saved shortcut, and inline explanation is accepted. Fresh signed PID 13650 remains running. Next: route switching through deletion/persistence. | [→](2026-09-11.md) |
| 2026-09-06 | Continue opening-style acceptance | Added native center frame/AXPress regression; 124 focused and 304 full tests pass. Signed build/live AX verified. Saved test checklist and pre-clear handoff; no new user acceptance. Task 5.1 open. | [→](2026-09-06.md) |
| 2026-09-05 | HUD Opening Styles and trigger diagnosis | User verified the center-drift fix through BetterMouse and continued Warp tab-navigation suppression; recorded tests: 303 passed. Native-trigger and remaining acceptance checks stay open. | [→](2026-09-05.md) |
| 2026-09-04 | Execute HUD Motion v1 Wave 3 | Added summon fade and safe outer-branch crossfades; immediate commit/dismissal preserved. All 48 focused tests and Debug build pass. Next: Wave 4 native motion controls; live checks remain in Wave 5. | [→](2026-09-04.md) |
| 2026-09-04 | Investigate HUD animation feasibility | Confirmed the overlay can support restrained role-based motion; recorded safe effects, rejected disruptive ones, and established immediate interaction with Reduce Motion-aware presentation. Next: plan Motion v1. | [→](2026-09-04.md) |
| 2026-09-04 | Close the remaining App Switcher v1 live checks | A fresh signed build passed; the user confirmed recent-usage ordering and clean rapid Apps↔Snap re-pointing with no stale icons. App Switcher v1 is complete; HUD-animation feasibility was captured for later. | [→](2026-09-04.md) |
| 2026-09-04 | Live-verify App Switcher activation and prototype a richer circular layout | Routed tap-toggle commits through native AppKit mouse-up, then added and live-verified a pointer-aligned full-circle running-app ring with optional labels. Build and 249 tests pass. Next: MRU/re-point checks, then scope the next switcher increment. | [→](2026-09-04.md) |
| 2026-09-04 | Clarify dynamic Apps and clean up Selected Item controls | Confirmed live running-app names/icons; made Apps read-only in the inspector, hid preserved inactive children, centralized outer-item creation, and moved Delete to the footer. Signed builds pass. Next: verify activation, MRU, rapid re-pointing; review label crowding. | [→](2026-09-04.md) |
| 2026-09-04 | Decide Action selector UX and fix App Switcher Settings preview | Logged the Action choice-grid decision; migrated legacy Apps configs losslessly; fixed dynamic-parent commit and preview Reveal overwriting the clicked branch. Full suite and signed build pass; user confirmed the Apps/Snap sequence. Next: live-HUD Apps verification. | [→](2026-09-04.md) |

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
