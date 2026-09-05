# Implementation Plan — HUD Opening Styles

**Created:** 2026-09-05 · **Status:** Wave 5 open: keyboard and BetterMouse-to-keyboard opening work; direct native mouse-trigger failure and remaining acceptance are open.

## Goal

Add Circular Sweep, Iris Reveal, Bloom, and Staggered Segments to Opening, with a safe
replayable Settings preview, preserving immediate interaction and existing motion behavior.

## Acceptance criteria

The detailed contracts and AC1–AC9 live in the specification linked below.

- [x] Six persisted Opening choices, compatible decoding, unchanged Fade default (AC1–AC2).
- [ ] All four effects meet their visual and duration contracts (AC3).
- [x] Fixed targets, immediate actions/dismissal, safe branch composition and cancellation (AC4–AC6).
- [x] Native Settings controls and shared, isolated, replayable preview (AC7).
- [ ] Automated, signed live, accessibility, and performance evidence recorded (AC8–AC9).

## Specs and code evidence

- [HUD opening styles specification](specs/hud-opening-styles.md) — authoritative behavior,
  proposed placement, defaults, interruption, preview, and acceptance criteria.
- `01_Project/MousePlus/Models/HUDMotionConfiguration.swift`: summon currently `off`/`fade`;
  decoding falls back per field, and default duration is 0.15 seconds.
- `01_Project/MousePlus/Utilities/HUDMotionPolicy.swift`: role resolver, duration clamp,
  and spatial-to-fade Reduce Motion policy already exist.
- `01_Project/MousePlus/Views/RingMenuView.swift`: `hasAppeared` currently drives whole-content
  opacity; `motion(for:)` uses `interactionEnabled` to suppress editor motion. Input uses
  fixed geometry; native release handling additionally lives in `RingWindowController`.
- `Views/Components/HUDOuterBandMotion.swift` and `HUDOuterBranchMotion.swift` already own
  independent outer progress and frozen branch snapshots. Preserve those responsibilities.
- `Views/MenuEditor/RingPreviewSelector.swift`: real renderer with editor-only input and
  disabled animation. It is not the new playback surface.
- `Views/RingAppearanceSettingsPane.swift`: the existing native Opening popup uses
  `appearanceBinding` → `SettingsWorkspaceCoordinator.edit([.appearance])` → persisted/live
  application. `MotionSettingsTestHost` already exercises this real control path.

Paths in the tasks are relative to `01_Project/MousePlus/`, unless prefixed otherwise.
New filenames are proposed. Check actual target membership when adding files.

## Resume / execution boundary

1. Read this plan, its spec, current `docs/PROJECT_STATE.md`, and applicable Directions
   `/execute` procedure when the user asks to implement. Start at Task 1.1.
2. Scope is supplied by the conversation: implement all four styles and the preview,
   not only the first two suggested effects. Detailed defaults are in the spec.
3. Review the proposed placement in the existing Animation section as part of accepting
   execution scope. Current authorization is planning only; do not launch implementation
   merely because this file exists.
4. Preserve the pre-existing dirty documentation: Motion v1 closure changed project state,
   task/archive/index files and session logs, and deleted its completed plan. This new
   root plan deliberately replaces that completed plan, rather than restoring its tasks.
   No application source changes existed at planning time. No fetch/merge/commit/push was
   performed here; do not infer cross-Mac synchronization from this plan.
5. Planning validation is documentation/source inspection only. The prior 91 focused / 272
   full-suite results belong to Motion v1, not these proposed effects.
6. Model fit for lifecycle, rendering/AX separation, and integration review: deep capability
   with high reasoning. Current host setting is not reliably visible. Routine enum/control
   changes can use balanced capability; use the deeper setting for Tasks 2.1 and 5.1.

## Validation commands

Run from repository root. Use the project's configured signing identity and normal Xcode
environment. If sandbox access blocks Xcode services, follow the established permission
workflow; do not disable signing or edit identity settings to make a check pass.

**B — authoritative build**

```bash
xcodebuild -workspace 01_Project/MousePlus.xcworkspace -scheme MousePlus -configuration Debug build
```

**F — focused suite** (add the proposed new classes when created; before then omit them)

