import MacUIKitSettings

enum SettingsSection: String, SettingsTab {
    case general
    case triggers
    case ringAppearance
    case menuItems

    var title: String {
        switch self {
        case .general: "General"
        case .triggers: "Triggers"
        case .ringAppearance: "Ring Appearance"
        case .menuItems: "Menu Items"
        }
    }

    var systemImage: String {
        switch self {
        case .general: "gear"
        case .triggers: "cursorarrow.click.2"
        case .ringAppearance: "circle.dashed"
        case .menuItems: "circle.hexagongrid"
        }
    }

    var placement: SettingsTabPlacement {
        self == .general ? .general : .standard
    }
}
