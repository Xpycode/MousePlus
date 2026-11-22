# App HUD Inheritance Specification

**Status:** Approved 2026-11-22 — planned in `docs/plans/app-hud-inheritance-implementation.md`.
**Created:** 2026-11-22
**Last Updated:** 2026-11-22
**Decision:** [2026-11-22 — App HUD slots inherit from Global unless overridden](../docs/decisions.md)
**Builds on:** [App-Specific HUDs](app-specific-huds.md) (complete)

---

## Problem Statement

### What problem does this solve?

An App HUD is a one-time copy of the Global HUD, so later Global edits never reach it. The user
recorded Command-C on the Global Copy item, then used the ring in Safari, which has its own App HUD.
That HUD's Copy item had no keystroke, and the ring failed with "Send Keystroke needs action
details". The user expected Global to apply. The current hint ("New App HUDs copy Global once;
later edits stay independent") did not prevent the surprise.

### Who has this problem?

MousePlus users with one or more App HUDs who keep refining their Global HUD.

### How is it handled today?

Edit the same item in Global and in every App HUD, or reset the App HUD, which recopies all of
Global and throws away its app-specific changes.

---

## Proposed Solution

### One-Liner

Items in an App HUD follow their Global item until you customize them for that app. Customized,
hidden and app-only items stay as you set them.

### Confirmed design rules (2026-11-22)

| Question | Decision |
|---|---|
| How an app item stays linked | By **item ID**. A copied app item keeps its Global item's ID. Reordering Global moves the inherited items with it. |
| What an override covers | The **whole item**: label, icon, action, action details, keystroke, colors, dynamic source and its outer-ring sub-items. Editing any of them detaches the whole item until you choose **Revert to Global**. Editing a sub-item counts as editing its parent middle item. |
| Items added or deleted in Global | **Follow Global.** A new Global item appears in every App HUD that follows Global's order. A deleted Global item disappears from App HUDs where it was inherited. Where an app customized it, that copy stays as an app-only item. |
| Reordering in an App HUD | **Custom order per ring.** Reordering the inner or middle ring in an app gives that ring its own order. New Global items go at the end of that ring. **Revert Order** brings back Global's order. |
| Deleting an inherited item in an App HUD | **Hide, restorable.** The item is hidden in that app only and stays hidden if Global changes it later. You can bring it back from **Hidden Items (N)…**. Deleting an app-only or customized item deletes it, as today. |
| Controls | Approved layout, see "Editor controls" below. |

### Key Capabilities

1. **Resolution:** when a HUD opens for an app, each ring is built from Global plus that app's
   overrides, hidden items, app-only items and any custom order. The result is fixed for the life
   of that HUD.
2. **Override:** the first edit to an inherited item in an App HUD stores an app-owned copy and
   marks the item as customized.
3. **Revert:** **Revert to Global** drops the app copy, and the item follows Global again.
4. **Hide and restore:** an inherited item can be hidden per app and restored from a list.
5. **Migration:** existing App HUDs are converted once, without changing what any ring shows on
   first launch.

### User Flow

1. Source/input: the Global HUD and a Safari App HUD created earlier.
2. User action: in Settings, Menu Items, with the Global profile selected, record Command-C on
   the Copy item. Click Save.
3. Destination/output: the Safari HUD's Copy item, which was never customized for Safari.
4. Observable outcome: in Safari, the ring's Copy item sends Command-C without any Safari-specific
   edit. In Settings, with the Safari profile selected, the Copy item shows "Follows Global".

### Editor controls (approved 2026-11-22, UI-change protocol)

- **Profile bar (`MenuItemsPane.profileBar`):** the copy hint (`menuItems.profile.copyExplanation`)
  changes to "App HUDs follow Global until you edit an item." A **Hidden Items (N)…** `AppKitButton`
  goes after **Delete…**. It shows only for an App HUD and is disabled when N is 0. It opens a list
  of hidden Global items with a **Show** action for each.
- **Selected-item editor (`SlotEditorForm`, top row, App HUD only):**
  - An inherited item shows "Follows Global" with a **Customize** button. Clicking it detaches
    the item as an unchanged app copy. Editing a field without clicking it still customizes the
    item. (Decided 2026-11-22.)
  - A customized item shows "Customized for <App>" with an enabled **Revert to Global** button.
  - An app-only item shows "Only in <App>", with no revert button.
- **Order (approved 2026-11-22):** in `SlotEditorForm.footerControls`,
  directly after **Move Later**, add a **Revert Order** `AppKitButton`. It shows only in an App HUD
  when the selected item's ring has its own order. It sits next to the Move buttons because that
  is where the order changes. In an App HUD, the **Delete Item** button reads **Hide in <App>**
  for an inherited item.
- **Ring preview (`RingPreviewSelector`):** customized items get a small dot. It is decoration
  only: no hit target and no change to selection. Its accessibility label adds ", customized for
  <App>".
- Profile messages (`addAppHUD`, and the Reset text in `profileSemantics`) are rewritten to say
  that the HUD follows Global instead of being an independent copy.

---

## Acceptance Criteria

**Resolution and propagation**

- **AC1.** Given a Safari HUD whose Copy item is inherited, when Global's Copy keystroke changes
  and is saved, then the next Safari HUD sends the new keystroke.
- **AC2.** Given a Safari HUD with a customized Copy item, when Global's Copy changes, then
  Safari's Copy is unchanged.
- **AC3.** Given a customized item, when the user clicks Revert to Global and saves, then the item
  matches the current Global item and later Global edits reach it.
- **AC4.** Given a Safari HUD that follows Global's middle order, when a new item is added to
  Global's middle ring, then it appears in Safari's middle ring at the same position as in Global.
