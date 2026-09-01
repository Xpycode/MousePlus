# Unified Settings Workspace Specification

**Status:** Approved for planning
**Created:** 2026-09-01
**Last Updated:** 2026-09-01

---

## Problem Statement

### What problem does this solve?

Configuring and validating MousePlus is split between a compact tabbed Settings window, a separate Menu Editor window, and the global ring itself. A user must leave the editor to discover whether an action works, while saves and action failures are largely invisible. Several selectable action types are not implemented, the default Copy, Paste, Mission Control, and Spotlight items are inert empty commands, and some Settings writers can replace a corrupt configuration with defaults. The result is a workflow that looks configured even when nothing was saved or executed.

### Who has this problem?

MousePlus users who customize ring contents, triggers, and appearance—especially users configuring the app for the first time or diagnosing an action that appears to do nothing.

### How do they solve it today?

They open Settings, launch a second Menu Editor window, edit a wedge, wait without visible save confirmation, leave the editor, summon the global ring, and try the action. Failures require inspecting source, logs, or the configuration file. Keystroke actions cannot be authored as first-class actions at all.

---

## Proposed Solution

### One-Liner

Replace the compact tabbed preferences and standalone editor handoff with one resizable sidebar Settings workspace where users can select, configure, save, and test every supported ring action with visible results.

### Key Capabilities

1. A single sidebar workspace for General, Triggers, Ring Appearance, and Menu Items.
2. An embedded, side-by-side Menu Items editor with ring preview and identity-based item editing.
3. A first-class Send Keystroke action recorded inline through ShortcutKit.
4. In-place Test Action with explicit success, failure, and unavailable feedback.
5. Safe configuration persistence with visible load/save state, backup-backed reset, and no destructive fallback after decode failure.

### Information Architecture

The Settings sidebar contains these sections in this order:

1. **General** — app-level guidance and diagnostics entry points.
2. **Triggers** — keyboard trigger, mouse-button trigger, trigger modes, Settings shortcut, and Accessibility status.
3. **Ring Appearance** — ring geometry, dimming, and animation.
4. **Menu Items** — embedded ring preview and selected-item editor; this is the primary workspace pane.

Search and deep links are future-compatible concerns, not required for this release. The selected section should persist while the Settings window remains alive. Opening Settings normally selects General; an internal request may open a specific section when that facility is added.

### Window and Pane Layout

- Use the shared `MacUIKitSettings.SettingsSidebarShell` pattern, backed by a resizable `HSplitView`, not `NavigationSplitView` or Tahoe liquid-glass navigation.
- The sidebar has the shared shell's 180–250 point width range.
- The Settings window opens large enough for the Menu Items workflow and cannot shrink below a usable workspace size. The current editor's 900 × 600 minimum is the baseline; the planning pass must validate the final minimum after accounting for the sidebar and shell padding.
- General, Triggers, and Ring Appearance use the standard pane header and a vertically scrolling settings form.
- Menu Items uses the available detail area directly rather than nesting the whole editor inside another grouped form.
- Within Menu Items, the ring preview is on the left and the selected-item detail pane is on the right, separated by a draggable divider. Each pane has a minimum width; the detail pane scrolls vertically when needed.
- The editor's band selector, spoke count, add/reset controls, save state, and Test Action remain visible without requiring the user to scroll to the bottom of a long item form.

### Menu Items Editor Behavior

- Preserve the current identity-based selection and binding model for inner items, middle items, and middle-item sub-items.
- Preserve current limits: at most 8 inner items, 8 middle items, and 12 sub-items per middle item; sub-items remain direct actions with no fourth level.
- Selecting a preview wedge selects the corresponding item and shows its editor. Selecting a sub-item in the detail pane selects that sub-item without losing its parent context.
- The editor supports icon, label where rendered, action type, action-specific data, add, remove, and top-level reorder.
- Invalid SF Symbols remain persisted but render through the established placeholder resolver. The UI identifies the invalid value without making the wedge disappear.
- Changing action type clears incompatible payload data and initializes a valid default when the new type requires one.
- Unimplemented action types do not appear as normal selectable choices. Existing configuration values using an unavailable type remain decodable and visible as unavailable, with an explanation and no misleading Test Action success.
- Unknown action-type raw values are preserved losslessly through decode and re-encode. They remain visible as unavailable and are never collapsed to `custom` merely to keep the containing configuration decodable.
- The existing standalone Menu Editor is retired after migration. Temporary controller scaffolding may remain only during staged implementation and must not remain as a user-facing second editor at completion.

