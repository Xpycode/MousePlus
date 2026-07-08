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

## 2026-04-29 - Trigger Model: Both Keyboard + Mouse Button, Mouse-Button as Premium

**Context:** The original v1 plan supported keyboard hotkey only, with the assumption that MX Master users would map a mouse button → keystroke via Logi Options+ / BetterMouse. While debugging the "hotkey not triggering" blocker we re-examined this and found a fundamental flaw.

**Options Considered:**
1. Keyboard shortcut only — simplest, works with any input device, lets users remap mouse buttons via vendor software
2. Mouse button only — most on-brand for "MousePlus", no system-shortcut collisions, but excludes trackpad-only users
3. Both, user picks in Settings — flexibility, but more UI surface

**Decision:** Option 3 — both, mouse-button as the premium path. Three sub-decisions follow:
- **D1:** Ship with no default trigger; user picks during onboarding. Avoids the entire class of system-shortcut collisions (Spotlight/Alfred/Raycast/etc).
- **D2:** Tap-to-toggle semantics = ring opens on first tap, stays open, user clicks a slice to confirm action. *Not* "tap shortcut twice to confirm" (matches Spotlight/Mission Control conventions).
- **D3:** Hand-roll the keyboard recorder UI; do not pull in `sindresorhus/KeyboardShortcuts`. We have to build the mouse-button recorder anyway, so visual parity matters more than ~150 LOC saved.

**Rationale:** Keyboard-shortcut-via-vendor-remap loses **hold-and-release semantics** — Logi Options+ / BetterMouse fire a discrete `keyDown→keyUp` pair on click, not a sustained hold. Hold-and-release is a v1 feature (Blender pie-menu pattern); option 1 silently degrades it for the exact users we target. Mouse-button capture via `NSEvent.addGlobalMonitorForEvents(.otherMouseDown/.otherMouseUp)` preserves both interaction modes natively, and bypasses every keyboard-shortcut collision (Ctrl+Space → input switcher, Cmd+Space → Spotlight, etc).

**Consequences:**
- Settings tab gets two recordable trigger fields (keyboard + mouse), each with its own hold/tap mode toggle
- Both sources unify into a single `TriggerEvent` stream consumed by the ring controller
- Mouse-button trigger requires Accessibility (same TCC entry as keyboard); we additionally declare `NSInputMonitoringUsageDescription` because some macOS configs gate global mouse events behind Input Monitoring
- Settings must surface a "vendor software may intercept this button" tooltip — Logi Options+ / SteerMouse / Karabiner consume buttons before macOS sees them unless the user sets the chosen button to "No Action"
- Implementation phased across Waves 2–5: W2 service refactor with protocol-based monitor split, W3 mouse-button backend, W4 Settings UI + recorders, W5 onboarding-flow polish

---

## 2026-04-29 - Sandbox: Non-sandboxed for v1

**Context:** The empty `<dict/>` in MousePlus.entitlements meant the app was *implicitly* sandboxed (Xcode template default of `ENABLE_APP_SANDBOX = YES`), which is incompatible with `NSEvent.addGlobalMonitorForEvents` for keyboard or mouse events without temporary-exception entitlements that Apple does not grant for direct distribution.

**Options Considered:**
1. Sandboxed with temporary entitlements — only granted for MAS apps; not for direct distribution (and even there, increasingly hard for global event monitors)
2. Non-sandboxed — full access, but blocks the MAS path
3. Hybrid (CGEventTap as a Helper Tool with separate sandbox profile) — used by some pro utilities but massively over-engineered for v1

**Decision:** Non-sandboxed. Explicit declaration `com.apple.security.app-sandbox = false` in `MousePlus.entitlements`; matching `ENABLE_APP_SANDBOX = NO` after stripping the legacy `YES` from `project.pbxproj` target settings.

**Rationale:** Aligns with the GPLv3 + direct-distribution path locked in 2026-04-26. MAS was already deferred. Non-sandboxed is the simplest, most reliable footing for global event monitoring; we can revisit if a MAS-compatible v2 architecture (Helper Tool split) ever becomes worth the effort.

**Consequences:**
- Cannot ship to MAS in current form; would require non-trivial re-architecture
- `entitlements` file must remain explicit (silent removal would let Xcode re-enable sandbox at any point)
- Notarization for direct distribution is unaffected — non-sandboxed apps notarize normally with hardened runtime

---

## 2026-04-29 - Info.plist: Static, at Project Root

**Context:** Adding `NSAccessibilityUsageDescription` and `NSInputMonitoringUsageDescription` to the Info.plist via `INFOPLIST_KEY_*` xcconfig entries silently failed — keys appeared in `xcodebuild -showBuildSettings` but not in the built bundle's Info.plist.

**Options Considered:**
1. Stay with `GENERATE_INFOPLIST_FILE = YES` and use `INFOPLIST_KEY_*` — broken: only a curated whitelist of keys is auto-mapped (`LSUIElement`, `CFBundleDisplayName`, etc.); arbitrary keys drop without warning
2. Build-phase script that injects keys via PlistBuddy — works but adds a script step + opaque failure modes
3. Static Info.plist referenced via `INFOPLIST_FILE` — fully reliable; one file to grep for any plist-related question

