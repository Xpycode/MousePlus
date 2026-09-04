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

/// Deterministic presentation values derived from one normalized clock.
/// Wave 2 preserves Fade/Off and temporarily fades unimplemented spatial
/// styles; later renderer waves extend this frame without changing lifecycle.
struct HUDOpeningMotionFrame: Equatable, Sendable {
    let progress: CGFloat
    let artworkOpacity: Double

    static func resolve(
        descriptor: HUDMotionPresentationDescriptor,
        progress rawProgress: CGFloat
    ) -> Self {
        let progress = min(max(rawProgress, 0), 1)
        let opacity: Double
        switch descriptor.effect {
        case .instant, .emphasis, .radialReveal:
            opacity = 1
        case .fade, .circularSweep, .irisReveal, .bloom, .staggeredSegments:
            opacity = Double(progress)
        }
        return Self(progress: progress, artworkOpacity: opacity)
    }
}
