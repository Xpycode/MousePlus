import CoreGraphics

/// Explicit rendering context for the shared ring renderer.
///
/// Interaction is deliberately not part of this value: the noninteractive
/// opening preview may animate, while the interactive menu editor stays static.
enum HUDRingPresentationMode: Equatable, Sendable {
    case live
    case staticEditor
    case openingPreview

    func motion(
        for role: HUDMotionRole,
        configuration: HUDMotionConfiguration,
        reduceMotion: Bool
    ) -> HUDMotionPresentationDescriptor {
        guard self != .staticEditor else { return .instant }
        return HUDMotionPolicy.resolve(
            role: role,
            configuration: configuration,
            reduceMotion: reduceMotion
        )
    }
}

/// A playback request is stable across ordinary SwiftUI redraws. Only a new
/// invocation identity is allowed to replay an entrance; live preference or
/// layout changes settle the current presentation instead.
struct HUDOpeningMotionRequest: Equatable, Sendable {
    let descriptor: HUDMotionPresentationDescriptor
    let playbackEnabled: Bool
    let invocationID: Int

    var shouldAnimate: Bool {
        playbackEnabled && descriptor.effect != .instant
    }
}

enum HUDOpeningMotionTransition: Equatable, Sendable {
    case unchanged
    case replay
    case settle

    static func resolve(
        previous: HUDOpeningMotionRequest?,
        current: HUDOpeningMotionRequest
    ) -> Self {
        guard current.shouldAnimate else { return .settle }
        guard let previous else { return .replay }
        if previous.invocationID != current.invocationID { return .replay }
        if previous != current { return .settle }
        return .unchanged
    }
}

/// Deterministic presentation values for all opening styles, derived from one
/// normalized clock without coupling visual progress to interaction state.
struct HUDOpeningMotionFrame: Equatable, Sendable {
    enum Mask: Equatable, Sendable {
        case none
        case circularSweep(CGFloat)
        case iris(radius: CGFloat)
    }

    let effect: HUDMotionPresentationEffect
    let progress: CGFloat
    let artworkOpacity: Double
    let centerOpacity: Double
    let artworkScale: CGFloat
    let mask: Mask

    static func resolve(
        descriptor: HUDMotionPresentationDescriptor,
        progress rawProgress: CGFloat,
        deadZoneRadius: CGFloat = 0,
        revealRadius: CGFloat = 0
    ) -> Self {
        let progress = min(max(rawProgress, 0), 1)
        let eased = easeOut(progress)
        let artworkOpacity: Double
        let centerOpacity: Double
        let artworkScale: CGFloat
        let mask: Mask
        switch descriptor.effect {
        case .instant, .emphasis, .radialReveal:
            artworkOpacity = 1
            centerOpacity = 1
            artworkScale = 1
            mask = .none
        case .fade:
            // Preserve the shipped Fade curve; only the new spatial reveals
            // use the specification's explicit ease-out progress.
            artworkOpacity = Double(progress)
            centerOpacity = Double(progress)
            artworkScale = 1
            mask = .none
        case .circularSweep:
            artworkOpacity = 1
            centerOpacity = 1
            artworkScale = 1
            mask = progress >= 1 ? .none : .circularSweep(eased)
        case .irisReveal:
            artworkOpacity = 1
            centerOpacity = 1
            artworkScale = 1
            let radius = deadZoneRadius + (revealRadius - deadZoneRadius) * eased
            mask = progress >= 1 ? .none : .iris(radius: radius)
        case .bloom:
            artworkOpacity = Double(eased)
            centerOpacity = 1
            artworkScale = bloomScale(progress)
            mask = .none
        case .staggeredSegments:
            artworkOpacity = 1
            centerOpacity = 1
            artworkScale = 1
            mask = .none
        }
        return Self(
            effect: descriptor.effect,
            progress: progress,
            artworkOpacity: artworkOpacity,
            centerOpacity: centerOpacity,
            artworkScale: artworkScale,
            mask: mask
        )
    }

    /// Clockwise ordering of slot start edges relative to 12 o'clock. The
    /// stable index tie-breaker protects exact wrap-boundary configurations.
    static func staggerRank(
        index: Int,
        slotCount: Int,
        angularOffset: CGFloat
    ) -> Int {
        guard slotCount > 0 else { return 0 }
        let boundedIndex = min(max(index, 0), slotCount - 1)
        let step = 2 * CGFloat.pi / CGFloat(slotCount)
        let ordered = (0..<slotCount).map { slot -> (index: Int, angle: CGFloat) in
            let start = angularOffset + CGFloat(slot) * step
            return (slot, normalizedAngle(start + .pi / 2))
        }.sorted {
            if $0.angle == $1.angle { return $0.index < $1.index }
            return $0.angle < $1.angle
        }
        return ordered.firstIndex { $0.index == boundedIndex } ?? boundedIndex
    }

    /// Each band spends 55% of total time launching segments and 45% fading
    /// them. A one-slot band uses the full duration, as specified.
    static func staggerOpacity(
        globalProgress rawProgress: CGFloat,
        rank: Int,
        slotCount: Int
    ) -> Double {
        guard slotCount > 0 else { return 0 }
        let progress = min(max(rawProgress, 0), 1)
        if slotCount == 1 { return Double(easeOut(progress)) }
        let boundedRank = min(max(rank, 0), slotCount - 1)
        let delay = 0.55 * CGFloat(boundedRank) / CGFloat(slotCount - 1)
        let local = min(max((progress - delay) / 0.45, 0), 1)
        return Double(easeOut(local))
    }

    private static func easeOut(_ progress: CGFloat) -> CGFloat {
        let inverse = 1 - progress
        return 1 - inverse * inverse * inverse
    }

    private static func bloomScale(_ progress: CGFloat) -> CGFloat {
        if progress <= 0.75 {
            let local = progress / 0.75
            return 0.92 + (1.015 - 0.92) * easeOut(local)
        }
        let local = (progress - 0.75) / 0.25
        let smooth = local * local * (3 - 2 * local)
        return 1.015 + (1 - 1.015) * smooth
    }

    private static func normalizedAngle(_ angle: CGFloat) -> CGFloat {
        let turn = 2 * CGFloat.pi
        let remainder = angle.truncatingRemainder(dividingBy: turn)
        return remainder < 0 ? remainder + turn : remainder
    }
}
