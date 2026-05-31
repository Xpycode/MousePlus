# HUD Actions Plan — What the Ring Actually *Does*

Status: **planned 2026-05-30.** Research-backed specs for five HUD action types, to be
built after / alongside the HID trigger track. Companion to `IMPLEMENTATION_PLAN.md`
(which covered the ring *rendering*). This doc covers the **actions a selected wedge fires**.

Each feature's API claims were verified against real sources: `acsandmann/menuanywhere`
(menu mirror), `rxhanson/Rectangle` (window snapping), live `man screencapture`, and Apple
docs. Where a source contradicted assumptions, the spec follows the source.

---

## 0. Current reality (why this doc exists)

`ActionService.execute` today handles only **2 of 4** advertised action types:

| ActionType | State |
|---|---|
| `appSwitch` | ✅ works (activate-or-launch by bundle ID) |
| `custom` | ✅ works (`zsh -c actionData`, fire-and-forget) |
| `clipboard` | ❌ `break` stub — **dropping** (user has a separate clipboard app, ClipSmart/Aloft; bridge to it via `appSwitch`/`custom` instead of reimplementing) |
| `menuBar` | ❌ `break` stub — **Feature A below** |

Default sample wedges are half-decorative: three inner items are `.custom` with empty
`actionData` (no-ops); only app-switch and the one `open -a Calculator` custom command
actually do anything end-to-end.

---

## 1. Shared foundation (build ONCE — all five features depend on it)

Do this first; it's the substrate. ~1–1.5 days.

### 1.1 Extend `ActionType`
```swift
enum ActionType: String, Codable, CaseIterable {
    case appSwitch, custom          // existing, keep
    case menuBar                    // existing case, finally implemented (Feature A)
    case windowSnap                 // NEW (Feature B) — actionData = SnapZone.rawValue
    case systemToggle               // NEW (Feature D) — actionData = SystemToggle.rawValue
    case screenshot                 // NEW (Feature E) — actionData = ShotMode.rawValue
    // 'clipboard' removed (see §0)
    // dynamic app switcher (Feature C) reuses .appSwitch on commit; marker on the PARENT wedge
}
```
Dedicated cases (not overloaded `custom`) keep config UI typed, avoid a shell-injection
surface for system actions, and let each action carry a type-safe payload in `actionData`.

### 1.2 Async / dynamic `RingViewModel.expand()`
Two features (A menu-mirror, C app-switcher) populate the **outer ring from a live source**,
not from static `subItems`. Make expansion async-capable with a **stale-expansion guard**:

```swift
func expand(_ parentIndex: Int) {
    guard parentIndex >= 0, parentIndex < middleItems.count else { return }
    expandedParentIndex = parentIndex
    let parent = middleItems[parentIndex]
    switch parent.dynamicSource {                 // nil ⇒ existing static path
    case .appMenuMirror: populateMenuMirror(parentIndex)      // Feature A
    case .runningApps:   populateRunningApps(parentIndex)     // Feature C
    case .none:          outerItems = parent.subItems ?? []   // unchanged
    }
}
// In each async populate: after the await, `guard expandedParentIndex == parentIndex else { return }`
// before assigning outerItems — the user may have re-pointed mid-fetch.
```
Show a transient "loading" / empty-arc state while the async fetch is in flight.

### 1.3 `IconSource` — real app icons in wedges (Feature C needs this)
`RingMenuItem.icon` is a `String` and `WedgeView` only does `Image(systemName:)`. App icons
are `NSImage` and aren't `Codable`. **Do NOT put `NSImage` in the model.** Instead:

- Keep `RingMenuItem` a pure Codable value type (static config stays SF-Symbol strings).
- Add `enum IconSource { case sfSymbol(String); case appIcon(NSImage) }`.
- `WedgeView` takes an explicit `iconSource: IconSource` param; `RingMenuView` computes it
  per wedge from a side dictionary `dynamicIcons: [RingMenuItem.ID: NSImage]` held on the VM
  (cleared in `reset()`/`collapse()`).
- Render: SF symbol → tint white when highlighted; app icon → **never tint** (full-color),
  `.resizable().frame(28×28).clipShape(RoundedRectangle(cornerRadius: 6))`.

