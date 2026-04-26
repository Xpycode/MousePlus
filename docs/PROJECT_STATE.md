# Project State

## Quick Facts
- **Project:** MousePlus (renamed from PointerActions on 2026-04-26)
- **Started:** 2026-01-09 (as PointerActions)
- **Current Phase:** implementation (resuming after rename)
- **Last Session:** 2026-04-26-a (rename + relocate + build verified + pushed to GitHub + GPLv3)
- **Repo:** https://github.com/Xpycode/MousePlus (public, GPLv3)
- **Build:** ✅ clean under `xcodebuild -workspace 01_Project/MousePlus.xcworkspace -scheme MousePlus -configuration Debug build`

## One-Liner

Radial quick-access menu summoned by mouse-button or hotkey — app switching, clipboard, menu bar access, and custom actions in a beautiful ring interface. Designed to complement BetterMouse; built for MX Master 3s/4 owners but works with any mouse or trackpad.

## Current Focus

Project bootstrap complete: renamed, builds clean, public on GitHub, GPLv3 in place. Now back to the original v1 blocker — getting the ring menu to actually appear when triggered.

**Hotkey not triggering ring menu** — three likely causes, in order of probability:
1. `MousePlus.entitlements` is empty (`<dict/>`) — sandbox isn't configured and there's no Accessibility entry, so the system never prompts for the permission `NSEvent.addGlobalMonitorForEvents` needs
2. Ctrl+Space conflicts with Spotlight, which intercepts the event before our global monitor sees it
3. The `NSEvent` monitor reference may not be retained for the lifetime of the app

**Open question that should be answered before debugging:** should the primary trigger be a **mouse button** (more on-brand for MousePlus, plays to the MX Master 3s/4 gesture button, sidesteps the Spotlight conflict entirely) instead of / alongside a keyboard hotkey?

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

**Distribution / Brand / Legal (decided 2026-04-26):**
- Distribution: direct download primary, MAS evaluated later (caveat: GPLv3 vs MAS terms — see decisions.md)
- Pricing: free or ~€5 one-time, no subscription, no phone-home (final price decided at v1.0 ship-day)
- License: **GPLv3** — chosen over user's usual MIT default to prevent closed-source commercial forks
- Repo: public at github.com/Xpycode/MousePlus

## Action Types (v1)

1. **App Switcher** - as sub-menu
2. **Clipboard** - copy, paste, clipboard manager integration
3. **Menu Bar Access** - show current app's menu with search
4. **Custom Commands** - open app, run shortcut

## Blockers

- Trigger detection not yet working — see Current Focus for the three suspected causes. Needs entitlements work + a trigger-model decision before debugging.

## Next Actions
1. [x] Map discovery to architecture
2. [x] Create Xcode project with proper structure
3. [x] Rename PointerActions → MousePlus (2026-04-26)
4. [x] Confirm clean build under new name (xcodebuild succeeded after Config/ path fix)
5. [x] Push to public GitHub (Xpycode/MousePlus, GPLv3)
6. [ ] **Decide trigger model:** keyboard hotkey only, mouse button only, or both
7. [ ] Add Accessibility entitlement + sandbox decision to `01_Project/Config/MousePlus.entitlements`
8. [ ] Add logging to `HotkeyService.swift`, run app, grant Accessibility, verify events arrive
9. [ ] Get ring menu visible at the cursor (the actual radial UI)
10. [ ] Refine ring visuals
11. [ ] Implement first action type (App Switcher likely simplest)

---
*Updated automatically by Claude during sessions*
