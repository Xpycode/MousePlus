# Tasks

> **Persistent task tracker.** Lives in `docs/`. Progress syncs to PROJECT_STATE.md.

## Active plan

- None. [Use Global ring](plans/use-global-ring.md) is complete.

## Backlog
<!-- Ideas and future work. Added by /interview, user input, or discovered during development. -->
<!-- Priority: top = highest, bottom = lowest -->

- [ ] **Inbox (2026-11-22):** in the Atlas helper, the Add App HUD picker didn't list Safari (Activity Monitor was listed). Check whether the picker skips Safari's location (`/Applications/Safari.app` is a cryptex-backed app) on a real desktop.

- [ ] **Pre-existing test failure:** `WorkspaceAccessibilityTests.testFillUnusedSlotsUsesNativeCheckboxAndUpdatesSharedCustomization`
  fails with `XCTAssertEqual failed: ("[]") is not equal to ("[...Field.menuItems]")`. It also fails
  at e456859, before the App HUD inheritance work (checked 2026-11-22), so it isn't a regression from it.
  [2026-11-21 session](sessions/2026-11-21.md#progress).

- [ ] Explore a draggable MousePlus app icon on the welcome screen for Accessibility setup.
  The user would drag it into the Accessibility list in System Settings, then enable MousePlus.
  In a future session, check which supported macOS versions accept this drop.

- [ ] Fix the silent **Request Access…** button in Settings → Triggers → Keystroke posting.
  On November 27 the user saw no response. After they manually enabled MousePlus in Input
  Monitoring, the warning disappeared. The button calls `CGRequestPostEventAccess()` and
  rechecks permission. A simulated denial confirmed the state stays denied and the UI offers no
  further guidance. Calculator Copy now passes in both Settings profiles. The outstanding work is
  to explain a persistent denial and verify recovery. [Delivery check](sessions/2026-11-27.md#test-action-recipients)

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

- [ ] Dedicate future design sessions to how MousePlus looks in use. Explore translucency,
  gradients and glass materials in the radial menu and Settings. Compare how clearly the
  menu, labels and selected slice read over light, dark and visually busy windows.

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
