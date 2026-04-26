# Decisions Log

This file tracks the WHY behind technical and design decisions.

---

## 2026-01-09 - Menu Depth: Two Levels

**Context:** How deep should nested menus go?

**Options Considered:**
1. Single level - simpler but too limiting for grouped actions
2. Two levels - allows grouping without spatial complexity
3. Unlimited - maximum flexibility but hard to navigate

**Decision:** Two levels (primary ring → sub-ring)

**Rationale:** Grouping is essential (e.g., "Apps" → app list) but more than two levels becomes disorienting in a radial UI.

**Consequences:** Action types must be designed to work within this constraint.

---

## 2026-01-09 - Trigger Methods: Both

**Context:** How should users interact with the ring menu?

**Options Considered:**
1. Hold+release only (game-style) - fast for experts
2. Tap+click only - more deliberate, forgiving
3. Both - flexibility for different preferences

**Decision:** Support both methods

**Rationale:** Different contexts and users prefer different interactions. Hold+release is faster; tap+click is easier for new users.

**Consequences:** Need to detect intent from timing, or provide a setting.

---

## 2026-01-09 - Persistence: Configuration Only (v1)

**Context:** What data should persist between sessions?

**Options Considered:**
1. Configuration only - simple, just menu setup and settings
2. Configuration + usage data - enables smart features like frecency sorting

**Decision:** Configuration only for v1

**Rationale:** Keeps initial scope manageable. Usage tracking can be added later.

**Consequences:** Architecture should not preclude future usage tracking.

---

## 2026-01-09 - Visual Style: Beautiful but Functional

**Context:** What aesthetic direction?

**Options Considered:**
1. Utilitarian (Blender-style) - fast, functional, minimal
2. Beautiful (Pieoneer-style) - polished, delightful, premium feel
3. Beautiful but functional - best of both

**Decision:** Beautiful but functional

**Rationale:** User values polish and wants to publish eventually. Visual quality is a differentiator.

**Consequences:** Extra attention to animations, blur, typography, spacing.

---

## 2026-01-09 - App Presence: Menu Bar + Settings Window

**Context:** How should the app appear in macOS?

**Options Considered:**
1. Menu bar only - minimal, but how to access settings?
2. Dock app - clutters dock for a utility
3. Menu bar + settings window - standard utility pattern

**Decision:** Menu bar app with separate settings window

**Rationale:** Ring menu is the primary UI; settings are secondary. No dock clutter.

**Consequences:** LSUIElement = YES, need to handle settings window lifecycle properly.

---

## 2026-01-09 - Overlay Window: NSPanel

**Context:** How to show the ring menu floating above all apps?

**Options Considered:**
1. NSPanel - special floating window type
2. SwiftUI Window with `.windowStyle(.plain)` - cleaner but less control
3. NSWindow subclass - maximum control but most code

**Decision:** NSPanel with SwiftUI content inside

**Rationale:** Battle-tested approach for floating utility panels. Spotlight, Raycast use similar patterns. Precise control over window level and behavior.

**Consequences:** Need to bridge AppKit (NSPanel) with SwiftUI content.

---

## 2026-01-09 - Global Hotkey: NSEvent Monitor

**Context:** How to detect keyboard shortcut when app isn't frontmost?

**Options Considered:**
1. CGEvent tap - low-level, can intercept, needs Accessibility permission
2. NSEvent.addGlobalMonitorForEvents - simpler, observe-only
3. Third-party library (MASShortcut, HotKey) - easiest but external dependency
4. Carbon RegisterEventHotKey - deprecated but reliable

**Decision:** NSEvent.addGlobalMonitorForEvents for v1

**Rationale:** Sufficient for observing hotkeys from BetterMouse. Can upgrade to CGEvent tap if we need to intercept keys later.

**Consequences:** Can't prevent hotkey from reaching other apps (probably fine).

---

## 2026-01-09 - Menu Bar Access: AXUIElement API

**Context:** How to access the current app's menu bar?

**Options Considered:**
1. AXUIElement API - query accessibility tree
2. NSMenu manipulation - limited to own app
3. AppleScript/JXA - slower, more prompts

**Decision:** AXUIElement API

**Rationale:** Only reliable way to access other apps' menus. Menu Anywhere uses this too. Requires Accessibility permission (user approved this).

