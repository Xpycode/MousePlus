# Menu Items Editor Plan — Customize the Inner + Middle Rings

Status: **planned 2026-05-31-b.** Research-backed plan (4 fan-out agents: codebase scout,
SwiftUI-macOS patterns, the two hard pickers, competitive-UX) for a Settings feature that lets
users customize the radial menu's **inner** and **middle** rings and each middle wedge's
**sub-items** (the outer arc). Companion to `IMPLEMENTATION_PLAN.md` (ring rendering) and
`HUD_ACTIONS_PLAN.md` (what a wedge does).

Chosen interaction model (user-decided 2026-05-31-b): **a dedicated, resizable editor window,
WYSIWYG-lite** — a live ring preview you *click to select a slot*, with a detail form below.
(Not a drag-on-canvas; no shipping radial app does that. Not in-tab; the 460×460 Settings pane is
too small for the preview + form + pickers.)

---

## 0. Goal & current reality

**Goal.** Make the inner + middle rings user-customizable in-app, with the outer ring continuing
to react to the middle ring (as it already does). Replace the Settings **"Menu Items" tab stub**
(`MenuSettingsView` = `Text("Menu item customization coming soon")`,
`Views/SettingsView.swift:143`).

**What already works (no change needed):**
- The data model is layout-agnostic: `Configuration { inner: [RingMenuItem], middle: [RingMenuItem], … }`;
  `RingMenuItem { id: UUID, label, icon: String /*SF Symbol*/, actionType, actionData: String, subItems: [RingMenuItem]?, keyboardShortcut }`.
- **Outer-reacts-to-middle** is intrinsic: `RingViewModel.expand()` sets
  `outerItems = middleItems[wedge].subItems`. Inner items are **direct-only** (never expand).
- Persistence: `actor ConfigurationService.load()/save()` → `~/Library/Application Support/MousePlus/config.json`.
- Live-apply seam exists for appearance/triggers (`AppDelegate.applyAppearance`/`applyTriggers`);
  we add a sibling `applyMenuItems`.

**The gap is purely UI.** Today the only way to edit either ring is hand-editing `config.json`
(as done this session to inject the Snap wedge). This editor removes that need.

**Min target macOS 14** (`Shared.xcconfig` `MACOSX_DEPLOYMENT_TARGET = 14.0`); `@Observable`/
`@Bindable` available; no strict-concurrency flag set. Build SDK is macOS 26.

---

## 1. Architecture & new files

```
Views/MenuEditor/
  MenuEditorView.swift         # the editor: band switch + ring preview + slot form + toolbar
  RingPreviewSelector.swift    # reuse RingMenuView (hit-testing off) + click-to-select overlay + ghosts
  SlotEditorForm.swift         # detail form for the selected slot (symbol/label/action/sub-items)
  ActionDataEditor.swift       # action-type-aware data control (app picker / command / snap zone / …)
  SymbolField.swift            # SF-Symbol text field + live validation + curated popover grid
  AppPickerSheet.swift         # installed/running app list (+ "Other…" NSOpenPanel) → bundle ID
ViewModels/
  MenuEditorModel.swift        # @MainActor @Observable working state (copies of inner/middle), edits, invariants
Controllers/
  MenuEditorWindowController.swift   # dedicated resizable window (mirrors InputRecorderWindowController)
Resources/
  CuratedSymbols.swift         # ~60–90 hand-picked SF Symbol names grouped by category (for the grid)
```

Edits to existing files:
- `Views/SettingsView.swift` — replace `MenuSettingsView` body with a **launcher** (a short blurb,
  a small static ring thumbnail, an **"Open Menu Editor…"** button, and "Reset to Defaults").
- `MousePlusApp.swift` (`AppDelegate`) — add `applyMenuItems` hook + a `showMenuEditor()` entry
  (menu-bar item optional); hold the `MenuEditorWindowController`.
- `Controllers/MenuBarController.swift` — optional "Customize Menu…" item.

---

## 2. Editor model — the safe-binding core (`MenuEditorModel`)

`@MainActor @Observable final class MenuEditorModel`. Holds **working copies** of the two rings
(deep copies of `config.inner`/`config.middle`); editing mutates these, an autosave debounce
persists + live-applies. **`RingMenuItem` stays a `Codable` struct** — we do NOT convert it to a
class (too invasive across the model/config/action pipeline).

```swift
enum EditorBand { case inner, middle }
struct SlotSelection: Equatable { var band: EditorBand; var itemID: UUID? ; var subItemID: UUID? }

@MainActor @Observable final class MenuEditorModel {
    var inner: [RingMenuItem]
    var middle: [RingMenuItem]
    var selection: SlotSelection?
    var activeBand: EditorBand = .middle

    var spokeCount: Int { RadialGeometry.spokeCount(innerCount: inner.count, middleCount: middle.count) }
    var spokesUsed: Int { max(inner.count, middle.count) }       // for "N of 8 used"
    var atSpokeCap: Bool { spokesUsed >= 8 }
    // add / remove / moveCW / moveCCW / collapseGaps / load(from:) / merged(into:) …
}
```

