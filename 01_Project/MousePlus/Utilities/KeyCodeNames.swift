import AppKit

/// Human-readable names for keyboard virtual key codes and mouse button numbers,
/// plus a `displayString` for a `TriggerBinding`. Used by the Triggers settings tab
/// to render what a recorded binding maps to ("Ctrl+Opt+F5", "Middle Click", "Button 4 (Back)").
enum KeyCodeNames {
    /// Common macOS virtual key codes (`kVK_*`) → display label. Anything not listed
    /// falls back to "Key <code>" so an unusual key still shows something sensible.
    static let map: [UInt16: String] = [
        // Letters
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V",
        11: "B", 12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T",
        31: "O", 32: "U", 34: "I", 35: "P", 37: "L", 38: "J", 40: "K",
        45: "N", 46: "M",
        // Number row
        18: "1", 19: "2", 20: "3", 21: "4", 22: "6", 23: "5",
        25: "9", 26: "7", 28: "8", 29: "0",
        // Punctuation
        24: "=", 27: "-", 30: "]", 33: "[", 39: "'", 41: ";",
        42: "\\", 43: ",", 44: "/", 47: ".", 50: "`",
        // Whitespace / editing
        36: "Return", 48: "Tab", 49: "Space", 51: "Delete", 53: "Escape",
        // Function keys
        96: "F5", 97: "F6", 98: "F7", 99: "F3", 100: "F8", 101: "F9", 103: "F11",
        105: "F13", 107: "F14", 109: "F10", 111: "F12", 113: "F15",
        118: "F4", 120: "F2", 122: "F1", 123: "←", 124: "→", 125: "↓", 126: "↑",
        // Keypad / nav
        114: "Help", 115: "Home", 116: "Page Up", 117: "Fwd Delete",
        119: "End", 121: "Page Down",
    ]

    static func key(_ code: UInt16) -> String {
        map[code] ?? "Key \(code)"
    }

    /// Modifier names as text in canonical Apple order ("Ctrl+Opt+Shift+Cmd"), or ""
    /// when none. Text (not glyphs) because the ⌃⌥⇧⌘ glyphs render too close together
    /// to read at a glance in the Triggers settings tab.
    static func modifiers(_ raw: UInt) -> String {
        let m = NSEvent.ModifierFlags(rawValue: raw)
        var parts: [String] = []
        if m.contains(.control)  { parts.append("Ctrl") }
        if m.contains(.option)   { parts.append("Opt") }
        if m.contains(.shift)    { parts.append("Shift") }
        if m.contains(.command)  { parts.append("Cmd") }
        return parts.joined(separator: "+")
    }

    /// macOS `buttonNumber` → friendly name. 0/1/2 are fixed; 3/4 are conventionally
    /// the side back/forward buttons on extended mice (others are vendor-defined).
    static func mouseButton(_ n: Int) -> String {
        switch n {
        case 0: return "Left Click"
        case 1: return "Right Click"
        case 2: return "Middle Click"
        case 3: return "Button 4 (Back)"
        case 4: return "Button 5 (Forward)"
        default: return "Button \(n + 1)"
        }
    }
}

extension TriggerBinding {
    /// One-line label for the current binding, e.g. "Ctrl+Opt+F5", "Middle Click", "Not set".
    var displayString: String {
        switch self {
        case .none:
            return "Not set"
        case let .keyboard(keyCode, modifiers, _):
            let mods = KeyCodeNames.modifiers(modifiers)
            let key = KeyCodeNames.key(keyCode)
            return mods.isEmpty ? key : "\(mods)+\(key)"
        case let .mouseButton(buttonNumber, _):
            return KeyCodeNames.mouseButton(buttonNumber)
        }
    }

    /// The interpretation mode carried by this binding (defaults to `.holdRelease` when unset).
    var mode: TriggerMode {
        switch self {
        case .none: return .holdRelease
        case let .keyboard(_, _, mode): return mode
        case let .mouseButton(_, mode): return mode
        }
    }

    /// Return a copy of this binding with a different `mode` (no-op for `.none`).
    func withMode(_ mode: TriggerMode) -> TriggerBinding {
        switch self {
        case .none:
            return .none
        case let .keyboard(keyCode, modifiers, _):
            return .keyboard(keyCode: keyCode, modifiers: modifiers, mode: mode)
        case let .mouseButton(buttonNumber, _):
            return .mouseButton(buttonNumber: buttonNumber, mode: mode)
        }
    }
}
