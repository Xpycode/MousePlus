# App-Specific HUDs Specification

**Status:** Automated implementation complete — signed-live AC19 pending
**Created:** 2026-09-11
**Last Updated:** 2026-09-11

---

## Problem Statement

### What problem does this solve?

MousePlus currently presents one global action layout regardless of which application the user is
working in. That makes the HUD dependable, but it prevents its limited radial slots from holding the
commands that matter most in the current app. The user also needs a predictable way to reach the
global layout without turning contextual behavior off or getting trapped in a persistent mode.

### Who has this problem?

MousePlus users who work across several macOS applications and want each application to have a small,
deliberately curated radial action layout while preserving a familiar global HUD for actions used
everywhere.

### How is it handled today?

All applications use `Configuration.inner` and `Configuration.middle`. The HUD already captures the
frontmost process before its non-activating panel appears, but it uses that context only when an
action needs a target. The older app-aware command-ring plan proposes changing only the outer ring;
that is useful for command discovery, but it does not provide a complete app-specific HUD.

## Proposed Solution

### One-Liner

Let a frontmost application select its own complete action layout, fall back safely to the Global
HUD, and provide a separate configurable Global HUD trigger that can switch contexts at any time.

### Key Capabilities

1. Store one Global action layout plus at most one complete action layout for each application bundle
   identifier.
2. Resolve the Contextual HUD from the frontmost application at summon time, with deterministic
   fallback to Global.
3. Provide an independent Global HUD keyboard shortcut that always bypasses app-specific resolution.
4. Let the Contextual and Global invocation routes replace one another in place while the HUD is
   visible, without executing a stale selection.
5. Create, select, edit, and delete app profiles inside the existing Menu Items workspace.
6. Identify the active HUD context in the center without removing or changing the center's Settings
   action.

### Product Model

- **Global HUD:** the existing `inner` and `middle` action layout. Existing configurations therefore
  remain the Global HUD without migration choices or data loss.
- **App HUD:** an independent copy of the complete inner and middle action layout, keyed by the
  application's stable bundle identifier. It includes labels, icons, actions, action payloads,
  sub-items, dynamic sources, and item-level color overrides.
- **Global presentation:** triggers other than the new Global HUD route, ring geometry, visibility
  policy, menu/ring appearance defaults, motion, opening style, and behavior settings are shared by
  every HUD. App profiles do not duplicate these settings.
- **One profile per app:** v1 does not support several named layouts for the same application.
- **Independent after creation:** creating an App HUD copies the Global action layout once. Later
  edits to Global do not silently modify the App HUD, and app-specific edits do not modify Global.

This specification supersedes the older `APP_COMMANDS_PLAN.md` assumption that Rings 1 and 2 must
always remain identical across apps. It does not replace that plan's separate menu-command browsing,
search, pagination, or pinning ideas; those may later populate items inside this profile model.

### Context Resolution

At the beginning of every new HUD invocation, before the panel appears:

1. Capture a frontmost-app snapshot containing the process identifier and bundle identifier.
2. Ignore MousePlus itself as an app-profile candidate.
3. For a **Contextual HUD** invocation, resolve an exact bundle-identifier match.
4. If a matching readable profile exists, snapshot that App HUD for the invocation.
5. If there is no match, no bundle identifier, or the profile cannot be decoded, use the Global HUD.
6. For a **Global HUD** invocation, use Global without consulting app profiles.

The resolved action layout and target-app snapshot remain stable for that invocation. Ordinary
frontmost-app changes do not mutate a HUD already on screen. Only an explicit Contextual/Global
invocation can replace its visible layout.

### Trigger Model

- The existing Keyboard Trigger and Mouse Button Trigger are the **Contextual HUD** routes.
- Add a separately recorded **Global HUD Shortcut** in Settings → Triggers. It is a keyboard binding
  so BetterMouse or another mouse utility can map a physical button to it using the already-supported
  route. It is unbound by default and supports Hold-release and Tap-toggle like the contextual
  keyboard trigger.
