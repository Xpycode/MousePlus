# App-Aware Command Rings + Menu-Bar Palette — Implementation Plan

**Status:** Planned (2026-05-30). Parked behind the HID/trigger backend track per `PROJECT_STATE.md`, but **Phase 0 is independently valuable** (it implements the long-stubbed `menuBar` action). Ring-UI track; does not depend on the HID++ decision (#17).

**Relationship to `docs/HUD_ACTIONS_PLAN.md` (READ THIS FIRST).** That doc already specs the AX menu-bar engine as its **Feature A (App Menu-Bar Mirror)** and a **shared foundation** (§1.1 `ActionType` extension, §1.2 async `expand()` with a `dynamicSource` enum, §1.3 `IconSource`, §1.4 AX-permission plumbing, §1.6 sandbox reality). **This doc does NOT re-spec those — it builds on them** and adds the three things the user asked for in the 2026-05-30 design conversation that the HUD plan explicitly calls net-new / deferred:
1. **Curated per-app shortcut profiles** (top-N commands pinned to RING 3 wedges) — new.
2. **Center-hub command palette / search** — HUD plan Feature A explicitly notes the search palette is "NOT in menuanywhere's current source — net-new" and defers it. This doc owns it.
3. **Pagination** of RING 3, **Liquid Glass**, and **pin-from-search self-curation**.

Two designs for "the app's menus" coexist: HUD plan Feature A = *browse all menus via native `NSMenu` handoff* (radial top-level index → real menu at cursor); this doc = *curated few in the ring + searchable rest in the palette, invoked via direct AX press*. Both share one `AccessibilityService`. Align naming with the HUD plan (below) — do **not** introduce parallel types.

**Research basis:** 5 parallel research agents (2026-05-30) — codebase map (render + action backend), AX menu-bar API recipe, SwiftUI Liquid Glass APIs, non-activating-panel text-input pattern. Sources cited inline per section.

---

## 1. Concept

Make the ring **aware of the frontmost app** and surface that app's own commands — both as curated muscle-memory wedges and as a searchable palette. This is the same underlying capability as **Paletro** / **menuanywhere** (an Accessibility walk of the frontmost app's menu bar), rendered as a radial menu instead of a list.

**Design principle that drove every decision:** a radial menu wins at *spatial muscle memory* (~8–16 fixed-direction commands), and loses at *"find any of 200 commands"* (that's search's job). So the ring holds the curated few; the center hub opens search for the long tail.

### Ring model (agreed with user)

```
      ┌─ CENTER HUB → opens SEARCH palette (separate panel; all current-app commands)
ring ─┤
      ├─ RING 1 (inner)  → stable global quick-actions (copy/paste/…). Same in every app.
      ├─ RING 2 (middle) → SOURCE SELECTORS. Each wedge decides what RING 3 becomes.
      │                     sources: static | appMenus | appShortcuts
      └─ RING 3 (outer)  → CHAMELEON. Hidden until a RING 2 wedge summons it.
                            Content depends on the chosen RING 2 source.
                            May paginate via a "More →" wedge (stable page→angle).
```

- **RING 1 / RING 2 stay stable** across apps → muscle memory preserved. Only RING 3 is app-aware.
- **Pagination keeps muscle memory** *only if* each command maps to a stable `(page, angle)` — page 1 / up-left is always the same command. Most-used on page 1; overflow on later pages; deep overflow → use search instead.
- **Center hub ≠ a RING 2 source.** Search is reached only via the center; it is not duplicated as a wedge.

This maps almost 1:1 onto the existing concentric-wedge engine — RING 3 is already `outerItems`, already empty until `expand()`. The core change is letting a RING 2 wedge declare a **dynamic source** instead of only static `subItems`.

---

## 2. Current-state ground truth (from codebase map)

Paths under `01_Project/MousePlus/`. Verified 2026-05-30.

### What exists
- **Render:** `Views/RingMenuView.swift` ZStack of 3 bands (inner `:99–122`, middle `:126–149`, outer `:151–174`). Per-wedge draw in `Views/Components/WedgeView.swift` — fill at `:106–110`, glyph at `:115`. Ring backing is a single `.ultraThinMaterial` circle at `RingMenuView.swift:42–44`. **No container wraps the wedges.** Dead-zone center circle at `RingMenuView.swift:46–49`.
- **Geometry:** `Utilities/RadialGeometry.swift` — `hitTest` `:86–131`, `outerArcSpan` `:222–239`.
- **State:** `ViewModels/RingViewModel.swift` — `load(from:)` `:67–73`, `updateActive` `:94–105`, `commitActive()` `:113–133`, `expand(_:)` `:138–142` (`outerItems = middleItems[parentIndex].subItems ?? []` — **static**).
- **Window:** `Controllers/RingWindowController.swift` `createPanel()` `:93–117` — `.nonactivatingPanel`, `isOpaque=false`, `backgroundColor=.clear`, `level=.floating`, `becomesKeyOnlyIfNeeded=true`. `FirstMouseHostingView` `:11–13`.
- **Input:** `onContinuousHover` `RingMenuView.swift:73–78` → `updateActive`; `DragGesture` `:80–88` → commit; `onTapGesture` `:90–92`. Dismissal in `Services/DismissMonitor.swift` (local+global Esc, global click-outside).
- **Config:** `Services/ConfigurationService.swift` (actor) — `~/Library/Application Support/MousePlus/config.json`; `load()` `:13–21`, `save(_:)` `:23–35`. `Models/Configuration.swift` already splits `inner`/`middle` with a legacy `items` shim.
- **Actions:** `Services/ActionService.swift` `execute(_:)` `:6–22` — `.appSwitch`✅, `.custom`✅ (shell), `.clipboard`❌ stub, `.menuBar`❌ stub (`:15–16`).
- **Settings:** `Views/SettingsView.swift` TabView — General / Triggers / Ring Appearance / Menu Items(stub) `:4–29`. Debounced save pattern in `Views/TriggersSettingsView.swift:178–190`. Live-apply hooks `AppDelegate.applyAppearance`/`applyTriggers` (static closures, `MousePlusApp.swift:31,36`).

