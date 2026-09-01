# Tasks

> **Persistent task tracker.** Lives in `docs/`. Progress syncs to PROJECT_STATE.md.

## Backlog
<!-- Ideas and future work. Added by /interview, user input, or discovered during development. -->
<!-- Priority: top = highest, bottom = lowest -->

- [ ] [Task description]

## Current Sprint
<!-- Active work. Populated by /plan or /execute. Keep focused (3-7 tasks). -->
<!-- When done: /log moves to tasks-archive.md -->

- [ ] Wave 1: add lossless action/keystroke models, posting service, and AppKit control wrappers
- [ ] Wave 2: build and verify the single safe configuration coordinator with backup and close barriers
- [ ] Wave 3: unify action validation, completion results, contextual targets, and error routing
- [ ] Wave 4: replace tabbed Settings, migrate panes, embed Menu Items, and retire the second editor
- [ ] Waves 5–6: add recorder/Test/recovery/accessibility UI and complete runtime live-apply/error integration
- [ ] Wave 7: pass automated, adversarial, accessibility, and reduced T12 live gates

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