### 1.4 Accessibility-permission plumbing (Features A, B, parts of D)
All AX-based features share **one** TCC grant (`kTCCServiceAccessibility`). Build a single
reusable status row + `AXIsProcessTrustedWithOptions([prompt: true])` flow.
**Pre-prime in Settings, never mid-gesture** — a TCC consent dialog popping during a
hold-release pie gesture loses the gesture and silently fails. When the user adds an
AX-backed wedge, probe/prompt then, in a calm context.

### 1.5 Dismiss-before-action seam (Feature E needs it)
`RingViewModel.requestClose` (set by AppDelegate, fired at `RingViewModel.swift:132` on a
direct commit) already tears down the panel. Screenshot capture must run *after* the panel
is gone — fire `requestClose()`, `await Task.yield()` one runloop tick, then capture.

### 1.6 ⚠️ Sandbox / App Store reality (product decision — log to decisions.md)
**Features A, B, and D cannot ship in a sandboxed App Store build** — cross-app AX control
(A, B), shelling to system binaries, and scripting System Events/Finder (D) are all
sandbox-illegal. This reinforces the **direct-distribution / GPLv3** path already chosen.
Keep each behind its service so a future sandboxed target can compile them out. Feature E
(interactive screenshots) and Feature C (app switch) are the only two that could survive a
sandbox (E would need a ScreenCaptureKit backend swap).

---

## Feature A — App Menu-Bar Mirror  ⭐ the differentiator

**Goal.** A middle wedge "App Menu" that expands the outer ring to the **frontmost app's
top-level menus** (File/Edit/View/Window/Help…); committing one **hands off to the real
native menu at the cursor**.

