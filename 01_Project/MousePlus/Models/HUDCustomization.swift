import Foundation

/// Controls whether a ring derives its geometry from its items or reserves a
/// user-selected number of angular positions.
enum SlotCountMode: String, Codable, CaseIterable, Sendable {
    case auto
    case fixed
}

/// Invocation-level policy for presenting configured outer/submenu items.
enum OuterRingVisibility: String, Codable, CaseIterable, Sendable {
    case alwaysVisible
    case revealBeyondInnerRing
    case alwaysHidden
}

/// Orientation of an icon relative to its wedge. Labels always remain upright.
enum IconOrientation: String, Codable, CaseIterable, Sendable {
    case upright
    case radial
    case tangential
}

/// Layout settings owned independently by each top-level ring.
struct HUDRingLayout: Codable, Equatable, Sendable {
    static let supportedSlotRange = 1...8

    var slotCountMode: SlotCountMode
    var fixedSlotCount: Int
    /// Clockwise degrees. Canonical values are in `0..<360`.
    var angularOffset: Double

    init(
        slotCountMode: SlotCountMode = .auto,
        fixedSlotCount: Int = 8,
        angularOffset: Double = 0
    ) {
        self.slotCountMode = slotCountMode
        self.fixedSlotCount = Self.clampedSlotCount(fixedSlotCount)
        self.angularOffset = Self.normalizedAngle(angularOffset)
    }

    private enum CodingKeys: String, CodingKey {
        case slotCountMode, fixedSlotCount, angularOffset
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        slotCountMode = (try? c.decode(SlotCountMode.self, forKey: .slotCountMode)) ?? .auto
        fixedSlotCount = Self.clampedSlotCount(
            (try? c.decode(Int.self, forKey: .fixedSlotCount)) ?? 8
        )
        angularOffset = Self.normalizedAngle(
            (try? c.decode(Double.self, forKey: .angularOffset)) ?? 0
        )
    }

    static func clampedSlotCount(_ value: Int) -> Int {
        min(max(value, supportedSlotRange.lowerBound), supportedSlotRange.upperBound)
    }

    static func normalizedAngle(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        let result = value.truncatingRemainder(dividingBy: 360)
        return result < 0 ? result + 360 : result
    }
}

/// Optional ring-level presentation overrides. `nil` means inherit from the
/// menu default (and ultimately the application's current presentation).
struct HUDRingAppearance: Codable, Equatable, Sendable {
    var iconOrientation: IconOrientation?
    var wedgeColor: HUDColor?
    var iconColor: HUDColor?

    init(
        iconOrientation: IconOrientation? = nil,
        wedgeColor: HUDColor? = nil,
        iconColor: HUDColor? = nil
    ) {
        self.iconOrientation = iconOrientation
        self.wedgeColor = wedgeColor
        self.iconColor = iconColor
    }

    private enum CodingKeys: String, CodingKey {
        case iconOrientation, wedgeColor, iconColor
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        iconOrientation = try? c.decode(IconOrientation.self, forKey: .iconOrientation)
        wedgeColor = try? c.decode(HUDColor.self, forKey: .wedgeColor)
        iconColor = try? c.decode(HUDColor.self, forKey: .iconColor)
    }
}

struct HUDRingCustomization: Codable, Equatable, Sendable {
    var layout: HUDRingLayout
    var appearance: HUDRingAppearance

    init(layout: HUDRingLayout = .init(), appearance: HUDRingAppearance = .init()) {
        self.layout = layout
        self.appearance = appearance
    }

    private enum CodingKeys: String, CodingKey { case layout, appearance }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        layout = (try? c.decode(HUDRingLayout.self, forKey: .layout)) ?? .init()
        appearance = (try? c.decode(HUDRingAppearance.self, forKey: .appearance)) ?? .init()
    }
}

/// Persisted customization for HUD geometry and presentation.
///
/// Defaults deliberately reproduce the pre-customization HUD: item-derived
/// slots, no rotation, upright icons, application-owned colors, and outer
/// items presented whenever their parent is expanded.
struct HUDCustomization: Codable, Equatable, Sendable {
    var inner: HUDRingCustomization
    var middle: HUDRingCustomization
    var outerAppearance: HUDRingAppearance
    var outerRingVisibility: OuterRingVisibility
    var iconOrientation: IconOrientation
    var wedgeColor: HUDColor?
    var iconColor: HUDColor?

    init(
        inner: HUDRingCustomization = .init(),
        middle: HUDRingCustomization = .init(),
        outerAppearance: HUDRingAppearance = .init(),
        outerRingVisibility: OuterRingVisibility = .alwaysVisible,
        iconOrientation: IconOrientation = .upright,
        wedgeColor: HUDColor? = nil,
        iconColor: HUDColor? = nil
    ) {
        self.inner = inner
        self.middle = middle
        self.outerAppearance = outerAppearance
        self.outerRingVisibility = outerRingVisibility
        self.iconOrientation = iconOrientation
        self.wedgeColor = wedgeColor
        self.iconColor = iconColor
    }

    private enum CodingKeys: String, CodingKey {
        case inner, middle, outerAppearance, outerRingVisibility
        case iconOrientation, wedgeColor, iconColor
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        inner = (try? c.decode(HUDRingCustomization.self, forKey: .inner)) ?? .init()
        middle = (try? c.decode(HUDRingCustomization.self, forKey: .middle)) ?? .init()
        outerAppearance = (try? c.decode(HUDRingAppearance.self, forKey: .outerAppearance)) ?? .init()
        outerRingVisibility = (try? c.decode(OuterRingVisibility.self, forKey: .outerRingVisibility)) ?? .alwaysVisible
        iconOrientation = (try? c.decode(IconOrientation.self, forKey: .iconOrientation)) ?? .upright
        wedgeColor = try? c.decode(HUDColor.self, forKey: .wedgeColor)
        iconColor = try? c.decode(HUDColor.self, forKey: .iconColor)
    }

    static let `default` = HUDCustomization()
}
