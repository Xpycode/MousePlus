# Tasks

> **Persistent task tracker.** Lives in `docs/`. Progress syncs to PROJECT_STATE.md.

## Backlog
<!-- Ideas and future work. Added by /interview, user input, or discovered during development. -->
<!-- Priority: top = highest, bottom = lowest -->

- [ ] Scope the next MousePlus App Switcher increment beyond the live-verified full-circle running-app ring: compare window switching, recent apps, search, grouping/paging, app-specific actions, and keyboard/pointer hybrids.

## Current Sprint
<!-- Active work. Populated by /plan or /execute. Keep focused (3-7 tasks). -->
<!-- When done: /log moves to tasks-archive.md -->

- [x] Task 1.1: Add the role-based HUD motion model and legacy animation-setting decode bridge.
- [x] Task 1.2: Add a pure Reduce Motion-aware semantic motion policy resolver.
- [x] Task 2.1: Replace the blanket spring with scoped hover and branch-dimming feedback.
- [x] Task 2.2: Implement localized and full-circle outer-ring reveal presentations.
- [x] Task 3.1: Add a short summon fade and intentional outer-branch crossfade.
- [ ] Task 4.1: Expand Ring Appearance → Animation with role-specific native controls.
- [ ] Task 5.1: Complete automated, adversarial, performance, accessibility, and signed-live verification.

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
