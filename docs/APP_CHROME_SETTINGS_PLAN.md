# Help, Feedback, Tip, and Appearance — Settings Plan

**Status:** Planned (2026-09-04). Not a ring/HUD action — this is app-chrome UI, entirely inside
the Settings workspace. Independent of the HUD action track (`HUD_ACTIONS_PLAN.md`) and the HID++
decision; can be built any time.

**Why Settings, not the menu bar.** MousePlus is `LSUIElement`-only: the status item's `NSMenu`
(`Controllers/MenuBarController.swift`) is a short utility menu (About / Preferences / Identify
Input / Restart / Quit), not a full app menu bar with a Help menu. Confirmed by user decision
(2026-09-04): these four items go into **Settings**, not appended to that status-item menu.

**Ground truth (verified 2026-09-04).**
- `SettingsSection` (`Models/SettingsSection.swift`) is a 4-case enum (`general`, `triggers`,
  `ringAppearance`, `menuItems`) driving a sidebar `List` in `SettingsView.swift:22–27`, each with
  a `title` and `systemImage`. Adding a section is a 3-point change: the case, its `title`/
  `systemImage`, and a `switch` arm in `SettingsView.swift:38–47`.
- `GeneralSettingsPane.swift` already has an **"Appearance" section** (`:16–20`) — but it is only
  a caption pointing to Ring Appearance ("Ring geometry, dimming, and animation are configured in
  Ring Appearance"), not an actual control. **This is a naming collision to resolve, not reuse**:
  Ring Appearance = per-ring HUD wedge colors/geometry; the new "Appearance" the user is asking
  about = app-chrome light/dark, which doesn't exist anywhere yet. Do not add chrome-appearance
  controls into that caption section — it would conflate two unrelated meanings of "Appearance"
  under one label.
- **No app-wide color-scheme control exists at all.** `MousePlusApp.swift:20` sets only
  `.windowStyle(.hiddenTitleBar)`; there is no `.preferredColorScheme` anywhere. Per this
  ecosystem's App Shell Standard (`~/ProgrammingProjects/0-DIRECTIONS/__DIRECTIONS/cookbook/00-app-shell.md`,
  `47_project-ui-conventions.md`), the standard is dark-default with a user-facing light switch —
  **MousePlus's Settings window currently just follows the system appearance, unmanaged.** This
  plan is also the fix for that gap, not just a place to park a picker.
- `GeneralSettingsPane`'s "Application" section (`:35–46`) already establishes the pattern for a
  simple labeled section + `AppKitButton` — reuse this exact composition for Help/Feedback/Tip
  rather than inventing new chrome.
- `AppKitButton` exists as the project's non-raw-SwiftUI button wrapper (used at
  `GeneralSettingsPane.swift:27,40`) — per `47_project-ui-conventions.md` / the App Shell Standard,
  all new buttons here must use it, not a bare SwiftUI `Button`.
- No repo/support URL constants exist yet outside `docs/PROJECT_STATE.md`
  (`https://github.com/Xpycode/MousePlus`, public GPLv3). No tip-jar URL exists anywhere in the
  project — this is a **placeholder the user must supply** (Ko-fi / GitHub Sponsors / Buy Me a
  Coffee — pick one before Phase 1 ships; T4 below blocks on it).

---

## 1. Scope

A **new sidebar section** (not folded into General, to avoid the Appearance-label collision above
and because it groups cleanly as "about this app" content):

| Item | Behavior |
|---|---|
| **Help** | Opens the project's help surface in the default browser — the GitHub repo/README (or a Wiki page if one exists later) via `NSWorkspace.shared.open`. No in-app help viewer for v1. |
| **Feedback** | Opens `https://github.com/Xpycode/MousePlus/issues/new` (public GPLv3 project already lives on GitHub — Issues is the natural, already-existing venue; no new infrastructure). A `mailto:` fallback is explicitly **not** v1 — avoids maintaining a second feedback channel. |
| **Leave a tip** | Opens a tip-jar URL in the browser. **Blocked on the user supplying the URL** (§ Ground truth) — nothing else about this item is technically interesting; it is one `NSWorkspace.shared.open(URL)` call once the link exists. |
| **Appearance** | A Light / Dark / System picker controlling the Settings window's `.preferredColorScheme`, persisted via `@AppStorage`. This is the one item with real implementation weight (§3). |

All four are simple, independent, and low-risk — this plan does not need execute-wave phasing at
the depth of the HUD action plans; one wave covers it.

---

## 2. Section placement

Add a 5th `SettingsSection` case. Two reasonable names — **pick one before starting** (this plan
recommends the first):

- **`about`** ("About", `systemImage: "info.circle"`) — conventional macOS naming, groups
  Help/Feedback/Tip/Appearance under a familiar label users already expect at the bottom of a
  sidebar.
- `support` — reads slightly better for Feedback/Tip but undersells Appearance living there.

```swift
enum SettingsSection: CaseIterable {
    case general, triggers, ringAppearance, menuItems, about   // new

    var title: String {
        switch self {
        // …
        case .about: "About"
        }
    }
    var systemImage: String {
        switch self {
        // …
        case .about: "info.circle"
        }
    }
}
```
Order matters for the sidebar `List` (`SettingsView.swift:22–27`, driven by
`SettingsSection.orderedCases()`) — place `about` **last**, after Menu Items, matching the macOS
convention of About/support content trailing functional settings.

---