### Send Keystroke Action

- Add a first-class `sendKeystroke` action type; do not encode keystrokes as shell commands.
- The persisted payload represents one physical key plus explicit modifiers in a decode-tolerant form. On decode, a non-empty legacy `RingMenuItem.keyboardShortcut` value migrates into the canonical payload only when no canonical payload already exists; new encodes retire the legacy field so there is one writable source of truth.
- Use ShortcutKit's inline recorder behavior: click-to-record, live candidate, Command-key capture, layout-aware display, sticky candidate, Save, Cancel, and Clear.
- Recording changes only the selected ring item's action payload. It must not register the item as a global MousePlus trigger.
- Recorder teardown caused by section switching or closing Settings cancels capture cleanly and leaves the last committed shortcut unchanged.
- The consuming `zPackages` revision must be clean and pinned to an exact commit during planning; MousePlus must not depend on a package's dirty working tree.
- Shortcut conflicts warn but allow Save unless the recorder can reliably prove that the shortcut is unusable or system-reserved. A blocked shortcut remains visible with the reason and is never silently discarded.

### Test Action

- The selected direct action has a visible **Test Action** control beside the action editor or persistent editor chrome.
- Test Action uses the same `ActionService` execution path and payload validation as the live ring.
- Test Action first flushes the selected edit through the normal safe-save path. Execution begins only after persistence succeeds; a save failure leaves the action untested and presents the save error.
- Testing does not dismiss Settings, mutate ring navigation state, or require summoning the global ring.
- AppDelegate records the previously active external application before activating Settings and refreshes that candidate when Settings regains focus from another app. Contextual tests display their intended target, use that captured external PID plus a current screen snapshot, and are unavailable when no safe target exists.
- A successful test shows a concise success result. A thrown error shows the localized error in the pane and remains visible until the user edits, retries, or dismisses it.
- Success semantics are defined per action rather than meaning only that dispatch began. In particular, custom shell commands await termination and report launch errors and non-zero exit status; application switching reports failure when launch or activation cannot be completed.
- Empty or invalid payloads disable Test Action and explain what is missing.
- Expandable middle items are containers and cannot be tested as actions; their direct sub-items can be tested.
- Tests must not fake support for unimplemented action types.
- The live ring must also stop discarding execution errors silently. Failures use the specified brief non-activating error HUD with a route to the relevant Settings item; successful actions remain silent.

### Persistence and Feedback

The workspace has one authoritative configuration-editing boundary. Individual panes may maintain local editable state, but all writes follow the same safety rules.

Visible state is expressed as:

- **Loading** — controls that could overwrite configuration are disabled.
- **Saving…** — a write is pending or in progress.
- **Saved** — the latest displayed edits are durably written.
- **Save Failed** — displayed edits remain in memory, the failure reason is shown, and retry is available.
- **Load Failed** — the existing file is left untouched and configuration-mutating controls remain disabled until the user retries or chooses an explicit recovery operation.

Additional rules:

- Debounced edits are flushed when Settings closes or when a pane owning dirty state is torn down.
- Cancellation of a debounce task is not treated as a completed save.
- Every save starts from a successfully decoded current configuration and merges the pane's owned fields, preventing one pane from reverting another pane's changes.
- Decode failure never falls back to `Configuration()` for a subsequent automatic write.
- Live apply occurs only after persistence succeeds. A failed save cannot make the running app appear successfully configured for changes that will vanish on relaunch.
- Save and execution errors are never discarded with `try?` at the user-facing boundary.
- Closing with a failed save preserves the file on disk and warns that the in-memory edits are not durable.
- Closing with dirty state after a failed flush presents **Retry**, **Discard Changes**, and **Cancel Close**. The workspace does not disappear—and its only in-memory copy is not lost—unless the retry succeeds or the user explicitly discards the edits.

### Reset and Recovery