```bash
xcodebuild -workspace 01_Project/MousePlus.xcworkspace -scheme MousePlus -configuration Debug -destination 'platform=macOS' test \
  -only-testing:MousePlusTests/ConfigurationServiceTests \
  -only-testing:MousePlusTests/HUDMotionPolicyTests \
  -only-testing:MousePlusTests/HUDOpeningMotionTests \
  -only-testing:MousePlusTests/HUDOpeningPreviewTests \
  -only-testing:MousePlusTests/HUDOuterBandMotionTests \
  -only-testing:MousePlusTests/HUDOuterBranchMotionTests \
  -only-testing:MousePlusTests/RingRuntimeInteractionTests \
  -only-testing:MousePlusTests/RingViewModelHUDTests \
  -only-testing:MousePlusTests/SettingsWorkspaceCoordinatorTests \
  -only-testing:MousePlusTests/WorkspaceAccessibilityTests
```

For a task, narrow F to the classes named in its Backpressure line. Check result-bundle
counts and test discovery; a successful command selecting no tests is not evidence.
Tests must use temporary stores / injected services, never the user's live configuration.

**T — complete scheme test plan**

```bash
xcodebuild -workspace 01_Project/MousePlus.xcworkspace -scheme MousePlus -configuration Debug -destination 'platform=macOS' test
```

**D — documentation and whitespace**

```bash
git diff --check
```

## Tasks

### Wave 1 — Persisted styles and policy

- [x] **1.1: Extend opening choices and policy without changing defaults.**
  - Targets: `Models/HUDMotionConfiguration.swift`, `Utilities/HUDMotionPolicy.swift`,
    `Views/Components/HUDOuterBandMotion.swift` (exhaustive effect handling if needed),
    `../MousePlusTests/ConfigurationServiceTests.swift`, `HUDMotionPolicyTests.swift`.
  - Work: add the four stable raw values in the spec; resolve all style × master × Reduce
    Motion combinations. Retain the per-field migration and existing role behavior. Audit
    effect switches; new summon effects must not accidentally become outer reveal effects.
  - Success: round-trip every opening choice; legacy/missing/unknown/malformed values retain
    their specified fallbacks; duration clamp/NaN handling and Off/Reduce Motion work.
  - Backpressure: F narrowed to configuration, policy and existing outer-band tests; B.

### Wave 2 — Shared opening lifecycle and stable interaction

- [x] **2.1: Extract the opening presentation owner, retaining Fade/Off behavior.**
  - Depends on: 1.1.
  - Targets: `Views/RingMenuView.swift`, new `Views/Components/HUDOpeningMotion.swift`, new
    `Utilities/HUDOpeningMotionFrame.swift`, `Views/Components/WedgeView.swift` as needed;
    `../MousePlusTests/HUDOpeningMotionTests.swift` (new), `MousePlusTests.swift`.
    Inspect `Controllers/RingWindowController.swift` and `ViewModels/RingViewModel.swift`;
    change them only if a minimal presentation invalidation bridge is necessary.
  - Work: replace `hasAppeared` with one invocation-scoped normalized progress owner;
    separate live/static-editor/opening-preview motion policy from interaction permission.
    Establish pure frame helpers and explicit replay/reset identity. Keep native input,
    center control and AX target geometry outside future masks/transforms.
  - Work: finish on valid aiming/branch opening, settle on relevant preference/layout changes,
    and discard on hide. No per-wedge tasks, global implicit animation, or completion-gated
    action. Unimplemented choices may use Fade internally until Wave 3, but are not exposed
    in Settings before their real renderer exists.
  - Success: Fade/Off regressions pass; selection, native early mouse-up, rapid hide/reopen,
    and live overrides cannot wait for or restart opening. Static editor stays static.
  - Backpressure: F narrowed to opening, runtime interaction and HUD view-model tests; B.
    Add hosted checks for stable native/AX geometry where pure tests cannot establish it.

### Wave 3 — Four renderers (share Wave 2 infrastructure)

