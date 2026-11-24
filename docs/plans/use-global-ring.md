# Use Global ring

**Scope** — Implement the approved Inner and Middle checkbox placement and the [whole-ring behavior](../../specs/app-hud-inheritance.md#addendum-use-global-ring-added-2026-11-22-during-e2). Work is confined to one ring of one app profile. Each producer owns its sources and tests. The coordinator owns integration, build resources, verification and records.

**Progress** — 4/4 complete on 2026-11-24.

## Tasks and verification

- [x] **1.1 Storage and resolution.** Preserve unlocked legacy data and unknown fields. Resolve a locked band from Global and retain its sibling. Own AppHUDProfile, AppHUDResolver and AppHUDInheritanceTests. Verify persistence, migration, propagation and repair with resolver tests.
- [x] **1.2 Editor behavior.** Load the resolved lock state, count pending customizations, reset only the selected band and protect item and sub-item mutations. Own MenuEditorModel and its tests. Verify selection, stale writes and unlock with model tests.
- [x] **1.3 Settings controls.** Place a native checkbox above the item count in each eligible ring. Confirm removal of existing customizations and keep Test Action available. Own MenuEditor views and affected native controls. Verify with the integration build and helper screenshots.
- [x] **2.1 Integration and acceptance.** Wire the editor state through autosave, fresh-disk reconciliation and conflict detection. Own SettingsWorkspaceCoordinator and its tests. Verify the Debug build, focused logic tests, independent review and the toggle/cancel/confirm workflow in the helper.

The three first-wave tasks have no prerequisites or external gates. Their agreed interfaces are per-band lock state, persisted order state and the editor's query, confirmation and setter methods. Integration consumes all three. Atlas and test output are required to report the corresponding checks as passed.

## Execution log

- The storage, editor and controls tasks are assigned to three fresh contexts. The coordinator integrates their shared interfaces and owns Git.
- Independent review found four issues. The integrated changes recheck confirmation counts after reload, disable contextual Delete and validate its target by ID, observe metadata-only edits for autosave, and keep item origins independent when rings share an ID.
- The Debug app and test bundles built. All 94 focused hostless XCTest cases passed (34 resolver, 33 editor, 5 preview, 13 coordinator, 9 Test Action). These ran in a standalone XCTest bundle linked from Xcode's compiled objects.
- Atlas verified both checkbox positions, cancel, confirm, clean-ring locking, unlocking, disabled Add Item, locked selected-item status and the absence of the checkbox in Global. See the [verification and handoff record](../sessions/2026-11-24.md).
