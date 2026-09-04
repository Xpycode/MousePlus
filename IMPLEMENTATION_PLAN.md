# HUD Motion v1 — Implementation Plan

> **Status:** In progress. Wave 1 completed 2026-09-04; Wave 2 is next.
> **Source:** `docs/sessions/2026-09-04.md` §HUD animation feasibility and
> `docs/decisions.md` §HUD motion is role-based and presentation-only.

## Goal

Add fast, configurable, Reduce Motion-aware animation to ring summon, wedge hover, outer-ring
expansion, and branch replacement without delaying or moving MousePlus's logical pointer targets.

## Product Contract

**Logic snaps; pixels glide.** `RadialGeometry`, `RingViewModel` selection/expansion state, native
mouse-up handling, action dispatch, and dismissal remain immediate and authoritative. Animation is
presentation-only and is never awaited before accepting input or executing an action.

### Settings placement

Extend the existing **Settings → Ring Appearance → Animation** section. Do not add a new sidebar
destination. Reuse `AppKitCheckbox`, `AppKitPopup`, and `AppKitSlider` through the existing
`SettingsWorkspaceCoordinator.edit([.appearance])` persistence/live-apply path.

The v1 surface contains:

- Master **Animate ring** checkbox.
- **Motion speed** slider, preserving the current 0.05–0.5 second range and saved value.
- **Opening:** Off / Fade.
- **Hover:** Off / Emphasis.
- **Outer ring:** Off / Radial reveal.
- **Branch change:** Off / Crossfade.
- A short note that macOS Reduce Motion replaces spatial motion with a fade or instant update.

Only implemented choices appear. The role-specific enums are intentionally extensible so later
styles can be added without another persistence redesign. The embedded Menu Items preview remains
animation-free; it previously suffered layout jumps from runtime spring/scale animation.

## Acceptance Criteria

- [ ] Existing configurations retain their saved master animation setting and duration after the
      new role-based motion configuration is introduced.
- [ ] Fresh configurations default to Fade opening, Emphasis hover, Radial reveal outer expansion,
      Crossfade branch changes, animation enabled, and the existing 0.15-second base response.
- [ ] Summoning the HUD uses at most a short opacity presentation; the panel frame and final pointer
      geometry are present immediately.
- [ ] Hover changes animate only emphasis (wedge/accent/border and a subtle icon scale), complete
      quickly, and do not move wedge boundaries or labels.
- [ ] Localized outer items visually unfold from their parent direction; full-circle running apps
      reveal simultaneously from the outer band's inner radius, without a 12-item cascade.
- [ ] Apps↔Snap and other branch changes crossfade briefly while the existing expansion epoch still
      prevents late dynamic results from becoming visible.
- [ ] Direct actions and cancellation dismiss immediately; no animation completion participates in
      commit, action, or close logic.
- [ ] The master switch, role controls, and speed persist and apply to the next live invocation.
- [ ] With macOS Reduce Motion enabled, radial/scale motion is replaced with a short fade or an
      instant update; VoiceOver labels, values, order, and activation remain unchanged.
- [ ] Rapid pointer sweeps, both trigger modes, and a 12-app full circle show no missed commits,
      stale icons, continuous idle animation, or visible/logical target disagreement.
- [ ] Focused tests, the complete test target, `git diff --check`, and the authoritative Debug build
      pass before signed live verification.

## Non-Goals

- No rotating rings, orbiting icons, particles, animated blur, continuous glow, 3D/depth motion,
  hue cycling, or bounce on every hover.
- No long per-wedge staggering, action-success celebration, delayed dismissal, or input gating.
- No panel movement/resize animation and no change to the native AppKit mouse-up commit boundary.
- No Liquid Glass dependency, `phaseAnimator`, keyframe sequence, `Canvas`, or `drawingGroup` unless
  later profiling proves a concrete need.
- No new Settings destination and no per-item/per-wedge animation overrides in v1.

## Existing Foundation and Delta

### Already present

- `RingMenuView` inserts the outer band with parent-anchored scale plus opacity and applies one
  configurable spring to `expandedParentIndex` and `activeSelection`.
- `AnnularWedge.animatableData` interpolates both angles and radii.
- `AppearanceConfig` persists `animationEnabled` and `animationDuration`; Ring Appearance edits them
  through native AppKit controls and the safe Settings coordinator.
- Dynamic Apps expansion uses an incrementing epoch plus expanded-parent guard; do not replace it.
- `RingWindowController` creates a fresh non-activating panel at the final size and position, then
  tears it down immediately on close.
- `RingPreviewSelector` explicitly disables runtime animation to prevent preview movement.

### Needed