- [x] **3.1: Implement Circular Sweep and Iris Reveal masks.**
  - Depends on: 2.1.
  - Targets: `Utilities/HUDOpeningMotionFrame.swift`, `Views/Components/HUDOpeningMotion.swift`,
    `Views/RingMenuView.swift`, `../MousePlusTests/HUDOpeningMotionTests.swift`.
  - Work: sweep clockwise from top in the existing +y-down convention; iris from r0 to r2.
    Apply masks to artwork and backing, leaving semantic targets intact. Handle zero and
    full progress explicitly so a full circle cannot collapse to an empty path at 360°.
    At completion remove transient clipping, including at strokes/label edges.
  - Success: endpoint and intermediate frames match the spec; independent rotations,
    small/large radii and crossing the angular wrap do not rotate/reflow content or leak
    hidden material. Branch expansion settles the opening rather than being double-masked.
  - Backpressure: F narrowed to opening and outer-band/branch tests; B; record visual
    inspection at progress 0, a middle frame, and 1 during development.

- [x] **3.2: Implement bounded Bloom on artwork only.**
  - Depends on: 2.1; work sequentially with 3.1 because shared files overlap.
  - Targets: opening frame/renderer files, `Views/RingMenuView.swift`,
    `../MousePlusTests/HUDOpeningMotionTests.swift`, `MousePlusTests.swift`.
  - Work: implement 0.92 → restrained overshoot ≤1.015 → exactly 1.00 and opacity 0 → 1
    over one normalized duration. Use the final HUD center as the anchor, with no panel
    resizing. Keep native center and accessibility action targets untransformed.
  - Success: scale bounds and exact endpoint are tested; selection ends visual displacement;
    native early release and AX activation still target the same final wedge exactly once.
  - Backpressure: F narrowed to opening and runtime interaction tests; B; inspect actual
    AX frames and screen-edge clipping in a hosted/live view, not only resolver output.

- [x] **3.3: Implement staggered segment presentation with one shared clock.**
  - Depends on: 2.1; integrate after 3.1–3.2 to avoid overlapping renderer edits.
  - Targets: opening frame/renderer files, `Views/RingMenuView.swift`,
    `Views/Components/WedgeView.swift` if needed, `../MousePlusTests/HUDOpeningMotionTests.swift`.
  - Work: derive ranks per band from final slot geometry and implement the spec's total-
    duration cadence. Animate artwork and matching backing coverage together. Preserve
    empty slots, independent inner/middle counts and rotations; do not reorder model items.
    One progress value drives all segments. Preserve final material rendering at progress 1.
  - Success: deterministic ordering across angle wrap; zero/one/many-item cases and fixed
    empty slots behave; last segment finishes by baseDuration; no layout/label reflow,
    extra AX nodes, persistent seams, or per-segment scheduled callbacks.
  - Backpressure: F narrowed to opening tests (cadence, endpoints, counts/rotations, backing
    coverage); B; inspect the material/label result at intermediate and final frames.

### Wave 4 — Native Settings and dedicated preview

- [x] **4.1: Expose all styles and add safe shared-renderer replay.**
  - Depends on: 3.1, 3.2, 3.3.
  - Targets: `Views/RingAppearanceSettingsPane.swift`, new `Views/Components/HUDOpeningPreview.swift`,
    `Views/RingMenuView.swift`; `../MousePlusTests/SettingsWorkspaceCoordinatorTests.swift`,
    `WorkspaceAccessibilityTests.swift`, new `HUDOpeningPreviewTests.swift`.
  - Work: extend existing Opening popup in the spec's order; add the fixed preview and
    existing `AppKitButton` wrapper immediately below it. Reuse current bindings and
    disabled/accessibility conventions; do not create a new Settings destination.
  - Work: isolated current-layout model, explicit replay token, initial static display,
    one replay per style selection, speed applied on next replay, cancel on pane exit,
    effective Reduce Motion caption, and no command/AX activation path. Existing menu
    editor preview continues to suppress all motion and retain editing selection.
  - Success: exercise actual native popup/replay actions; every style persists/reloads and
    live-applies while preserving an unrelated external edit. Replay adds no dirty fields,
    save/live-apply events, service queries or actions. Rapid replay replaces previous work;
    Off and unloaded states disable controls correctly. Keyboard/AX metadata is correct.
  - Backpressure: F narrowed to coordinator, accessibility, opening preview and opening
    tests; B. Review control placement in running Settings at its minimum window size.

### Wave 5 — Integration and live acceptance

