# HUD Opening Styles Specification

**Status:** In progress; implementation and Settings preview complete, final acceptance pending.
**Created / updated:** 2026-09-05
**Authorization:** The user requested a plan for Circular Sweep, Iris Reveal, Bloom,
Staggered Segments, and the suggested replayable Settings preview for a future session.
The detailed timings and preview placement below are proposed implementation defaults.

## Problem statement

Opening currently offers only Off and Fade. Users who want a more expressive entrance
cannot choose one, although the existing motion system already separates presentation
from selection and action timing. The outer ring's existing Radial reveal is a separate
effect for submenu expansion, not a choice for opening the complete menu.

## Proposed solution

Add four opening choices and a safe, replayable preview under the existing Ring Appearance
Animation section. Retain the saved Fade default and all existing motion roles.

### User flow and proposed placement

1. Open Settings → Ring Appearance → Animation.
2. The existing Opening `AppKitPopup` lists, in order: Off, Fade, Circular Sweep,
   Iris Reveal, Bloom, Staggered Segments. Keep its identifier `appearance.motion.summon`.
3. Use the existing Motion speed slider (0.05–0.5 seconds, default 0.15 seconds).
   Its value is the total opening duration, including the stagger's last segment.
4. Directly below Opening, show a compact, fixed 240-point square preview and an
   `AppKitButton` titled “Replay opening”, identifier `appearance.motion.replayOpening`.
   Hover, Outer ring, Branch change, and the existing Reduce Motion note follow it.
5. On first display, the preview is fully revealed. Changing Opening plays it once;
   the replay button restarts it on demand. Speed edits update the next replay without
   repeatedly restarting during slider dragging. There is no automatic loop.
6. Master Off or Opening Off shows the final static preview and disables Replay.
   Style choices remain saved while master Off disables the controls. Under Reduce Motion,
   Replay demonstrates the effective fade; a short caption explains that substitution.

The location follows `RingAppearanceSettingsPane`'s existing `motionStyleRow` and
`appearanceBinding` → `SettingsWorkspaceCoordinator.edit([.appearance])` wiring. Preview
playback is local state, not a configuration edit. Review this concrete placement when
starting implementation; the current request authorizes planning only.

### Visual contract

All styles animate the top-level menu entrance. The native center Settings control stays
at its final location and remains available; for the four new styles it appears immediately.
Existing Fade/Off retain their current visual behavior. New effects do not rotate icons
or change the user's chosen caption orientation.

| Style / persisted value | Intended presentation |
|---|---|
| Circular Sweep / `circularSweep` | A sector mask uncovers the ring clockwise from 12 o'clock through one complete turn. The mask moves; wedge geometry, icons, and labels stay in place. The start direction is independent of configured ring rotation. |
| Iris Reveal / `irisReveal` | A circular mask expands from the dead-zone radius to the middle band's outer radius, uncovering the menu from the center outward. Labels and icons are revealed at their final size and position. |
| Bloom / `bloom` | Ring artwork scales about the HUD center from 0.92 to 1.00 with a fade. A single restrained spring-like settle peaks at no more than 1.015 and ends exactly at 1.00 within the chosen duration. No spinning or repeated bouncing. The native center control and input surface are outside the transform. |
| Staggered Segments / `staggeredSegments` | Each ring's wedges fade in successively clockwise, using one shared progress value. Each segment's fill, backing, icon, label, and border appear together. No translation or scale is required. |

Use ease-out progress for Sweep and Iris. For Bloom, use a bounded, duration-normalized
curve with exact endpoints, rather than a spring whose tail can outlast the speed setting.
For Staggered Segments, use linear global progress and ease-out per segment. Within each
band, order slots by the normalized clockwise angle of their start edge relative to
12 o'clock; ties use slot index. Empty fixed slots count in the cadence but never gain
icons, labels, or accessibility nodes. Inner and middle bands run concurrently, each
spending 55% of the total duration starting segments and 45% finishing their fades:
for rank `i` among `N` slots, delay fraction is `N > 1 ? 0.55*i/(N-1) : 0`, and local
progress is `clamp((globalProgress-delay)/0.45, 0...1)`. A one-slot band fades over the
whole duration. An empty band requires no work. These constants may be tuned during
the live pass without changing the style names or adding settings.

Backing material must follow each reveal. A full backing disk appearing before the
segments would undermine the stagger. Prefer masks over the existing material surface;
avoid layering duplicate translucent surfaces. At progress 1, render the original final
surface without mask seams, missing empty-slot backing, or altered shadows.

### Interaction, composition, and interruption

- The panel is installed at its final frame and alpha. Authoritative radii, angles,
  centroids, hit tests, action targets, and accessibility frames never interpolate.
- Opening progress belongs to the presentation, scoped to one HUD invocation. Each new
  summon starts at zero; hover changes, ordinary redraws, and branch identity changes
  do not restart it. Never put animation progress into persisted settings or action state.
- When aiming first produces a valid action selection, or a submenu begins opening,
  finish the opening presentation immediately without an animation transaction. This
  prevents Bloom or an incomplete reveal obscuring a target while it is being selected.
  Do not finish merely because an initial hover callback reports the center dead zone.
- Native mouse-up, hold-release, center actions, and accessibility activation remain
  immediate even if that presentation update has not rendered. Nothing awaits completion.
- Outer expansion and branch crossfades keep their current policies. A branch opening
  during summon finishes the summon first; an already-present outer branch renders with
  its existing role while the top-level entrance is completed. Do not double-mask it or
  replay an opening sweep when changing branches.
- Escape, outside dismissal, direct action, and hide discard opening state immediately.
  Reopening cannot inherit an old frame or a delayed callback.
