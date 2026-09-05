# Tasks

> **Persistent task tracker.** Lives in `docs/`. Progress syncs to PROJECT_STATE.md.

## Backlog
<!-- Ideas and future work. Added by /interview, user input, or discovered during development. -->
<!-- Priority: top = highest, bottom = lowest -->

- [ ] Scope the next MousePlus App Switcher increment beyond the live-verified full-circle running-app ring: compare window switching, recent apps, search, grouping/paging, app-specific actions, and keyboard/pointer hybrids.

## Current Sprint
<!-- Active work. Populated by /plan or /execute. Keep focused (3-7 tasks). -->
<!-- When done: /log moves to tasks-archive.md -->

Implementation in progress; fixed a reproduced post-mount panel-center drift, with 303 scheme tests passing. User confirms selected runtime animation works via keyboard and BetterMouse mapped to keyboard. Direct physical mouse-trigger behavior remains open. Details and validation:
[HUD Opening Styles implementation plan](../IMPLEMENTATION_PLAN.md).

- [ ] Task 5.1: Close remaining native mouse-trigger and visual/accessibility acceptance. User confirms selected animation works via keyboard and BetterMouse → ⌃⌥⌘M; direct MousePlus mouse-button triggering previously reported fade-only and has not been physically rechecked after the layout fix. The new diagnostics and a failing regression exposed post-mount panel-center drift, now fixed. Preserve the working BetterMouse setup and disabled direct binding: the user explicitly wants button 5 to stop advancing Warp tabs. Any physical native-trigger reproduction must be isolated from Warp. Settings-click dismissal remains accepted.

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
