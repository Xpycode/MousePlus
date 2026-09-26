# Tasks

> **Persistent task tracker.** Lives in `docs/`. Progress syncs to PROJECT_STATE.md.

## Backlog
<!-- Ideas and future work. Added by /interview, user input, or discovered during development. -->
<!-- Priority: top = highest, bottom = lowest -->

- [ ] Expand the Menu Items icon browser beyond the current curated SF Symbols and add search/filtering
  inside its existing Browse popover. Requested during app-specific HUD E1 acceptance on 2026-09-11;
  placement and exact catalog scope still need confirmation under the UI-change protocol.

- [ ] Scope the next MousePlus App Switcher increment beyond the live-verified full-circle running-app ring: compare window switching, recent apps, search, grouping/paging, and keyboard/pointer hybrids. Complete app-specific HUDs are finished separately.

- [ ] Center outer-ring labels beneath their icons when an expansion chevron is present. A
  2026-09-11 user screenshot shows the `Apps` and `Snap` labels centered under the combined
  icon-plus-chevron row rather than under the icon itself, shifting both labels toward the
  chevron. Confirmed visual polish issue; non-blocking for Opening Styles acceptance.

- [ ] Before release, perform the deferred VoiceOver acceptance pass for Opening Styles: Settings
  label/value and Replay button, preview semantics, and stable live-HUD action labels/order with
  immediate activation. Explicitly skipped by the user on 2026-09-11; untested, not failed.

- [ ] Before release, complete deferred Opening Styles coverage outside the supported BetterMouse
  route: isolated direct MousePlus physical mouse triggering, maximum geometry and screen edges,
  branch/configuration combinations, and smoothness on other supported Macs. Explicitly deferred
  by the user on 2026-09-11; untested, not failed.

## Current Sprint
<!-- Active work. Populated by /plan or /execute. Keep focused (3-7 tasks). -->
<!-- When done: /log moves to tasks-archive.md -->

- [x] Verify the corrected signed build has no recurring permission dialog, then compare saved
  preview dimensions with the live HUD. Recorder A/original-chord acceptance already passed.
  Startup permission requests succeeded and no dialog helper recurred during observation.
  User confirmed permission behavior, usual HUD triggering, and Global preview/layout parity pass
  on 2026-09-26. App left running; no commit or push. Recovery and backup details:
  [2026-09-26 handoff](sessions/2026-09-26.md).

---

## Progress Calculation

```
Sprint Progress = checked in Current Sprint / total in Current Sprint
Overall Progress = (archived count + checked) / (backlog + current + archived)
```

Archived task count is read from `tasks-archive.md` header.

## Workflow Integration

| Command | Action |
|---------|--------|
| `/interview` | Adds tasks to Backlog |
| `/plan` | Moves Backlog → Current Sprint |
| `/execute` | Checks off tasks as waves complete |
| `/log` | Archives checked tasks, updates PROJECT_STATE.md progress bar |
| `/status` | Reports progress from checkbox counts |

---
*Location: `docs/TASKS.md`. Parsed by Directions app.*
