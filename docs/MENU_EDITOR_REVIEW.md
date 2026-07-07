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
