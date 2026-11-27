# Session History

## Active Project
**MousePlus** (formerly PointerActions, renamed 2026-04-26) — Radial quick-access menu for macOS

## Current Status
→ See [PROJECT_STATE.md](../PROJECT_STATE.md)

## Sessions

| Date | Focus | Outcome | Log |
|------|-------|---------|-----|
| 2026-11-27 | Select the app icon and organize local installers | Verified the eight-wedge Radial Fan icon in Finder, organized signed installers in 04_Exports and logged permission and appearance work. The first Accessibility grant in AppAtlas remains open. | [Log](2026-11-27.md#resume) |
| 2026-11-26 | Retry MousePlus Accessibility approval | The signed baseline requested access again. The picker disabled Open while the macOS permission alert remained available. Check the Accessibility list from that alert before testing the second build. | [Log](2026-11-26.md) |
| 2026-11-25 | Check Accessibility across signed builds | The installed baseline passed signature verification. The helper's Accessibility picker kept Open disabled for both copies. Diagnose the first grant before testing the second build. | [Log](2026-11-25.md) |
| 2026-11-24 | Use Global ring | Inner and Middle switches implemented and tested. 94 focused checks passed. Confirm, cancel and independent editing verified in Atlas. | [Log](2026-11-24.md) |
| 2026-11-22 | App HUD inheritance live acceptance | E2 passed in Safari after reverting a migrated Copy that had no keystroke; inheritance plan complete. Footer buttons fit one row (Earlier/Later). Spec addendum: per-ring Use Global switch (AC20–27). Next: plan it. | [Log](2026-11-22.md#session-4-2026-11-22-app-hud-inheritance-live-acceptance) |
| 2026-11-22 | App HUD inheritance execution (all waves) | All 11 tasks done in 7 commits (unpushed): migrate/resolve/save sparse overrides, Settings UI for inherited/customized/hidden items. 250/251 focused tests (one was already failing), review clean, Atlas Settings check passed after two layout fixes. Next: E2 user live acceptance. | [Log](2026-11-22.md#session-3-2026-11-22-app-hud-inheritance-execution) |
| 2026-11-22 | App HUD inheritance spec + plan | Spec approved: app menus follow Global by item ID; whole-item Customize/Revert, hide/restore, custom order, 8-item warning, Test Action source. Plan: 11 tasks, 5 waves + 2 acceptance checks. Next: /execute Wave 1. | [Log](2026-11-22.md#session-2-2026-11-22-app-hud-inheritance-spec-and-plan) |
| 2026-11-22 | Mouse trigger reaching other apps (Warp tabs), Global menu save guard, Test Action keystroke target | Trigger button is now captured so other apps never see it; Global menu saves refuse to overwrite external changes; Test Action sends keystrokes to the remembered app. User-verified; 75/75 focused tests; committed. Decided App HUDs will inherit from Global. Next: inheritance spec. | [Log](2026-11-22.md) |
| 2026-11-21 | Fix the stale Menu Items preview and US-only key labels; then Send Keystroke not reaching Safari | Key labels now follow the keyboard layout (confirmed). Preview fix is a precaution; cause not reproduced. Ring clicks made MousePlus the active app, so keystrokes missed Safari; fixed by a ring panel that cannot take keyboard focus plus a focus hand-back; 114 focused tests passed before the panel change, user accepted live. Committed. Next: decide on local signing. | [Log](2026-11-21.md) |
| 2026-11-18 | Set up MousePlus on the reset M4 Pro | Fresh clone; unsigned Debug build runs (no certs on this Mac). Found two bugs: Menu Items preview shows sample ring while "Saved" (possible overwrite risk) and US-only key labels (German # shows as \). Config backed up. Next: diagnose preview bug. | [Log](2026-11-18.md) |
| 2026-09-26 | Recorder, preview, and permission-dialog recovery | Recorder verified; preview dimensions fixed; 11 tests pass. Stuck macOS dialog cleared; corrected signed app passed permission, trigger, and layout acceptance. Merged and pushed to main; next: scope trigger onboarding. | [Log](2026-09-26.md) |
| 2026-09-25 | Export a notarized MousePlus app | Release 0.1.0 (1) archived with Developer ID and hardened runtime; Apple accepted notarization. Stapled ZIP passed extraction, signature, and Gatekeeper checks. Local artifact only; next: acceptance testing and release prerequisites. | [→](2026-09-25.md) |
| 2026-09-17 | Complete Finder/Global acceptance and install a versioned build | E1/AC19 passed and the plan was archived. Developer ID-signed Release 0.1.0 (1) was installed and launched from `/Applications` on M1-Max; local build is unnotarized. | [→](2026-09-17.md) |
| 2026-09-13 | HUD appearance options and Finder/Global live acceptance | Transparent/complete backing accepted; recorded 134 tests. Fresh signed build and live checks through action targeting pass. Next: relaunch persistence, deletion, and post-delete fallback. Test app quit; commit/push requested for all pending work. | [→](2026-09-13.md) |
| 2026-09-11 | Close Opening Styles, plan app-specific HUDs, and execute Waves 1–5 | E1 setup/collision acceptance passed: no trigger beep, duplicate retains the saved shortcut, and inline explanation is accepted. Fresh signed PID 13650 remains running. Next: route switching through deletion/persistence. | [→](2026-09-11.md) |
| 2026-09-06 | Continue opening-style acceptance | Added native center frame/AXPress regression; 124 focused and 304 full tests pass. Signed build/live AX verified. Saved test checklist and pre-clear handoff; no new user acceptance. Task 5.1 open. | [→](2026-09-06.md) |
| 2026-09-05 | HUD Opening Styles and trigger diagnosis | User verified the center-drift fix through BetterMouse and continued Warp tab-navigation suppression; recorded tests: 303 passed. Native-trigger and remaining acceptance checks stay open. | [→](2026-09-05.md) |
| 2026-09-04 | Execute HUD Motion v1 Wave 3 | Added summon fade and safe outer-branch crossfades; immediate commit/dismissal preserved. All 48 focused tests and Debug build pass. Next: Wave 4 native motion controls; live checks remain in Wave 5. | [→](2026-09-04.md) |
| 2026-09-04 | Investigate HUD animation feasibility | Confirmed the overlay can support restrained role-based motion; recorded safe effects, rejected disruptive ones, and established immediate interaction with Reduce Motion-aware presentation. Next: plan Motion v1. | [→](2026-09-04.md) |
| 2026-09-04 | Close the remaining App Switcher v1 live checks | A fresh signed build passed; the user confirmed recent-usage ordering and clean rapid Apps↔Snap re-pointing with no stale icons. App Switcher v1 is complete; HUD-animation feasibility was captured for later. | [→](2026-09-04.md) |

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
