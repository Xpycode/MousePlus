import Foundation

/// An action persisted in a ring-menu item. Unknown strings are represented
/// explicitly so saving a configuration written by a newer version is lossless.
enum ActionType: Codable, Hashable, CaseIterable {
    case appSwitch
    case menuBar
    case windowSnap
    case systemToggle
    case screenshot
    case sendKeystroke
    case custom
    case unavailable(String)

    /// Every action name understood by this version, including unavailable ones.
    static let allCases: [ActionType] = [
        .appSwitch, .menuBar, .windowSnap, .systemToggle, .screenshot,
        .sendKeystroke, .custom,
    ]

    /// Actions offered when creating or changing an action in the editor.
    static let selectableCases: [ActionType] = [
        .appSwitch, .windowSnap, .sendKeystroke, .custom,
    ]

    init(rawValue: String) {
        switch rawValue {
        case "appSwitch": self = .appSwitch
        case "menuBar": self = .menuBar
        case "windowSnap": self = .windowSnap
        case "systemToggle": self = .systemToggle
        case "screenshot": self = .screenshot
        case "sendKeystroke": self = .sendKeystroke
        case "custom": self = .custom
        default: self = .unavailable(rawValue)
        }
    }

    var rawValue: String {
        switch self {
        case .appSwitch: "appSwitch"
        case .menuBar: "menuBar"
        case .windowSnap: "windowSnap"
        case .systemToggle: "systemToggle"
        case .screenshot: "screenshot"
        case .sendKeystroke: "sendKeystroke"
        case .custom: "custom"
        case .unavailable(let value): value
        }
    }

    var isSelectable: Bool { Self.selectableCases.contains(self) }

    var displayName: String {
        switch self {
        case .appSwitch: "App Switcher"
        case .menuBar: "Menu Bar"
        case .windowSnap: "Window Snap"
        case .systemToggle: "System Toggle"
        case .screenshot: "Screenshot"
        case .sendKeystroke: "Send Keystroke"
        case .custom: "Custom"
        case .unavailable(let value): "Unavailable (\(value))"
        }
    }

    var systemImage: String {
        switch self {
        case .appSwitch: "square.grid.2x2"
        case .menuBar: "menubar.rectangle"
        case .windowSnap: "rectangle.split.2x1"
        case .systemToggle: "switch.2"
        case .screenshot: "camera.viewfinder"
        case .sendKeystroke: "keyboard"
        case .custom: "terminal"
        case .unavailable: "questionmark.circle"
        }
    }

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self.init(rawValue: raw)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}
