import Foundation

/// A single item in the ring menu
struct RingMenuItem: Identifiable, Codable, Hashable {
    let id: UUID
    var label: String
    var icon: String          // SF Symbol name or app bundle identifier
    var actionType: ActionType
    var actionData: String    // App bundle ID, command, etc.
    var subItems: [RingMenuItem]?
    var keystrokePayload: KeystrokePayload?

    init(
        id: UUID = UUID(),
        label: String,
        icon: String,
        actionType: ActionType,
        actionData: String = "",
        subItems: [RingMenuItem]? = nil,
        keystrokePayload: KeystrokePayload? = nil
    ) {
        self.id = id
        self.label = label
        self.icon = icon
        self.actionType = actionType
        self.actionData = actionData
        self.subItems = subItems
        self.keystrokePayload = keystrokePayload
    }

    var hasSubItems: Bool {
        guard let subItems else { return false }
        return !subItems.isEmpty
    }

    private enum CodingKeys: String, CodingKey {
        case id, label, icon, actionType, actionData, subItems, keystrokePayload
        case keyboardShortcut
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        label = try container.decode(String.self, forKey: .label)
        icon = try container.decode(String.self, forKey: .icon)
        actionType = try container.decode(ActionType.self, forKey: .actionType)
        actionData = try container.decodeIfPresent(String.self, forKey: .actionData) ?? ""
        subItems = try container.decodeIfPresent([RingMenuItem].self, forKey: .subItems)

        if let canonical = try container.decodeIfPresent(KeystrokePayload.self, forKey: .keystrokePayload) {
            keystrokePayload = canonical
        } else if let legacy = try container.decodeIfPresent(String.self, forKey: .keyboardShortcut),
                  !legacy.isEmpty {
            keystrokePayload = .migratingLegacy(legacy)
        } else {
            keystrokePayload = nil
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(label, forKey: .label)
        try container.encode(icon, forKey: .icon)
        try container.encode(actionType, forKey: .actionType)
        try container.encode(actionData, forKey: .actionData)
        try container.encodeIfPresent(subItems, forKey: .subItems)
        try container.encodeIfPresent(keystrokePayload, forKey: .keystrokePayload)
        // `keyboardShortcut` is decode-only and intentionally retired.
    }
}

// MARK: - Sample Data

extension RingMenuItem {
    /// Inner band — symbol-only quick actions (labels are not rendered in the inner ring,
    /// but kept for accessibility / settings UI). Independent of `sampleItems` (middle band).
    static let sampleInnerItems: [RingMenuItem] = [
        RingMenuItem(
            label: "Copy",
            icon: "doc.on.doc",
            actionType: .sendKeystroke,
            keystrokePayload: .key(keyCode: 8, modifiers: 1 << 20)
        ),
        RingMenuItem(
            label: "Paste",
            icon: "doc.on.clipboard",
            actionType: .sendKeystroke,
            keystrokePayload: .key(keyCode: 9, modifiers: 1 << 20)
        ),
        RingMenuItem(
            label: "Mission Control",
            icon: "rectangle.3.group",
            actionType: .custom,
            actionData: "open -b com.apple.exposelauncher"
        ),
        RingMenuItem(
            label: "Spotlight",
            icon: "magnifyingglass",
            actionType: .sendKeystroke,
            keystrokePayload: .key(keyCode: 49, modifiers: 1 << 20)
        ),
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
