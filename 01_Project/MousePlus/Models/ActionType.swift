import Foundation

/// Types of actions that can be triggered from the ring menu
enum ActionType: String, Codable, CaseIterable {
    case appSwitch      // Switch to/launch an application
    case clipboard      // Clipboard operations (copy, paste, history)
    case menuBar        // Access current app's menu bar
    case custom         // Custom command or shortcut

    var displayName: String {
        switch self {
        case .appSwitch: "App Switcher"
        case .clipboard: "Clipboard"
        case .menuBar: "Menu Bar"
        case .custom: "Custom"
        }
    }

    var systemImage: String {
        switch self {
        case .appSwitch: "square.grid.2x2"
        case .clipboard: "doc.on.clipboard"
        case .menuBar: "menubar.rectangle"
        case .custom: "terminal"
        }
    }
}