**Consequences:** Must handle permission flow gracefully. App requires Accessibility permission.

---

## 2026-01-09 - Animation: User-Selectable

**Context:** Should ring appearance be instant or animated?

**Options Considered:**
1. Always instant - fastest
2. Always animated - more polished
3. User-selectable - flexibility

**Decision:** User-selectable (setting in preferences)

**Rationale:** Different users prefer different feel. Some want speed, some want polish.

**Consequences:** Animation code must be conditional. Store preference in UserDefaults.

---

## 2026-01-09 - Dismiss Methods: All

**Context:** How should the ring menu close?

**Options Considered:** Various combinations of click-outside, escape, release-hotkey

**Decision:** Support all dismiss methods:
- Click outside → dismiss
- Press Escape → dismiss
- Release hotkey → dismiss (in hold mode)

**Rationale:** Maximum flexibility, matches user expectations from other radial menus.

**Consequences:** Need to track hotkey state (pressed vs released) and monitor multiple events.

---

## 2026-04-26 - Rename: PointerActions → MousePlus

**Context:** After 3.5 months of pause, resuming the project alongside fresh landscape research on macOS mouse utilities. The user wanted a more product-friendly brand and was about to start a new "MousePlus" project from scratch — until we discovered PointerActions already exists and is exactly the radial-menu shape that interests them.

**Options Considered:**
1. Resume as PointerActions — fastest, but "PointerActions" is engineery and doesn't market well
2. Rename PointerActions → MousePlus in place — preserves all 10 architectural decisions, working menu-bar shell, and Directions structure
3. Keep both — MousePlus as a separate (Finder-extension) product, PointerActions for later

**Decision:** Option 2 — rename in place.

**Rationale:** "MousePlus" is more product-marketable, matches the user's mental model (they have MX Master 3s + 4 and BetterMouse), and the radial menu *is* the underserved gap both research reports surfaced. Splitting attention across two codebases (option 3) made no sense for a non-developer building solo with AI assistance.

**Consequences:**
- All Xcode artifacts renamed: workspace, project, target, scheme, bundle ID (`com.xpycode.PointerActions` → `com.xpycode.MousePlus`), entitlements, xctestplan, app entry-point file
- Bundle ID change means a new app identity in macOS — will need a fresh Accessibility permission grant on first run
- Folder structure preserved (still uses `01_Project/`, `Config/`, `docs/`, `02_Design/`, `03_Screenshots/`)
- Not previously a git repo; initialised git as part of the rename
- Plan to push to public GitHub (license decision still open: GPLv3 vs MIT)

---

## 2026-04-26 - Distribution: Direct first, MAS later if feasible

**Context:** Where to ship MousePlus.

**Decision:** Direct download primary, evaluate Mac App Store as a v2 effort.

**Rationale:** Direct gives full freedom (trial period, custom licensing, free updates) and avoids App Store review delays. MousePlus's required APIs (NSEvent global monitor, AXUIElement for menu bar access) all work in MAS-sandboxed apps with the right entitlements, so MAS is not blocked — just deferred until the product is stable.

**Consequences:**
- Need notarization + code signing for direct distribution (Developer ID Application certificate; user has Apple Developer credentials per `~/.claude/apple-developer.md`)
- Sandbox should still be enabled even for direct distribution to keep MAS path open
- License/payment infrastructure: TBD (Stripe/Paddle/Gumroad if going paid, or open-source-only if free)

---

## 2026-04-26 - Pricing: Free or ~€5 one-time

**Context:** What to charge.

**Decision:** Either fully free (open source + donations) or ~€5 one-time. No subscription, no phone-home.

**Rationale:** Both 2026 landscape reports converged on this finding — users actively reject subscriptions (Mouseposé, SmoothScroll) and increasingly reject daily-license-check phone-home (BetterMouse complaint, Mac Mouse Fix bug #1136). Mac Mouse Fix's $2.99 lifetime is the proof point that low-price one-time wins this niche.

**Consequences:**
- If paid: must be lifetime, no online check, generous free trial
- If free: still need polish + signing + notarization (these aren't free of effort)
- Defer final price decision until v1.0 ship-day

---

*Add decisions as they are made. Future-you will thank present-you.*