- Turning motion Off, enabling Reduce Motion, or changing the active opening style,
  duration, or layout during a live entrance settles it immediately. New choices apply
  on the next summon. Turning Reduce Motion off never restarts the current entrance.
- For a fresh summon with Reduce Motion, all four spatial styles resolve to the existing
  fade policy and saved duration; no sweep, expanding mask, scale, or stagger remains.
  The user's saved choice is preserved. Do not change other roles' fallback behavior.

### Preview behavior and isolation

Use a separate `HUDOpeningPreview` with an isolated model and the shared production
opening renderer. Mirror current inner/middle items, radii, layout, colors, and labels;
use the current empty layout honestly. Fit the final ring inside a fixed canvas with
room for Bloom's overshoot. The preview does not expand branches or query running apps.

The existing `RingPreviewSelector` is an editor with persistent selection and deliberately
disables motion. Keep that behavior. Decouple motion playback permission from
`RingMenuView.interactionEnabled`, so a noninteractive dedicated preview can animate
without activating runtime pointer/action handling. Prefer a small explicit presentation
mode (live, static editor, opening preview) over several interacting booleans.

The dedicated preview has no executable wedge/center accessibility actions, drag editing,
global hotkeys, panel creation, or service/action dispatch. Expose it as one descriptive
image/group, with the selected/effective style in its accessible description. The native
Replay button remains keyboard accessible. Repeated replay cancels/replaces the prior
invocation; leaving the pane cancels it. Other settings changes rebuild the static preview
without initiating a new animation. Preview playback cannot mark configuration dirty.

## Acceptance criteria

- **AC1 — Choices:** Given loaded Settings, choosing any of the six Opening entries through
  its native control updates the effective style, survives save/relaunch, and preserves
  unrelated configuration and other motion roles.
- **AC2 — Compatibility:** Given legacy configuration, a missing summon value, an unknown
  value, or a malformed role field, decoding preserves the existing tolerant defaults and
  unrelated valid fields. Existing `off`/`fade` raw values and default Fade remain unchanged.
- **AC3 — Visuals:** Given each new style and no input, summon produces its visual contract
  and reaches the identical final menu by the configured duration. Verify slow and fast
  settings, independent band rotations/counts, empty slots, and visible/hidden labels.
- **AC4 — Immediate input:** Given a 0.5-second entrance, aiming and releasing before it
  completes invokes the correct action once in both trigger modes. Center action,
  accessibility activation, Escape, and outside dismissal never wait for motion.
- **AC5 — Composition:** Given rapid Apps → Snap → Apps changes during opening, summon
  finishes, existing outer transitions remain correct, and no stale icon, delayed action,
  ghost surface, or restart appears. Cover a twelve-app full-circle branch and static arcs.
- **AC6 — Overrides/lifecycle:** Given any new choice, master Off/Opening Off is instant,
  Reduce Motion uses a fade, live setting changes settle safely, and close/reopen begins a
  fresh entrance without callbacks from an earlier invocation.
- **AC7 — Preview:** Given Settings, changing style or pressing Replay plays the same
  opening effect once in place, respects effective motion preferences, executes no
  commands, and adds no persistence writes beyond actual preference edits. Repeated
  playback and pane navigation leave no continuing animation work.
- **AC8 — Accessibility:** Given VoiceOver or keyboard-only navigation, controls report
  their labels, selected values and disabled states; preview artwork has no action nodes;
  live HUD actions keep stable target frames, order, labels and immediate activation.
- **AC9 — Performance:** Given motion at rest or a dismissed HUD, no repeating timer,
  per-wedge task, or timeline remains active. Signed live observation covers smoothness
  at speed extremes and maximum supported configured rings. Report observations separately
  from any measured frame/CPU trace; test results alone do not prove visual quality.

## Technical considerations and boundaries

- Extend `HUDSummonMotionStyle` and the existing pure `HUDMotionPolicy`; audit all exhaustive
  `HUDMotionPresentationEffect` switches, including `HUDOuterBandMotionFrame.resolve`.
  A dedicated opening descriptor is acceptable if it avoids coupling unrelated roles.
- Replace `RingMenuView.hasAppeared`'s one-shot opacity with a reusable opening presentation
  owner and deterministic frame/mask helpers. Keep `RingWindowController` frame, native
  release forwarding, and dismissal behavior authoritative.
- For Bloom, transforming a subtree that owns accessibility modifiers can move AX frames
  even with fixed logical geometry. Keep semantic targets outside transformed artwork and
  verify real native hit/AX frames; do not assume `.allowsHitTesting(false)` solves both.
- Share rendering between live and preview without copying the full ring implementation.
  Use existing `AppKitPopup`, `AppKitButton`, slider and checkbox wrappers for controls.
- No new framework, shader dependency, external asset, permission, or configuration store
  is required. No new privacy surface is intended.
- Out of scope: new outer-expansion/hover/branch styles, animated dismissal, spinning text,
  sound/particles, per-style direction/easing controls, random styles, looping previews,
  App Switcher feature expansion, onboarding, and signing changes.

## Open questions / implementation discretion

No missing user information blocks this plan. Final visual tuning and the exact preview
size may be adjusted during live verification while preserving the contracts above.
Scope is user-requested; implementation defaults and layout are proposed, not live-accepted.

## Related

- [Implementation plan](../IMPLEMENTATION_PLAN.md)
- [Existing motion decision](../docs/decisions.md#2026-09-04---hud-motion-is-role-based-and-presentation-only)
- [Motion v1 completion evidence](../docs/sessions/2026-09-05.md)