**Identity, never index — this directly prevents the bug class behind the 2026-05-31 outer-band
"Index out of range" crash.** Two rules:
1. The detail form binds to the selected item via an **id-keyed safe-subscript `Binding`**, not
   `array[index]`:
   ```swift
   func binding(for id: UUID, in keyPath: ReferenceWritableKeyPath<MenuEditorModel,[RingMenuItem]>) -> Binding<RingMenuItem>? {
       guard self[keyPath: keyPath].firstIndex(where: { $0.id == id }) != nil else { return nil } // gone → nil, no crash
       return Binding(
           get: { self[keyPath: keyPath].first { $0.id == id } ?? RingMenuItem(label:"",icon:"",actionType:.custom) },
           set: { nv in if let i = self[keyPath: keyPath].firstIndex(where: { $0.id == id }) { self[keyPath: keyPath][i] = nv } }
       )
   }
   ```
2. Lists use `ForEach($inner)` / `ForEach($middle)` element bindings (SwiftUI keys them by
   `Identifiable` identity, surviving reorder/delete) with `.onMove`/`.onDelete`.

**Invariants enforced in the model (and reflected in the UI):**
- **Inner ring is symbol-only + direct-only:** inner items never carry `subItems` and never render
  a label in the ring (the editor suppresses the label field for inner slots).
- **Depth cap 3:** only **middle** items may have `subItems` (= the outer arc); outer/sub-items are
  direct-only — the editor offers no "sub-sub-items."
- **8-spoke cap:** `N = min(8, max(inner.count, middle.count))`. Adding is disabled at 8 with an
  inline "Max 8 spokes" note (graceful, not an error after the fact).

---

## 3. Interaction model (WYSIWYG-lite, dedicated window)

```
┌─ Menu Editor (resizable, ~560×620 min) ─────────┐
│ ( Inner | Middle )        6 of 8 spokes used     │
│              live concentric ring preview         │
│        (click a wedge or a dashed ghost slot)     │
│  ──────────────────────────────────────────────  │
│  Selected: spoke 3 · Middle                       │
│   Icon   [ 􀎟 safari        ] [grid ▦]             │
│   Label  [ Safari              ]                  │
│   Action ( App Switch ▾ )                         │
│   App    [ Safari        ] [Choose…]              │
│   ▸ Sub-items (outer arc)   2   [＋]               │
│   [◀ move] [move ▶]   [Delete]                    │
│                              [Reset…]   [Done]    │
└───────────────────────────────────────────────────┘
```

- **`RingPreviewSelector`** = the existing `RingMenuView` rendered from a dedicated preview
  `RingViewModel` (safe to instantiate a 2nd VM — no singletons/side-effects in `init`), with
  `.allowsHitTesting(false)`, **overlaid** by transparent selection buttons. Button frames come
  from `RadialGeometry.centroid`/`wedgeAngles` — the same math the live ring uses — so "click the
  wedge you see" maps exactly. **Empty spokes draw as dashed ghost wedges** labeled to invite
  "click to add."
- **Band switch** = segmented `Picker` (Inner | Middle); selecting a spoke highlights *both*
  rings on that spoke to teach the shared-spoke alignment.
- **Sub-items** are edited **inline** (a disclosure section in the form), one level deep — no
  navigation stack (it fights a small window). Selecting a middle slot shows its sub-item arc in
  the preview, exactly as it appears at runtime.
- **Reorder** = `◀ move` / `move ▶` buttons on the selected slot for v1 (more discoverable/reliable
  than tiny drags); in-list `.onMove` drag is a nice-to-have.

---

## 4. Action-type-aware editing (`ActionDataEditor`)

`actionType` is a `Picker` over `ActionType.allCases`; the data control swaps on it:

| ActionType | Editor control | Notes |
|---|---|---|
| `appSwitch` | **App picker** → stores `actionData = bundleID` | see §5B |
| `custom` | `TextField` (multiline, `axis:.vertical`) → `actionData = command` | warn/disable-save on empty/whitespace |
| `windowSnap` | `Picker` over `SnapZone.allCases` → `actionData = zone.rawValue` | trivial; type-safe |
| `menuBar` | shown, **"(coming soon)"**, disabled | action throws `.notImplemented` today |
| `systemToggle` | shown, **"(coming soon)"**, disabled | "" |
| `screenshot` | shown, **"(coming soon)"**, disabled | "" |

