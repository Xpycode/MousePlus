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

/// Orientation of an icon relative to its wedge.
enum IconOrientation: String, Codable, CaseIterable, Sendable {
    case upright
    case radial
    case tangential
}

/// Orientation of a wedge's label text, resolved independently from icon
/// orientation. `radial`/`tangential` are auto-flipped into a readable
/// half-plane by the presentation layer; the persisted value only records
/// intent.
enum LabelOrientation: String, Codable, CaseIterable, Sendable {
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
///
/// `labelVisible` is the exception: it has no menu-level default to inherit,
/// so it is always resolved explicitly. Its compatibility default differs by
/// owning ring (inner hidden, middle/outer shown), so tolerant decoding
/// threads that default in via `init(from:defaultLabelVisible:)` rather than
/// this type's own fallback.
struct HUDRingAppearance: Codable, Equatable, Sendable {
    var iconOrientation: IconOrientation?
    var labelOrientation: LabelOrientation?
    var labelVisible: Bool
    var wedgeColor: HUDColor?
    var iconColor: HUDColor?

    init(
        iconOrientation: IconOrientation? = nil,
        labelOrientation: LabelOrientation? = nil,
        labelVisible: Bool = true,
        wedgeColor: HUDColor? = nil,
        iconColor: HUDColor? = nil
    ) {
        self.iconOrientation = iconOrientation
        self.labelOrientation = labelOrientation
        self.labelVisible = labelVisible
        self.wedgeColor = wedgeColor
        self.iconColor = iconColor
    }

    private enum CodingKeys: String, CodingKey {
        case iconOrientation, labelOrientation, labelVisible, wedgeColor, iconColor
    }

    init(from decoder: Decoder) throws {
        try self.init(from: decoder, defaultLabelVisible: true)
    }

    /// Tolerant decode that lets the owning ring supply its own
    /// compatibility default for `labelVisible` when that field, or the
    /// whole object, is missing or invalid.
    init(from decoder: Decoder, defaultLabelVisible: Bool) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        iconOrientation = try? c.decode(IconOrientation.self, forKey: .iconOrientation)
        labelOrientation = try? c.decode(LabelOrientation.self, forKey: .labelOrientation)
        labelVisible = (try? c.decode(Bool.self, forKey: .labelVisible)) ?? defaultLabelVisible
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
        try self.init(from: decoder, defaultLabelVisible: true)
    }

    /// Tolerant decode that threads a ring-specific `labelVisible`
    /// compatibility default down into `appearance`.
    init(from decoder: Decoder, defaultLabelVisible: Bool) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        layout = (try? c.decode(HUDRingLayout.self, forKey: .layout)) ?? .init()
        appearance = (try? Self.decodeAppearance(from: c, defaultLabelVisible: defaultLabelVisible))
            ?? HUDRingAppearance(labelVisible: defaultLabelVisible)
    }

    private static func decodeAppearance(
        from container: KeyedDecodingContainer<CodingKeys>,
        defaultLabelVisible: Bool
    ) throws -> HUDRingAppearance {
        let nested = try container.superDecoder(forKey: .appearance)
        return try HUDRingAppearance(from: nested, defaultLabelVisible: defaultLabelVisible)
    }
}

/// Persisted customization for HUD geometry and presentation.
///
/// Defaults deliberately reproduce the pre-customization HUD: item-derived
/// slots, no rotation, upright icons and labels, application-owned colors,
/// outer items presented whenever their parent is expanded, and the inner
/// ring's label hidden while the middle and outer rings' labels are shown.
struct HUDCustomization: Codable, Equatable, Sendable {
    var inner: HUDRingCustomization
    var middle: HUDRingCustomization
    var outerAppearance: HUDRingAppearance
    var outerRingVisibility: OuterRingVisibility
    var iconOrientation: IconOrientation
    var labelOrientation: LabelOrientation
    var wedgeColor: HUDColor?
    var iconColor: HUDColor?

    init(
        inner: HUDRingCustomization = .init(appearance: .init(labelVisible: false)),
        middle: HUDRingCustomization = .init(),
        outerAppearance: HUDRingAppearance = .init(),
        outerRingVisibility: OuterRingVisibility = .alwaysVisible,
        iconOrientation: IconOrientation = .upright,
        labelOrientation: LabelOrientation = .upright,
        wedgeColor: HUDColor? = nil,
        iconColor: HUDColor? = nil
    ) {
        self.inner = inner
        self.middle = middle
        self.outerAppearance = outerAppearance
        self.outerRingVisibility = outerRingVisibility
        self.iconOrientation = iconOrientation
        self.labelOrientation = labelOrientation
        self.wedgeColor = wedgeColor
        self.iconColor = iconColor
    }

    private enum CodingKeys: String, CodingKey {
        case inner, middle, outerAppearance, outerRingVisibility
        case iconOrientation, labelOrientation, wedgeColor, iconColor
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        inner = (try? Self.decodeRing(from: c, forKey: .inner, defaultLabelVisible: false))
            ?? HUDRingCustomization(appearance: .init(labelVisible: false))
        middle = (try? Self.decodeRing(from: c, forKey: .middle, defaultLabelVisible: true))
            ?? .init()
        outerAppearance = (try? Self.decodeAppearance(from: c, forKey: .outerAppearance, defaultLabelVisible: true))
            ?? .init()
        outerRingVisibility = (try? c.decode(OuterRingVisibility.self, forKey: .outerRingVisibility)) ?? .alwaysVisible
        iconOrientation = (try? c.decode(IconOrientation.self, forKey: .iconOrientation)) ?? .upright
        labelOrientation = (try? c.decode(LabelOrientation.self, forKey: .labelOrientation)) ?? .upright
        wedgeColor = try? c.decode(HUDColor.self, forKey: .wedgeColor)
        iconColor = try? c.decode(HUDColor.self, forKey: .iconColor)
    }

    private static func decodeRing(
        from container: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys,
        defaultLabelVisible: Bool
    ) throws -> HUDRingCustomization {
        let nested = try container.superDecoder(forKey: key)
        return try HUDRingCustomization(from: nested, defaultLabelVisible: defaultLabelVisible)
    }

    private static func decodeAppearance(
        from container: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys,
        defaultLabelVisible: Bool
    ) throws -> HUDRingAppearance {
        let nested = try container.superDecoder(forKey: key)
        return try HUDRingAppearance(from: nested, defaultLabelVisible: defaultLabelVisible)
    }

    static let `default` = HUDCustomization()
}
