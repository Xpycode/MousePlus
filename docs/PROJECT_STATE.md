# Project State

## Quick Facts
- **Project:** MousePlus (renamed from PointerActions on 2026-04-26)
- **Started:** 2026-01-09 (as PointerActions)
- **Current Phase:** implementation (resuming after rename)
- **Last Session:** 2026-04-26 (rename + relocate)

## One-Liner

Radial quick-access menu summoned by mouse-button or hotkey — app switching, clipboard, menu bar access, and custom actions in a beautiful ring interface. Designed to complement BetterMouse; built for MX Master 3s/4 owners but works with any mouse or trackpad.

## Current Focus

Project rebranded and relocated. Resuming work on the original v1 blocker:
**Hotkey (Ctrl+Space) not triggering ring menu** — likely Accessibility permission missing (entitlements file is empty) or NSEvent global monitor not retained, or Ctrl+Space being eaten by Spotlight before our monitor sees it.

Open question for the rebrand: should the primary trigger be a **mouse button** (more on-brand for MousePlus + plays to MX Master gesture button) instead of / alongside Ctrl+Space?

## Key Decisions Made

See `decisions.md` for full rationale.

**Product:**
- Two-level menu depth (ring → sub-ring)
- Both trigger methods (hold+release AND tap+click)
- User-selectable animation (instant vs animated)
- All dismiss methods (click outside, Escape, release hotkey)

**Technical:**
- NSPanel + SwiftUI for ring overlay
- NSEvent.addGlobalMonitorForEvents for hotkey
- AXUIElement API for menu bar access (requires Accessibility permission)
- JSON for config, UserDefaults for settings

## Action Types (v1)

1. **App Switcher** - as sub-menu
2. **Clipboard** - copy, paste, clipboard manager integration
3. **Menu Bar Access** - show current app's menu with search
4. **Custom Commands** - open app, run shortcut

## Blockers

- Hotkey (Ctrl+Space) not triggering - likely Accessibility permission or event monitor issue

## Next Actions
1. [x] Map discovery to architecture
2. [x] Create Xcode project with proper structure
3. [x] Rename PointerActions → MousePlus (2026-04-26)
4. [ ] Confirm clean build under new name
5. [ ] Decide trigger model: keyboard hotkey only, mouse button only, or both
6. [ ] Add Accessibility entitlement + permission flow
7. [ ] **Debug hotkey/button detection — get ring menu to appear at pointer**
8. [ ] Refine ring visuals
9. [ ] Implement first action type

---
*Updated automatically by Claude during sessions*