- An exact binding collision between the contextual keyboard trigger and Global HUD Shortcut is
  unusable and must be rejected with a reason while preserving the previously saved binding.
- No modifier convention such as Shift is hard-coded. A modifier-based alternate can be recorded by
  the user as an ordinary distinct shortcut.

When no HUD is visible, either route opens its resolved layout at the pointer. When a HUD is visible:

- Invoking the other route replaces the action layout in the existing panel, preserves its anchor,
  clears selection and outer expansion, and transfers gesture ownership to the new invocation.
- Releasing the previous Hold-release trigger after a switch cannot commit an item from the new
  layout.
- Invoking the same route retains the existing trigger-mode behavior, including Tap-toggle dismissal.
- If Contextual resolution produces Global because the frontmost app has no profile, switching from
  Global to Contextual keeps the Global layout but still resets stale interaction state safely.

Profile replacement is presentation-only. It must not delay hit testing, action dispatch, dismissal,
or accessibility activation. It does not replay the full opening animation; a restrained existing
branch-style transition may be used, with the established Reduce Motion fallback.

### Active-Context Indicator

The center remains the native Settings control. It also communicates the resolved context:

- App HUD: installed app icon and display name, with a small Settings affordance retained.
- Global HUD: MousePlus/global symbol and the name “Global,” with the Settings affordance retained.
- The accessible label includes both the existing action and context, for example
  “Open MousePlus Settings — Finder HUD active.”

The exact compact composition may be tuned against the existing dead-zone dimensions during live UI
review. It must not reduce the current center hit target, change drag behavior, or create a second
overlapping accessibility action.

### Settings User Flow

1. Open Settings → Menu Items.
2. A native profile selector above the existing editor shows **Global** followed by configured apps.
3. Choose **Add App HUD…** and select an installed application through the existing app-picker
   pattern.
4. MousePlus creates the app profile by copying the current Global action layout and selects it.
5. Edit its inner and middle rings with the existing preview/editor workflow. Saving and live apply
   use the workspace's existing visible Saving/Saved/Failed state and safe merge behavior.
6. Select Global or another app to edit that layout. The preview clearly names which profile is being
   edited.
7. Delete an App HUD only after confirmation. Its application immediately falls back to Global;
   Global itself cannot be deleted.

Do not add another Settings destination. New controls belong in the existing Menu Items and Triggers
panes. They must use the project's AppKit-backed control wrappers; this feature does not introduce a
new SwiftUI-control exception or a new navigation/split-view architecture.

### First Prototype Target

Finder is the first live prototype and acceptance target because it is installed on every supported
Mac, has a stable bundle identifier, and offers obvious visible actions. The user creates the Finder
profile by copying Global and changes at least one inner and one middle action. MousePlus does not ship
a hard-coded Finder profile to existing or new users.

## Acceptance Criteria

### Profile Persistence and Editing

- [x] **AC1 — Backward compatibility:** Given an existing configuration without app profiles, when it
  is loaded and saved, then its existing inner and middle layouts become and remain the Global HUD,
  all unrelated valid settings are preserved, and no app profile is created implicitly.
- [x] **AC2 — Create by copy:** Given a loaded Global HUD, when the user adds a Finder HUD, then the new
  profile initially contains an equal but independently editable copy of both action rings and the
  Global HUD remains unchanged.
- [x] **AC3 — Independent edits:** Given Global and Finder profiles, when an item is added, removed,
  reordered, or edited in either profile, then only the selected profile changes and both profiles
  survive quit and relaunch.
- [x] **AC4 — Safe persistence:** Given a corrupt present configuration or a failed save, when the user
  attempts a profile edit, then MousePlus does not replace the file with defaults, does not report a
  false success, and preserves the recoverable user data under the existing workspace recovery rules.
