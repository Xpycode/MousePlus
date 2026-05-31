import Foundation

/// Types of actions that can be triggered from the ring menu.
///
/// Dedicated cases (rather than overloading `.custom`) keep the config UI typed,
/// avoid a shell-injection surface for system actions, and let each action carry
/// a type-safe payload in `RingMenuItem.actionData` (see `HUD_ACTIONS_PLAN.md` §1.1).
///
/// ## Dropped: `clipboard`
/// The old `.clipboard` case was removed (deferred to the user's separate clipboard
/// app; bridge via `.appSwitch`/`.custom`). Because `RingMenuItem` is `Codable` and
/// existing `config.json` files on disk still contain `"actionType": "clipboard"`,
/// removing the case from a plain `String`-rawValue enum would make those configs
/// fail to decode — taking the saved *trigger binding* down with them. The custom
/// `init(from:)` below maps any unknown/legacy raw value (including `"clipboard"`) to
/// `.custom`, which is a no-op when `actionData` is empty — exactly how the old
/// clipboard stub behaved. So old configs keep loading; the items just become inert
/// custom no-ops until re-bound.
enum ActionType: String, Codable, CaseIterable {
    case appSwitch      // Switch to/launch an application
    case menuBar        // Access current app's menu bar (HUD Feature A)
    case windowSnap     // Snap frontmost window to a screen zone (HUD Feature B); actionData = SnapZone.rawValue
    case systemToggle   // One-shot system action (HUD Feature D); actionData = SystemToggle.rawValue — not yet implemented
    case screenshot     // Interactive screen capture (HUD Feature E); actionData = ShotMode.rawValue — not yet implemented
    case custom         // Custom command or shortcut

    var displayName: String {
        switch self {
        case .appSwitch: "App Switcher"
        case .menuBar: "Menu Bar"
        case .windowSnap: "Window Snap"
        case .systemToggle: "System Toggle"
        case .screenshot: "Screenshot"
        case .custom: "Custom"
        }
    }

    var systemImage: String {
        switch self {
        case .appSwitch: "square.grid.2x2"
        case .menuBar: "menubar.rectangle"
        case .windowSnap: "rectangle.split.2x1"
        case .systemToggle: "switch.2"
        case .screenshot: "camera.viewfinder"
        case .custom: "terminal"
        }
    }

    // MARK: - Codable (legacy-tolerant)

    /// Decodes the raw string, mapping any unrecognized value (notably the dropped
    /// `"clipboard"`) to `.custom` so older/forward configs never fail to decode.
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = ActionType(rawValue: raw) ?? .custom
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}