- Reset to Defaults is scoped explicitly: the Menu Items reset changes inner and middle ring items only; other Settings panes retain their values.
- Before resetting Menu Items, MousePlus creates a recoverable backup of the last successfully decoded configuration.
- The backup is an atomic copy stored beside the configuration in MousePlus Application Support. One named pre-reset backup is retained and replaced only after the next backup has been created successfully, so recovery survives a crash, relaunch, or closing Settings.
- The confirmation states exactly what will reset and that a backup will be available.
- After reset saves successfully, the UI offers **Undo Reset** for the current Settings session. Undo restores the backed-up menu items through the normal safe-save path.
- Session-only Undo is a convenience over the durable backup; after relaunch, recovery remains available as an explicit restore operation when a pre-reset backup exists.
- If backup creation or reset persistence fails, the reset does not live-apply and the current disk file remains intact.
- General-purpose repair of arbitrary hand-edited JSON is out of scope; the load-failure state may offer retry and reveal the file location without overwriting it.

### User Flow

1. The user opens MousePlus Settings and selects **Menu Items** in the sidebar.
2. The embedded preview and item editor load from the existing configuration; the workspace reports **Saved** once the loaded state is established.
3. The user selects an inner, middle, or outer item in context.
4. The user edits appearance and chooses a supported action. For Send Keystroke, they record and save a shortcut inline.
5. The workspace reports **Saving…**, then **Saved**, or presents **Save Failed** without pretending the change is durable.
6. The user invokes **Test Action** and sees success or an actionable error in the same pane.
7. The user closes Settings. Any pending edit is flushed safely; no second editor window or global-ring verification loop is required.

---

## Acceptance Criteria

### Workspace and Navigation

- [ ] Given MousePlus Settings is opened, when the window appears, then one resizable sidebar workspace contains General, Triggers, Ring Appearance, and Menu Items in the specified order.
- [ ] Given the Settings window is resized, when it reaches its minimum size, then the sidebar, ring preview, persistent editor controls, and a usable portion of the detail form remain accessible without overlapping.
- [ ] Given the user selects Menu Items, when the pane appears, then the ring preview and selected-item editor are visible side by side in the same window.
- [ ] Given the unified workspace is complete, when the user opens Menu Items, then no launcher or separate Menu Editor window is part of the user flow.

### Editing and Model Integrity

- [ ] Given an inner, middle, or sub-item exists, when the user selects it, then the form edits that item by stable identity even after another item is inserted, removed, or reordered.
- [ ] Given one top-level band has 8 items, when the user views that band's Add control, then it is disabled while the other band remains independently addable below its own cap.
- [ ] Given a middle item has 12 sub-items, when it is selected, then Add Sub-item is disabled and the existing sub-items remain editable.
- [ ] Given a window-snap item loses its sub-items, when it becomes a direct action, then it contains a valid snap-zone payload and Test Action does not silently no-op.
- [ ] Given an item contains an invalid SF Symbol name, when preview and form render it, then a placeholder remains visible and the invalid value is identified.
- [ ] Given an item changes to a different action type, when the change is committed, then incompatible action data is removed and the new action starts with a valid or explicitly incomplete payload.
- [ ] Given a saved item uses an unimplemented action type, when it loads, then it remains decodable and is shown as unavailable rather than as a working selectable action.
- [ ] Given an item contains an unknown future action-type raw value, when any pane saves the configuration, then that raw value survives decode and re-encode unchanged and remains shown as unavailable.

### Send Keystroke

- [ ] Given Send Keystroke is selected, when the user clicks its recorder, then key capture starts inline without registering or firing a global MousePlus trigger.
- [ ] Given recording is active, when the user enters a modifier chord including Command, then the candidate remains visible after modifier release and can be saved.
- [ ] Given a candidate is visible, when the user chooses Cancel or leaves the pane, then the previous committed shortcut remains unchanged.
- [ ] Given a shortcut is committed, when Settings is reopened, then the same physical key and modifiers load and display with the current keyboard layout's label.
- [ ] Given a Send Keystroke item is invoked from Test Action or the live ring, when execution succeeds, then both paths emit the same key-down/key-up semantics defined by the Send Keystroke action contract.

### Test Action and Errors