**Decision:** Option 3. Static `Info.plist` at `01_Project/Info.plist` (project root, *outside* `fileSystemSynchronizedGroups` to prevent it being auto-bundled as a resource). `GENERATE_INFOPLIST_FILE = NO`. Removed conflicting `GENERATE_INFOPLIST_FILE = YES` and `INFOPLIST_KEY_CFBundleDisplayName` overrides from `project.pbxproj` target build settings.

**Rationale:** The `INFOPLIST_KEY_*` whitelist is undocumented and brittle — every future custom key (App Transport Security exceptions, custom URL schemes, intent metadata, etc.) would re-discover this trap. Static plist makes "what's in our Info.plist" a one-file question. Project-root location avoids the Xcode-16 synced-folder gotcha that bundles every file as a resource.

**Consequences:**
- Bundle/version variables (`$(PRODUCT_NAME)`, `$(MARKETING_VERSION)`, etc.) still flow through xcconfig as plist value substitutions — no change in versioning workflow
- Future plist keys go directly in the static file, no xcconfig dance required
- The two-line removal in `project.pbxproj` (the legacy `GENERATE_INFOPLIST_FILE = YES;` + `INFOPLIST_KEY_CFBundleDisplayName = ...;` per Debug/Release config) must stay removed; if Xcode auto-adds them back via the GUI, override them in xcconfig

---

## 2026-04-29 - Stable Debug Signing (Apple Development cert)

**Context:** Throughout the W2 refactor, every rebuild invalidated the user's Accessibility grant. The app's ad-hoc signature (`Signature=adhoc`, no Team Identifier) gives every build a fresh cdhash; macOS TCC stores grants against `(bundleID, cdhash)`, so each iteration cost ~30 seconds of re-granting (toggle off/on, drag .app, occasionally `tccutil reset`). Doing this 8+ times in a row wore out everyone's patience.

**Options Considered:**
1. Stay ad-hoc — accept the re-grant tax forever
2. Self-signed cert — works, but adds keychain setup for any future contributor
3. Apple Development cert (we have one — `gregor.myller@simsaladim.com`, Team `H56HM4MMZS`) — gives a stable Designated Requirement based on cert chain + bundle ID, not cdhash

**Decision:** Option 3, applied only to Debug builds. `Debug.xcconfig`:
```
CODE_SIGN_STYLE = Manual
CODE_SIGN_IDENTITY = 2D26CB1211F32FD4E3C6EF413EC1EDD6F30631AA
DEVELOPMENT_TEAM = H56HM4MMZS
```

Reference SHA-1 by hash (not name "Apple Development") because Xcode's macOS pipeline still resolves the canonical name to "Mac Development" (legacy), which doesn't match modern certs by name. Hash is unambiguous.

**Rationale:** The cdhash still changes per build, but the requirement string macOS records on grant (`identifier "com.xpycode.MousePlus" and anchor apple generic and certificate leaf[subject.CN] = "Apple Development: ... (H56HM4MMZS)" and certificate 1[field.1.2.840.113635.100.6.2.1] /* exists */`) is satisfied by any subsequent build with the same bundle ID + Apple Dev cert chain. One re-grant after switching to stable signing; subsequent rebuilds preserve it.

**Consequences:**
- Debug builds require the cert in keychain — verified present (`security find-identity -v -p codesigning`)
- The previously-revoked first cert (`81DC...`) is irrelevant; we use cert SHA-1 `2D26...`
- Release.xcconfig still uses ad-hoc / unset — Release will get its own decision when we wire notarization (separate Apple Distribution cert: `FDMSRXXN73`)
- Tests.xcconfig untouched — UI test target doesn't need TCC

---

## 2026-04-29 - Test Trigger Default: Numpad-Clear

**Context:** Multiple test triggers explored during W2 verification. ⌘⌃M (initial) collided with Raycast's Calculator hotkey. ⌃⌥⌘P (next) wasn't registering because the user's keypresses arrived without modifier flags (cause unknown — possibly a third-party remapper, possibly the user wasn't pressing the literal modifier keys; not worth diagnosing now since W4 makes the trigger user-configurable). F19 was tried but the user couldn't locate it. We did capture that the user's keyboard reports kc=83 (Numpad 1) cleanly, confirming a numpad is present.

**Decision:** Numpad-Clear (keyCode 71, no modifiers) as the W2/W3 test default until W4 ships the recorder UI.

**Rationale:** Discoverable on Apple keyboards with numpad (top-left of the numpad block, labeled "Clear"). Very rarely bound by anything else. Zero modifiers eliminates an entire class of "did you really press the modifier" debugging.

**Consequences:** This is throwaway. W4 deletes this default per D1 (no default ships; user picks during onboarding).

---

## 2026-04-29 - Per-Machine Signing Override (refines 2026-04-29 Stable Debug Signing)

**Context:** Source for MousePlus is shared between two Macs (M4 Pro + M1 Max) via Syncthing and git. The "Stable Debug Signing" decision earlier today pinned the M4 Pro's Apple Development cert SHA-1 (`2D26CB1211…`) directly in `Debug.xcconfig`. This file is tracked + synced — when work moved to the M1 Max for W3 verification, the build failed with `No certificate for team 'H56HM4MMZS' matching '2D26CB1211…' found` because the M1 Max has its own Apple Development cert under the same Team ID with a different SHA-1 (`B2D5D457…`). Each Mac generates its own dev cert; that's normal. We need a pattern where each Mac builds without trampling the other through Syncthing/git.

