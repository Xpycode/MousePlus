# Menu Editor — Code Review & Feature-Gap Audit (2026-07-07)

**Scope:** branch `feature/menu-editor` (Waves 1–4, `19bbab6`→`822b360`) — full read of all
11 changed files + integration context, an independent deep-review agent pass over the same
diff, a runtime validation of every curated SF Symbol, and clean signed builds before/after.
This document is the review-feedback input Wave 5 (T11) was waiting for.

**Verdict: ✅ Approved after fixes.** Seven defects found (2 critical, 4 important, 1 minor);
all fixed in this pass and build-verified. No security issues. Codebase health is good:
6,423 Swift LOC total, largest file 429 lines, nothing over the 500-line threshold.

---

## 1. Fixed in this pass (all build-verified)

| # | Sev | File | Defect → Fix |
|---|-----|------|--------------|
| 1 | Critical | `RingPreviewSelector.swift` | The "+ add" ghost for a band full to the current spoke count N got its position **clamped onto the last real wedge** (`wedgeAngles` clamps index to N−1) and, being later in the ZStack, **stole its clicks** — on the default 4/4 config, clicking the last wedge added a blank item instead of selecting. Ghost now renders only when a genuinely empty spoke exists (`i < n`); a band full to N relies on the toolbar Add button. |
| 2 | Critical | `MenuEditorWindowController.swift` | **Corrupt-config wipe:** `(try? load()) ?? Configuration()` treated a *present-but-undecodable* `config.json` like a missing one → editor filled with sample defaults → autosave **persisted defaults over the user's real file** 400ms later. Related: closing the window *before the first load completed* flushed an empty model merged into a default config (wiping rings **and** the trigger binding). Both closed by a `LoadState` gate (`pending/loaded/failed`): saves only run in `.loaded`; a decode failure locks saving and explains itself via `NSAlert`. Hand-editing `config.json` is established practice in this project, so this path was realistic. |
| 3 | Important | `MenuEditorModel.swift` (+ `MenuEditorView`, preview) | **Per-band cap:** `atSpokeCap` used `max(inner, middle) ≥ 8`, so middle reaching 8 wrongly blocked adding inner items even though N wouldn't grow. New `atCap(for:)` gates per band; `atSpokeCap` remains only for the "N of 8" readout. |
| 4 | Important | `MenuEditorWindowController.swift` | **Cross-window lost update:** autosave merged into the `baseConfig` snapshot taken at window-open, so an appearance/trigger change made in Settings *while the editor was open* was silently reverted by the editor's next save. `saveNow()` now re-reads the on-disk config as the merge base at save time — the same read-modify-write pattern `RingAppearanceSettingsView` already uses. |
| 5 | Important | `MenuEditorWindowController.swift` | **Close→reopen race:** the close-flush ran as a detached task while a quick reopen read the file *before the flush landed*, loading stale rings which the autosave chain then wrote back over the flushed edit. The flush now lives in `saveTask` and `refreshFromDisk()` awaits any pending save before reading. |
| 6 | Important | `MenuEditorModel.swift` | **Stale payload on action-type switch:** changing `.appSwitch` → `.windowSnap` kept the bundle-id in `actionData`; the picker displayed "Left" (its fallback) while the runtime `SnapZone(rawValue:)` failed and the action silently no-oped. Binding setters now reset `actionData` to the new type's default when a type switch carries the old payload along unchanged (model invariant 4 — done in the model, not `.onChange`, to dodge the view-identity trap where selection switches would wipe the newly selected item). |
| 7 | Minor | `MenuEditorWindowController.swift` | Each close→reopen armed **another** self-re-arming `withObservationTracking` chain (they observe the model, which outlives the window). Single chain enforced via `isObservingModel`. |

**Enhancement:** `AppPickerSheet` no longer fetches an `NSImage` icon for every installed app
up-front (hundreds of `NSWorkspace.icon(forFile:)` calls blocking sheet presentation); icons
resolve lazily per visible row (`AppIconView`), so the sheet opens instantly.

## 2. Verified clean (checked, no issue)

- **Curated symbols:** all 89 unique names in `CuratedSymbols.swift` validated at runtime via
  `NSImage(systemSymbolName:)` — zero invalid, no blank tiles in the picker grid.
- **Id-keyed bindings** in `MenuEditorModel` are crash-safe against stale selections (the
  index-based `ForEach` crash class from the 2026-05-31 outer-band fix cannot recur here).