- [ ] Given a selected direct action has a valid payload, when the user invokes Test Action, then MousePlus executes it through `ActionService` and shows a success or localized failure result in the pane.
- [ ] Given the selected action has an unsaved edit, when the user invokes Test Action, then the edit is flushed first and execution occurs only after the workspace reaches Saved.
- [ ] Given the selected action cannot be saved, when the user invokes Test Action, then execution does not occur and the save failure remains visible.
- [ ] Given a selected action has an empty or invalid payload, when the editor renders, then Test Action is disabled and the missing requirement is explained.
- [ ] Given a selected middle item is a container, when the editor renders, then Test Action is unavailable for the container while each direct sub-item remains testable.
- [ ] Given an action type is not implemented, when it is displayed from existing configuration, then Test Action cannot report success and the pane names the unavailable capability.
- [ ] Given a live-ring action throws, when execution ends, then the error is no longer silently discarded and the user has a visible failure route.
- [ ] Given a custom shell command exits non-zero, when it is tested, then the result is failure rather than success merely because the process launched.
- [ ] Given a contextual action is selected, when Test Action is available, then the pane names the captured external target; if no safe target exists, testing is disabled with an explanation.

### Safe Persistence

- [ ] Given a valid configuration is loaded, when the user edits an owned field, then the workspace reports Saving… followed by Saved only after the merged configuration is written successfully.
- [ ] Given edits are inside the debounce interval, when the pane is replaced or Settings closes, then the latest dirty state is flushed rather than reverted or lost.
- [ ] Given the configuration cannot be decoded, when Settings loads, then Load Failed is shown, mutating controls are disabled, and the existing file is not overwritten.
- [ ] Given the configuration becomes unwritable, when a save is attempted, then Save Failed and a retry affordance appear, the prior disk file remains intact, and the failed edit is not live-applied.
- [ ] Given Triggers and Ring Appearance are edited while Menu Items is open, when Menu Items saves, then those newer fields remain unchanged on disk.
- [ ] Given no edits were made, when Settings closes, then it does not rewrite the configuration file.
- [ ] Given dirty edits fail to flush while Settings is closing, when the close barrier appears, then Retry, Discard Changes, and Cancel Close preserve the user's explicit choice and closing cannot silently lose the in-memory edits.

### Reset and Recovery

- [ ] Given a valid configuration is loaded, when the user confirms Reset Menu Items, then a recoverable backup is created before only inner and middle items are replaced with defaults.
- [ ] Given reset succeeds, when the user chooses Undo Reset during the same Settings session, then the previous menu items are restored and saved through the normal persistence path.
- [ ] Given backup creation or reset saving fails, when reset is attempted, then no reset is live-applied and the failure is shown.
- [ ] Given Settings closes or MousePlus relaunches after a reset, when the durable pre-reset backup still exists, then the previous menu items remain available through an explicit restore operation.

### Accessibility and UI Conventions

- [ ] Given Full Keyboard Access is enabled, when the user navigates Settings, then every sidebar destination, editor control, recorder action, Test Action, retry, reset, and undo operation is keyboard reachable with a visible focus state.
- [ ] Given VoiceOver is running, when focus moves through the ring preview, then each selectable wedge announces its band, label or position, action type, and selected state.
- [ ] Given a control communicates save, validation, availability, or execution state, when that state changes, then it is conveyed by text or accessibility value and not by color alone.
- [ ] Given the workspace is implemented, when its primary-window structure is inspected, then it uses the approved resizable split-pane pattern and does not use `NavigationSplitView` or Tahoe-specific sidebar styling.
- [ ] Given app-owned interactive controls are added or replaced, when implementation is reviewed, then they use the project's AppKit-backed control wrappers except for an explicitly approved shared-shell exception.

### Reduced T12 Smoke Test

- [ ] Given automated model and persistence tests pass, when the final live smoke test runs, then the user can open the unified workspace, edit and save one ring item, record and test one keystroke, reopen Settings to confirm persistence, and invoke the edited item from the live ring without a second editor window.

---

## Technical Considerations

### Dependencies

- `MacUIKitSettings.SettingsSidebarShell` for the shared sidebar frame and `SettingsTab` ordering.
- `ShortcutKit.ShortcutRecorder` and `CustomKeyboardShortcut` for inline keystroke capture and display.
- Existing `MenuEditorModel`, `RingPreviewSelector`, `SlotEditorForm`, `ConfigurationService`, `ActionService`, and live-apply hooks.
- Planning must select and record an exact clean `zPackages` commit before MousePlus pins either package.

### Architecture Notes

