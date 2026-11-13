# MousePlus — Codex Instructions

MousePlus is a macOS radial quick-access menu displayed at the pointer.

## Stack and architecture

- macOS 14+, SwiftUI views hosted by AppKit `NSPanel`/`NSHostingView`.
- `NSStatusItem` and `LSUIElement`; preserve the no-Dock-icon behavior.
- Global hotkeys use `NSEvent`; menu-bar access uses `AXUIElement`; app discovery uses `NSWorkspace`.
- JSON configuration lives in Application Support; settings use UserDefaults.
- View models are `@MainActor`/`@Observable`; shared services are actors.

## Build and verification

```bash
xcodebuild -workspace 01_Project/MousePlus.xcworkspace \
  -scheme MousePlus -configuration Debug build
```

Run relevant tests and perform live checks for permissions, hotkeys, menu-bar access, and overlay
lifecycle. Treat `xcodebuild` as authoritative over isolated SourceKit diagnostics.

## Directions

Use the globally installed `directions` skill and the master `commands/*.md` procedures. Read
`docs/PROJECT_STATE.md` for current state, `docs/decisions.md` for rationale, and `docs/sessions/` for
handoffs. Do not copy universal Directions docs into this repository.


<!-- DIRECTIONS-PROJECT:START -->
## Shared Directions workflow

- **Local master:** `/Users/sim/ProgrammingProjects/0-DIRECTIONS/__DIRECTIONS`.
- For Directions commands, use the installed Directions skill in Codex or read the master's
  `commands/<name>.md` completely. Slashless forms work too. Approved-plan continuation uses
  `commands/execute.md`; status alone does not authorize execution.
- Resolve shared `reference/...` from that master. Read universal guidance there on demand;
  use the relevant host global template's routing section if global guidance is unavailable.
  Report a missing master instead of using copied universal guides.
- This section supersedes older generic Directions workflow, copied-guide loading, automatic
  app-control and PR-ceremony instructions in this file. Preserve project-specific architecture,
  build commands, security constraints and product requirements above.
- Retained numbered guides in `docs/` are legacy references, not workflow authority. Preserve
  their project-specific additions; consult them only for relevant historical/project evidence.
- Preserve existing state, selected plans, open gates and session history. Legacy task/state
  reconciliation is separate work; never mark a manual gate complete from an old checkbox.
- Before builds/tests, read the master's `34_testing.md` and inspect startup effects. Desktop/app
  control requires explicit user permission; older automatic quit/launch instructions do not grant it.
  Give full absolute paths for user-operated file/app steps. Preserve dirty work and user limits.
<!-- DIRECTIONS-PROJECT:END -->
