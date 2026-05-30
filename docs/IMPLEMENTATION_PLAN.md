# IMPLEMENTATION_PLAN — Concentric Ring Menu UI

**Created:** 2026-05-30
**Status:** ✅ COMPLETE — T1–T12 done. All 5 wave build-gates green; full interactive flow verified by hand 2026-05-30.
**Funnel stage:** plan → build → interactive verify ✓ → done
**Executed:** 2026-05-30 via `/execute`. Each wave built clean under the backpressure command before proceeding. T12 verified live by the user: trigger (Fn+F5 / mouse-button→F5), concentric render (inner symbols + middle labels, correct orientation), expand (middle → outer arc), hold-to-select (middle-click hold-release), and dismissal (click-outside closes; Esc collapses expanded→root then closes). Two integration bugs surfaced during verification and were fixed (see §7).
**Workstream:** UI/interaction layer. **Independent of** the HID++ backend track (decision #17) — touches no trigger/HID code beyond one commit-path wire-up.

---

## 1. Goal (one sentence)

Replace the current circles-in-a-ring menu with a **concentric wedge ("pie") menu**: an inner symbol ring + a middle labeled ring sharing locked spokes, plus an on-demand outer ring that expands as a localized arc from a parent wedge, with focus-dimming of the inactive branches.

---

## 2. Design model (the spec we're building to)

### 2.1 Concentric bands (radii are defaults; live in `AppearanceConfig`)

```
        ┌─ r3 = 224  outer band edge ─┐
        │   ┌─ r2 = 150  middle edge ─┐│
        │   │   ┌─ r1 = 78 inner edge┐││
        │   │   │   ┌ r0 = 24 deadzone┐│││
   ─────┴───┴───┴───●───┴───┴───┴─────   (radius from center →)
        outer  middle inner  ·  dead
        band    band   band      zone
```

| Band | Radius range | Holds | Spoke count |
|------|--------------|-------|-------------|
| **Dead zone** | `0 → r0` (24) | nothing — cancel/back region | — |
| **Inner** | `r0 → r1` (24→78) | 6–8 **symbol-only** quick actions | `N` |
| **Middle** | `r1 → r2` (78→150) | labeled items; each **direct** or **expandable** | `N` (locked to inner) |
| **Outer** | `r2 → r3` (150→224) | sub-commands of one expanded middle item; **direct only** (max depth 3) | `M` (own count) |

- **Spoke lock:** `N = min(8, max(innerCount, middleCount))`. Both inner and middle render `N` angular wedges sharing the same divider lines. A band with fewer items than `N` renders the extra wedges as **dim empty placeholders** so alignment holds. *(Decision: pad rather than stretch — keeps the symmetry the user asked for. Log to `decisions.md` as a real choice.)*
- **Inner vs middle are independent action sets** (per user: "small one with symbols" + "bigger circle for expandable menus or direct commands") — not parent/child. They merely share spoke geometry.
- All band widths ≥ 44 pt radial reach (Apple HIG min target): inner 54, middle 72, outer 74. ✓

### 2.2 Hit-testing — single container, angle + radius (Blender model)

Selection follows the **cursor direction**, not precise wedge-polygon containment. One container view computes from a single pointer stream:

```
dx,dy = loc - center
dist  = hypot(dx,dy)
theta = atan2(dy,dx) normalized to [0, 2π)   // +y is down in SwiftUI → matches on-screen CW

dist ≤ r0                  → no selection (dead zone / cancel)
r0 < dist ≤ r1             → inner,  index = floor(theta / (2π/N))
r1 < dist ≤ r2             → middle, index = floor(theta / (2π/N))
r2 < dist ≤ r3 (expanded)  → outer,  index = map theta within parent arc span → [0,M)
```

`activeSelection = (band, index)?` drives both highlight and dimming. **Do not** rely on per-wedge `contentShape` hit-testing (causes boundary flicker/dead zones — see research pitfalls).

### 2.3 Expansion & dimming

- Clicking/committing an **expandable middle wedge `p`** → `expandedParentIndex = p`, populate `outerItems`, render outer band as a **localized arc** centered on wedge `p`'s mid-angle. Arc span ≈ parent wedge width when `M` is small; grows symmetrically (both directions) toward a fuller ring as `M` increases. Never a free-floating full circle.
- **Dim model (default):** everything drops to **0.30 opacity** except the **live branch** — middle wedge `p` + the outer arc items stay **1.0**. Inner ring dims fully (matches user's "first circle maybe dimmed too").
- **`keepSpokeLit` toggle** (config, default off): also keep inner wedge `p` at 1.0 for a continuous center→parent→arc "lit slice."
- **Dimmed wedges stay clickable (branch-switching):** committing a *different* expandable middle wedge while one is already expanded re-points `expandedParentIndex` and re-renders the outer arc — no explicit collapse needed. Committing a dimmed *direct* wedge fires its action and closes. So hit-testing in §2.2 stays fully live across inner+middle even while expanded; only the *opacity* changes, never the actionability.
- **Instant vs animated** (existing `AppearanceConfig.animationEnabled`): animated wraps state in `withAnimation(.spring(response:0.18,...))`; outer ring enters via `.transition(.scale(scale:0.1, anchor: <parent centroid UnitPoint>).combined(with:.opacity))`. Instant = plain assignment, no transition.

### 2.4 Interaction modes (reuse existing trigger pipeline — no changes there)

- **holdRelease:** `DragGesture(minimumDistance:0)` updates `activeSelection` on `.onChanged`; `.onEnded` commits the active wedge (or cancels in dead zone).
- **tapToggle:** `onContinuousHover` updates `activeSelection`; a click commits.
- Both already routed via `AppDelegate.hideRing(commitHovered:)` / `toggleRing()`; we only repoint the commit to `viewModel.commitActive()`.

---

## 3. Gap analysis (exists vs needed)

| Area | Exists today | Needed |
|------|--------------|--------|
| Item layout | Circles offset around a ring (`RingMenuView`) | Annular **wedges**, two concentric rings |
| Hit-testing | per-item `onTapGesture`/`onHover` | single-container **angle+radius** math |
| State model | flat `items` + `currentSubItems` (replace) | inner/middle sets + `expandedParentIndex` + `activeSelection(band,index)` |
| Config | flat `Configuration.items` | `inner` / `middle` split + migration shim |
| Dimming | hover recolors one item | branch-aware **opacity** model |
| Outer ring | submenu *replaces* items | concurrent **localized-arc** outer band w/ transition |
| Panel | `makeKeyAndOrderFront`, `fittingSize` | fixed square size, `acceptsFirstMouse`, `isFloatingPanel`, multi-display centering |
| Dismiss | flags exist, not implemented | Escape (keyCode 53) + click-outside monitors |

Reusable as-is: `RingMenuItem` (has `subItems`/`icon`/`actionType`), trigger services, `ActionService` contract, `MenuBarController`, permissions/onboarding.

---

## 4. Waves & tasks

**Backpressure (all tasks):**
`xcodebuild -workspace 01_Project/MousePlus.xcworkspace -scheme MousePlus -configuration Debug build`
Visual tasks additionally verify with `/preview <file>` and a launch.

### Wave 1 — Foundations (parallel, no deps)

| # | Task | Target file | Done when |
|---|------|-------------|-----------|
| T1 | `AnnularWedge` Shape (`Path.addArc` outer + reverse inner, `animatableData`); honor SwiftUI flipped-clockwise convention | `Views/Components/AnnularWedge.swift` (new) | Builds; `/preview` shows a clean donut slice at given angles/radii |
| T2 | `RadialGeometry` pure helpers: band edges, `N`, `hitTest(point,center)->(Band,Int)?`, `wedgeAngles(band,index)`, `centroid(band,index)->CGPoint`, `outerArcSpan(parent,M)` | `Utilities/RadialGeometry.swift` (new) | Builds; angle/band math returns expected indices for sample points |
| T3 | Config: add `inner`/`middle` item sets + decode migration (old `items` → `middle`); keep `items` CodingKey for back-compat | `Models/Configuration.swift` | Builds; decoding a pre-split JSON puts items in `middle`, no crash |

### Wave 2 — State & item view (depends on W1)

| # | Task | Target file | Done when |
|---|------|-------------|-----------|
| T4 | Rewrite `RingViewModel`: `innerItems`, `middleItems`, `outerItems`, `expandedParentIndex?`, `activeSelection?`; methods `updateActive(point,center)`, `commitActive()`, `expand(_)`, `collapse()`, `reset()` | `ViewModels/RingViewModel.swift` | Builds; unit-style check: `updateActive` sets correct `(band,index)` |
| T5 | `WedgeView` (replaces inline `RingItemView`): icon (+optional label) at centroid, opacity from a `dimmed: Bool`, symbol-only mode for inner | `Views/Components/WedgeView.swift` (new) | Builds; `/preview` shows symbol-only vs labeled variants |

### Wave 3 — The menu view (depends on W2)

| # | Task | Target file | Done when |
|---|------|-------------|-----------|
| T6 | Rewrite `RingMenuView`: concentric ZStack of inner+middle wedges; single-container `onContinuousHover` + `DragGesture(minimumDistance:0)`; dead zone; branch dim model; `contentShape(Rectangle())` on container | `Views/RingMenuView.swift` | Builds; `/preview` at rest shows two aligned rings; cursor angle highlights correct wedge |
| T7 | Outer-ring expansion: localized-arc layout around parent wedge + `.scale(anchor:).combined(.opacity)` transition; inactive branches dim to 0.30 | `Views/RingMenuView.swift` | Builds; `/preview` expanded state shows arc radiating from parent, rest dimmed |

### Wave 4 — Integration (depends on W3)

| # | Task | Target file | Done when |
|---|------|-------------|-----------|
| T8 | Panel fixes: fixed square size `2*r3 + pad` (not `fittingSize`); `acceptsFirstMouse` via `NSHostingView` subclass; `isFloatingPanel`, `hidesOnDeactivate`; screen-under-cursor centering + `visibleFrame` clamp (multi-display) | `Controllers/RingWindowController.swift` | Launch: ring centers on pointer on any display, first click registers |
| T9 | Repoint commit: `AppDelegate.hideRing(commitHovered:)` → `viewModel.commitActive()`; expandable middle wedge → `expand()` instead of replace | `MousePlusApp.swift`, `ViewModels/RingViewModel.swift` | Launch: hold-release fires active wedge; tap-toggle click selects; expand works |
| T10 | Dismiss: Escape (keyCode 53) + click-outside global monitors honoring `BehaviorConfig.dismissOnEscape`/`dismissOnClickOutside`; collapse outer ring before closing root | `Controllers/RingWindowController.swift` or new `Services/DismissMonitor.swift` | Launch: Esc and outside-click close; Esc on expanded ring collapses to root first |

### Wave 5 — Settings & verification

| # | Task | Target file | Done when |
|---|------|-------------|-----------|
| T11 | Settings: band-radius sliders, dim-opacity, `keepSpokeLit`, instant/animated; persist via `AppearanceConfig` | `Views/SettingsView.swift`, `Models/Configuration.swift` | Builds; changing a slider updates the live ring |
| T12 | Full-flow verification: open → hover inner & middle → expand a middle item → select an outer item → dismiss (Esc + outside). Capture `/preview` of rest + expanded states | — | All five steps work on a launched build; preview captures attached to session log |

---

## 5. Open decisions to confirm (non-blocking — defaults chosen)

1. **Unequal inner/middle counts** → *pad shorter ring with dim placeholders* (chosen). Alternative: forbid in config UI.
2. **Dimmed wedges still clickable?** → **RESOLVED: stay clickable.** Committing another expandable wedge switches branches in place; a direct wedge fires + closes. (No collapse step required.)
3. **Inner ↔ middle relationship?** → **RESOLVED: independent action sets** sharing only spoke geometry — inner does not repopulate middle.
4. **Confirm-on-release radius** (Blender "Pie Confirm") → **off** by default; optional later polish.

---

## 6. Risks

- **Flipped-clockwise arc bug** — verify `AnnularWedge` visually via `/preview` before wiring (research flagged this as the #1 easy-to-get-wrong thing).
- **NSPanel first-click swallowed** — addressed by `acceptsFirstMouse` (T8); test explicitly.
- **Hover flicker** — avoided by single-container angle math (not per-wedge hover).

---

## 7. Execution log (2026-05-30, `/execute`)

| Wave | Tasks | Result |
|------|-------|--------|
| 1 | T1 `AnnularWedge`, T2 `RadialGeometry`, T3 config split | ✅ BUILD SUCCEEDED |
| 2 | T4 `RingViewModel` rewrite (+legacy shims), T5 `WedgeView` | ✅ BUILD SUCCEEDED |
| 3 | T6+T7 `RingMenuView` (concentric + outer arc) | ✅ BUILD SUCCEEDED |
| 4 | T8 panel fixes, T9 commit repoint, T10 `DismissMonitor` | ✅ BUILD SUCCEEDED |
| 5 | T11 Settings + `AppearanceConfig` wiring | ✅ BUILD SUCCEEDED |

**New files:** `Views/Components/AnnularWedge.swift`, `Views/Components/WedgeView.swift`, `Utilities/RadialGeometry.swift`, `Services/DismissMonitor.swift`.
**Rewritten:** `RingViewModel.swift`, `RingMenuView.swift` (old `RingItemView` deleted), `RingWindowController.swift`.
**Extended:** `Configuration.swift` (inner/middle split + AppearanceConfig band radii/dim/keepSpokeLit), `MousePlusApp.swift` (commit repoint, dismiss + live-apply hooks), `SettingsView.swift` (Ring Appearance tab).

**Decisions during exec (vs §5):**
- Legacy `RingViewModel` API kept as shims through Waves 2–3 so the project compiled at every gate; removed in T9 (grep-confirmed zero references).
- `Band` gained `Equatable`; `AppearanceConfig` gained `Equatable` + a defaulting custom `init(from:)` so pre-T11 config JSON still decodes.
- Hold-release commit landing on a *different* expandable wedge **closes** (release = commit) rather than re-pointing; in-view mouse/drag branch-switching still re-points in place. (Refinement candidate if it feels wrong in use.)
- §2.1 spoke-lock padding decision logged to `decisions.md` (2026-05-30 "Ring spoke-lock: pad shorter band").

**T12 — ✅ DONE (verified live 2026-05-30).** User exercised open → hover inner & middle → expand a middle item → select an outer item → dismiss. All work. The three §6 risks all cleared: wedge orientation correct (no flipped-clockwise bug), first click registers, and hover/drag selection tracks the cursor on the non-activating panel.

**Bugs found & fixed during T12 verification:**
1. **App quit on last-window-close** (`fix: keep app alive when the last window closes`) — LSUIElement app whose only SwiftUI scene is `Settings`; closing the auto-opened "Identify Input" diagnostic window terminated the app and killed the trigger. Added `applicationShouldTerminateAfterLastWindowClosed -> false`; made that window `.miniaturizable`.
2. **Escape didn't dismiss** (`fix: Escape dismissal — add local key monitor`) — `DismissMonitor` used only a global key monitor, which can't see Escape when focus is on our own panel (click-outside worked because a global mouse-down is inherently to another app). Added an `addLocalMonitorForEvents` keyDown monitor for Escape.
3. **Trigger key:** swapped Numpad-Clear → F5 (`chore: set F5 + middle-click as test triggers`). Note F5 collides with the system/Perplexity voice key on a bare press; use Fn+F5 directly or map a mouse button to F5 (sends the raw keycode).

*Original plan: 12 tasks across 5 waves. T1–T12 built & verified 2026-05-30.*
