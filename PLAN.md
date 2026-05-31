# Execution Plan — Menu Items Editor

Source of truth for scope: `docs/MENU_EDITOR_PLAN.md`. This file tracks wave/task completion.
Branch: `feature/menu-editor`. Build gate after each wave:
`xcodebuild -workspace 01_Project/MousePlus.xcworkspace -scheme MousePlus -configuration Debug build`

All source lives under `01_Project/MousePlus/` (Xcode 16 synchronized groups — new files auto-register).

## Goal
Make the inner + middle rings user-customizable in-app via a dedicated resizable editor window
(WYSIWYG-lite: click-to-select live ring preview + detail form), replacing the `MenuSettingsView` stub.

## Tasks

### Wave 1 (foundation — parallel, no shared files)
- [x] **T1**: `AppDelegate.applyMenuItems` live-apply hook (mirror `applyAppearance`) -> `01_Project/MousePlus/MousePlusApp.swift`
- [x] **T2**: `MenuEditorModel` working-state model (id-keyed safe bindings, invariants, spoke cap) -> `01_Project/MousePlus/ViewModels/MenuEditorModel.swift`

### Wave 2 (pickers — parallel, independent components)
- [x] **T3**: `SymbolField` + `Resources/CuratedSymbols.swift` -> `01_Project/MousePlus/Views/MenuEditor/SymbolField.swift`, `01_Project/MousePlus/Resources/CuratedSymbols.swift`
- [x] **T4**: `AppPickerSheet` (installed+running scan, search, Other…) -> `01_Project/MousePlus/Views/MenuEditor/AppPickerSheet.swift`
- [x] **T5**: `ActionDataEditor` (type-aware control) -> `01_Project/MousePlus/Views/MenuEditor/ActionDataEditor.swift`

### Wave 3 (editor shell — depends W1, W2)
- [x] **T6**: `RingPreviewSelector` (reuse RingMenuView, hit-test off, selection overlay, ghosts; sub-item selection via labeled strip) -> `01_Project/MousePlus/Views/MenuEditor/RingPreviewSelector.swift`
- [x] **T7**: `SlotEditorForm` (symbol/label/action/sub-items/move/delete) -> `01_Project/MousePlus/Views/MenuEditor/SlotEditorForm.swift`
- [x] **T8**: `MenuEditorView` assembly (band switch, count, preview+form) -> `01_Project/MousePlus/Views/MenuEditor/MenuEditorView.swift`

### Wave 4 (window, persistence, launcher — depends W3)
- [ ] **T9**: `MenuEditorWindowController` + replace `MenuSettingsView` stub with launcher -> `01_Project/MousePlus/Controllers/MenuEditorWindowController.swift`, `01_Project/MousePlus/Views/SettingsView.swift`
- [ ] **T10**: load-on-open + debounced save + live-apply + Reset-to-Defaults wiring

### Wave 5 (edge cases + verification)
- [ ] **T11**: UI invariants (8-cap, symbol validation, inner no-label, sub-items middle-only, appSwitch icon note)
- [ ] **T12**: user-driven live verification (no synthetic input)
