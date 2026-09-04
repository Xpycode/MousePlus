# Sustained-Use HUD Redesign Specification

**Status:** Complete
**Created:** 2026-09-02
**Last Updated:** 2026-09-04

---

## Problem Statement

### What problem does this solve?

MousePlus already works as a focused, single-purpose radial menu, but its fixed geometry and indirect editing loop make it difficult to explore the HUD's broader potential. A first-time user or the app's developer should be able to discover Settings, vary the layout and appearance, and evaluate changes quickly without repeatedly leaving the editor or risking real actions.

### Who has this problem?

- A first-time MousePlus user testing what the radial HUD can do.
- A sustained user expanding an established one-purpose menu into a broader command surface.
- The MousePlus developer iterating on HUD layouts and visual behavior.

### How do they solve it today?

They open Settings through the menu bar or global shortcut, edit item arrays whose rings share spoke geometry, and summon the runtime HUD again to inspect the result. Empty padding wedges remain visible, the rings cannot be rotated or sized independently, icons have one fixed orientation, and colors cannot be configured at menu, ring, or item level.

---

## Proposed Solution

### One-Liner

Turn the HUD editor into a safe, live experimentation surface with center access to Settings, configurable ring geometry and visibility, orientation controls, and inheritable wedge and icon colors.

### Key Capabilities

1. Open Settings directly from a dedicated control in the HUD center.
2. Configure the outer ring as always visible, pointer-revealed, or always hidden.
3. Give the inner and middle rings independent automatic or fixed slot counts, with unused fixed slots preserving geometry while rendering invisibly.
4. Give the inner and middle rings independent angular offsets.
5. Configure upright, radial, or tangential icon orientation through a menu default with optional per-ring overrides.
6. Configure wedge and icon colors through menu defaults, optional ring overrides, and optional item overrides, with `Default/Inherit` and accessible contrast protection.
7. Show all supported changes immediately in a safe, interactive editor preview that never executes configured actions.
8. Present small, fixed choice sets as compact segmented buttons so available options and the current selection are visible without opening a menu.

### User Flow

1. The user summons the runtime HUD and activates the center Settings control.
2. MousePlus dismisses the HUD and opens Settings at the menu editor.
3. The user selects menu-wide, ring-level, or item-level layout and appearance controls.
4. The live HUD preview updates immediately and supports hover, selection, outer-ring reveal, and layout testing without executing actions.
5. Saved changes apply to the next runtime HUD invocation; existing configurations retain their previous appearance and behavior after migration.

### Editor Choice Controls

- Use compact, tab-like segmented controls for small, fixed, mutually exclusive choices—such as outer-ring visibility, slot-count mode, and icon orientation—when their labels fit clearly.
- The selected segment must remain visually unambiguous at a glance, and every segment must expose its label to accessibility APIs.
- Use a dropdown only when the choice list is long, dynamic, label-heavy, or cannot fit without truncation. Numeric ranges and color selection keep their purpose-built controls.
- Control choice must not change the stored option semantics or make the live preview behave differently.

### Configuration Semantics

#### Outer-ring visibility

- **Always visible:** the outer ring is shown according to the current expanded-parent behavior.
- **Reveal beyond inner ring:** crossing beyond the inner ring reveals the outer ring, which remains visible until that HUD invocation closes.
- **Always hidden:** the outer ring and its wedges are not rendered at runtime; configured sub-items remain stored and editable.

#### Slot counts

- Inner and middle rings are configured independently.
- **Auto:** rendered slot count follows the number of configured items, within the supported ring limit.
- **Fixed:** the chosen slot count controls spacing. Unused slots remain in the angular geometry but have no visible wedge, label, icon, hover state, accessibility target, or executable action.
- A fixed count may not be lower than the number of configured items. The editor prevents or clearly resolves attempts to create that invalid state without dropping items.

#### Rotation and icon orientation

- Inner and middle rings each have an independent angular offset over a full turn.
- The menu defines the default icon orientation: **upright**, **radial**, or **tangential**.
- Each ring, including outer-ring items, may inherit the menu default or override it.
- Orientation changes affect icon presentation, not wedge labels or hit geometry.

#### Colors

- Wedge and icon colors are separate properties.
- Resolution order is item override → ring override → menu default → application default.
- Menu, ring, and item controls offer `Default/Inherit`; item and ring values may be returned to inheritance without changing their ancestors.
- The final rendered icon color must retain accessible contrast against the resolved wedge color. When the requested result is insufficient, MousePlus applies a deterministic accessible fallback and represents that resolved result in the preview.
- Selection, hover, disabled/dimmed, and off-branch presentation remain distinguishable when custom colors are active.

---

## Acceptance Criteria

### Center Settings Access

- [x] Given the runtime HUD is open, when the user activates its center Settings control, then the HUD dismisses and Settings opens at the menu editor.
- [x] Given either hold-release or tap-toggle activation, when the center Settings control is activated, then no configured menu action executes.
- [x] Given the center Settings control is visible, when VoiceOver inspects it, then it has a stable identifier, a descriptive label, and an actionable Settings role.

### Outer-Ring Visibility