- A tolerant role-based motion model that absorbs the two legacy appearance fields.
- A pure resolver from role + saved style + duration + Reduce Motion to a render descriptor.
- Scoped animations instead of one container-wide spring.
- Distinct localized/full-circle outer reveal behavior and intentional branch replacement.
- A view-local summon presentation that does not animate the AppKit window or logical geometry.
- Existing-section Settings controls and accessibility/live verification.

---

## Tasks

### Wave 1 — Persistence and policy foundations

- [x] **1.1: Add the role-based motion model and legacy decode bridge**
  → `01_Project/MousePlus/Models/HUDMotionConfiguration.swift` (new),
  `01_Project/MousePlus/Models/Configuration.swift`, configuration fixtures/tests
  - Define typed styles for summon (`off`/`fade`), hover (`off`/`emphasis`), outer expansion
    (`off`/`radialReveal`), and branch change (`off`/`crossfade`), plus master enable and base duration.
  - Add `AppearanceConfig.motion`; when absent, seed master enable and duration from the legacy
    `animationEnabled`/`animationDuration` keys and use the v1 style defaults.
  - Decode every new field tolerantly so missing or unknown values fall back independently rather
    than taking down the complete configuration.
  - Success: current-production and partial/legacy JSON preserve prior behavior; new JSON round-trips
    all roles; malformed role values fall back only for that role.
  - Backpressure:
    `xcodebuild -workspace 01_Project/MousePlus.xcworkspace -scheme MousePlus -configuration Debug test -only-testing:MousePlusTests/ConfigurationServiceTests`

- [x] **1.2: Add a pure HUD motion policy resolver**
  → `01_Project/MousePlus/Utilities/HUDMotionPolicy.swift` (new),
  `01_Project/MousePlusTests/HUDMotionPolicyTests.swift` (new)
  - Resolve semantic role, selected style, master switch, clamped duration, and Reduce Motion into a
    small presentation descriptor (`instant`, `fade`, or spatial effect plus duration).
  - Make Reduce Motion substitution explicit and testable: never emit scale/radial geometry motion
    when it is enabled; color/opacity feedback may remain short.
  - Keep policy free of `RingViewModel` mutations and action timing.
  - Success: a table-driven test covers every role × master switch × Reduce Motion combination and
    duration bounds.
  - Backpressure:
    `xcodebuild -workspace 01_Project/MousePlus.xcworkspace -scheme MousePlus -configuration Debug test -only-testing:MousePlusTests/HUDMotionPolicyTests`

### Wave 2 — Scoped wedge and outer-band presentation

- [ ] **2.1: Replace the blanket spring with scoped hover and branch-dimming feedback**
  → `01_Project/MousePlus/Views/RingMenuView.swift`,
  `01_Project/MousePlus/Views/Components/WedgeView.swift`
  - Remove the container-wide `animation(... value: activeSelection/expandedParentIndex)` modifiers.
  - Apply the resolved hover descriptor only to emphasis color, border, opacity, and a restrained
    icon scale (target approximately 1.03; no bounce, translation, or label motion).
  - Scope expansion-related dimming separately so a pointer sweep cannot restart unrelated geometry
    animation throughout the complete view tree.
  - Success: selection remains immediately correct under rapid sweeps; only the old/new visual
    emphasis interpolates; Off and master-disabled modes snap.
  - Backpressure: focused `RingViewModelHUDTests`, then authoritative Debug build.

- [ ] **2.2: Implement localized and full-circle outer-ring reveal presentations**
  → `01_Project/MousePlus/Views/Components/HUDOuterBandMotion.swift` (new),
  `01_Project/MousePlus/Views/RingMenuView.swift`,
  `01_Project/MousePlus/Views/Components/WedgeView.swift`
  - Localized arc: visually interpolate each outer wedge from the parent midpoint and `r2` to its
    final angles/`r3`; fade glyphs in without moving their final hit targets.
  - Full-circle Apps: reveal all wedges simultaneously outward from `r2`; do not sweep clockwise or
    stagger up to twelve entries.
  - Under Reduce Motion use fade-only; Off snaps. Keep the localized material backing and wedge
    content synchronized so no detached halo appears.
  - Success: static submenus communicate parentage, Apps stays fast and balanced, and hit testing uses
    final `RadialGeometry` from the first frame.
  - Backpressure: focused radial/HUD integration tests, `git diff --check`, authoritative Debug build.

### Wave 3 — Summon and branch lifecycle