- [x] **AC5 — Delete:** Given a Finder profile, when the user confirms its deletion, then Finder uses
  Global on the next invocation, Global is unchanged, and the deletion survives relaunch.

### Context Resolution

- [x] **AC6 — Exact app match:** Given Finder is frontmost and a Finder profile exists, when the
  Contextual HUD is summoned, then the Finder action layout appears and the captured Finder process
  remains the target for actions from that invocation.
- [x] **AC7 — Global fallback:** Given a frontmost app with no profile, a missing bundle identifier,
  MousePlus as the candidate, or an unreadable profile entry, when the Contextual HUD is summoned,
  then the Global action layout appears without an empty or partially mixed HUD.
- [x] **AC8 — Frozen invocation:** Given an App HUD is visible, when the frontmost application changes
  without a new MousePlus invocation, then the visible layout does not change and no item is retargeted
  silently.
- [x] **AC9 — No summon I/O:** Given profiles are already loaded, when either HUD route is summoned,
  then profile selection completes from the in-memory configuration before panel presentation and
  performs no per-summon disk read.

### Global and Contextual Switching

- [x] **AC10 — Global bypass:** Given Finder is frontmost and has a profile, when the Global HUD
  Shortcut is invoked, then the Global layout appears rather than the Finder layout.
- [x] **AC11 — Contextual return:** Given the Global HUD is visible over Finder, when a Contextual HUD
  trigger is invoked, then the panel stays at the same pointer anchor, the Finder layout replaces
  Global, and the active selection and outer expansion are cleared.
- [x] **AC12 — Global switch:** Given the Finder HUD is visible, when the Global HUD Shortcut is
  invoked, then the panel stays at the same pointer anchor, Global replaces Finder, and no selected
  Finder item executes.
- [x] **AC13 — Release isolation:** Given a Hold-release invocation is still physically held when the
  other HUD route replaces it, when the old trigger is released, then it cannot commit any item in the
  replacement layout; only the new invocation owns subsequent release behavior.
- [x] **AC14 — Same-route behavior:** Given a Tap-toggle HUD is visible, when its same invocation route
  is triggered again, then existing dismissal behavior remains unchanged.
- [x] **AC15 — Duplicate shortcut:** Given the Global HUD Shortcut recorder captures the exact
  contextual keyboard binding, when recording completes, then the collision is explained, the old
  saved Global binding remains intact, and runtime routing is unambiguous.

### UI and Accessibility

- [x] **AC16 — Context indication:** Given either HUD is visible, then the center communicates the
  resolved app name/icon or Global state while retaining its existing Settings click target, drag
  behavior, frame, and a single accurate accessibility action.
- [x] **AC17 — Settings selection:** Given multiple profiles, when the user changes the native profile
  selector, then the preview and editor identify and display only the selected profile; changing the
  selection alone does not dirty or save configuration.
- [x] **AC18 — Reduce Motion:** Given Reduce Motion is enabled, when a visible HUD changes profile,
  then no spatial profile-change motion occurs and interaction remains immediate.
- [ ] **AC19 — Live Finder proof:** Given a signed fresh build and a user-created Finder profile with
  at least one changed inner and middle action, when the user alternates Finder and an unconfigured
  app and exercises both invocation routes, then Finder/Global selection, in-place switching,
  fallback, action targeting, save, and relaunch persistence all match this specification.

## Technical Considerations

### Data and Compatibility

- Keep existing `Configuration.inner` and `Configuration.middle` as the canonical Global layout for
  backward compatibility.
- Add a decode-tolerant bundle-ID-keyed app-profile collection with an empty default. Unknown or bad
  individual profile data must not destroy otherwise valid Global configuration.
- Use a dedicated action-layout value or equivalent boundary so app profiles cannot accidentally
  duplicate triggers, appearance, behavior, or `HUDCustomization`.