Showing the three unimplemented types as visible-but-disabled keeps the UI forward-ready and
honest (no dead wedges silently created).

**⚠️ App-icon nuance (call out in the UI).** `RingMenuItem.icon` is an SF-Symbol string and the
ring renders it via `Image(systemName:)`. **Real app icons are Feature C / `IconSource`, not yet
built** — so an `appSwitch` wedge displays its chosen SF Symbol, *not* the app's real icon. The
app picker therefore (a) sets `actionData` to the bundle ID and (b) **suggests** a sensible SF
Symbol but leaves `icon` user-editable. When `IconSource` lands, the picker can flip to real icons
with no model change (the model already only stores strings).

---

## 5. The two hard pickers (research-verified)

### 5A. SF Symbol picker (`SymbolField`)
- **No first-party picker or runtime enumeration exists** (verified — the "`SymbolsPicker` API"
  is a *third-party* package, not Apple). So: a `TextField` + **live validity check** via the
  failable `NSImage(systemSymbolName:accessibilityDescription:) != nil` (macOS 11+) — `Image(systemName:)`
  is non-failable and renders blank for bad names, so it can't be the validator, only the preview.
- Plus a **curated popover grid** of ~60–90 hand-picked symbol names grouped by category
  (`Resources/CuratedSymbols.swift`) for discoverability; typed names still validate freely.
- Red-tint + block-save on an invalid non-empty name (prevents shipping a blank wedge).
- *Upgrade path (nice-to-have):* swap in `xnth97/SymbolPicker` (MIT, macOS 13+) for the full
  searchable catalog — cheap, no model change.

### 5B. Installed-app picker (`AppPickerSheet`)
- Non-sandboxed → **unrestricted** read of `/Applications`, `/System/Applications`,
  `~/Applications` (no bookmarks/entitlements). Build a searchable `List` of installed apps:
  scan those dirs (filter `URLResourceValues.isApplication`, macOS 11+) + merge
  `NSWorkspace.shared.runningApplications`; show `localizedName` + `NSWorkspace.shared.icon(forFile:)`.
- Store the **bundle identifier** (`Bundle(url:)?.bundleIdentifier`) — stable across moves/updates;
  resolve back to a URL/icon at display time via `NSWorkspace.urlForApplication(withBundleIdentifier:)`
  (NOT deprecated). **Avoid** deprecated `LSCopyApplicationURLsForBundleIdentifier`.
- **"Other…"** escape hatch = `NSOpenPanel` / `.fileImporter` with `allowedContentTypes:[.application]`
  (`UTType`, macOS 11+; replaces deprecated `allowedFileTypes`), `directoryURL = /Applications`.

---

## 6. Data flow — load / edit / autosave / live-apply

Mirror `RingAppearanceSettingsView` exactly (the proven pattern):
1. **On window open:** `MenuEditorModel.load(from: try await configService.load())`.
2. **Edit** mutates the working `inner`/`middle`; the live preview re-renders automatically
   (`@Observable`).
3. **Debounced autosave** (≈400 ms, cancel-on-change): load full config, swap in the edited
   `inner`/`middle`, `configService.save(config)`, then on `@MainActor` call
   `AppDelegate.applyMenuItems?(config)`.
4. **`AppDelegate.applyMenuItems`** (new, sibling of `applyAppearance`): updates
   `self.configuration` + pushes into the running `ringViewModel.innerItems/middleItems` and
   `reset()`s it, so the next ring-open reflects edits with no restart.
5. **Reset to Defaults:** load `RingMenuItem.sampleInnerItems`/`sampleItems` into the working
   copy (confirm-gated); supersedes the manual Snap-wedge injection from 2026-05-31-b.

Autosave (not an explicit Save) matches the appearance tab and avoids "unsaved changes" anxiety;
"Done" just closes the window.

---

## 7. Wave-based build plan (build-gated, `/execute`-ready)

Estimate ≈ **3–4 dev-days**. Each wave ends green under
`xcodebuild -workspace 01_Project/MousePlus.xcworkspace -scheme MousePlus -configuration Debug build`.

**Wave 1 — Foundation & model (no UI risk).**
- **T1** `AppDelegate.applyMenuItems` hook + wiring in `loadConfiguration()` (mirror `applyAppearance`).
- **T2** `MenuEditorModel` — working copies, `SlotSelection`, id-keyed safe bindings, add/remove/
  moveCW/moveCCW/collapseGaps, spoke-count/cap echoes, `load(from:)` / `merged(into:)`, invariant
  enforcement (inner: no subItems/no label; sub-items only on middle).