### What does NOT exist (confirmed — corrects earlier assumptions)
1. **No keyboard-shortcut execution anywhere.** No `CGEvent` key posting. `RingMenuItem.keyboardShortcut: String?` is stored (`RingMenuItem.swift:11`) but **never read for execution** — display-only/unused.
2. **`ActionType.menuBar` is a stub** — enum case + icon exist, execution is empty.
3. **No frontmost-app awareness.** No `NSWorkspace.frontmostApplication` read for context, no `didActivateApplicationNotification` listener. (`switchToApp` uses `runningApplications` only to *switch*.)
4. **No live-reload hook for items.** `RingViewModel.load(from:)` runs once at startup (`MousePlusApp.swift:172`); only `appearance`/`triggers` have live hooks.

---

## 3. Architecture additions

### 3.1 New services

**`AccessibilityService`** — the keystone, **shared with HUD plan Feature A**. AX menu-bar engine (also satisfies the existing `.menuBar` stub). **Threading: `@MainActor` coordinator per the HUD plan** (Feature A's native-`NSMenu` handoff is main-thread-affine), with bulk AX reads offloaded to a `userInitiated` background queue and results hopped back. The search palette path (this doc) only needs the read + direct-`AXPress` half, so it can consume the same engine without the NSMenu surface.
- `func commands(forPID pid: pid_t) async -> [MenuCommand]` — walk `AXMenuBar → AXMenuBarItem → AXMenu → AXMenuItem`, flatten leaves to `MenuCommand { title, path:[String], shortcut:String?, axElementRef, enabled }`.
- `func invoke(_ command: MenuCommand, in app: NSRunningApplication) async` — activate app if needed, then `AXUIElementPerformAction(element, kAXPressAction)`.
- Implementation notes (from AX research agent):
  - **Titles + shortcuts read cold/silently** for AppKit apps — no menu opening, no flicker. *Enabled/checkmark* state is lazy (re-read on show if needed).
  - **Batch** attribute reads with `AXUIElementCopyMultipleAttributeValues` (1 IPC/item vs ~8). Run **off main thread**; parallelize per top-level menu.
  - **Cache per bundleID** (structure + shortcuts rarely change); re-validate `enabled` on show.
  - **Modifier decode (critical):** `kAXMenuItemCmdModifiers` bit `0x08` = **noCommand** (inverted): `0x01`=⇧, `0x02`=⌥, `0x04`=⌃, `(mods & 0x08)==0` ⇒ ⌘. `0x18`=fn. Plain `⌘C` reports `0`. Fall back to `kAXMenuItemCmdVirtualKey` (table) then `kAXMenuItemCmdGlyph` for non-printable keys.
  - **Robustness:** `AXUIElementSetMessagingTimeout(axApp, 0.25)`; guard `kAXMenuBarAttribute` with `CFGetTypeID(...) == AXUIElementGetTypeID()`; Electron/Java apps expose incomplete menus → degrade gracefully.
  - **Invoke caveat:** prefer **direct leaf `kAXPressAction`** (works without visibly opening the menu). Element refs can go stale → optionally re-resolve by index-path. Avoid `kAXShowMenuAction` chains (multi-second stalls).
  - Sources: [menuanywhere](https://github.com/acsandmann/menuanywhere), [Menu-Bar-Search](https://github.com/BenziAhamed/Menu-Bar-Search), [AXMenuItemModifiers](https://developer.apple.com/documentation/applicationservices/axmenuitemmodifiers), [buckleyisms on the inverted ⌘ bit](https://buckleyisms.com/blog/making-sense-of-kaxmenuitemcmdmodifiersattribute/).

**`FrontmostAppService` (@MainActor, @Observable)** — track context.
- Publishes `frontmostBundleID: String?` via `NSWorkspace.shared.notificationCenter` `didActivateApplicationNotification`.
- Also exposes a snapshot taken **at ring-show time** (the app to target), since our panels are non-activating.

**`CommandSearchEngine`** — fuzzy filter (Phase 3). 20-line subsequence scorer (consecutive-run + word-start bonus) is plenty for ~200 items; optionally `ordo-one/FuzzyMatch` later for highlighting. (Source: [objc.io fuzzy search](https://www.objc.io/blog/2020/08/18/fuzzy-search/).)

### 3.2 Model changes

`Models/MenuCommand.swift` (new): `{ id, title, path:[String], shortcut:String?, enabled:Bool }` + a non-Codable transient `axElement`. Codable form stores `path` for re-resolution; AX element is re-acquired at invoke time.

`Models/RingMenuItem.swift` — **extend the HUD plan's `dynamicSource` enum (§1.2)** rather than adding a parallel type. HUD plan defines `.appMenuMirror` / `.runningApps` / `.none`; add one case:
```swift
enum DynamicSource: Codable, Hashable {
    case none            // existing static path: use subItems
    case appMenuMirror   // HUD plan Feature A — RING 3 = live AX menu walk
    case runningApps     // HUD plan Feature C — RING 3 = running apps
    case appShortcuts    // THIS doc — RING 3 = curated profile for frontmost app
}
```
Add a **pagination** marker for RING 3 overflow (a synthesized "More →" item kind that re-points the page rather than firing). The HUD plan's §1.2 `expand()` switch gains an `.appShortcuts` arm.

`Models/ActionType.swift` — the HUD plan already adds `.menuBar` (implemented, Feature A) + `windowSnap`/`systemToggle`/`screenshot`. Add `.menuCommand` (fire a *resolved leaf* menu command by AX press — what the search palette picks need, distinct from `.menuBar` which opens a whole menu) and optionally `.keyShortcut` (post a `CGEvent` chord, secondary path).

`Models/Configuration.swift` — add:
```swift
var appProfiles: [String: AppProfile]   // bundleID → curated item sets
struct AppProfile: Codable { var ring3Shortcuts: [RingMenuItem]; /* future: ring1/2 overrides */ }
```
Decode-tolerant (default `[:]`), matching the existing migration style.

### 3.3 Execution

- `ActionService.execute` gains `.menuCommand` → `accessibilityService.invoke(cmd, in: targetApp)` and (optional) `.keyShortcut` → CGEvent chord posted to `.cgSessionEventTap` (Maccy pattern; needs the Accessibility permission already required). For app commands **prefer `.menuCommand` (AX press)** — it works for commands that have no keyboard shortcut at all, which is the whole point.
- Target app = the snapshot from `FrontmostAppService` taken when the ring/palette opened (panels are non-activating, so the user's app usually stays frontmost; re-activate before dispatch as a safety net).

### 3.4 Live context reload

- Add `AppDelegate.applyItems`-style hook (mirrors `applyAppearance`) so edited profiles propagate without restart.
- On ring-show (`showRing()`, `MousePlusApp.swift:180`), resolve RING 1/2 from config and **stash the frontmost app**; RING 3 stays empty until a source wedge expands.

---

## 4. Phased implementation

Each phase is independently shippable and build-gated (`xcodebuild -workspace 01_Project/MousePlus.xcworkspace -scheme MousePlus -configuration Debug build`).

### Phase 0 — AX foundation (keystone; standalone value)
**This is HUD plan §1.1/§1.2/§1.4 + Feature A's `AccessibilityService`.** If the HUD track builds Feature A first, Phase 0 is already done — this doc just consumes it. If this track goes first, build the engine here and Feature A reuses it.

**Exit:** can read and fire any frontmost AppKit app's menu command via a hardcoded ring item. No UI/settings changes required.

#### Execute waves (run via `/execute`)

**Backpressure (every task):**
`xcodebuild -workspace 01_Project/MousePlus.xcworkspace -scheme MousePlus -configuration Debug build`
The verify wave additionally launches the build; the user presses their own trigger (**no synthetic input injection** — see memory `no-synthetic-input-injection`).

**Reuse, don't rebuild (ground truth, verified 2026-05-30):**
- **AX-permission plumbing already exists** — `Services/PermissionsService.swift` (`@MainActor @Observable`) does `AXIsProcessTrusted()` / `promptAccessibility()` / `openAccessibilitySettings()` / `startPolling()`. Phase 0 **consumes it**; HUD plan §1.4 is therefore already satisfied — do **not** add a parallel TCC flow.
- The execute call site is `RingViewModel.commitActive()` (`ViewModels/RingViewModel.swift:128–129` → `actionService.execute(item)`); `actionService` is owned at `:49`. The `.menuBar` stub is `Services/ActionService.swift:15–16`. The frontmost snapshot point is `MousePlusApp.swift:180–193` (`showRing()`); commit dispatch is `:208`.

##### Wave 1 — Models & context (parallel, no deps)

| # | Task | Target file | Done when |
|---|------|-------------|-----------|
| P0-T1 | `MenuCommand` model: `{ id, title, path:[String], shortcut:String?, enabled:Bool }` + a **transient non-Codable** `axElement: AXUIElement?` (re-resolved at invoke time). `Codable` persists `path` only. | `Models/MenuCommand.swift` (new) | Builds; encode→decode round-trips and drops `axElement` cleanly |
| P0-T2 | Add `ActionType.menuCommand` (fire a *resolved leaf* via AX press) + its `displayName`/`systemImage`. **Keep `.menuBar`.** To keep the exhaustive switch green this wave, add a temporary `break` arm for `.menuCommand` in `ActionService.execute` (filled in W3). Do **not** drop `.clipboard` here — that's the HUD plan's call. | `Models/ActionType.swift`, `Services/ActionService.swift` | Builds; `CaseIterable` includes `.menuCommand`; `ActionService` still compiles |
| P0-T3 | `FrontmostAppService` (`@MainActor @Observable`): publish `frontmostBundleID` via `NSWorkspace.shared.notificationCenter` `didActivateApplicationNotification`; expose `snapshotTarget() -> NSRunningApplication?` capturing the front app **at call time** (panels are non-activating). | `Services/FrontmostAppService.swift` (new) | Builds; logs front-app changes; `snapshotTarget()` returns the app frontmost at the moment of call |

##### Wave 2 — AX engine (depends on W1: `MenuCommand`)

| # | Task | Target file | Done when |
|---|------|-------------|-----------|
| P0-T4 | `AccessibilityService` (`@MainActor` coordinator; bulk reads on a `userInitiated` queue, results hopped back — §3.1). **(a) Enumerate+decode:** `commands(forPID:) async -> [MenuCommand]` walking `AXMenuBar → AXMenuBarItem → AXMenu → AXMenuItem`, flatten leaves; batch via `AXUIElementCopyMultipleAttributeValues`; **modifier decode** (`0x08`=noCommand inverted ⇒ ⌘; `0x01`⇧ `0x02`⌥ `0x04`⌃ `0x18`fn; fall back to `kAXMenuItemCmdVirtualKey`→`kAXMenuItemCmdGlyph`); `AXUIElementSetMessagingTimeout(_,0.25)`; type-guard `kAXMenuBarAttribute`; per-`bundleID` structure cache; degrade gracefully on Electron/Java. **(b) Invoke:** `invoke(_:in:) async` → activate app if needed, `AXUIElementPerformAction(_, kAXPressAction)` on the leaf; re-resolve by index-path if the ref is stale; avoid `kAXShowMenuAction`. | `Services/AccessibilityService.swift` (new) | Builds; a debug dump of `commands(forPID:)` for **Safari/Finder/Xcode** shows correct titles + shortcut strings with no visible menu flicker; `invoke` fires a leaf without opening the menu |

##### Wave 3 — Wiring (depends on W2). Contract for parallelism: `func execute(_ item: RingMenuItem, targetApp: NSRunningApplication?) async throws`

| # | Task | Target file | Done when |
|---|------|-------------|-----------|
| P0-T5 | `ActionService` gains an injected `AccessibilityService`; implement the `.menuCommand` arm → `accessibilityService.invoke(cmd, in: targetApp)` (resolve `cmd` from `item.actionData`/`path`). Widen the signature to `execute(_:targetApp:)`. Leave `.menuBar` routed to Feature A (HUD plan) — out of Phase 0 scope; keep its arm a documented no-op, not a silent stub. | `Services/ActionService.swift` | Builds; `.menuCommand` path is real (no `break`); switch exhaustive |
| P0-T6 | Capture + thread the target app: instantiate `FrontmostAppService` (+ `AccessibilityService`) at app scope; in `showRing()` (`MousePlusApp.swift:180`) stash `frontmostAppService.snapshotTarget()` **before** our panel takes focus; pass it through `RingViewModel.commitActive()` into `actionService.execute(item, targetApp:)` (`:128–129`). Gate `.menuCommand` commits on `PermissionsService.isGranted` (prompt if not). | `MousePlusApp.swift`, `ViewModels/RingViewModel.swift` | Builds; the bundleID stashed at show-time matches the app that was frontmost when the trigger fired |

##### Wave 4 — Verification

| # | Task | Target file | Done when |
|---|------|-------------|-----------|
| P0-T7 | Seed a **hardcoded** `.menuCommand` ring item with `path = ["Edit","Paste"]` (e.g. in `RingMenuItem.sampleItems`). Launch; with TextEdit frontmost and text on the clipboard, **the user presses their trigger** (Fn+F5 / mouse-button→F5) and commits that wedge. Confirm Paste fires in the front app via AX press (no keystroke synthesis). Attach the W2 decode dump for Safari/Finder/Xcode to the session log. | `Models/RingMenuItem.swift` (sample only) + manual | Paste executes in the frontmost app; decode dump correct; AX prompt appears via `PermissionsService` if not yet trusted |

**Net Phase 0 deliverables:** `Models/MenuCommand.swift`, `Services/FrontmostAppService.swift`, `Services/AccessibilityService.swift` (new); `Models/ActionType.swift`, `Services/ActionService.swift`, `ViewModels/RingViewModel.swift`, `MousePlusApp.swift` (edited). `PermissionsService` reused unchanged. No settings/UI surface — that's Phase 1+.

### Phase 1 — Dynamic RING 3
1. `RingMenuItem.WedgeSource` + `RingViewModel.expand()` interception (`:138–142`): for `.appMenus`/`.appShortcuts`, populate `outerItems` **async** (show a "Loading…" placeholder wedge; AX walk is tens–hundreds of ms).
2. Pagination: "More →" wedge re-points `outerItems` to the next page; stable `(page, angle)` mapping; cap pages (deep overflow defers to search).
3. Two seed RING 2 wedges: **"App Menus →"** (`.appMenuMirror`) and **"App Shortcuts →"** (`.appShortcuts`).

**Exit:** expanding a RING 2 wedge fills RING 3 with the live front-app menu, paginated.

#### Execute waves (run via `/execute`)

**Depends on:** Phase 0 (consumes `AccessibilityService.commands(forPID:)` + `FrontmostAppService.snapshotTarget()`).
**Backpressure (every task):** same `xcodebuild … build`; the verify wave launches and the **user presses their trigger** (no synthetic input).

**Naming alignment (the plan drifts — pin it here):** use **§3.2's `DynamicSource`** enum (`.none` / `.appMenuMirror` / `.runningApps` [HUD Feature C] / `.appShortcuts`). Do **not** introduce a parallel `WedgeSource` or `.appMenus` case. The async-`expand()` stale-guard mirrors **HUD plan §1.2** — reuse its epoch-token pattern, don't invent a second one.

| Wave | # | Task | Target file | Done when |
|---|---|------|-------------|-----------|
| **W1 — model** | P1-T1 | Extend `RingMenuItem` with a `DynamicSource` field (§3.2 enum) + a synthesized **pagination marker** item-kind (a "More →" wedge that re-points the page rather than firing an action). Decode-tolerant default `.none`. | `Models/RingMenuItem.swift` (+ `Models/DynamicSource.swift` if HUD plan hasn't created it) | Builds; pre-existing config decodes with `.none`; pagination marker is representable |
| **W2 — async expand** (needs W1 + Phase 0) | P1-T2 | `RingViewModel.expand()` interception (`:138–142`): for `.appMenuMirror`/`.appShortcuts`, set a **"Loading…" placeholder** wedge immediately, then `await accessibilityService.commands(forPID:)` for the show-time snapshot's pid; populate `outerItems`. **Stale-guard** with an epoch token (HUD §1.2) so a late result for a collapsed/re-pointed expansion is dropped. | `ViewModels/RingViewModel.swift` | Builds; expanding a dynamic wedge shows "Loading…" then real items; collapsing mid-fetch discards the late result |
| **W3 — pagination ∥ seed wedges** (needs W2) | P1-T3 | Pagination: "More →" marker re-points `outerItems` to the next page; **stable `(page, angle)` mapping** (page 1 / a given direction is always the same command); cap page count (deep overflow → defer to Phase 3 search). | `ViewModels/RingViewModel.swift` | Builds; a >`M`-command menu paginates; the same command sits at the same `(page, angle)` across opens |
| | P1-T4 | Two seed RING 2 wedges in sample config: **"App Menus →"** (`.appMenuMirror`) and **"App Shortcuts →"** (`.appShortcuts`). | `Models/RingMenuItem.swift` (sample data) | Builds; both wedges render in RING 2 at rest |
| **W4 — verify** | P1-T5 | Launch; with a known app frontmost, **user presses their trigger**, expands "App Menus →"; confirm RING 3 fills with that app's live menu leaves and paginates via "More →". | manual | RING 3 shows live front-app commands; pagination keeps stable angles |

**Net Phase 1 deliverables:** `DynamicSource` on `RingMenuItem` (+ pagination marker); async `RingViewModel.expand()` with stale-guard; two seed RING 2 wedges. No new services — reuses Phase 0.

### Phase 2 — App profiles + curation
1. `Configuration.appProfiles` + resolution at show-time (frontmost bundleID → profile, fallback to default).
2. **Auto-scan seeding:** walk the menu bar, propose top-N commands; user pins the wanted ones.
3. **"App Commands" settings tab** (copy `TriggersSettingsView` load/debounce-save pattern): pick app → see auto-scan suggestions + manual add → reorder into RING 3 slots.

**Exit:** per-app curated RING 3; profile persists; survives relaunch.

#### Execute waves (run via `/execute`)

**Depends on:** Phase 1 (the `.appShortcuts` source + async `expand()`) and Phase 0 (`AccessibilityService` for auto-scan).
**Backpressure:** same `xcodebuild … build`.

**Reuse, don't rebuild:** persistence migration style = the existing `Configuration` inner/middle legacy shim (decode-tolerant default); settings UI = `Views/TriggersSettingsView.swift` load + debounced-save (`:178–190`) and the `Views/SettingsView.swift` `TabView`; live-apply = an `AppDelegate.applyItems` hook mirroring `applyAppearance`/`applyTriggers` (§3.4). Auto-scan reads the **Phase 0** `AccessibilityService` walk — no new enumeration.

| Wave | # | Task | Target file | Done when |
|---|---|------|-------------|-----------|
| **W1 — persistence** | P2-T1 | Add `appProfiles: [String: AppProfile]` to `Configuration` (+ `struct AppProfile { var ring3Shortcuts: [RingMenuItem] }`). Decode-tolerant (default `[:]`), matching the inner/middle shim. | `Models/Configuration.swift` | Builds; pre-existing config decodes with empty `appProfiles`; round-trips |
| **W2 — resolution ∥ auto-scan** (needs W1) | P2-T2 | Show-time resolution: at `showRing()`, map the frontmost bundleID → `AppProfile`, feed `profile.ring3Shortcuts` into the `.appShortcuts` source (fallback to a default profile). Add the `applyItems` live-reload hook so edits propagate without restart (§3.4). | `MousePlusApp.swift`, `ViewModels/RingViewModel.swift` | Builds; switching front app changes which profile the `.appShortcuts` wedge resolves to |
| | P2-T3 | Auto-scan ranker: a "propose top-N" helper over the `AccessibilityService` menu walk (enabled leaves, shortcut-bearing first; simple heuristic — no frecency yet). Returns `[MenuCommand]` suggestions for a bundleID. | `Services/AccessibilityService.swift` (extension) or `Services/CommandRanker.swift` (new) | Builds; returns a sensible top-N for Safari/Finder |
| **W3 — settings tab** (needs W1+W2) | P2-T4 | "App Commands" settings tab: pick app → auto-scan suggestions (P2-T3) + manual add → drag-reorder into RING 3 slots; persist via debounced save (Triggers pattern). Register the tab in `SettingsView`. | `Views/AppCommandsSettingsView.swift` (new), `Views/SettingsView.swift` | Builds; editing a profile saves and live-applies via `applyItems` |
| **W4 — verify** | P2-T5 | Curate an app's RING 3 in the new tab, quit + relaunch, confirm the profile persists and the `.appShortcuts` wedge shows the curated set for that app. | manual | Per-app RING 3 survives relaunch; correct profile resolves per front app |

**Net Phase 2 deliverables:** `Configuration.appProfiles` + `AppProfile`; show-time resolution + `applyItems` hook; auto-scan ranker; `AppCommandsSettingsView`. Reuses Phase 0 engine + Triggers settings pattern.

### Phase 3 — Center-hub command palette
1. `CommandPalettePanel: NSPanel` — **`.nonactivatingPanel` set at init** (never `setStyleMask` later — `kCGSPreventsActivationTag` gotcha), override `canBecomeKey`/`canBecomeMain` → `true`, `level=.floating`, `hidesOnDeactivate=false`. (Source: [philz.blog](https://philz.blog/nspanel-nonactivating-style-mask-flag/).)
2. SwiftUI search view: `TextField` + `@FocusState` focused `onAppear`; results list of fuzzy-ranked `MenuCommand`s.
3. Center dead-zone tap (`RingMenuView.swift:46–49` → new `viewModel.openSearch()`) opens the palette near the ring.
4. **Capture frontmost app before show; on selection `orderOut` → `NSApp.yieldActivation(to:)` + `app.activate()` → dispatch** (AX press / CGEvent). Dismiss via `cancelOperation` (Esc) + `resignKey` (click-outside) using `orderOut(nil)`. (Sources: [Multi.app](https://multi.app/blog/nailing-the-activation-behavior-of-a-spotlight-raycast-like-command-palette) — but **do not** copy its `becomeKey{NSApp.activate()}`; [Maccy CGEvent paste](https://github.com/p0deje/Maccy).)
5. **Pin-or-execute:** result row → ⏎ executes; ⌘⏎ (or a pin button) writes the command into the front app's `AppProfile.ring3Shortcuts`. This is what makes the ring **self-curating** — the differentiator over Paletro.

**Exit:** center opens search; pick fires in the right app; pin adds to that app's ring.

#### Execute waves (run via `/execute`)

**Depends on:** Phase 0 (`MenuCommand`, `AccessibilityService`, `ActionService.execute(_:targetApp:)`) and Phase 2 (`AppProfile` for the pin write). Phase 1 not strictly required.
**Backpressure:** same `xcodebuild … build`; verify launches with the user pressing their trigger.

**Reuse, don't rebuild:** dispatch goes through Phase 0's `ActionService.execute(_:targetApp:)`; the target app is the show-time `FrontmostAppService.snapshotTarget()`. **Critical gotcha:** the palette is a *key* panel (unlike the ring) — set `.nonactivatingPanel` **at init**, never via `setStyleMask` later (`kCGSPreventsActivationTag`); override `canBecomeKey`/`canBecomeMain → true`. Do **not** copy Multi.app's `becomeKey{NSApp.activate()}`.

| Wave | # | Task | Target file | Done when |
|---|---|------|-------------|-----------|
| **W1 — foundations** (parallel) | P3-T1 | `CommandSearchEngine`: ~20-line subsequence fuzzy scorer (consecutive-run + word-start bonus) over `[MenuCommand]`. | `Services/CommandSearchEngine.swift` (new) | Builds; ranks "epst" → "Paste"/"Edit ▸ Paste" above noise on a sample set |
| | P3-T2 | `CommandPalettePanel: NSPanel` — `.nonactivatingPanel` set **at init**, `canBecomeKey`/`canBecomeMain → true`, `level = .floating`, `hidesOnDeactivate = false`. | `Controllers/CommandPalettePanel.swift` (new) | Builds; panel shows without stealing activation; accepts key input |
| **W2 — view ∥ entry point** (needs W1) | P3-T3 | `CommandPaletteView`: `TextField` + `@FocusState` focused `onAppear` (fallback `makeFirstResponder` if focus races); results list = `CommandSearchEngine` over `accessibilityService.commands(forPID:)` of the captured front app. | `Views/CommandPaletteView.swift` (new) | Builds; typing filters live front-app commands |
| | P3-T4 | `RingViewModel.openSearch()` + center dead-zone tap (`RingMenuView.swift:46–49`) + an `AppDelegate` hook that presents `CommandPalettePanel` near the ring (mirrors `requestClose`). | `ViewModels/RingViewModel.swift`, `Views/RingMenuView.swift`, `MousePlusApp.swift` | Builds; tapping the ring center opens the palette |
| **W3 — selection handling** (needs W2 + Phase 2) | P3-T5 | On pick: `orderOut` → `NSApp.yieldActivation(to:)` + `app.activate()` → dispatch via `ActionService.execute(cmd, targetApp:)`. **⏎ executes; ⌘⏎ (or pin button) writes the command into the front app's `AppProfile.ring3Shortcuts`** (self-curation). Dismiss via `cancelOperation` (Esc) + `resignKey` (click-outside) → `orderOut(nil)`. | `Views/CommandPaletteView.swift`, `Controllers/CommandPalettePanel.swift` | Builds; ⏎ fires in the right app; ⌘⏎ adds to that app's profile |
| **W4 — verify** | P3-T6 | Launch; **user presses trigger**, taps center, searches, ⏎ a command → fires in the originally-frontmost app; ⌘⏎ a command → reopen ring, confirm it now sits in that app's RING 3. | manual | Search fires in the correct app; pinned command appears in the app's ring after relaunch |

**Net Phase 3 deliverables:** `CommandSearchEngine`, `CommandPalettePanel`, `CommandPaletteView` (new); `RingViewModel.openSearch()` + center-tap wiring; selection/pin handling. Reuses Phase 0 dispatch + Phase 2 `AppProfile`.

### Phase 4 — Liquid Glass + legibility
1. Wrap each band in a `GlassEffectContainer` (gated `#available(macOS 26.0,*)`; plain pass-through below). Replace the single backing circle (`RingMenuView.swift:42–44`) accordingly.
2. Per-wedge `adaptiveGlass(in: AnnularWedge(...))` ViewModifier: `glassEffect(.regular[.tint][.interactive], in: shape)` on 26+, `.background(.ultraThinMaterial, in: shape)` + stroke on 14/15. Inject at `WedgeView.swift:106–110`.
3. RING 3 expansion morph: `glassEffectID` + `@Namespace` with `withAnimation`; `.matchedGeometry` transition (the appearing wedges share the container spacing).
4. **Legibility (mandatory — this is the Tahoe backlash, and a floating-over-anything HUD is maximally exposed):** use `.regular` not `.clear`; `.foregroundStyle(.primary/.secondary)` (vibrant) not fixed grays; explicit `strokeBorder` for definition; test under **Reduce Transparency / Increase Contrast / Reduce Motion** (custom shapes don't get the system's automatic border treatment — drive it yourself). (Sources: [Apple HIG Materials](https://developer.apple.com/design/human-interface-guidelines/materials), [applying Liquid Glass to custom views](https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views).)

**Exit:** glass on Tahoe, material on Sonoma/Sequoia, legible over busy wallpaper.

#### Execute waves (run via `/execute`)

**Depends on:** nothing in Phases 1–3 — purely cosmetic, can land anytime after the concentric ring (already done). **Sequence it last** because it's the highest-risk-for-lowest-functional-payoff and needs hardware to verify.
**Backpressure:** same `xcodebuild … build` — **but** `glassEffect`/`GlassEffectContainer` only *compile* against the **macOS 26 SDK (Xcode 26)**. The `#available(macOS 26.0, *)` runtime guard does **not** make the symbols compile on an older SDK. **Pre-flight gate:** confirm the build toolchain has the 26 SDK before W1; if not, this whole phase is blocked on a toolchain upgrade — note it and stop.
**Verification reality:** `/preview` can't render this multi-file macOS view, and glass on **concave annular shapes** is undocumented (§6 — Apple's examples are capsules/circles). The W4 verify therefore **requires a real macOS 26 machine**; there is no automated substitute.

| Wave | # | Task | Target file | Done when |
|---|---|------|-------------|-----------|
| **W1 — modifier** | P4-T1 | `adaptiveGlass(in: some Shape)` ViewModifier: `glassEffect(.regular[.tint][.interactive], in: shape)` on `#available(macOS 26.0, *)`, else `.background(.ultraThinMaterial, in: shape)` + `strokeBorder`. Self-contained; both branches compile. | `Utilities/AdaptiveGlass.swift` (new) | Builds on the 26 SDK; the `else` branch builds and renders material on a 14/15 run |
| **W2 — apply** (parallel, needs W1) | P4-T2 | Inject `adaptiveGlass(in: AnnularWedge(...))` per wedge at `WedgeView.swift:106–110` (replacing the bare fill). | `Views/Components/WedgeView.swift` | Builds; wedges carry glass on 26, material on 14/15 |
| | P4-T3 | Wrap the bands in a `GlassEffectContainer` (gated; plain pass-through below 26); replace the single backing `.ultraThinMaterial` circle at `RingMenuView.swift:42–44`. | `Views/RingMenuView.swift` | Builds; container present on 26, no regression on 14/15 |
| **W3 — morph ∥ legibility** (needs W2) | P4-T4 | RING 3 expansion morph: `glassEffectID` + `@Namespace` with `withAnimation`; `.matchedGeometry`-style transition so appearing outer wedges share container spacing. | `Views/RingMenuView.swift` | Builds; on 26 the outer arc morphs in rather than hard-cutting |
| | P4-T5 | Legibility hardening in the modifier: `.regular` (never `.clear`); `.foregroundStyle(.primary/.secondary)` vibrant (not fixed grays); explicit `strokeBorder` for definition on custom shapes; honor **Reduce Transparency / Increase Contrast / Reduce Motion** (drive these manually — custom shapes get no automatic system border). | `Utilities/AdaptiveGlass.swift` | Builds; flipping each accessibility setting visibly changes the rendering |
| **W4 — verify (hardware-gated)** | P4-T6 | On a **real macOS 26 machine**: glass renders legibly over a busy wallpaper, the annular concave shape doesn't break border-blending, expansion morph is smooth. Then on **Sonoma/Sequoia**: material fallback + stroke is legible. Sweep the three accessibility settings on both. | manual (two OS versions) | Legible + correct on 26 *and* on 14/15; accessibility sweeps pass; concave-shape risk (§6) cleared or logged |

**Net Phase 4 deliverables:** `Utilities/AdaptiveGlass.swift` (new); glass containers + per-wedge glass in `RingMenuView`/`WedgeView`; expansion morph. **Hard gates:** macOS 26 SDK to compile, macOS 26 hardware to verify — without both, this phase cannot complete.

---

## 5. Decisions to log in `decisions.md`

- **Min deployment target stays macOS 14.** Liquid Glass is macOS 26-only (`glassEffect`/`GlassEffectContainer` are `@available(macOS 26.0,*)`); 14 and 15 both need the `#available` conditional + `.ultraThinMaterial` fallback, so 14-vs-15 doesn't change the glass story. Adoption research (2026-05-30): Tahoe ~50% overall and **higher in MousePlus's technical/recent-hardware segment** (TelemetryDeck skews indie-dev) but ~half of users remain on Sequoia/Sonoma → **conditional glass, not min-26**.
- **App commands fire via AX press (`.menuCommand`), not synthesized keystrokes**, because AX works for commands with *no* shortcut. CGEvent keystroke kept as a secondary `.keyShortcut` path.
- **Non-sandboxed** (already decided) is what makes cross-app AX menu reading viable; **App Store path must re-validate** that the AX entitlement reads arbitrary frontmost apps under sandbox before committing (flagged by AX research).
- **Center hub owns search; RING 2 owns sources** — no duplicate search wedge.

---

## 6. Risks / open questions

- **Sandbox + AX (MAS):** un-sandboxed reference apps; verify before any App Store build.
- **Non-AppKit apps** (Electron/Java) expose incomplete menus → show "no commands available" / shortcuts-only gracefully.
- **AX walk latency** (tens–hundreds ms; pathological apps seconds) → async + per-bundleID cache + placeholder wedge + `AXUIElementSetMessagingTimeout`.
- **Palette focus race:** `@FocusState` may fire before the panel is key → fallback `panel.makeFirstResponder(field)` after `makeKeyAndOrderFront`.
- **Glass on concave annular shapes:** border-blending aesthetic is undocumented (Apple examples use capsules/circles) → **verify on a real macOS 26 machine**; `/preview` can't render this multi-file macOS view.
- **Stale AX element refs** post menu rebuild → re-resolve by index-path on invoke.
- **Sequencing vs HID track:** Phase 0 is independently valuable; full feature parks behind the HID++ decision per `PROJECT_STATE.md`.

---

## 7. New / touched files (summary)

| Action | File |
|---|---|
| **New** | `Services/AccessibilityService.swift` (AX engine) |
| **New** | `Services/FrontmostAppService.swift` |
| **New** | `Models/MenuCommand.swift` |
| **New** | `Controllers/CommandPalettePanel.swift` + `Views/CommandPaletteView.swift` (Phase 3) |
| **New** | `Views/AppCommandsSettingsView.swift` (Phase 2) |
| **New** | `Utilities/AdaptiveGlass.swift` (ViewModifier, Phase 4) |
| Edit | `Models/RingMenuItem.swift` (extend `dynamicSource` with `.appShortcuts`, pagination marker) |
| Edit | `Models/ActionType.swift` (`.menuCommand`, `.keyShortcut`) |
| Edit | `Models/Configuration.swift` (`appProfiles`) |
| Edit | `Services/ActionService.swift` (new action cases) |
| Edit | `ViewModels/RingViewModel.swift` (`expand()` dynamic sources, `openSearch()`) |
| Edit | `Views/RingMenuView.swift` (center-tap, glass containers) |
| Edit | `Views/Components/WedgeView.swift` (adaptiveGlass) |
| Edit | `Views/SettingsView.swift` (App Commands tab) |
| Edit | `MousePlusApp.swift` (applyItems hook, frontmost snapshot on show) |
