import Foundation

enum HUDMotionRole: CaseIterable, Hashable, Sendable {
    case summon
    case hover
    case outerExpansion
    case branchChange
}

enum HUDMotionPresentationEffect: Equatable, Sendable {
    case instant
    case fade
    case emphasis
    case radialReveal
    case circularSweep
    case irisReveal
    case bloom
    case staggeredSegments
}

struct HUDMotionPresentationDescriptor: Equatable, Sendable {
    let effect: HUDMotionPresentationEffect
    let duration: Double

    static let instant = HUDMotionPresentationDescriptor(effect: .instant, duration: 0)
}

/// Converts saved semantic choices into presentation-only render instructions.
/// The policy has no dependency on selection, expansion, commit, or action state.
enum HUDMotionPolicy {
    static let minimumDuration = 0.05
    static let maximumDuration = 0.5

    static func resolve(
        role: HUDMotionRole,
        configuration: HUDMotionConfiguration,
        reduceMotion: Bool
    ) -> HUDMotionPresentationDescriptor {
        guard configuration.isEnabled else { return .instant }

        let requestedEffect: HUDMotionPresentationEffect
        switch role {
        case .summon:
            switch configuration.summon {
            case .off:
                return .instant
            case .fade:
                requestedEffect = .fade
            case .circularSweep:
                requestedEffect = .circularSweep
            case .irisReveal:
                requestedEffect = .irisReveal
            case .bloom:
                requestedEffect = .bloom
            case .staggeredSegments:
                requestedEffect = .staggeredSegments
            }
        case .hover:
            guard configuration.hover == .emphasis else { return .instant }
            requestedEffect = .emphasis
        case .outerExpansion:
            guard configuration.outerExpansion == .radialReveal else { return .instant }
            requestedEffect = .radialReveal
        case .branchChange:
            guard configuration.branchChange == .crossfade else { return .instant }
            requestedEffect = .fade
        }

        let effect: HUDMotionPresentationEffect
        if reduceMotion && isSpatial(requestedEffect) {
            effect = .fade
        } else {
            effect = requestedEffect
        }

        return HUDMotionPresentationDescriptor(
            effect: effect,
            duration: clampedDuration(configuration.baseDuration)
        )
    }

    private static func isSpatial(_ effect: HUDMotionPresentationEffect) -> Bool {
        switch effect {
        case .emphasis, .radialReveal, .circularSweep, .irisReveal, .bloom, .staggeredSegments:
            return true
        case .instant, .fade:
            return false
        }
    }

    private static func clampedDuration(_ duration: Double) -> Double {
        guard duration.isFinite else { return HUDMotionConfiguration.default.baseDuration }
        return min(max(duration, minimumDuration), maximumDuration)
    }
}