**Wave 2 — Pickers (independent components; parallelizable).**
- **T3** `SymbolField` + `Resources/CuratedSymbols.swift` (validation + grid popover).
- **T4** `AppPickerSheet` (installed+running scan, search, "Other…" panel) → `(bundleID, name, suggestedSymbol)`.
- **T5** `ActionDataEditor` (type-aware control; unimplemented types shown disabled "coming soon").

**Wave 3 — Editor shell (depends W1, W2).**
- **T6** `RingPreviewSelector` (reuse `RingMenuView`, hit-testing off; selection overlay via
  `RadialGeometry`; dashed ghost wedges for empty spokes; sub-item arc for the selected middle slot).
- **T7** `SlotEditorForm` (symbol, label [hidden for inner], `ActionDataEditor`, inline sub-items
  section [middle only], move ◀/▶, delete).
- **T8** `MenuEditorView` assembly (band segmented Picker, "N of 8 used", preview + form, Reset/Done;
  binds `MenuEditorModel`; debounced autosave + `applyMenuItems`).

**Wave 4 — Window, persistence, launcher (depends W3).**
- **T9** `MenuEditorWindowController` (resizable, min ~560×620; mirror `InputRecorderWindowController`;
  `NSApp.activate`); replace `MenuSettingsView` stub with launcher (blurb + thumbnail + "Open Menu
  Editor…" + "Reset to Defaults"); optional menu-bar item.
- **T10** load-on-open + debounced save + live-apply + Reset-to-Defaults; persistence across relaunch.

**Wave 5 — Edge cases & live verification.**
- **T11** UI invariants: 8-cap disables Add + inline note; SF-symbol validation blocks blanks;
  empty/ghost-slot add flow; sub-items only on middle; app-icon nuance note for `appSwitch`.
- **T12** **user-driven live verification** (no synthetic input — see memory `no-synthetic-input`):
  edit inner/middle, add an app via the picker, set a `windowSnap` zone, reorder, add/remove
  sub-items, Reset; confirm the live ring (open via the user's `⌃⌥⌘M`) reflects edits and they
  persist across quit+relaunch.

---

## 8. Risks & mitigations
- **Index-vs-identity binding (the prior crash class).** → id-keyed safe-subscript bindings +
  `ForEach($array)`; select by id, never cache an index. (§2)
- **Small-window navigation creep.** → no `NavigationStack`/split-view; segmented band switch +
  inline one-level sub-items; the ring preview is the navigator. (research-backed)
- **SF-symbol validity / blank wedges.** → `NSImage(systemSymbolName:)` validation gates save. (§5A)
- **`appSwitch` shows an SF Symbol, not the app icon** (until `IconSource`/Feature C). → explicit
  UI note; model unchanged so the future flip is free. (§4)
- **Live-apply while a ring is on-screen** is unlikely (editor window holds focus); `applyMenuItems`
  ends with `reset()` so no stale expansion. Low risk.
- **Spoke gaps after deletes.** → "collapse gaps" affordance; ghost wedges make gaps legible
  rather than mysterious.

## 9. Decisions to log in `decisions.md` (when built)
- Menu editor = **dedicated resizable window, click-to-select live ring preview + detail form**
  (not in-tab, not drag-canvas) — fits the content, matches complex-Mac-editor norms, reuses the
  window-controller pattern. (User-decided 2026-05-31-b.)
- `RingMenuItem` **stays a struct**; editor uses id-keyed safe bindings (no `@Observable`-class
  conversion) — minimizes blast radius and prevents the index-binding crash class.
- SF-Symbol picker = **zero-dependency** curated grid + `NSImage` validation for v1
  (`xnth97/SymbolPicker` as a later upgrade).
- App picker = **bundle-ID stored**, installed+running scan + `NSOpenPanel(.application)` fallback;
  non-sandboxed so no bookmarks (would need them only for a future sandboxed/App-Store target).
- Autosave (debounced) + `applyMenuItems` live-apply, mirroring the appearance tab.

## References
- Codebase seams: `Views/SettingsView.swift` (RingAppearance pattern + `MenuSettingsView` stub),
  `MousePlusApp.swift` (`applyAppearance`/`applyTriggers` hooks), `Services/ConfigurationService.swift`,
  `ViewModels/RingViewModel.swift`, `Views/RingMenuView.swift`, `Utilities/RadialGeometry.swift`,
  `Controllers/InputRecorderWindowController.swift` (window pattern), `Models/{RingMenuItem,Configuration,ActionType,SnapZone}.swift`.
- SwiftUI macOS: `List`+`ForEach($)`+`.onMove` (no `EditButton` on macOS); bind by identity;
  `@Observable`/`@Bindable` (macOS 14+).
- Pickers: `NSImage(systemSymbolName:)` validation; `UTType.application`; `NSWorkspace`
  (`runningApplications`, `icon(forFile:)`, `urlForApplication(withBundleIdentifier:)`).