- [x] Given outer-ring mode is `Always visible` and a middle item has sub-items, when that parent is expanded, then its outer ring is visible using the configured outer-ring appearance.
- [x] Given outer-ring mode is `Reveal beyond inner ring`, when a HUD invocation begins, then the outer ring starts hidden.
- [x] Given conditional mode and a hidden outer ring, when the pointer crosses beyond the inner ring, then the outer ring appears and remains visible until that invocation closes.
- [x] Given conditional mode has revealed the outer ring, when the pointer moves back inward, then the outer ring remains visible and its hit testing stays stable.
- [x] Given outer-ring mode is `Always hidden`, when a parent with sub-items is encountered, then no outer wedges or outer hit targets render, while the stored sub-items remain unchanged.

### Independent Slot Counts and Hidden Wedges

- [x] Given inner and middle rings have different item counts and both use `Auto`, when the HUD renders, then each ring derives its own slot count rather than sharing a spoke count.
- [x] Given a ring uses a valid fixed slot count larger than its item count, when it renders, then configured items retain fixed angular positions and unused slots render invisibly.
- [x] Given an unused fixed slot, when the user hovers, clicks, releases, or uses VoiceOver over its angular region, then it cannot become active or execute an action and exposes no phantom accessibility element.
- [x] Given a fixed count equals the configured item count, when another item is added, then the editor prevents the invalid state or offers an explicit non-destructive count increase; it never drops or overlaps items.
- [x] Given the other ring changes between auto and fixed, when the preview updates, then the untouched ring's slot count and item positions remain unchanged.

### Independent Rotation

- [x] Given different offsets for the inner and middle rings, when the HUD and preview render, then each ring begins at its own configured angle and visual wedges, icons, hover regions, and selection hit testing remain aligned.
- [x] Given an offset is adjusted across the end of a full turn, when it is saved and reloaded, then the angle is normalized without a visible jump or loss of precision.

### Icon Orientation

- [x] Given a ring inherits the menu orientation, when the menu default changes among upright, radial, and tangential, then that ring's icons update immediately in the preview.
- [x] Given a ring overrides the menu orientation, when the menu default changes, then the overridden ring remains unchanged.
- [x] Given radial or tangential orientation and a rotated ring, when any icon renders, then its transform is derived from its final wedge angle and remains centered within its wedge.

### Wedge and Icon Colors

- [x] Given no color overrides, when an existing configuration loads, then wedges and icons match the pre-redesign application colors.
- [x] Given menu-level wedge or icon colors, when rings and items inherit, then the resolved colors appear consistently in the preview and runtime HUD.
- [x] Given a ring-level override and an item-level override, when the HUD renders, then item overrides ring, ring overrides menu, and clearing either override restores inheritance immediately.
- [x] Given a requested icon/wedge combination does not meet the project's chosen contrast threshold, when it renders, then MousePlus applies the documented accessible icon fallback in both preview and runtime.
- [x] Given custom colors, when a wedge becomes selected, hovered, dimmed, disabled, or part of an off-branch path, then each applicable state remains visually distinguishable.

### Live HUD Preview

- [x] Given an editor control changes layout, visibility, orientation, or color, when its value changes, then the preview updates immediately without requiring a save-and-resummon cycle.
- [x] Given conditional outer-ring mode in the preview, when the pointer crosses beyond the inner ring, then the preview reproduces the runtime reveal-and-latch behavior.
- [x] Given the user hovers or selects a configured preview wedge, when the interaction completes, then the editor may select or inspect that item but never invokes its configured action.
- [x] Given custom radii or geometry larger than the preview area, when the preview renders, then it scales to fit without changing the runtime geometry values or overlapping editor controls.

### Editor Choice Visibility

- [x] Given a setting has two to four short, fixed choices that fit the editor, when it is presented, then all choices appear simultaneously in a compact segmented control and the current selection is visible without opening a menu.
- [x] Given a choice set is long, dynamic, or would truncate materially, when it is presented, then the editor uses an appropriate dropdown or purpose-built control instead of an unreadable segmented control.
- [x] Given keyboard or VoiceOver navigation reaches a segmented choice, when focus moves among its options, then each option and the selected state are announced and can be changed without a pointer.

### Persistence and Migration

- [x] Given a configuration written before this redesign, when it decodes, then all new fields receive compatibility defaults and the runtime HUD remains visually and behaviorally unchanged.
- [x] Given a migrated configuration is saved, when it is loaded again, then all menu, ring, and item values round-trip without losing unknown action data or configured sub-items.
- [x] Given a partial configuration omits any new nested field, when it decodes, then only that field receives its compatibility default and the rest of the configuration remains intact.
- [x] Given invalid persisted slot counts, angles, modes, or colors, when the configuration loads, then values are clamped or replaced by documented safe defaults without replacing unrelated user configuration.

---

## Technical Considerations

### Data and Migration