- Keep `MenuEditorView` as reusable composition where practical, but move persistence ownership out of `MenuEditorWindowController` into a workspace-scoped configuration coordinator or equivalent single editing boundary.
- The coordinator owns load state, dirty state, debounce/flush behavior, merge-before-save, backup/reset recovery, and visible status. Panes should not independently implement fallback-to-default read-modify-write loops.
- Preserve `MenuEditorModel`'s UUID-keyed bindings and model invariants.
- Add one canonical action validation contract shared by the editor, Test Action, and `ActionService` so enabled state and runtime behavior cannot disagree.
- Define a result channel from `ActionService` to both Settings and the live ring. Do not couple the service actor directly to SwiftUI presentation.
- Present live-ring execution failures in a brief non-activating error HUD with a route to the relevant Settings item; successful actions add no HUD friction.
- Evolve the action-type model so unknown raw values are both decode-tolerant and losslessly re-encodable. A plain fallback from an unknown value to `.custom` is insufficient because any later save destroys the original value.
- On decode, migrate any non-empty legacy `RingMenuItem.keyboardShortcut` into the canonical Send Keystroke payload when no canonical payload already exists, then retire the legacy field from newly encoded configurations. There must never be two writable shortcut representations.
- Retain the user's existing configuration path and schema compatibility; this is an in-place UI and model evolution, not a reset migration.

### Performance

- Loading or switching Settings panes must not scan applications or validate the entire SF Symbol catalog synchronously on the main thread.
- The ring preview should update interactively while editing; persistence remains debounced to avoid a disk write per keystroke.
- App icons and other expensive picker content remain lazy-loaded.

### Security and Safety

- Configuration and backups stay local under MousePlus Application Support; no network or telemetry is introduced.
- Custom commands remain explicitly labeled as shell commands and execute only on direct user test or ring invocation, never while editing or loading.
- Test Action must not run an action as a side effect of validation, save, selection, or shortcut recording.
- Send Keystroke uses a private `CGEventSource`, explicit modifier flags on both events, and the agreed event tap from the approved Send Keystroke design; Accessibility denial must produce an actionable error.

### Project UI Convention Exception

The chosen shell correctly uses the approved `HSplitView` approach and avoids `NavigationSplitView`. The shared `SettingsSidebarShell` and ShortcutKit recorder are approved as narrow, documented exceptions to the project-wide AppKit-backed interactive-control convention. This exception does not extend to app-specific controls introduced by the feature.

---

## Out of Scope

Explicitly excluded from this specification:

- Implementing menu-bar mirror, system toggles, or screenshot actions.
- Settings search, control-level indexing, deep-link routing, and temporary row highlighting.
- Reordering outer sub-items beyond the current editor capability.
- A fourth ring/menu depth or changed spoke/sub-item limits.
- A general JSON repair editor or cloud configuration sync.
- A redesigned ring HUD, new visual theme, or macOS Tahoe/Liquid Glass treatment.
- Reworking mouse/HID trigger discovery or resolving the HID++ strategy decision.
- Building implementation waves or changing Swift application code during the specification session.

---

## Resolved Questions

| Question | Decision |
|----------|----------|
| May the shared shell and ShortcutKit recorder use SwiftUI interactive controls? | Yes. They are narrow, documented shared-package exceptions. App-specific controls remain AppKit-backed unless separately approved. |
| What `zPackages` revision will MousePlus pin? | Planning must select and record an exact clean commit. A dirty working tree is not an integration source. |
| How is `RingMenuItem.keyboardShortcut` handled? | Decode and migrate any non-empty legacy value when no canonical payload exists, then retire it from new encodes. The canonical Send Keystroke payload is the only writable source. |
| How are live-ring execution failures presented? | A brief non-activating error HUD provides the failure and a route to the relevant Settings item; success stays silent. |
| What is the ShortcutKit conflict policy? | Warn but allow ordinary conflicts; block only reliably proven unusable or system-reserved shortcuts, always with a visible reason. |

---

## Related

- Decision: [`docs/decisions.md`](../docs/decisions.md) — “Unified Sidebar Settings Workspace” (2026-09-01)
- Discovery session: [`docs/sessions/2026-09-01.md`](../docs/sessions/2026-09-01.md)
- Existing editor plan: [`docs/MENU_EDITOR_PLAN.md`](../docs/MENU_EDITOR_PLAN.md)
- Existing editor review: [`docs/MENU_EDITOR_REVIEW.md`](../docs/MENU_EDITOR_REVIEW.md)
- Send Keystroke design: [`docs/SEND_KEYSTROKE_PLAN.md`](../docs/SEND_KEYSTROKE_PLAN.md)