## 3. Appearance control

```swift
enum AppColorScheme: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var displayName: String { … }        // "System", "Light", "Dark"
    var colorScheme: ColorScheme? {        // nil = follow system
        switch self { case .system: nil; case .light: .light; case .dark: .dark }
    }
}
```
- Store as `@AppStorage("appColorScheme") private var appColorScheme: AppColorScheme = .system`
  (raw-value-backed `AppStorage`, matching the project's existing `UserDefaults`-for-settings
  convention per the tech stack table in `CLAUDE.md`).
- Apply via `.preferredColorScheme(appColorScheme.colorScheme)` on the Settings window's root view
  (`SettingsView.swift` body, or the enclosing `Scene` in `MousePlusApp.swift` if the modifier
  needs to sit above the sidebar `HStack` to affect the whole window chrome including the sidebar
  `List`).
- **Scope is the Settings window only for v1** — the ring HUD's own light/dark is already handled
  per-ring inside Ring Appearance (per `PROJECT_STATE.md`'s "tab/light-dark/per-ring" verification
  note) and must **not** be touched by this control; conflating the two would break the
  already-verified Ring Appearance behavior. If a future pass wants one global scheme driving both
  Settings chrome and ring defaults, that is a separate decision to log then, not assumed here.
- A picker control (native `Picker`, not a raw-SwiftUI segmented control if the App Shell Standard
  restricts that here — check `47_project-ui-conventions.md`'s specific guidance on `Picker`
  before implementing; other panes in this project don't yet show a `Picker` precedent to copy).

---

## 4. Phased implementation

Build-gated: `xcodebuild -workspace 01_Project/MousePlus.xcworkspace -scheme MousePlus -configuration Debug build`

### Wave 1 — model + section scaffold (parallel-friendly)

| # | Task | Target file | Done when |
|---|------|-------------|-----------|
| T1 | Add `.about` case to `SettingsSection` (title, systemImage, ordering last). | `Models/SettingsSection.swift` | Builds; "About" appears at the bottom of the sidebar |
| T2 | `AppColorScheme` enum (§3). | `Models/AppColorScheme.swift` (new) or inline in the new pane's file if the project prefers small enums co-located (check sibling precedent, e.g. `SnapZone`) | Builds |
| T3 | `AboutSettingsPane` view: four sections (Help, Feedback, Leave a Tip, Appearance) composed like `GeneralSettingsPane`'s existing "Application" section (`AppKitButton` + caption text, `Form`/`.formStyle(.grouped)`). Wire into `SettingsView.swift`'s switch (`:38–47`). | `Views/AboutSettingsPane.swift` (new), `Views/SettingsView.swift` | Builds; selecting "About" shows all four controls |

### Wave 2 — behavior (needs Wave 1)

| # | Task | Target file | Done when |
|---|------|-------------|-----------|
| T4 | Help/Feedback/Tip buttons call `NSWorkspace.shared.open(URL(string:)!)` with the repo README URL, the GitHub new-issue URL, and the tip-jar URL. **Blocked:** tip-jar URL must be supplied by the user before this ships — stub it behind a `#warning`/TODO or simply omit the button until the URL exists, rather than shipping a dead link. | `Views/AboutSettingsPane.swift` | Builds; Help and Feedback open correctly in the browser; Tip either opens correctly or is cleanly absent pending the URL |
| T5 | `@AppStorage`-backed `AppColorScheme` picker; `.preferredColorScheme` applied to the Settings window root (§3). | `Views/AboutSettingsPane.swift`, `Views/SettingsView.swift` (or `MousePlusApp.swift` if the modifier must sit higher) | Builds; switching Light/Dark/System visibly re-themes the Settings window without relaunch; Ring Appearance's own light/dark is unaffected |

### Wave 3 — verify

| # | Task | Done when |
|---|------|-----------|
| T6 | Clean signed build. Open Settings → About: Help and Feedback open the correct URLs in the default browser; Appearance picker flips the Settings window's scheme live in all three modes; Ring Appearance's per-ring colors are unchanged by the Appearance picker. | All four items verified live |

**Net deliverables:** `Models/AppColorScheme.swift` (or inline), `Views/AboutSettingsPane.swift`
(new); `Models/SettingsSection.swift`, `Views/SettingsView.swift` (edited). No new services, no
persistence beyond one `@AppStorage` key.

---

## 5. Open questions (resolve before/at implementation start)

- **Tip-jar URL** — which platform (Ko-fi / GitHub Sponsors / Buy Me a Coffee)? Blocks T4 for that
  one button only; everything else in this plan is unblocked.
- **Section name** — `about` vs `support` (§2); cosmetic, pick one and move on.
- **Help destination** — repo README is the zero-effort v1 choice; a dedicated docs/Wiki page is a
  later upgrade that doesn't change this plan's shape (just the URL constant).

## 6. Decisions to log in `decisions.md`

- Help/Feedback/Tip/Appearance live in Settings, not the status-item menu — MousePlus has no
  traditional app menu bar to hang them on (user decision, 2026-09-04).
- "Appearance" (this plan, app chrome) and "Ring Appearance" (existing tab, per-ring HUD colors)
  are deliberately kept separate — the Appearance picker here scopes to the Settings window only
  and must not touch ring color/light-dark behavior already signed-live-verified.
- Feedback routes to GitHub Issues (already the project's public home), not a new `mailto:` or
  form — no new infrastructure for a project this size.
