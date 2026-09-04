import Foundation

enum HUDSummonMotionStyle: String, Codable, CaseIterable, Equatable, Sendable {
    case off
    case fade
}

enum HUDHoverMotionStyle: String, Codable, CaseIterable, Equatable, Sendable {
    case off
    case emphasis
}

enum HUDOuterExpansionMotionStyle: String, Codable, CaseIterable, Equatable, Sendable {
    case off
    case radialReveal
}

enum HUDBranchChangeMotionStyle: String, Codable, CaseIterable, Equatable, Sendable {
    case off
    case crossfade
}

/// Persisted motion preferences grouped by the visual role they control.
///
/// Decoding is deliberately field-tolerant. A future or malformed value for one
/// role falls back only that role and leaves the remaining saved choices intact.
struct HUDMotionConfiguration: Codable, Equatable, Sendable {
    var isEnabled: Bool
    var baseDuration: Double
    var summon: HUDSummonMotionStyle
    var hover: HUDHoverMotionStyle
    var outerExpansion: HUDOuterExpansionMotionStyle
    var branchChange: HUDBranchChangeMotionStyle

    init(
        isEnabled: Bool = true,
        baseDuration: Double = 0.15,
        summon: HUDSummonMotionStyle = .fade,
        hover: HUDHoverMotionStyle = .emphasis,
        outerExpansion: HUDOuterExpansionMotionStyle = .radialReveal,
        branchChange: HUDBranchChangeMotionStyle = .crossfade
    ) {
        self.isEnabled = isEnabled
        self.baseDuration = baseDuration
        self.summon = summon
        self.hover = hover
        self.outerExpansion = outerExpansion
        self.branchChange = branchChange
    }

    private enum CodingKeys: String, CodingKey {
        case isEnabled, baseDuration, summon, hover, outerExpansion, branchChange
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = HUDMotionConfiguration.default

        isEnabled = (try? container.decode(Bool.self, forKey: .isEnabled))
            ?? defaults.isEnabled
        baseDuration = (try? container.decode(Double.self, forKey: .baseDuration))
            ?? defaults.baseDuration
        summon = (try? container.decode(HUDSummonMotionStyle.self, forKey: .summon))
            ?? defaults.summon
        hover = (try? container.decode(HUDHoverMotionStyle.self, forKey: .hover))
            ?? defaults.hover
        outerExpansion = (try? container.decode(HUDOuterExpansionMotionStyle.self, forKey: .outerExpansion))
            ?? defaults.outerExpansion
        branchChange = (try? container.decode(HUDBranchChangeMotionStyle.self, forKey: .branchChange))
            ?? defaults.branchChange
    }

    static let `default` = HUDMotionConfiguration()
}
