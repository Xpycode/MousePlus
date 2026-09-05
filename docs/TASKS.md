# Tasks

> **Persistent task tracker.** Lives in `docs/`. Progress syncs to PROJECT_STATE.md.

## Backlog
<!-- Ideas and future work. Added by /interview, user input, or discovered during development. -->
<!-- Priority: top = highest, bottom = lowest -->

- [ ] Scope the next MousePlus App Switcher increment beyond the live-verified full-circle running-app ring: compare window switching, recent apps, search, grouping/paging, app-specific actions, and keyboard/pointer hybrids.

## Current Sprint
<!-- Active work. Populated by /plan or /execute. Keep focused (3-7 tasks). -->
<!-- When done: /log moves to tasks-archive.md -->

Implementation in progress; user confirms selected runtime animation works via keyboard and BetterMouse mapped to keyboard. Direct native mouse-trigger behavior remains open; 53 focused tests pass. Details and validation:
[HUD Opening Styles implementation plan](../IMPLEMENTATION_PLAN.md).

- [ ] Task 5.1: Close remaining native mouse-trigger and visual/accessibility acceptance. User confirms selected animation works via keyboard and BetterMouse → ⌃⌥⌘M; direct MousePlus mouse-button triggering still reports fade-only. Failing live traces show pointer-hover settlement at progress zero before replay; initial native pointer/hover coordinates need comparison. Preserve the working BetterMouse setup. Settings-click dismissal remains accepted.

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
