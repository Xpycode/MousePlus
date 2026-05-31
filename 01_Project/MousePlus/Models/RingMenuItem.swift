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
    /// Inner band — symbol-only quick actions (labels are not rendered in the inner ring,
    /// but kept for accessibility / settings UI). Independent of `sampleItems` (middle band).
    static let sampleInnerItems: [RingMenuItem] = [
        RingMenuItem(label: "Copy", icon: "doc.on.doc", actionType: .custom, actionData: ""),
        RingMenuItem(label: "Paste", icon: "doc.on.clipboard", actionType: .custom, actionData: ""),
        RingMenuItem(label: "Mission Control", icon: "rectangle.3.group", actionType: .custom, actionData: ""),
        RingMenuItem(label: "Spotlight", icon: "magnifyingglass", actionType: .custom, actionData: ""),
    ]

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
            label: "Snap",
            icon: "rectangle.split.2x1",
            actionType: .windowSnap,    // parent marker; commit expands to the zone arc
            subItems: SnapZone.allCases.map { zone in
                RingMenuItem(
                    label: zone.displayName,
                    icon: zone.systemImage,
                    actionType: .windowSnap,
                    actionData: zone.rawValue
                )
            }
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