- [ ] **5.1: Verify all contracts and record an accurate handoff.**
  - Depends on: 4.1.
  - Targets: all changed source/tests, this plan, specification, `docs/PROJECT_STATE.md`,
    `docs/TASKS.md`, and a new session log when closing implementation.
  - Work: run F, T, B and D; inspect actual result bundles. Review lifecycle cancellation,
    cross-role transactions, material masks, stable hit/AX geometry, native control wiring,
    preview isolation, and idle work. Fix concrete issues before the live handoff.
  - Live matrix: all four new styles plus Fade/Off; 0.05/0.15/0.5 seconds; both trigger modes;
    early release, repeated reopen, center drag/action, Escape/outside/direct dismissal;
    static branches and twelve-app Apps → Snap → Apps; independent counts/rotations and
    empty slots; labels on/off; maximum supported geometry at screen edges; master Off,
    live preference changes, Reduce Motion; preview replay/pane navigation; VoiceOver and
    keyboard control traversal. Observe smoothness and any clipping/seams on supported Macs.
  - Success: launch the exact signed build and identify its path; signature verification
    passes; test results and actual live observations are recorded separately. Visual
    acceptance covers each new effect, not just an app-launch smoke. Record any untested
    OS/device cases or missing VoiceOver/performance observations explicitly.
  - Backpressure: F + T + B + D; `codesign --verify --deep --strict` with the exact built app
    path; signed live matrix and user acceptance. No invented measurements or inherited
    Motion v1 results. If live review is pending, keep this task open.
  - Live remediation: user verification found that Settings replayed the selected style but a
    fresh runtime HUD did not, and that a HUD opened over the active Settings window ignored
    clicks in Settings and did not reliably close on a repeated trigger. These are blocking
    lifecycle defects. Same-app Settings dismissal is now live-confirmed. The apparent remaining
    runtime-animation failure was first observed while three different MousePlus binaries were
    running concurrently. A subsequent clean single-process check still showed only the panel's
    quick fade, confirming initial insertion settles before the selected renderer is visible. The
    live panel now performs the preview's reliable replay-identity transition one frame after mount,
    guarded against stale invocations. The expanded 31-test focused suite passes. User verification
    confirms that the selected animation now runs in the actual HUD, but the entire settled HUD is
    briefly visible before that animation begins. Acceptance remains blocked. The next remediation
    must mount animated runtime content concealed and non-playing, then arm exactly one guarded
    post-mount replay; Off and accessibility-resolved instant presentation must remain immediately
    visible.
  - Concealed-mount remediation implemented: runtime requests explicitly await mount, with hidden
    artwork/center and no playback task armed. The existing guarded callback starts one replay;
    early interaction or preference changes settle immediately and suppress that delayed replay.
    Off/disabled motion remain visible; Reduce Motion retains its Fade fallback. The failing
    playback-arming regression is now green, and 51 focused tests pass, including real-panel
    concealment/replay/interruption checks. Fresh Debug build and strict Developer ID verification
    pass at `/tmp/MousePlus-ConcealedMount-Live.mCxNaw/Build/Products/Debug/MousePlus.app`
    (2026-09-05 12:35:47 CEST). Actual material pixels, user flash confirmation, tap-toggle, and
    remaining visual/accessibility acceptance still require user review. Task 5.1 stays open.
  - Latest user review supersedes the acceptance expectation above: the flash is gone, but runtime
    opening is back to a fade and the selected effect is not visible. The exact cause is not yet
    established. The 51-test pass is valid automated evidence, not proof of the actual visual result:
    hosted opening tests record frames with clear placeholder content, bypassing the full ring's
    material composition and interaction-driven settle callbacks. Next: trace the selected request,
    awaiting-mount flag, guarded replay, settle causes, and displayed progress through the actual
    runtime renderer; restore the effect while keeping the initial frame concealed. No new fix or
    rollback was made during pre-clear logging. App-control preference superseded by the later standing quit/relaunch authorization (see latest session entry).


  - Runtime diagnosis follow-up (2026-09-05): full RingMenuView, centered on the pointer with
    interactions enabled and the production 16 ms replay delay, produces intermediate frames for
    every animated style. Isolated AppKit bitmap captures show a concealed mount and progressive
    Staggered Segments using six/eight slots and independent rotations. An initial test at a fixed
    screen point failed because it put a wedge under the physical pointer; tracing confirmed
    legitimate hover settlement. That is not proof of a controller-placement defect or the user's
    root cause. No speculative playback/placement fix was applied.
  - Added two repeatable full-renderer regression tests: selected effect/intermediate frames and
    actual RingMenuView selection-driven interruption before replay. Physical hover is disabled
    in these retained automated tests; native interaction still has its existing coverage. Added
    bounded Debug-only per-panel logging of selected style, effective frame effect, replay,
    intermediate frame, and first settle reason. 53 focused tests pass; stronger selected-effect and center-concealment assertions passed in a
    targeted rerun. Fresh Debug build and strict Developer ID verification pass at
    `/tmp/MousePlus-OpeningDiagnostic-Live/Build/Products/Debug/MousePlus.app`
    (2026-09-05 13:17:04 CEST). Next is a user-controlled reproduction and HUDOpening log
    inspection with that diagnostic app; Task 5.1 remains open.

  - Follow-up correction: the first diagnostic artifact compiled out the owner because custom
    Debug.xcconfig did not define Swift DEBUG. Added the inherited DEBUG compilation condition;
    fresh build and strict signature pass, and diagnostic format strings are verified in the
    executable. Quit prior PID 97681 gracefully and launched PID 1506 from
    `/tmp/MousePlus-OpeningDiagnostic-Enabled/Build/Products/Debug/MousePlus.app`.
    The user's global preference now explicitly authorizes this quit/relaunch for every fresh
    runnable desktop-app build. Await a new opening trace; the fade-only cause is still unverified.

  - User confirmation: the keyboard shortcut animates correctly, and mapping the mouse button to
    that shortcut in BetterMouse works too. Keep MousePlus's direct mouse binding disabled to
    avoid duplicate triggers in that setup. Live logs from the corrected diagnostic build show
    both full 0.5-second stagger playback and failing invocations settled by pointer hover at
    progress zero before replay. Trigger coordinates, mounted local pointer/center, and first
    settle pointer are now logged. No native-trigger fix or coordinate root cause is established;
    Task 5.1 remains open for that path and the rest of the acceptance matrix.