- Bundle identifier is identity; display name and icon are presentation resolved from `NSWorkspace`.
  Preserve a profile for a temporarily missing application and display a recoverable missing-app
  state in Settings.
- Profile editing must extend `SettingsWorkspaceCoordinator`'s fresh-read merge, load gate,
  serialized save, backup, undo/reset, and live-apply guarantees rather than adding another writer.

### Runtime Architecture

- Replace the current PID-only capture with one immutable frontmost-app snapshot shared by profile
  resolution and action targeting. PID is transient action context; bundle identifier is durable
  profile identity.
- Resolve the layout in the app/window coordinator before mounting or replacing the HUD. Keep
  `RingViewModel` responsible for one resolved layout, not for reading configuration from disk.
- Give every invocation a route/owner identity so stale keyboard or mouse up-events cannot commit
  after an in-place profile replacement.
- Preserve the existing dynamic Running Apps source, full-circle outer layout, stale-expansion guard,
  native mouse-up commit path, non-activating panel, and immediate dismissal/action behavior.

### Performance

- Profile lookup is an in-memory dictionary operation performed before display.
- Switching profiles must not enumerate applications, walk Accessibility trees, or rebuild services.
- No repeating task, observer, or timer may remain solely for app-profile selection after dismissal.

### Security and Privacy

- Frontmost-app identity comes from local `NSWorkspace` state and is stored only in the existing local
  JSON configuration when the user creates a profile.
- This feature adds no network access, telemetry, entitlement, or permission prompt. Individual
  configured actions retain their existing permission and error behavior.

### UI Convention Check

- Place the profile selector and Add/Delete actions in the existing Menu Items workspace and the
  Global HUD Shortcut in the existing Triggers pane.
- Use `NSPopUpButton`/`NSButton` through existing AppKit wrappers or purpose-built equivalents.
- Do not introduce `NavigationSplitView`, a Tahoe liquid-glass sidebar, or new raw SwiftUI interactive
  controls. Preserve the current `HSplitView`-based workspace.
- Before implementation, confirm exact placement against the rendered Menu Items and Triggers panes
  under the UI Changes Protocol.

## Out of Scope

- Sparse per-slot inheritance or overrides between Global and App HUDs.
- Automatic propagation of later Global layout changes into an existing App HUD.
- Per-app triggers, motion, geometry, behavior, menu/ring appearance, or opening styles.
- More than one named profile for the same bundle identifier.
- Profile rules based on window title, document, website, URL, workspace, Space, or display.
- Automatic profile creation, suggested commands, frequency learning, menu-bar crawling, command
  search/palette, pagination, and pin-from-search behavior from `APP_COMMANDS_PLAN.md`.
- A shipped hard-coded Finder layout.
- A second direct physical-mouse slot dedicated to Global in v1; BetterMouse can map a mouse gesture
  to the Global keyboard shortcut while direct MousePlus mouse coverage remains a deferred release
  check.
- Import/export, cloud sync, or sharing of profiles.
- Redesigning the center Settings interaction or the established HUD opening/branch motion system.

## Open Questions

No unresolved behavior question blocks planning. The exact center icon/gear composition and restrained
in-place transition are implementation proposals to validate in a live UI review; they may be tuned
without changing profile selection, fallback, trigger, or accessibility semantics.

## Related

- [Implementation plan](../IMPLEMENTATION_PLAN.md)
- [Current project state](../docs/PROJECT_STATE.md)
- [Discovery handoff](../docs/sessions/2026-09-11.md)
- [Older app-aware command-ring plan](../docs/APP_COMMANDS_PLAN.md)
- [Unified Settings workspace specification](unified-settings-workspace.md)
- [App Switcher implementation plan](../docs/APP_SWITCHER_PLAN.md)
- [App-aware command-ring decision](../docs/decisions.md#2026-05-30---app-aware-command-rings-min-target-ax-press-center-search-planned)
