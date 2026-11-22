# Tasks

> **Persistent task tracker.** Lives in `docs/`. Progress syncs to PROJECT_STATE.md.

## Active plan

- App HUD inheritance: [`plans/app-hud-inheritance-implementation.md`](plans/app-hud-inheritance-implementation.md). First ready: 1.1, 1.2, 1.3. Status lives in the plan.

## Backlog
<!-- Ideas and future work. Added by /interview, user input, or discovered during development. -->
<!-- Priority: top = highest, bottom = lowest -->

- [ ] **App HUD slots inherit from Global unless overridden** (decided 2026-11-22, see
  `decisions.md`). Today an App HUD is a one-time copy, so Global edits silently miss it (Cmd+C
  on Global Copy never reached the Safari HUD). Spec drafted 2026-11-22:
  [`specs/app-hud-inheritance.md`](../specs/app-hud-inheritance.md); planned in the active plan above.

- [ ] **Awaiting recurrence check:** Menu Items preview showed the built-in sample ring while the
  status said "Saved". Cause not reproduced; precautionary remount-after-load added 2026-11-21.
  If it recurs, check the Selected Item tab before clicking the ring.
  [2026-11-21 session](sessions/2026-11-21.md#progress).

- [ ] Set up a stable local signing identity on the M4 Pro (self-signed certificate, or sign Xcode
  into the Apple ID) so Accessibility permission survives rebuilds. Offered 2026-11-21; undecided.

- [ ] Test HID++ button diversion next to BetterMouse (MX Master 3S gesture button `0x00C3`) to
  settle the Logitech trigger-backend question; then spec a minimal Swift port. Call sequence,
  control IDs and pitfalls: [OPENLOGI_REFERENCE.md](OPENLOGI_REFERENCE.md). Added 2026-11-21.

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
