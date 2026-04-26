import Foundation

/// Full configuration for the ring menu
struct Configuration: Codable {
    var items: [RingMenuItem]
    var hotkey: HotkeyConfig
    var appearance: AppearanceConfig
    var behavior: BehaviorConfig

    init(
        items: [RingMenuItem] = RingMenuItem.sampleItems,
        hotkey: HotkeyConfig = .default,
        appearance: AppearanceConfig = .default,
        behavior: BehaviorConfig = .default
    ) {
        self.items = items
        self.hotkey = hotkey
        self.appearance = appearance
        self.behavior = behavior
    }
}

/// Hotkey configuration
struct HotkeyConfig: Codable {
    var keyCode: UInt16
    var modifiers: UInt        // NSEvent.ModifierFlags raw value

    static let `default` = HotkeyConfig(
        keyCode: 49,           // Space
        modifiers: 1 << 20     // Control
    )
}

/// Visual appearance settings
struct AppearanceConfig: Codable {
    var ringRadius: Double
    var itemSize: Double
    var animationEnabled: Bool
    var animationDuration: Double

    static let `default` = AppearanceConfig(
        ringRadius: 120,
        itemSize: 60,
        animationEnabled: true,
        animationDuration: 0.15
    )
}

/// Interaction behavior settings
struct BehaviorConfig: Codable {
    var holdToActivate: Bool       // Hold hotkey + release to select
    var tapToActivate: Bool        // Tap hotkey, click to select
    var dismissOnClickOutside: Bool
    var dismissOnEscape: Bool

    static let `default` = BehaviorConfig(
        holdToActivate: true,
        tapToActivate: true,
        dismissOnClickOutside: true,
        dismissOnEscape: true
    )
}