**Design = radial top-level index → native `NSMenu` handoff (menuanywhere's proven path).**
The ring is a fast radial index into the menu bar; AppKit/AX handle the deep lists,
submenus, and dynamic items where linear menus already win. Depth cap 3 is respected
(outer band = top-level names = direct "open this menu" actions). *Confirmed from source:
menuanywhere mirrors the AX subtree into a fresh `NSMenu` and `popUp`s at the cursor; it uses
`kAXPressAction` only on the final leaf item, after `app.activate()` + a 0.1s delay.*

**Key APIs.** `NSWorkspace.frontmostApplication.processIdentifier` (capture at ring-open!) →
`AXUIElementCreateApplication(pid)` → `kAXMenuBarAttribute` → children (`AXMenuBarItem`) →
`kAXTitleAttribute`. Leaf commit = `AXUIElementPerformAction(item, kAXPressAction)`. Batch
per-item reads with `AXUIElementCopyMultipleAttributeValues`. Lazy-populate submenus off a
`userInitiated` queue (AX IPC is slow — never walk the whole tree).

**Threading.** `@MainActor AccessibilityService`, **not** an `actor` — `NSMenu`/`NSMenuItem`
are main-thread-affine; offload only the bulk AX reads to a background queue and hop back.

**Surface.**
- `@MainActor AccessibilityService`: `isTrusted`, `ensureTrusted(prompt:)`,
  `topLevelMenus(forPID:) async -> [MenuEntry]`, `openMenu(_:atScreenPoint:frontApp:)`.
- `RingViewModel`: capture `frontPID`/`frontApp` in `onRingOpen()`; `populateMenuMirror`
  maps `[MenuEntry]` → outer `RingMenuItem`s (`actionType: .menuBar`, `actionData = entry.id`).
- `ActionService.menuBar` routes to the main-actor coordinator: `app.activate()` if not
  active → 0.1s settle → `openMenu(at: NSEvent.mouseLocation)`.

**Risks.** Capture pid at ring-open (non-activating panel *shouldn't* steal frontmost — verify).
Fullscreen apps: AX tree still exists so the mirror works (option-A AXPress-the-bar-item is
flaky there — another reason to prefer the mirror). Localized titles break an English-keyed
SF-Symbol map → fall back to label text. Re-check `AXIsProcessTrusted` on `.apiDisabled`.
`kAXMenuItemCmdVirtualKeyAttribute` spelling unverified — menuanywhere skips it; optional.

**Effort ≈ 1.5–2 days** (most of `buildItems`/NSMenu-mirror is portable from menuanywhere's
`MenuBuilder.swift`). **Depends on:** §1.1, §1.2, §1.4. **Defer:** B2 (fully ring-rendered
nested menus) and search palette (NOT in menuanywhere's current source — net-new).

---

## Feature B — Window Snapping  ⭐ most radial-native, lowest risk

**Goal.** Snap the frontmost window to halves / corners / maximize / center (stretch: thirds).
8 spokes = 8 screen directions — the direction you pick *is* where the window goes.

**Ring placement.** Its own middle wedge (`rectangle.split.2x1`) → expands to an outer arc of
8 directional sub-commands. Halves on cardinals, corners on diagonals, maximize at N, center
at S. Thirds (stretch) go in a deeper variant or modifier.

**Key APIs.** `AXUIElementCreateApplication(pid)` → `kAXFocusedWindowAttribute` (fallback
`kAXWindowsAttribute.first`) → set `kAXPositionAttribute` + `kAXSizeAttribute` via
`AXValueCreate(.cgPoint/.cgSize)`. Detect fixed-size via `AXUIElementIsAttributeSettable(.size)`.

**The two Rectangle hacks (use verbatim):**
1. **`AXEnhancedUserInterface` toggle** — some apps (Electron/Chromium, some Catalyst) ignore
   or mis-animate moves. Read the *app* element's `"AXEnhancedUserInterface"`; if true, set
   false before the move, restore true after (`disableEnable` default).
2. **Set order = size → position → size.** macOS clamps to display + min-size; shrink first so
   the move isn't blocked, then position, then size again to correct min-size clamping.

**Coordinate flip (the #1 bug source).** AX = top-left origin, +y down, on the **primary**
screen. AppKit `visibleFrame` = bottom-left, +y up, menu-bar/Dock already excluded. Compute
the target rect from the target screen's `visibleFrame`, then flip y about the **primary**
screen's `frame.maxY` (NOT the target screen's):
```
ax.origin.x = appKitRect.origin.x
ax.origin.y = NSScreen.screens[0].frame.maxY - appKitRect.maxY
ax.size     = appKitRect.size
```
Pick the target screen by largest overlap with the window's current frame (cursor's screen as
a tie-break, since the ring is pointer-anchored).

**Threading.** `actor WindowService` (AX calls are thread-safe and can block tens of ms — keep
off main so the ring doesn't jank). Resolve `NSScreen`/`NSEvent.mouseLocation` on `@MainActor`
first, pass plain `CGRect` geometry into the actor.

**Surface.** `enum SnapZone { …; func rect(in vf: CGRect) -> CGRect }`;
`actor WindowService.snap(_ zone:) throws`; `ActionService.windowSnap` → `SnapZone(rawValue:)`.

**Risks.** Fixed-size windows (skip resize, maybe still center). Native fullscreen / Stage
Manager (detect & bail, or accept slight misplacement — `visibleFrame` covers most). Spaces
(move on another Space can no-op). `_AXUIElementGetWindow` is private — **don't use** (not
needed for snapping).

**Effort ≈ 2–2.5 days** (+0.5 for thirds). **Depends on:** §1.1, §1.4. Self-contained
otherwise — good *first* build (no async-expand, no icons).

---

## Feature C — Dynamic App Switcher

**Goal.** A middle wedge "Apps" that expands the outer ring to **currently running apps**
(real icons + names); commit switches to it. Commit reuses the existing, working
`.appSwitch` path — only the *population* is new.

**Key APIs.** `NSWorkspace.runningApplications` → filter `activationPolicy == .regular` &
exclude self → `localizedName`, `bundleIdentifier`, `icon` (NSImage), `isActive`. Activate
with `app.activate()` (the codebase **already uses this correct macOS-14 form**;
`.activateIgnoringOtherApps` is deprecated/no-op on 14+).

**Ordering = self-tracked MRU.** No public z-order/MRU API. Observe
`NSWorkspace.didActivateApplicationNotification` **from app launch** (not ring-open) to build
a bundleID→last-activated map; most-recent-first, alphabetical tie-break. Exclude self.

**Icons.** Uses the §1.3 `IconSource` pattern — this is the feature that *requires* it.

**Overflow.** Typical 8–15 regular apps; outer ring comfortably fits ~10–12. **v1: cap at ~12
MRU**, no "More…" (depth cap 3 means outer can't open a deeper ring; paging is a v2 refill-in-
place). Verify outer `outerCount` can exceed `spokeCount` (it can — `RadialGeometry` takes
`outerCount` separately) but tune for legibility via `/preview`.

**Surface.** `actor AppSwitcherService`: `startTrackingMRU()` (launch), `runningApps() ->
[AppEntry]`. `RingViewModel.populateRunningApps` maps to outer `.appSwitch` wedges + stashes
icons in `dynamicIcons`.

**Risks.** Cooperative activation on macOS 14 *may* fail to focus-steal from a foreground app
(existing appSwitch works, so low risk — verify on hardware via **user-triggered** test, per
the no-synthetic-input rule; fallback `yieldActivation(to:)`/`activate(from:)`). Optionals
everywhere (`compactMap`). Start MRU observer at launch or first expansion falls back to
alphabetical. Strict-concurrency: reading `NSWorkspace` in an actor may warn → hop to
`@MainActor`, return the `[AppEntry]` value.

**Stretch (v2, don't build now):** cycle the active app's windows via `kAXWindowsAttribute`.

**Effort ≈ 1.5–2 days.** **Depends on:** §1.1 (marker), §1.2 (async expand), §1.3 (IconSource).

---

## Feature D — System Toggles

**Goal.** A set of one-shot system actions, best as **inner-ring** symbol-only quick toggles.

**v1 set (reliably doable on 14/15) — everything else deferred:**

| Toggle | Mechanism | Permission |
|---|---|---|
| Dark/Light mode | `osascript` → System Events `set dark mode to not dark mode` | Automation (System Events) |
| Display sleep | `pmset displaysleepnow` | none |
| Screen saver | `osascript` → `start current screen saver` | Automation |
| Volume up/down/set, Mute toggle | `osascript 'set volume …'` | **none** (standard addition, no app scripted) |
| Lock screen | **CGEvent ⌃⌘Q** (not private `SACLockScreenImmediate`) | Accessibility |
| Empty Trash (confirm-gated) | `osascript` → `tell Finder to empty` | Automation |

**Deferred (no reliable/clean path):** **DND/Focus** — no public toggle; the
`ncprefs`/`controlcenter` + killall hack is broken post-Monterey; only a user-authored
Shortcut works (poor UX). **Brightness** — only private `DisplayServicesSetBrightness`
(App-Store-fatal) or jittery CGEvent F1/F2. **Logout/Restart/Shutdown** — destructive, low
value in a quick menu.

**API facts (confirmed).** No public dark-mode API (`NSApp.effectiveAppearance` is read-only,
app-scoped). No public DND/Focus *setter* (`INFocusStatusCenter` is read-only). No public
brightness setter.

**Mechanism choice.** Use `Process` → `/usr/bin/osascript`, **not** `NSAppleScript`
(`NSAppleScript` must run on — and blocks — the main thread; wrong from an actor;
out-of-process osascript keeps it off-main and TCC still attributes to MousePlus). CGEvent for
lock screen (Accessibility, posted from `@MainActor`).

**Surface.** `actor SystemToggleService.perform(_ toggle: SystemToggle, arg:) async throws`
with `runAppleScript`/`shell`/`@MainActor postKey` helpers. `ActionType.systemToggle`,
`actionData = SystemToggle.rawValue` (+ optional `:arg`).

**Risks.** TCC prompts mid-gesture (pre-prime in Settings — §1.4). `set volume` shows **no**
system volume HUD → show our own brief HUD echo. Empty Trash destructive → confirm setting,
default on. Cold `osascript` spawn ~50–150 ms (fine for one-shots).

**Effort ≈ 3.5–4 days** for a polished v1 (the permission pre-priming + Settings picker +
HUD echo is most of it). **Depends on:** §1.1, §1.4 (for lock screen).

---

## Feature E — Screenshot Tools

**Goal.** Region/window/full capture to clipboard or file via the system `screencapture` tool.

**The TCC win — ship interactive modes only for v1.** Interactive `screencapture -i`/`-U`
(user-driven selection UI) do **NOT** trigger a Screen-Recording TCC prompt attributed to
MousePlus — the user's drag *is* the consent. **Silent** full-screen capture (`screencapture
<path>`, `-R`, `-m`, video `-v`/`-V`) **does** require Screen Recording TCC and must be gated
behind explicit UX. So v1 = interactive only → zero prompts, zero entitlement.

**Modes → argv** (exec `/usr/sbin/screencapture` directly):

| Mode | argv |
|---|---|
| region → clipboard | `-i -c` |
| region → file | `-i <path>` |
| window → clipboard | `-i -w -c` |
| window → file | `-i -w -o <path>` |
| full UI (⌘⇧5 style) | `-U` |
| timed full → file | `-T 5 -x <path>` |

**Ring placement.** Middle wedge "Screenshot" (`camera.viewfinder`) → outer arc of modes
(Region `crop`, Window `macwindow`, Full `rectangle.dashed`, Timed `timer`).

**Critical ordering.** Dismiss the ring **before** running `screencapture -i` (else the panel
is in the shot / steals the selection overlay's focus). Use §1.5: `requestClose()` →
`await Task.yield()` → capture.

**Surface.** `enum ShotMode { …; var isInteractive; func argv(filePath:) -> [String] }`;
`actor ScreenshotService.capture(_ mode:) async throws` + `defaultDesktopPath()` (app uses
`Date()`/`DateFormatter` → `~/Desktop/Screenshot <stamp>.png`). `ActionType.screenshot`,
`actionData = ShotMode.rawValue`.

**Risks.** Esc-cancel = exit 0, no file → treat "no file" as clean cancel, not error.
`Process.arguments` is argv (no shell) → spaces in path are safe. Sequoia monthly re-prompt
affects only the silent/SCK path. **Verify on real 14.x/15.x** (build host is 26.5) that
interactive modes produce no MousePlus-attributed prompt, and that `-v`/`-V` behave as the man
page states.

**Effort ≈ 0.5–1 day** (interactive-only). Silent + ScreenCaptureKit backend + recording:
+1–2 days, deferred (and the SCK backend is the App-Store migration path). **Depends on:**
§1.1, §1.5. Lowest effort of the five.

---

## Recommended build order

1. **§1 Shared foundation** (~1–1.5 d) — unblocks everything.
2. **Feature B — Window snapping** (~2 d). Most radial-native, self-contained (no async/icons),
   no cross-app menu complexity. Immediate "wow", proves the AX + permission plumbing.
3. **Feature E — Screenshots** (~0.5–1 d). Cheapest, no TCC for interactive, exercises the
   dismiss-before-action seam.
4. **Feature A — Menu mirror** (~1.5–2 d). The differentiator; reuses B's AX permission;
   portable from menuanywhere.
5. **Feature C — App switcher** (~1.5–2 d). Builds the IconSource + async-expand machinery.
6. **Feature D — System toggles** (~3.5–4 d). Most permission/UX surface; do last.

Total ≈ 10–13 dev-days for all five at v1 depth.

## Decisions to log in `decisions.md`
- Drop `ActionType.clipboard` — defer to the user's ClipSmart/Aloft app; bridge via app-switch.
- Menu mirror = radial top-level + native NSMenu handoff (B1); `AccessibilityService` is
  `@MainActor`, not an actor.
- Window snap = own middle wedge → outer arc of 8 directions; `actor WindowService`;
  size→pos→size + `AXEnhancedUserInterface` toggle; flip about primary `screens[0].frame.maxY`.
- App switcher = self-tracked MRU (no public z-order API); `IconSource` enum, NSImage never in
  the Codable model.
- System toggles = dedicated `ActionType.systemToggle` with a curated enum (no arbitrary
  shell); `Process`→`osascript`, not `NSAppleScript`; v1 set excludes DND & brightness.
- Screenshots = interactive `screencapture` modes only for v1 (no TCC); `ScreenCaptureKit`
  reserved for a future silent/sandboxed backend.
- **Product:** Features A/B/D are sandbox-incompatible → reinforces direct-distribution; keep
  each behind its service so a sandboxed target can compile them out.