- **AC5.** Given a Safari HUD with its own middle order, when a new item is added to Global's middle
  ring, then it appears at the end of Safari's middle ring.
- **AC6.** Given a Global item that is inherited in Safari, when it is deleted from Global, then
  it disappears from Safari.
- **AC7.** Given a Global item that is customized in Safari, when it is deleted from Global, then
  Safari keeps it and shows it as "Only in Safari".
- **AC8.** Given Global items reordered, when Safari follows Global's order, then Safari's
  inherited items appear in the new order, with app-only items kept next to their previous
  neighbor.

**Override, hide, order**

- **AC9.** Given an inherited item in an App HUD, when any field or any of its sub-items is edited,
  then the item becomes "Customized for <App>" and the ring preview shows a dot.
- **AC10.** Given an inherited item, when the user deletes it in an App HUD, then it is hidden,
  Hidden Items shows a count of 1, and Global is unchanged.
- **AC11.** Given a hidden item, when the user chooses Show in Hidden Items, then it returns as an
  inherited item at its Global position (or at the end of the ring if the ring has its own order).
- **AC12.** Given an App HUD ring with its own order, when the user chooses Revert Order, then
  inherited items follow Global's order, and app-only items follow the placement rule in AC8.
- **AC12a.** Given an inherited item, when the user clicks Customize, then it becomes
  "Customized for <App>" with identical content, and later Global edits no longer reach it.
- **AC12b.** Given any item tested from an App HUD, when Test Action runs, then the result names
  where the item comes from: "from Global", "customized for <App>" or "only in <App>".
- **AC13.** Given the Global profile is selected, then no inheritance controls, dots or Hidden
  Items button appear.

**Runtime and slot limits**

- **AC14.** Given a ring is limited to 8 items, when a Global save would make an App HUD's ring
  resolve to more than 8, then the save goes ahead. Settings warns "Not enough space in <App> HUD's
  <ring> ring: N items not shown", naming each affected App HUD, and that App HUD's editor lists
  the items that don't fit as not shown. The HUD shows the first 8 in resolved order. Hiding or
  deleting items in that App HUD clears the warning. (Decided 2026-11-22.)
- **AC15.** Given an App HUD is open, when Global is saved, then the open HUD is unchanged until it
  is dismissed. Resolution happens once per opening.

**Migration and compatibility**

- **AC16.** Given existing App HUDs from 0.1.0, when the new version first loads them, then every
  ring shows exactly the same items in the same order as before. Items identical to their Global
  item become inherited. Items that differ become customized. Items whose ID is not in Global
  become app-only. Global items missing from the app become hidden. A ring whose order differs
  from Global's gets its own order.
- **AC17.** Given a migrated configuration, when saved and reloaded, then the result is unchanged
  and unknown fields are preserved, keeping the current lossless-save guarantees.
- **AC18.** Given an App HUD entry that cannot be read, it stays quarantined and written back
  unchanged, as today.

**Save guards**

- **AC19.** Given another writer changed Global on disk, when Settings saves Global, then the
  existing external-change guard still refuses. App HUDs saved with inheritance metadata use the
  same per-profile reconcile as today. Editing Global alone must not register as a change to
  every App HUD.

---

## Technical Considerations

- **Storage:** `AppHUDProfile.layout` is a full `HUDActionLayout` today. The recommended model adds
  per-profile inheritance metadata next to `layout`: the set of inherited IDs (or override records),
  hidden IDs and a per-ring custom-order flag or ID list. This builds on the existing
  unknown-field preservation in `AppHUDProfile` and `Configuration`.
- **Older builds (decided 2026-11-22):** store inheriting App HUDs under a new key, not `layout`,
  and do not write a resolved snapshot. A 0.1.0 build then treats those entries as unreadable: it
  shows the Global HUD in those apps and writes the entries back unchanged (existing quarantine,
  `StoredAppHUDProfile.unavailable` → `resolveHUD` falls back to Global). This is safe and adds no
  extra code. The cost: while an older build is running, app menus show Global.
- **Resolution point:** `MousePlusApp.resolveInvocation(route:)` → `ResolvedHUDProfile`. A pure
  `resolve(global:profile:) -> HUDActionLayout` function is easy to unit-test and is shared by
  the runtime, the Settings preview and migration.
- **Editor:** `SettingsWorkspaceCoordinator.loadSelectedProfileIntoEditor` /
  `mergeEditorIntoSelectedProfile` must turn edits back into overrides: compare each edited item
  with its resolved Global item, mark hides on delete, and turn custom order on when a reorder
  happens. `MenuEditorModel` needs to know which items are inherited, customized or app-only for
  the controls.
- **Merge guard:** `reconcileAppHUDProfileChanges` compares stored profiles. Because inherited
  items are not stored per app, a Global-only edit must leave stored App HUD profiles byte-equal.
  This is AC19.
- **Opaque JSON:** `HUDActionLayout` keeps item-level unknown JSON (`preservedInnerJSON`). Inherited
  items take their unknown JSON from Global. Customized items keep their own.
- **UI conventions:** use only AppKit-backed controls (`AppKitButton`, `AppKitPopup`). Do not use
  SwiftUI `Button` or `NavigationSplitView`.

---

## Out of Scope

- Inheriting individual fields (an override covers the whole item).
- Inheriting between App HUDs, or chains of parent profiles.
- Changing presentation, motion, triggers or behavior settings (already global).
- Warnings that a Global edit "didn't reach" an App HUD (option 1, rejected).
- Syncing configuration between Macs.

---

## Open Questions

None blocking. Compatibility with older builds is not a goal (decided 2026-11-22: the app is
heading toward its first release candidate, and no released version has users). The existing
fallback to Global for unreadable entries is enough.
