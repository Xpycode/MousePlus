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
