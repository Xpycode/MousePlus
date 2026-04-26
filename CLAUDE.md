# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## First Step - Always

**Read `docs/00_base.md` before doing anything else.** It contains the complete Directions system for AI-assisted development.

---

## Project: MousePlus

Radial quick-access menu for macOS - triggered by hotkey, appears at pointer location.

### Quick Facts

- **Platform:** macOS 14+ (Sonoma)
- **UI Framework:** SwiftUI (views) + AppKit (window management)
- **Distribution:** Eventually App Store / notarized
- **Permissions Required:** Accessibility (for menu bar access)

### Tech Stack

| Component | Technology |
|-----------|------------|
| App shell | SwiftUI App + NSStatusItem (menu bar) |
| Ring overlay | NSPanel + SwiftUI content |
| Global hotkey | NSEvent.addGlobalMonitorForEvents |
| Menu bar access | AXUIElement API |
| App switching | NSWorkspace.runningApplications |
| Config storage | JSON file (Application Support) |
| Settings storage | UserDefaults |

### Project Structure

```
MousePlus/
├── MousePlusApp.swift       # Entry point, menu bar setup
├── Models/
│   ├── RingMenuItem.swift        # Menu item definition (Codable)
│   ├── ActionType.swift          # Enum: appSwitch, clipboard, menuBar, custom
│   └── Configuration.swift       # Full menu config
├── ViewModels/
│   ├── RingViewModel.swift       # Ring state, selection (@MainActor, @Observable)
│   └── SettingsViewModel.swift   # Settings state
├── Views/
│   ├── RingMenuView.swift        # The radial menu UI
│   ├── RingItemView.swift        # Individual pie slice
│   ├── SettingsView.swift        # Configuration UI
│   └── Components/
├── Controllers/
│   ├── MenuBarController.swift   # NSStatusItem management
│   └── RingWindowController.swift # NSPanel lifecycle
├── Services/
│   ├── HotkeyService.swift       # Global shortcut detection
│   ├── ActionService.swift       # Execute actions (actor)
│   ├── AccessibilityService.swift # AXUIElement for menu access
│   └── ConfigurationService.swift # Load/save config (actor)
└── Utilities/
    └── Extensions.swift
```

### Architecture Rules

- **ViewModels** are `@MainActor` and `@Observable`
- **Services** are `actor` types (thread-safe)
- **NSPanel** hosts SwiftUI content via NSHostingView
- **No dock icon** - set LSUIElement = YES in Info.plist

### Key Features (v1)

1. Two-level ring menu (primary → sub-ring)
2. Both trigger modes: hold+release AND tap+click
3. Action types: app switcher, clipboard, menu bar access, custom commands
4. User-selectable animation (instant vs animated)
5. Multiple dismiss methods: click outside, Escape, release hotkey

### References

- [menuanywhere](https://github.com/acsandmann/menuanywhere) - Menu bar access reference
- [Pieoneer](https://apps.apple.com/us/app/pieoneer/id6739781207) - Visual inspiration
- Blender pie menus - Interaction inspiration