- Extend the existing tolerant `Codable` model rather than relying on synthesized decoding for new keys.
- Model menu defaults separately from per-ring settings and nullable/inheriting item overrides. Preserve stable item UUIDs and current action payloads.
- Compatibility defaults must reproduce today's shared-spoke geometry, zero rotation, upright icons, current system colors, and current outer-ring behavior.
- Keep the existing top-level limits (currently eight inner and eight middle items) and outer sub-item cap unless a later decision explicitly changes them.
- Store colors in a stable, color-space-aware representation suitable for JSON round trips; do not persist platform object descriptions.

### Geometry and Interaction

- `RadialGeometry` currently derives one shared spoke count from inner and middle item counts. Independent counts and offsets require the renderer, centroid math, hit testing, editor overlay, and accessibility position logic to consume per-ring geometry from one source of truth.
- Hidden fixed slots still participate in angle calculation but must not create render, interaction, or accessibility artifacts.
- Conditional outer-ring reveal is invocation state, not persisted state. It latches only for the current invocation.
- The center control must coexist with the current dead zone and both trigger modes without creating an accidental action on release.

### Editor and UI Conventions

- New interactive Settings controls must use the project's AppKit wrappers (`NSViewRepresentable`) rather than SwiftUI `Button`, `Toggle`, `Picker`, `Slider`, `Stepper`, or `ColorPicker`; use `NSColorWell` for color input.
- Prefer the existing `NSSegmentedControl` wrapper for small fixed choice sets. Do not replace longer or dynamic menus mechanically; choose the control from the visibility and fit rules in this spec.
- The current `RingPreviewSelector` uses SwiftUI buttons as annular hit targets. This conflicts with the shared UI convention and must be reconciled during planning before expanding that interaction layer.
- The existing fixed preview/editor layout (`HStack` plus stable preview column) should remain stable unless the plan demonstrates a reason to change it.
- Minimum deployment remains macOS 14. The redesign must not depend on macOS 26-only visual APIs.

### Verification

- Add pure geometry tests covering independent counts, rotations, invisible slots, boundary normalization, and conditional reveal thresholds.
- Add tolerant decoding, migration, invalid-value, and round-trip tests for every new configuration level.
- Add editor-model tests for inheritance, invalid fixed counts, and preview action suppression.
- Add accessibility tests proving hidden slots are absent and the center Settings control is discoverable.
- Live-verify hover alignment, both trigger modes, conditional reveal latching, preview safety, migration appearance, and custom-color states in a signed build.

### Performance and Security

- Preview updates should remain responsive during continuous angle and color adjustments; avoid configuration writes or expensive model reconstruction for every pointer event.
- The preview must use a non-executing interaction path and must not call `ActionService`, post input events, launch processes/apps, or mutate external state.
- This work introduces no network access and should not expand app permissions.

---

## Out of Scope

Explicitly excluded from this spec:

- New action types or completion of unfinished HUD actions.
- Onboarding and default-trigger redesign.
- Logitech HID++ or other advanced device capture work.
- New themes beyond the specified wedge/icon color inheritance controls.
- Changes to the existing item and sub-item capacity limits.
- Executing real actions from the editor preview.
- Redesigning the overall Settings navigation or primary window shell.

---

## Open Questions

| Question | Status | Answer |
|----------|--------|--------|
| Where is Settings accessed from the HUD? | Resolved | A dedicated center control. |
| Does the preview execute configured actions? | Resolved | No; it supports safe hover, selection, reveal, and layout testing only. |
| How is the outer ring shown? | Resolved | User-selectable always visible, pointer-revealed, or always hidden modes. |
| Does a conditionally revealed outer ring hide again during the same invocation? | Resolved | No; it remains visible until that invocation closes. |
| How do slot counts work? | Resolved | Auto or fixed, independently for inner and middle rings; invisible unused fixed slots preserve geometry. |
| How are icon orientation and colors scoped? | Resolved | Menu defaults with optional ring overrides; colors additionally support item overrides. |
| Which contrast metric and threshold should govern automatic icon fallback? | Resolved | WCAG 2.2 relative luminance: 3:1 for meaningful icons/control states and 4.5:1 for small labels; preserve requested colors and render a deterministic black/white fallback when needed. |
| How should `Always hidden` present middle items that contain stored sub-items? | Resolved | Preserve the parent and sub-items, suppress expand/commit and the chevron, expose an unavailable reason, and warn in Settings; never execute the marker action as fallback. |
| What precise radial boundary reveals the conditional outer ring after rings gain independent radii/counts? | Resolved | An outward crossing of the configured inner outer edge (`r1`) after the pointer has been at or inside it; latch until the invocation resets. |

---

## Related

- Project decisions: [docs/decisions.md](../docs/decisions.md)
- Current configuration model: [Configuration.swift](../01_Project/MousePlus/Models/Configuration.swift)
- Current radial geometry: [RadialGeometry.swift](../01_Project/MousePlus/Utilities/RadialGeometry.swift)
- Existing editor preview: [RingPreviewSelector.swift](../01_Project/MousePlus/Views/MenuEditor/RingPreviewSelector.swift)
- Previous Settings spec: [unified-settings-workspace.md](unified-settings-workspace.md)
- Discovery handoff: [2026-09-02 session](../docs/sessions/2026-09-02.md)