## Operational learnings / risks

- Static editor preview currently suppresses motion twice (`interactionEnabled` policy and
  its own disabled motion config/transaction). Animate only the dedicated new preview.
- Masks and scale can affect AppKit material compositing and accessibility frames; pure
  geometry tests cannot close those risks. Require hosted/live evidence.
- Opening effects must not make hidden wedges await visibility before accepting input.
  Conversely, first valid aiming should reveal the final layout immediately.
- The existing native release bridge is authoritative; do not replace it with only a
  SwiftUI gesture because hosted gesture delivery was previously unreliable.
- Configurable ring radii plus Bloom's overshoot require checking the existing panel
  padding at maximum settings. Prefer bounded artwork/tuning over changing panel geometry.

## Blocked tasks

None at planning time. Implementation awaits a future execution request. Existing Logitech
capture and tip-jar URL blockers do not affect this feature.

## Execution log

| Wave | Started | Completed | Evidence |
|---|---|---|---|
| 1 | 2026-09-05 | 2026-09-05 | 31 focused tests + authoritative Debug build passed |
| 2 | 2026-09-05 | 2026-09-05 | 39 focused tests + authoritative Debug build passed |
| 3 | 2026-09-05 | 2026-09-05 | 35 focused tests + authoritative Debug build passed |
| 4 | 2026-09-05 | 2026-09-05 | 79 focused tests + authoritative Debug build + minimum-size live Settings inspection passed |
| 5 | 2026-09-05 | — | Review fixed endpoint-only interpolation (`e96ba44`), same-app dismissal/tap-toggle ownership, and initial runtime playback. A clean single-process check confirmed insertion still settled before spatial playback became visible, so runtime now performs the working preview's replay-identity transition one frame after panel mount with stale-invocation protection. The earlier 112 focused/290 full suites and latest 31 focused tests pass; Settings-click dismissal is live-confirmed. A fresh clean build at `/tmp/MousePlus-OpeningStyles-PostMount-Live/Build/Products/Debug/MousePlus.app` is timestamped 2026-09-05 11:10:58 CEST and passes strict Developer ID verification. Runtime animation and remaining live acceptance remain. |

Delete this disposable plan only after all tasks close; retain the specification and
completion evidence. Sync task completion with `docs/TASKS.md` during execution.