**Options Considered:**
1. Edit the SHA-1 on each Mac as you go — Syncthing pushes the change back, breaks the other Mac on next session, requires constant fix-up.
2. Switch to `CODE_SIGN_STYLE = Automatic` — Xcode picks a cert automatically per-machine, but TCC stable-grant strategy from `2026-04-29 Stable Debug Signing` breaks (cert chain becomes Xcode-managed and can rotate).
3. Switch to ad-hoc (`CODE_SIGN_IDENTITY = -`) — builds anywhere with no cert, but ad-hoc signing's missing Team Identifier is precisely what `2026-04-29 Stable Debug Signing` exists to avoid. Re-grants on every rebuild return.
4. Per-machine xcconfig include — base `Debug.xcconfig` is tracked + shared; a sibling `Debug.local.xcconfig` (gitignored, `.stignore`'d) holds only `CODE_SIGN_IDENTITY` per-machine. Pulled in via `#include?` so a missing local file doesn't error; bootstrap is one shell line per machine.

**Decision:** Option 4. `Debug.xcconfig` keeps shared values (`CODE_SIGN_STYLE = Manual`, `DEVELOPMENT_TEAM = H56HM4MMZS`, parent-include of `Shared.xcconfig`). The `CODE_SIGN_IDENTITY` line is removed from the tracked file and instead supplied by `01_Project/Config/Debug.local.xcconfig`, which contains exactly:
```
CODE_SIGN_IDENTITY = <this-mac-cert-sha-1>
```

Bootstrap on a new Mac:
```
security find-identity -v -p codesigning | grep "Apple Development"
echo 'CODE_SIGN_IDENTITY = <sha-1>' > 01_Project/Config/Debug.local.xcconfig
```

**Rationale:** Preserves the TCC-stable-grant property of the original signing decision per-machine. Each Mac satisfies the same Designated Requirement (anchor + Team ID + bundle ID), so prior TCC grants on each Mac persist across rebuilds *on that Mac* — exactly the property we wanted. Cross-machine TCC re-grants are unavoidable regardless of approach (different cert chains across machines, even under one Apple ID), so we accept that one-time cost. `#include?` makes the local file optional, which is gentler on first-time clones than a hard `#include` that errors before you can even read the bootstrap instructions.

**Consequences:**
- `01_Project/Config/Debug.local.xcconfig` is gitignored (`.gitignore` line: `01_Project/Config/Debug.local.xcconfig`) and Syncthing-ignored (`/Users/sim/ProgrammingProjects/.stignore` line: `**/Debug.local.xcconfig`).
- Pre-emptively listed `Release.local.xcconfig` in both ignore files for symmetry — when Release-build signing decisions land, this slot is ready.
- Documented bootstrap in the comment block at the top of `Debug.xcconfig` so a new contributor (or future machine) doesn't have to dig through git history.
- M1 Max local SHA-1: `B2D5D457082D9A5ED894BC62D820D584E04B578E`. M4 Pro local SHA-1: `2D26CB1211F32FD4E3C6EF413EC1EDD6F30631AA` (must be created on M4 Pro on next sync).
- This pattern is reusable across any Xcode project that crosses two Macs — strong cookbook candidate.

---

## 2026-04-29 - Mouse-Button Trigger Backend: IOHIDManager (replaces NSEvent for mouse path)

**Context:** W3 architecture verification on the M1 Max (Karabiner-never-installed, no Logi Options+) showed the existing `MouseButtonTriggerMonitor` (NSEvent global monitor) catches standard mouse buttons fine — left/right/middle and the back/forward side buttons all fire — but is *blind* to MX Master 3S extras: the thumb button (large oval), the wheel-mode-shift button, and at least one of the micro-buttons under the horizontal thumb wheel. User confirmed BetterMouse sees these events on the same machine, proving they're reachable from userspace and the limitation is purely the API tier we chose. MousePlus's value proposition is "made for MX Master owners" — shipping without their distinctive buttons would gut the product.

**Why NSEvent misses them:** Logitech ships those buttons on the **HID consumer page** (and likely vendor-specific reports for some). NSEvent's `otherMouseDown`/`otherMouseUp` only surfaces events whose HID origin is the standard Button page (usages 1–N). Consumer-page button presses are never translated into mouse-button NSEvents at all.

**Options Considered:**
1. Stay on NSEvent + document the limitation — "Logi Options+ users get the full button range; without it, only standard buttons work." Cheap but kills the MX Master pitch.
2. CGEventTap at session level (was the v1.1 plan for Karabiner-coexistence) — still doesn't surface consumer-page button presses; same blind spot, just one layer deeper. Doesn't solve this problem.
3. **IOHIDManager** — direct IOKit interface. Sees *every* HID event the device emits, on any usage page (Button, Consumer, vendor-specific). What BetterMouse, SteerMouse, USB Overdrive, and similar utilities use.
4. DriverKit virtual HID device (Karabiner approach) — solves the same problem but is wildly heavier (system extension, separate review/notarization story).

**Decision:** Option 3. Replace the NSEvent backend in `MouseButtonTriggerMonitor` with an IOHIDManager-based one. Keyboard path stays on NSEvent (no equivalent gap there). Sequenced as A → B per user request:

- **A — IOHIDDeviceInspector first.** Small enumerator that lists connected HID mouse devices and dumps every input element (`usagePage`, `usage`, cookie, min/max). Surface as a side panel in the Identify Input window. Runtime-data-driven design: see exactly what *this user's specific MX Master 3S* exposes before committing to the monitor's API surface.
- **B — Then the monitor.** Map button HID usages → existing `TriggerBinding.mouseButton(Int)` enum, sit behind the existing `TriggerMonitor` protocol so AppDelegate / `TriggerEvent` consumers don't change.

**Rationale:** IOHIDManager is the right abstraction tier — high enough to be practical Swift (vs. raw IOKit C), low enough to see everything we need. Permissions are exactly Input Monitoring, which we already require. No DriverKit, no kernel extension, no extra entitlements. Doing A before B prevents premature commitment: we'd rather observe what HID page each silent button uses on this exact device than guess from spec lore.

**Consequences:**
- **Likely retires the planned v1.1 CGEventTap upgrade.** That plan existed to coexist with Karabiner's DriverKit virtual HID device intercepting mouse buttons before NSEvent saw them. IOHIDManager reads from the physical device directly, before the event subsystem layer Karabiner intercepts at — so the Karabiner-installed-user case may "just work" without CGEventTap. Confirm during testing; if true, retire the v1.1 line.
- The Settings/recorder needs no API change — still records button presses by index, the index mapping just sources from a different backend.
- Vendor specifics (HID++ on Logitech) are unlikely to matter for plain button presses (those come through standard pages) but the inspector will tell us if any of the silent buttons require a vendor-page handler.
- One blind spot remains: if a button is fully intercepted by a userspace remapper higher in the stack (Logi Options+ rewriting events at the HID++ layer), even IOHIDManager may not see the *original* press. That's a separate concern about coexistence with vendor software, not about the API.
- Suggested file layout: `Services/HID/IOHIDDeviceInspector.swift` (A), `Services/HID/HIDMouseButtonMonitor.swift` (B). The existing `MouseButtonTriggerMonitor` becomes a thin facade or gets renamed.

---

## 2026-05-30 - Ring UI: Concentric Wedge Menu (supersedes circles-in-a-ring layout)

**Context:** The shipped `RingMenuView` lays items out as discrete circles offset around a single ring, with sub-menus *replacing* the item set (the original "two-level" model from 2026-01-09). The user re-imagined the visual/interaction model from scratch: two concentric rings shown simultaneously (an inner symbol ring + a bigger middle ring), with a third ring expanding on demand. This is a UI-layer redesign, planned in full in `IMPLEMENTATION_PLAN.md` (12 tasks / 5 waves). It runs independent of the HID++ backend track (decision #17) and touches only one line of trigger code (the commit path).

**Design decided (with the user, 2026-05-30):**
1. **Concentric bands by radius:** dead zone (~24pt, cancel/back) → inner symbol-only ring → middle labeled ring → on-demand outer ring. Defaults give every band ≥44pt radial reach (Apple HIG). All radii live in `AppearanceConfig`.
2. **Spoke lock inner↔middle:** both render `N = min(8, max(innerCount, middleCount))` wedges sharing divider lines; the shorter ring pads with dim empty placeholders to preserve symmetry. **Chosen over stretching** because the user explicitly wanted the rings to look aligned/symmetric even at odd counts (e.g. 7/7).
3. **Inner and middle are independent action sets** (confirmed with user) — inner = 6–8 symbol quick-actions, middle = its own labeled commands (direct or expandable). They share *only* spoke geometry; selecting an inner item does **not** repopulate the middle ring.
4. **Outer ring = localized arc**, anchored at the expanded parent wedge's mid-angle, growing both directions toward (but never reaching) a free-floating full circle. Outer items are **direct only** — preserves the long-standing max-depth-3 constraint (extends the 2026-01-09 "two levels" decision to three concentric rings, still bounded).
5. **Blender-style angle hit-testing:** a single container computes `(dist, theta)` from the cursor via `hypot`/`atan2`; selection follows *direction*, not precise wedge-polygon containment. **Chosen over per-wedge `contentShape` hit-testing**, which research flagged as the #1 source of boundary flicker and dead zones in radial menus.
6. **Focus dimming:** inactive branches drop to 0.30 opacity; the live `parent-wedge + outer-arc` stays 1.0. Optional `keepSpokeLit` config keeps the inner wedge at the same angle lit for a continuous center→arc slice.
7. **Dimmed wedges stay clickable (branch-switching)** (confirmed with user): committing a different expandable middle wedge re-points the expansion in place (no explicit collapse step); a direct dimmed wedge fires and closes. Only opacity changes when dimmed — never actionability.

**Rationale:** Matches the "beautiful but functional" direction (2026-01-09) and the Blender/Pieoneer references in CLAUDE.md. The angle-based hit-test and localized-arc expansion are the two choices most load-bearing for the "fast, muscle-memory" feel; both are backed by the pie-menu HCI literature (Callahan et al. CHI 1991; Don Hopkins) and Blender's interaction model. Reuses the entire trigger pipeline, NSPanel host, `RingMenuItem` model, and `ActionService` contract untouched.

**Consequences:**
- `RingMenuView` and `RingViewModel` are rewritten; `RingMenuItem` gains no new fields but is split across two sets in config.
- **Config migration:** `Configuration.items` (flat) splits into `inner` / `middle` sets. Decode shim maps legacy `items` → `middle` (same pattern as the 2026-04-29 `hotkey`→`triggers` migration), so existing config JSON keeps working.
- New files: `Views/Components/AnnularWedge.swift`, `Views/Components/WedgeView.swift`, `Utilities/RadialGeometry.swift`.
- `RingWindowController` needs: fixed square panel size (`2·r3 + pad`, not `fittingSize`), `acceptsFirstMouse` via an `NSHostingView` subclass (first-click-swallow fix for nonactivating panels), `isFloatingPanel`/`hidesOnDeactivate`, and screen-under-cursor centering with `visibleFrame` clamp for multi-display.
- Known correctness risk: SwiftUI's flipped-clockwise `Path.addArc` convention — `AnnularWedge` is verified visually via `/preview` before anything depends on it.
- The 2026-01-09 "Menu Depth: Two Levels" decision is **extended, not contradicted** — still hard-capped, now expressed as three concentric rings (inner + middle + one expansion) rather than ring → replace-with-subring.

---

## 2026-05-30 - Ring spoke-lock: pad shorter band (resolved during `/execute`)

**Context:** Plan §2.1 left this as a "real choice to log": when inner and middle bands have unequal item counts, the locked spoke count is `N = min(8, max(innerCount, middleCount))`, so the shorter band has fewer items than wedges.

**Decision:** The shorter band renders its surplus wedges as **dim empty placeholders** (`WedgeView(isPlaceholder: true)` — faint outline, no glyph, never highlightable, commits to nothing) rather than stretching its items to fill `N` wedges.

**Rationale:** The user explicitly wanted the two rings to look aligned/symmetric (shared divider spokes) even at odd counts. Stretching breaks the shared-spoke geometry; padding preserves it. Placeholders are inert so a cursor landing on one is a no-op (bounds-guarded in `RingViewModel.commitActive`/`item(for:)`).

**Alternative rejected:** Forbid unequal counts in the config UI — too restrictive, and pushes the constraint onto the user instead of the renderer.

---

## 2026-05-30 - Concentric Ring Menu: build-time refinements (during `/execute`)

Recorded so they aren't mistaken for the original spec:
- **Legacy-shim bridging:** `RingViewModel` kept its old API (`items`, `hoveredItem`, `selectItem`, …) as shims through Waves 2–3 so every wave's build gate stayed green, then deleted them in T9 once `RingMenuView` (T6) and `MousePlusApp` (T9) no longer referenced them (grep-confirmed). Avoids a multi-file big-bang that wouldn't compile mid-way.
- **Decode safety:** `Band` gained `Equatable` (for `ActiveSelection`); `AppearanceConfig` gained `Equatable` (for SwiftUI `.onChange`) and a **defaulting custom `init(from:)`** so pre-T11 config snapshots (missing the new band-radius/dim/keepSpokeLit keys) still decode.
- **Hold-release on a different expandable wedge → closes** (release = commit) rather than re-pointing the expansion. In-view mouse/drag branch-switching still re-points in place (decision #7 above holds for the pointer path). Flagged as a refinement candidate pending interactive feel.
- **`DismissMonitor`** uses global `NSEvent` monitors only: a global mouse-down inherently means "outside our overlay" (global monitors don't see our own panel's events), so no panel-frame math. Escape (keyCode 53) collapses an expanded ring to root first, then closes on a second press / when already at root.

---

## 2026-05-30 - HUD Actions Plan: what the ring actually *does* (research-backed, session-c)

**Context:** With the ring *rendering* done (`IMPLEMENTATION_PLAN.md`), an audit found the action
*backend* is mostly stubs — `ActionService.execute` handles only `appSwitch` + `custom`;
`clipboard`/`menuBar` are literal `break` cases, and several default wedges have empty
`actionData` no-ops. Specced five real action types, each source-verified by research agents
(`acsandmann/menuanywhere`, `rxhanson/Rectangle`, live `man screencapture`, Apple docs). Full
spec lives in `docs/HUD_ACTIONS_PLAN.md`; the load-bearing decisions are logged here.

**Decisions:**

1. **Drop `ActionType.clipboard`.** The user is building a separate clipboard manager
   (ClipSmart/Aloft). Bridge to it via an `appSwitch`/`custom` wedge instead of reimplementing
   clipboard inside MousePlus. *Rejected:* a native clipboard action set — duplicates a
   dedicated app for no gain.

2. **Menu-bar mirror = radial top-level → native `NSMenu` handoff** (not a fully ring-rendered
   menu tree). The outer ring shows only the frontmost app's top-level menus (File/Edit/…);
   committing one mirrors that menu's AX subtree into a fresh `NSMenu` and `popUp`s it at the
   cursor. `kAXPressAction` is used only on the final leaf, after `app.activate()` + a 0.1s
   settle. `AccessibilityService` is **`@MainActor`, not an `actor`** (NSMenu/NSMenuItem are
   main-thread-affine; only the slow bulk AX reads go to a background queue). *Rationale:*
   app menus are deep/dynamic trees and the ring is depth-capped at 3 — radial is a fast index,
   AppKit handles the lists. Matches menuanywhere's proven path. *Rejected:* (A) AXPress the
   live bar item (opens at the menu bar, flaky in fullscreen); (B2) recurse menus into rings
   (huge AX traffic, fights dynamic menus). *Deferred:* a search palette (NOT in menuanywhere's
   current source — would be net-new).

3. **Window snapping = own middle wedge → outer arc of 8 directions**, in an `actor
   WindowService`. Ports Rectangle's two non-obvious hacks verbatim: the
   `AXEnhancedUserInterface` toggle (off-before-move, restore-after, for Electron/Catalyst
   apps) and the **size→position→size** set order (beats display + min-size clamping). The AX
   y-flip pivots about the **primary** screen's `frame.maxY` (`NSScreen.screens[0]`), never the
   target screen's — the #1 multi-monitor bug. `_AXUIElementGetWindow` is private → not used.
   *Rationale:* 8 spokes = 8 screen directions is the most radial-native feature; self-contained.

4. **App switcher = self-tracked MRU.** No public app z-order/MRU API exists, so observe
   `NSWorkspace.didActivateApplicationNotification` from app launch (not ring-open) to order
   apps most-recent-first (alphabetical tie-break). The existing macOS-14 `app.activate()` call
   is already correct (`.activateIgnoringOtherApps` is deprecated/no-op). **Real app icons via
   an `IconSource` enum** passed to `WedgeView` + a side dictionary keyed by item id — `NSImage`
   is **never** put in the `Codable` `RingMenuItem` model (static config stays SF-Symbol
   strings). *Rejected:* resolving icons in SwiftUI `body` (re-runs, blocks main) and storing
   `NSImage` on the model (breaks `Codable`/`Hashable`).

5. **System toggles = dedicated `ActionType.systemToggle` with a curated enum** (not overloaded
   `custom`) — no arbitrary-shell injection surface, typed config UI, per-action TCC reasoning.
   Mechanism is `Process`→`/usr/bin/osascript`, **not `NSAppleScript`** (which must run on and
   blocks the main thread; wrong from an `actor`). Lock screen uses **CGEvent ⌃⌘Q**, not the
   private `SACLockScreenImmediate`. v1 set = dark mode, display sleep, screen saver,
   volume/mute, lock screen, empty trash (confirm-gated). **Deferred:** DND/Focus (no reliable
   public *setter* — the `ncprefs`/`controlcenter`+killall hack is broken post-Monterey;
   `INFocusStatusCenter` is read-only) and brightness (private `DisplayServices*` only, or
   jittery CGEvent keys). TCC must be **pre-primed in Settings**, never prompted mid-gesture.

6. **Screenshots = interactive `screencapture` modes only for v1.** Interactive `-i`/`-U`
   (user-driven selection UI) require **no Screen-Recording TCC** attributed to MousePlus — the
   user's drag *is* the consent. Silent full-screen/video capture *does* need the grant, so
   it's deferred behind explicit UX. New `ActionType.screenshot` + `ShotMode` enum; dismiss the
   ring (`requestClose` → `Task.yield()`) before capturing. `ScreenCaptureKit` is reserved for a
   future silent / sandboxed backend behind the same `ShotMode` abstraction.

7. **Product — sandbox incompatibility (reinforces direct distribution).** Features 2, 3, and 5
   (cross-app AX control; shelling to system binaries; scripting System Events/Finder) are
   **fundamentally incompatible with the App Store sandbox.** This hardens the already-chosen
   direct-distribution / GPLv3 path. Each feature stays behind its own service so a future
   sandboxed target can compile them out; only the app switcher (4) and interactive screenshots
   (6, via an SCK backend swap) could survive a sandbox.

**Shared foundation (build once, all five depend on it):** extend `ActionType`; make
`RingViewModel.expand()` async with a stale-expansion guard (dynamic outer ring); the
`IconSource` pattern; one reusable Accessibility-TCC status/prompt flow; the
dismiss-before-action seam (`requestClose` at `RingViewModel.swift:132`).

**Build order:** foundation (~1–1.5d) → window snap (~2d) → screenshots (~0.5–1d) → menu
mirror (~1.5–2d) → app switcher (~1.5–2d) → system toggles (~3.5–4d). ≈10–13 dev-days at v1.

---

*Add decisions as they are made. Future-you will thank present-you.*


## 2026-05-30 - App-Aware Command Rings: min target, AX-press, center-search (planned)

**Context:** User asked for app-specific shortcuts in the ring (top ~8 per app), a "pages" overflow in RING 3, and a search palette for all current-app commands — i.e. Paletro-class capability in the HUD. Planned in `APP_COMMANDS_PLAN.md` (builds on `HUD_ACTIONS_PLAN.md` Feature A). Backed by 5 research agents + Tahoe adoption research.

**Decisions:**

1. **Min deployment target stays macOS 14; Liquid Glass is conditional, not required.** `glassEffect`/`GlassEffectContainer` are `@available(macOS 26.0,*)` — neither 14 nor 15 has them, so the choice is min-26 (all-in glass) vs conditional. Adoption research (2026-05-30): Tahoe ~50% overall, higher in MousePlus's indie-dev/recent-hardware segment (TelemetryDeck skews that way), but ~half of users remain on Sequoia/Sonoma. → ship `if #available(macOS 26)` glass with a `.ultraThinMaterial` fallback. 14-vs-15 is independent of glass and held at 14 (both still get security updates as of May 2026).

2. **App commands fire via AX press (`.menuCommand`/`kAXPressAction`), not synthesized keystrokes.** AX works for commands that have *no* keyboard shortcut at all — the whole point of surfacing an app's menu. CGEvent keystroke kept as a secondary `.keyShortcut` path only.

3. **Center hub owns search; RING 2 owns sources.** Search is reached only via the center dead-zone tap (opens a separate non-activating `NSPanel` palette), never duplicated as a RING 2 wedge. RING 1/2 stay app-stable for muscle memory; only RING 3 is app-aware.

4. **Search is self-curating (pin-or-execute).** A palette result can fire immediately *or* be pinned into the frontmost app's `AppProfile.ring3Shortcuts` — the ring learns each app over time. This is the differentiator vs Paletro (a list that only searches).

5. **Pagination preserves muscle memory only via stable (page, angle) mapping.** Most-used on page 1; overflow on stable later pages; deep overflow defers to search rather than growing pages.

**Why it matters:** keeps the "made for power users on modern Macs" pitch (glass) without abandoning the ~half still on Sonoma/Sequoia; the Tahoe legibility backlash is a hard design constraint for a HUD floating over arbitrary content (use `.regular` not `.clear`, vibrant foreground, explicit stroke, test under Reduce Transparency / Increase Contrast).

**Consequences:** new `AccessibilityService` (shared with Feature A), `FrontmostAppService`, `CommandPalettePanel`; `Configuration.appProfiles`; `RingMenuItem.dynamicSource` gains `.appShortcuts`; `ActionType` gains `.menuCommand`(+`.keyShortcut`). Sandbox/MAS must re-validate cross-app AX reads before any App Store build.

---

## 2026-07-07 - Menu Editor Persistence Safety Model

**Context:** The 2026-07-07 code review of the menu editor (Waves 1–4) found three data-loss paths sharing one root cause: config writes trusted stale or unverified state. (a) Autosave merged edited rings into a `baseConfig` snapshot taken at window-open, silently reverting appearance/trigger changes made in Settings while the editor was open. (b) `(try? load()) ?? Configuration()` treated a corrupt-but-present `config.json` like a missing one, so the editor filled with sample defaults which autosave then persisted over the user's real (recoverable) file. (c) Closing the window before the first async load completed flushed a still-empty model merged into a default config — wiping rings *and* the trigger binding.

**Options Considered:**
1. Single shared `ConfigurationService` actor with read-modify-write inside the actor — cleanest concurrency story, but a wider refactor touching Settings, editor, and AppDelegate.
2. Fresh-disk-read merge base + load-state save gate per writer — small, local, matches the pattern `RingAppearanceSettingsView` already established.
3. Keep snapshots but push live updates between windows — most machinery, still racy.

**Decision:** Option 2, as two rules for anyone writing `config.json`:
1. **Merge into a fresh read, never a cached snapshot** — re-read the on-disk config at save time and swap in only your own section (editor: rings; appearance tab: appearance).
2. **Saves are gated on a successful load** — the editor's `LoadState` (`pending/loaded/failed`) blocks all saves until the file has been read successfully once; a decode failure locks saving and surfaces an `NSAlert` instead of "recovering" with defaults.

**Rationale:** Autosave inverts the usual safety calculus — loading defaults *is itself a write* 400ms later, so the guard must live at load time. `ConfigurationService.load()` already distinguishes the two cases (missing file → defaults without throwing; present-but-undecodable → throws); `try?` was erasing exactly the distinction that separates "fresh install" from "user data at risk". Hand-editing `config.json` is established practice in this project, so decode failure is a realistic input, not a theoretical one.

**Consequences:** Every future config-writing surface (onboarding, import, profile switcher) must follow both rules. Option 1 (shared actor with internal read-modify-write) remains the right endpoint if writers multiply; revisit when a third writer appears. Related fix in the same review: the close-flush now lives in `saveTask` and reopen awaits it, so close→quick-reopen can't resurrect stale rings over a just-flushed edit.

---

## T11 — Invalid SF Symbol handling: persist-with-placeholder + defensive render (2026-07-07)

**Context:** The Menu Items editor lets users type a free-form SF Symbol name for a wedge's icon. `Image(systemName:)` is non-failable — an unknown name renders as *nothing*, which on the icon-only inner ring is an invisible, unusable wedge. The editor autosaves (400 ms debounce) with no Save button, and `SymbolField` already flags invalid names in red. Open question from `MENU_EDITOR_PLAN.md` §5A: what should an invalid name do to the persisted config and the live ring?

**Options Considered:**
1. **Keep-last-valid** — the model accepts a name only once it's a real symbol; while the field shows invalid text, the ring keeps the previous icon. Cleanest data on disk, but needs a draft-text layer inside `SymbolField` and is ambiguous when the field is cleared.
2. **Revert-on-blur** — free typing while focused; on blur an invalid name snaps back to the last valid one. Few bad states on disk, but the in-progress typo silently vanishes (reads as lost work) and still needs a persist-side guard for the debounce window.
3. **Persist-with-placeholder + defensive render** — the model keeps the raw text (field stays red so the user can fix it); every `Image(systemName:)` that draws a user-supplied icon substitutes a known-safe placeholder for any unknown/empty name at draw time.

**Decision:** Option 3. Input can't be gated at the keystroke (a valid name like `star.fill` is typed through invalid prefixes `s`, `st`, …) and there's no Save button to gate (autosave), so the "no blank wedge" guarantee lives at the **render layer**, not on input. New `SFSymbol` util is the single source of truth (`isValid` / `placeholder` = `questionmark.circle` / `resolved`); `WedgeView` and `SlotEditorForm` render `SFSymbol.resolved(icon)`, and `SymbolField.isValidSymbol` forwards to `SFSymbol.isValid` so the field's red-flag rule and the ring's fallback can never disagree.

**Rationale:** One render-layer fix covers three surfaces at once — the live ring, the editor's WYSIWYG preview (it embeds the real `RingMenuView` rather than reimplementing it), and any config source (hand-edited `config.json`, a file from an older build). The placeholder itself must always be valid (it *is* the backstop), so it's a long-standing, universally available symbol, hardcoded, never user-supplied. Preserving the raw text (vs revert-on-blur) means nothing the user typed is destroyed; keeping the model dumb (vs keep-last-valid) adds no draft-state layer and leaves autosave untouched.

**Consequences:** A known-invalid icon string can reach disk, but it round-trips harmlessly (the renderer substitutes the placeholder) and the editor keeps showing it red until fixed. Any future icon-render site that draws a user-supplied name must also route through `SFSymbol.resolved()` — the guarantee is per-call-site, not global. If icon rendering ever centralizes (e.g. a single `RingGlyph` view), fold the resolve into it.

---

## App-shell access for a menu-bar-only app: global ⌥⌘, Settings hotkey + decode-tolerant `TriggersConfig` (2026-07-08)

**Context:** MousePlus is `LSUIElement` (no dock icon). The "Identify Input" diagnostic window was being auto-opened at every launch purely as a workaround for the M1 Max invisible-menu-bar-icon mystery — on that Mac it was the *only* doorway to Settings (via its embedded "Settings…" button). Removing that debug auto-open (it's a developer surface) would strand the M1 Max with no way into Preferences. So a reliable, always-present Settings entry point was needed first, and adding it meant introducing a new field to the on-disk `TriggersConfig`.

**Options Considered (Settings entry point):**
1. **Relaunch-opens-Settings** — `applicationShouldHandleReopen(_:hasVisibleWindows:)`; double-clicking the running app opens Preferences. Standard menu-bar-app idiom, zero new UI.
2. **Dedicated global hotkey** (default ⌥⌘,) via a `KeyboardTriggerMonitor`, rebindable in Settings ▸ Triggers.
3. **Chase the root-cause** invisible-`NSStatusItem` bug on the M1 Max. Open-ended, higher risk.

**Decision:** Option 2 (user's choice) — a rebindable global hotkey, shipped **bound** to ⌥⌘,. Explicitly **not** plain ⌘,. Separately, `TriggersConfig` gains a custom **decode-tolerant** `init(from:)`.

**Rationale:**
- **Why ⌥⌘, not ⌘,:** `NSEvent.addGlobalMonitorForEvents` is *observe-only* — it never consumes the event. A global `⌘,` watcher would therefore open MousePlus Settings *on top of* whatever the frontmost app does with `⌘,` (nearly every app maps it to its own Preferences). ⌥⌘, is rarely bound, so no double-fire.
- **Why decode-tolerant:** `TriggersConfig` relied on *synthesized* `Codable`, which throws `keyNotFound` for any missing key. Naively adding `openSettings` would make **every existing `config.json` fail to decode** — the same synthesized-`Codable` data-loss class the persistence-safety decision (2026-07-07) already fights. `decodeIfPresent ?? default` per field is the project's established tolerance pattern (`Configuration`, `AppearanceConfig` both do it).
- **Ships bound (unlike ring triggers):** the ring triggers ship unbound by design (onboarding sets them); the Settings hotkey is a *safety net*, so a default-off value would defeat its purpose. Via the decode default, existing users inherit ⌥⌘, automatically.

**Consequences:** Any future field added to an evolving on-disk `Codable` model must use per-field `decodeIfPresent`-with-default — do **not** rely on synthesized `Codable` for models that gain keys over time (reusable gotcha; cookbook candidate). Reaching Settings *from the HUD itself* (a ring wedge) is still a gap — the user's actual instinct was to look for a Settings icon in the ring — so the next step is a new `ActionType.openSettings` that drops a Settings wedge into the menu. The global monitor is re-armed after the Accessibility grant (global monitors don't retroactively start firing) and on rebind, mirroring `setupTriggers`/`applyTriggers`.

---
