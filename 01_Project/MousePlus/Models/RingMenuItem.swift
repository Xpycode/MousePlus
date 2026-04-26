import Foundation

/// A single item in the ring menu
struct RingMenuItem: Identifiable, Codable, Hashable {
    let id: UUID
    var label: String
    var icon: String          // SF Symbol name or app bundle identifier
    var actionType: ActionType
    var actionData: String    // App bundle ID, command, etc.
    var subItems: [RingMenuItem]?
    var keyboardShortcut: String?

    init(
        id: UUID = UUID(),
        label: String,
        icon: String,
        actionType: ActionType,
        actionData: String = "",
        subItems: [RingMenuItem]? = nil,
        keyboardShortcut: String? = nil
    ) {
        self.id = id
        self.label = label
        self.icon = icon
        self.actionType = actionType
        self.actionData = actionData
        self.subItems = subItems
        self.keyboardShortcut = keyboardShortcut
    }

    var hasSubItems: Bool {
        guard let subItems else { return false }
        return !subItems.isEmpty
    }
}

// MARK: - Sample Data

extension RingMenuItem {
    static let sampleItems: [RingMenuItem] = [
        RingMenuItem(
            label: "Apps",
            icon: "square.grid.2x2",
            actionType: .appSwitch,
            subItems: [
                RingMenuItem(label: "Safari", icon: "safari", actionType: .appSwitch, actionData: "com.apple.Safari"),
                RingMenuItem(label: "Finder", icon: "folder", actionType: .appSwitch, actionData: "com.apple.finder"),
                RingMenuItem(label: "Terminal", icon: "terminal", actionType: .appSwitch, actionData: "com.apple.Terminal"),
            ]
        ),
        RingMenuItem(
            label: "Clipboard",
            icon: "doc.on.clipboard",
            actionType: .clipboard
        ),
        RingMenuItem(
            label: "Menu",
            icon: "menubar.rectangle",
            actionType: .menuBar
        ),
        RingMenuItem(
            label: "Custom",
            icon: "terminal",
            actionType: .custom,
            actionData: "open -a Calculator"
        ),
    ]
}