- [ ] **3.1: Add a short summon fade and intentional outer-branch crossfade**
  → `01_Project/MousePlus/Views/RingMenuView.swift`,
  `01_Project/MousePlus/Controllers/RingWindowController.swift` only if a minimal lifecycle hook is
  required, `01_Project/MousePlusTests/RingViewModelHUDTests.swift`
  - Drive summon from view-local presentation state after the hosting view is installed; keep the
    `NSPanel` at its final frame/alpha for event routing and do not use AppKit window zoom/movement.
  - Key outer presentation replacement to the expanded parent/content generation so static-to-static
    and Apps↔Snap changes receive the configured short crossfade.
  - Preserve `expansionEpoch`, `expandedParentIndex`, dynamic icon clearing, native mouse-up, and
    immediate `orderOut` behavior exactly.
  - Success: a very fast trigger-up can still commit/cancel correctly during presentation; rapid
    re-pointing never reintroduces old app names/icons; dismissal remains instant.
  - Backpressure: runtime-interaction and HUD tests, then authoritative Debug build.

### Wave 4 — Existing-section Settings controls

- [ ] **4.1: Expand Ring Appearance → Animation with role controls**
  → `01_Project/MousePlus/Views/RingAppearanceSettingsPane.swift`,
  existing AppKit control wrappers as needed,
  `01_Project/MousePlusTests/SettingsWorkspaceCoordinatorTests.swift`,
  `01_Project/MousePlusTests/WorkspaceAccessibilityTests.swift`
  - Keep the current master checkbox; relabel the response slider as Motion speed without changing
    its stored range/value semantics.
  - Add four labeled `AppKitPopup` rows for Opening, Hover, Outer ring, and Branch change; disable
    them with the slider when the master switch is off.
  - Add stable accessibility identifiers and the Reduce Motion explanatory note. Do not add raw
    SwiftUI controls or another sidebar section.
  - Keep `RingPreviewSelector` motion disabled and update it to the new model API.
  - Success: values save through the existing debounced fresh-read merge, survive relaunch, live-apply
    to the next HUD invocation, and are complete/understandable through VoiceOver.
  - Backpressure: focused Settings persistence/accessibility tests, `git diff --check`, Debug build.

### Wave 5 — Closure gate

- [ ] **5.1: Complete automated, adversarial, performance, and signed-live verification**
  → tests, `docs/sessions/`, `docs/PROJECT_STATE.md`, `docs/TASKS.md`
  - Run focused tests and the complete MousePlus test target; run `git diff --check`; run the
    authoritative Debug build.
  - Review for accidental animation of layout, labels, pointer geometry, panel frame, accessibility
    order, and action/dismiss paths. Confirm no continuous timeline/timer remains active at rest.
  - Profile or inspect Core Animation behavior with twelve app wedges and rapid sweeps; the gate is
    no visible hitch, runaway redraw, or idle animation rather than an unmeasured optimization claim.
  - Signed live matrix: hold-release and tap-toggle; fast invoke→release; static submenu; 12-app full
    circle; repeated Apps→Snap→Apps; each role Off; master Off; slow/fast duration extremes; Reduce
    Motion; VoiceOver activation; Escape/click-outside/direct-action dismissal.
  - User acceptance: motion improves hierarchy and feedback without making the HUD feel slower or
    causing a visible wedge to disagree with the action under the pointer.
  - Backpressure:
    `xcodebuild -workspace 01_Project/MousePlus.xcworkspace -scheme MousePlus -configuration Debug test`
    then
    `xcodebuild -workspace 01_Project/MousePlus.xcworkspace -scheme MousePlus -configuration Debug build`

---

## Wave Dependencies

```text
Wave 1: persisted model + pure policy
   ↓
Wave 2: scoped hover/dimming + outer reveal
   ↓
Wave 3: summon + branch lifecycle
   ↓
Wave 4: Settings surface over verified roles
   ↓
Wave 5: full closure gate
```

Wave 4 intentionally follows runtime implementation so Settings never advertises an effect that does
not exist. Wave 3 follows Wave 2 because branch replacement must reuse the outer presentation seam,
not create a second animation system.

## Operational Learnings

- The non-activating panel's reliable release boundary is AppKit `mouseUp`; animation must not move
  commit ownership back into SwiftUI gesture completion.
- A visual transform can temporarily disagree with final radial hit testing. Keep durations short,
  keep logical geometry final, and prefer opacity/emphasis when spatial interpolation adds no meaning.
- The editor preview previously jumped when it inherited runtime spring/scale animation; do not
  re-enable it incidentally while migrating the appearance model.
- `AnnularWedge` already supplies the correct angle/radius interpolation seam; do not replace the
  geometry engine or add a `Canvas` merely to animate it.

## Blocked Tasks

None. Signed live verification requires the user's normal Accessibility-approved build/run flow, as
with prior HUD closure gates, but implementation can proceed through the automated waves first.

## Execution Log

| Wave | Started | Completed | Commits |
|------|---------|-----------|---------|
| 1 | 2026-09-04 | 2026-09-04 | `2fa266a`, `582513d` |
| 2 | | | |
| 3 | | | |
| 4 | | | |
| 5 | | | |

---
*Delete this root plan after all tasks close; preserve the outcome in the session log and project state.*