- **Window lifecycle** matches the `InputRecorderWindowController` pattern correctly for an
  LSUIElement app; ⌘Q does invoke `windowWillClose` before `applicationWillTerminate`
  (Apple's documented termination sequence), so close-flush also covers quit.
- **`applyMenuItems` wiring** correctly pushes edits into the live `RingViewModel` + `reset()`.
- **Codable migrations** (legacy `items`, `hotkey`, dropped `clipboard`) round-trip safely.
- **`.custom` command execution** (`/bin/zsh -c`) is user-authored automation, not an
  injection surface — no privilege boundary is crossed (same model as Raycast/Alfred).

## 3. Known remaining risks (accepted for now, ranked)

1. **Quit-during-debounce edit loss (narrow):** `windowWillClose`'s flush is an async task;
   on ⌘Q the process can exit before it runs, losing at most the last <400ms of edits.
   Fix would be a synchronous write path callable from `applicationWillTerminate`.
2. **Preview ignores user appearance:** the editor preview renders default `BandRadii` and
   dim settings, not the user's configured ones — geometry/hotspots stay self-consistent,
   but fidelity to the live ring drifts if radii were customized.
3. **Fixed 448pt preview vs 620pt min window:** at minimum height the detail form is squeezed
   to a sliver (scrollable, but cramped). Consider scaling the preview to fit, or a taller min.
4. **Sub-items strip overlaps bottom wedges:** the labeled sub-item buttons render inside the
   ring square and can sit over bottom-spoke hotspots while a middle item is expanded
   (v1-acknowledged in code comments).
5. **Full-to-N bands show no in-ring ghost** (deliberate consequence of fix #1) — adding then
   goes through the toolbar button only.

## 4. Wave 5 / T11 status after this review

| T11 item | Status |
|---|---|
| 8-spoke cap disables Add + inline note | ✅ done, now correctly per-band (fix #3) |
| Ghost/empty-slot add flow | ✅ fixed (fix #1) |
| Sub-items only on middle, depth cap 3 | ✅ enforced (invariants 1–2 + inner strip) |
| `appSwitch` renders SF Symbol, not app icon — note | ✅ present in `ActionDataEditor` |
| **SF-symbol validation gating save** | ⚠️ **still open** — `SymbolField` flags invalid names inline, but the model accepts them and autosave persists them (blank wedge in the live ring). With autosave there is no "save" to gate; needs a design choice: keep-last-valid, revert-on-blur, or persist-but-render-placeholder. |

T12 (user-driven live verify, no synthetic input) remains as planned — see §5 checklist in
`MENU_EDITOR_PLAN.md`.

## 5. Missing features (gap audit — candidates, not commitments)

**Editor, small (≤½ day each):**
- **Duplicate item** (top-level + sub-item) — common editor affordance, trivial on the model.
- **Symbol search** in the picker popover (free-text filter over the curated grid).
- **"Test command" button** for `.custom` (run now, surface exit status/output) — also the
  cheapest way to expose command failures, which are currently invisible.
- **Menu-bar entry** "Edit Menu Items…" in `MenuBarController` (today: Settings → Menu Items → button).
- **Keyboard-shortcut field:** `RingMenuItem.keyboardShortcut` exists in the model but has
  no editor UI *and no runtime handling* — either build both or drop the field.

**Editor, medium:**
- **Undo/redo** — Reset-to-Defaults is confirm-only and irreversible; with autosave, every
  slip persists within 400ms. A snapshot stack (or `NSUndoManager`) would cover both.
- **Sub-item reorder** (deliberately out of v1 scope; the move-button pattern is already there).
- **Drag-and-drop reorder** directly on the ring preview.
- **Config import/export** (share/backup `config.json` from the UI; pairs with the corrupt-file
  alert from fix #2, which currently tells the user to fix the file by hand).

**Runtime (pre-existing, tracked elsewhere):**
- `menuBar` / `systemToggle` / `screenshot` action types are typed stubs (`HUD_ACTIONS_PLAN.md`).
- **Action-failure feedback:** `commitActive()` fires actions with `try?` — an unresolvable
  bundle id or failing command is silent. A small HUD/notification would close the loop.
- **Onboarding gap:** fresh installs ship with no trigger bound (W5/D1, `PROJECT_STATE.md`).
- **Real app icons** in the ring (`IconSource`, HUD Feature C) — the editor already points at it.
- **Per-app ring profiles** (different rings per frontmost app) — larger, v2 territory.

## 6. Environment note (M4 Pro)

`01_Project/Config/Debug.local.xcconfig` contained the **M1 Max's** cert SHA (`B2D5D457…`),
which broke signed Debug builds on this machine ("No certificate for team H56HM4MMZS
matching…"). Rewrote it with this Mac's Apple Development SHA (`26570985…`) per the bootstrap
procedure documented in `Debug.xcconfig`; signed build verified. If the wrong-Mac file
reappears, the Syncthing ignore rules for `Debug.local.xcconfig` need checking.

---

## 7. Fable adversarial panel — round 2 (2026-07-07 part 3)

A second, independent review of the same `main...HEAD` diff by a **four-lens adversarial panel**
(four Claude Fable-5 reviewers, one lens each: *correctness*, *model-invariants*,
*persistence-safety*, *SwiftUI-identity*), each handed §1 above so it hunted for what the first
pass **missed** rather than re-flagging the seven fixed bugs. It surfaced **15 new findings**. The
top data-loss cluster was **cross-confirmed by 2–3 lenses independently** — and resolved a
disagreement: the *correctness* lens certified the `refreshFromDisk`/close-flush path as clean
("fix #5 holds"); the *persistence* and *SwiftUI-identity* lenses refuted it, and a direct code read
confirmed the refuters — **F1 is real** (a cancelled debounce task satisfies `await saveTask.value`
without ever writing).

**This pass fixed clusters A + B + D (build-verified).** Tier-2 (F5/F6) and all Tier-3 are logged
as accepted risks in §3 above / below.

| # | Sev | Status | File | Defect (brief) |
|---|-----|--------|------|----------------|
| **F1** | 🔴 data-loss | ✅ fixed (A) | `MenuEditorWindowController.swift` | `refreshFromDisk` treated a **cancelled** debounce task as a completed flush → reopen-during-debounce reloaded stale disk, reverted the model, then persisted the reverted rings. *(persistence + swiftui; correctness wrongly cleared it)* |
| **F2** | 🔴 data-loss | ✅ fixed (A) | `MenuEditorWindowController.swift:174-178` | `saveNow`'s `(try? load()) ?? baseConfig` fallback **overwrote a config that went corrupt AFTER open** — the `.loaded` gate was never re-checked. *(invariants + persistence + correctness — 3 lenses)* |
| **F3** | 🔴 data-loss | ✅ fixed (A) | `MenuEditorWindowController.swift`; `Configuration/ActionType` encode | A **zero-edit open→close→reopen rewrote `config.json`**, and encode doesn't round-trip what decode tolerates (legacy `clipboard`→`custom`, unknown keys dropped, inner sub-items stripped). Root cause: `@Observable` fires `onChange` on *assignment*, so `model.load` looked like an edit. *(persistence + swiftui)* |
| **F4** | 🔴 data-loss | ✅ fixed (A) | `MenuEditorWindowController.swift:177-179` | Save error `try?`-swallowed while live-apply proceeded → a persistently failing write loses the **whole session** behind a saved-looking UI. *(persistence)* |
| **F7** | 🟠 broken-fn | ✅ fixed (B) | `MenuEditorModel.swift` → `ActionService.swift:52` → `ActionDataEditor.swift` | Deleting all sub-items of the default "Snap"/"Apps" wedge makes it a **direct action with an empty payload** → silently no-ops at runtime **while the form claims "Snap to: Left."** Pure supported clicks. *(invariants)* |
| **F8** | 🟠 UX | ✅ fixed (B) | `MenuEditorModel.swift` / `SlotEditorForm.swift` | **Outer band had no spoke cap** — "Add Sub-item" never disabled → ring degrades into unhittable slivers + editor pane overflow. *(invariants)* |
| **F15** | 🟡 blank-icon | ✅ fixed (D) | `RingPreviewSelector.swift:220` | The sub-item strip rendered `sub.icon` raw instead of `SFSymbol.resolved(_:)` — **one render site the T11 fix missed** → blank icon for an invalid name. *(correctness)* |
| **F5** | 🟠 data-loss | ⏸ deferred | `SettingsView.swift:113`, `TriggersSettingsView.swift:183` | The corrupt-config→sample-defaults wipe fix #2 closed **is still live in both Settings writers**. One slider drag after the fix-#2 "your file is protected" alert overwrites the recoverable file. *Pre-existing; the branch's alert now over-promises.* *(persistence)* |
| **F6** | 🟠 edit-revert | ⏸ deferred | editor vs `SettingsView`/`TriggersSettingsView` writers | Residual **last-writer-wins race**: separate `ConfigurationService` instances, multi-await read-modify-write, nothing serializes them. Edit an item + drag a radii slider within ~1s → one reverts on disk. *(persistence)* |
| **F9** | 🟡 edge | ⏸ deferred | `MenuEditorModel.swift:96-101` | `load()` bypasses the 8-item band cap → over-cap items are invisible/undeletable in the UI but persist. *Hand-edit-gated.* *(invariants)* |
| **F10** | 🟡 edge | ⏸ deferred | `MenuEditorModel.swift:352-356` | Depth cap enforced asymmetrically on load: inner `subItems` scrubbed, middle sub-sub-items not → nested items laundered + false expand hint. *Hand-edit-gated.* *(invariants)* |
| **F11** | 🟡 UX | ✅ mostly fixed (A) | `MenuEditorWindowController.swift` → `MenuEditorModel.load` | Reopen while the app-picker sheet is open nuked selection + force-dismissed the sheet. Now the reopen skips `model.load` when disk == model, so a no-op reopen preserves selection/sheet. *(External-change reopens still clear it — acceptable.)* *(swiftui)* |
| **F12** | 🟡 conditional | ⏸ deferred | `SlotEditorForm.swift:24-31` | No `.id(model.selection)` on the detail form → `@State` + NSTextField first-responder can bleed across slot switches (possible cross-slot text write). *macOS-version-dependent.* *(swiftui)* |
| **F13** | 🟡 perf | ⏸ deferred | `RingPreviewSelector.swift:28` | `@State private var preview = RingViewModel()` allocates a throwaway view model (+`ActionService` actor) per body eval, i.e. per keystroke; plus a first-frame sample-ring flash. *(swiftui)* |
| **F14** | 🟡 mis-click | ⏸ deferred | `RingPreviewSelector.swift:34` | 44pt inner hotspots overlap ~5pt at 8 spokes → a boundary click selects the neighbor, or hits the ghost and silently appends. *2.5pt sliver.* *(correctness)* |

### Fixed this pass (A + B + D)

- **Cluster A — load/save path (`MenuEditorWindowController`):** new `isDirty` flag; `flushPendingSave()` persists deterministically instead of `await`-ing a possibly-cancelled task; `refreshFromDisk` refuses to overwrite the working model from disk while `isDirty` (local edits win) and skips `model.load` when disk == model (no churn, selection/sheet preserved); `saveNow` now **bails + alerts on a decode-throw** instead of clobbering with `baseConfig`, and **surfaces write failures** (`presentSaveFailure`) instead of swallowing them; a clean close writes nothing. Kills F1–F4, F11.
- **Cluster B — model normalization (`MenuEditorModel`):** `normalizeSnapPayloads()` (run in `init`/`load`/`resetToDefaults`/after `removeSubItem`) gives a *direct* `.windowSnap` item a real zone so it can't no-op behind a "Left" label (F7, invariant 4); parent markers with sub-items are skipped to avoid churn. New `maxSubItems = 12` cap (clears the 10-zone Snap default) gates `addSubItem` + disables the "Add Sub-item" button (F8, invariant 3, outer band).
- **Cluster D — render site (`RingPreviewSelector:220`):** `SFSymbol.resolved(sub.icon)` — completes T11's "no blank wedge" guarantee at the one missed draw site (F15).

### Deferred (accepted risk until scheduled) — extends §3

6. **F5 — Settings writers still wipe on corrupt config.** Same one-line pattern as the removed editor bug, in `SettingsView`/`TriggersSettingsView`. Should get the same load-gate; pre-existing, so out of this branch's scope but tracked.
7. **F6 — editor↔Settings last-writer-wins.** Needs a shared/serialized config writer (single `ConfigurationService`, or an actor-level RMW).
8. **F9 / F10 — load-time cap & depth-cap bypass.** Hand-edited/legacy configs only; a `load()`-time clamp (or surfacing over-cap items) would close them.
9. **F12 — detail-form identity.** `.id(model.selection)` on the editor subtree (safe now that action-type reset lives in the model) would give each slot fresh `@State`/focus.
10. **F13 — per-keystroke `RingViewModel` alloc.** Inject the preview model from the controller, or init it empty.
11. **F14 — 8-spoke inner hotspot overlap.** Clamp hotspot diameter to the inner chord, or use per-spoke `AnnularWedge` content shapes.
