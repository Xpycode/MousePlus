import SwiftUI

/// Pure, resolved presentation for one wedge's caption: whether the visual
/// `Text` renders, and the rotation that keeps radial/tangential captions
/// readable at every angle around the ring.
///
/// Deliberately separate from `WedgePresentation` (wedge/icon colors and
/// interaction state) and from `OrientedHUDIcon` (icon rotation): resolving
/// caption presentation independently keeps a hidden or reoriented label
/// from ever perturbing icon/chevron transforms.
struct LabelPresentation: Equatable, Sendable {
    /// Whether the visual caption should render. This governs the `Text`
    /// only — see `accessibilityLabel`, which stays populated regardless.
    let isCaptionVisible: Bool
    /// Rotation to apply to the caption, clockwise degrees, already
    /// auto-flipped into the readable half for radial/tangential text.
    let rotationDegrees: Double
    /// The wedge's accessible name. Always populated, independent of
    /// `isCaptionVisible`, so hiding the visual caption never removes the
    /// item's accessibility name.
    let accessibilityLabel: String

    init(
        accessibilityLabel: String,
        orientation: LabelOrientation,
        isVisible: Bool,
        wedgeMidpoint: Angle
    ) {
        self.accessibilityLabel = accessibilityLabel
        self.isCaptionVisible = isVisible
        self.rotationDegrees = Self.resolvedRotationDegrees(
            orientation: orientation,
            normalizedMidpointDegrees: wedgeMidpoint.degrees
        )
    }

    /// Convenience for callers holding a wedge's angular range rather than
    /// its precomputed midpoint (mirrors `WedgeView.normalizedMidpoint`'s
    /// own start/end-to-midpoint math).
    init(
        accessibilityLabel: String,
        orientation: LabelOrientation,
        isVisible: Bool,
        startAngle: Angle,
        endAngle: Angle
    ) {
        self.init(
            accessibilityLabel: accessibilityLabel,
            orientation: orientation,
            isVisible: isVisible,
            wedgeMidpoint: Self.midpoint(startAngle: startAngle, endAngle: endAngle)
        )
    }

    /// Mirrors `OrientedHUDIcon.rotationDegrees`'s base angle per
    /// orientation (`upright` stays 0, `radial` uses the wedge midpoint,
    /// `tangential` adds a quarter turn), then auto-flips 180° whenever that
    /// base angle would render the caption upside down.
    static func resolvedRotationDegrees(
        orientation: LabelOrientation,
        normalizedMidpointDegrees: Double
    ) -> Double {
        let midpoint = normalized(normalizedMidpointDegrees)
        switch orientation {
        case .upright:
            return 0
        case .radial:
            return readable(midpoint)
        case .tangential:
            return readable(normalized(midpoint + 90))
        }
    }

    /// SwiftUI's `.rotationEffect` rotates clockwise from upright, so a
    /// caption rotated by more than a quarter turn in either direction (any
    /// value strictly between 90° and 270°) reads upside down. Flip 180° to
    /// bring it back into the readable half. The boundaries themselves —
    /// 90° and 270° — are left unflipped: a caption exactly on its side is
    /// still legible, matching `OrientedHUDIcon`'s icon rotation, which
    /// never flips at all.
    private static func readable(_ degrees: Double) -> Double {
        degrees > 90 && degrees < 270 ? normalized(degrees + 180) : degrees
    }

    private static func midpoint(startAngle: Angle, endAngle: Angle) -> Angle {
        let start = startAngle.degrees
        var sweep = endAngle.degrees - start
        if sweep < 0 { sweep += 360 }
        return .degrees(normalized(start + sweep / 2))
    }

    private static func normalized(_ degrees: Double) -> Double {
        guard degrees.isFinite else { return 0 }
        let result = degrees.truncatingRemainder(dividingBy: 360)
        return result < 0 ? result + 360 : result
    }
}
