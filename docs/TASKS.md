# Tasks

> **Persistent task tracker.** Lives in `docs/`. Progress syncs to PROJECT_STATE.md.

## Backlog
<!-- Ideas and future work. Added by /interview, user input, or discovered during development. -->
<!-- Priority: top = highest, bottom = lowest -->

- [ ] Diagnose intermittent Settings window dragging failure. User reported recurrence on
  November 10 in the latest profile-tree build; graceful restart restored dragging. The
  header drag surface is present, so restart recovery is not proof of a permanent fix.
  Preserve settings and capture the failing window state if it recurs.

- [ ] Expand the Menu Items icon browser beyond the current curated SF Symbols and add search/filtering
  inside its existing Browse popover. Requested during app-specific HUD E1 acceptance on 2026-09-11;
  placement and exact catalog scope still need confirmation under the UI-change protocol.

- [ ] Scope the next MousePlus App Switcher increment beyond the live-verified full-circle running-app ring: compare window switching, recent apps, search, grouping/paging, and keyboard/pointer hybrids. Complete app-specific HUDs are finished separately.

- [ ] Center outer-ring labels beneath their icons when an expansion chevron is present. A
  2026-09-11 user screenshot shows the `Apps` and `Snap` labels centered under the combined
  icon-plus-chevron row rather than under the icon itself, shifting both labels toward the
  chevron. Confirmed visual polish issue; non-blocking for Opening Styles acceptance.

- [ ] Before release, perform the deferred VoiceOver acceptance pass for Opening Styles and
  first-run trigger onboarding: Settings label/value and Replay button, preview semantics, stable
  live-HUD action labels/order with immediate activation; onboarding guidance, recorder controls,
  selected binding, mode, and focus order. Opening Styles was deferred by the user on 2026-09-11;
  onboarding was deferred on 2026-09-27. Both remain untested, not failed.

- [ ] Before release, complete deferred Opening Styles coverage outside the supported BetterMouse
  route: isolated direct MousePlus physical mouse triggering, maximum geometry and screen edges,
  branch/configuration combinations, and smoothness on other supported Macs. Explicitly deferred
  by the user on 2026-09-11; untested, not failed.

- [ ] Show a visible cue when MousePlus is suspended after a permission loss it could not relaunch
  from (rate-limited, failed flush or failed launch): for example a status-item tooltip or menu
  line pointing to Restart. Raised by the permission-loss R5 review on 2026-11-13
  ([report](plans/permission-loss-wave4-report.md)). New UI: needs the UI-change protocol and approval.

Color-well remediation moved into the active plan as R2 on 2026-11-07;
automated checks and November 7 live confirmation passed; onboarding E1 remains separate.

## Active plan

[Permission-loss remediation, revision 2](plans/permission-loss-implementation.md): R0–R5 done,
G1 passed; R6 ready. Plan owns status/evidence. Original onboarding E1 below remains failed/open;
its historical checkbox is retained, not counted as remediation progress.

## Current Sprint
<!-- Active work. Populated by /plan or /execute. Keep focused (3-7 tasks). -->
<!-- When done: /log moves to tasks-archive.md -->

- [ ] Onboarding E1: Complete signed live onboarding acceptance.

Plan: [First-run trigger onboarding](plans/first-run-trigger-onboarding-implementation.md).

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
