import SwiftUI

/// Pure presentation state supplied to a wedge after inheritance and contrast
/// resolution have completed.
struct WedgePresentation: Equatable, Sendable {
    enum State: Equatable, Sendable {
        case normal
        case hovered
        case selected
        case disabled
        case offBranch(opacity: Double)
    }

    let wedgeColor: HUDColor
    let iconColor: HUDColor
    let labelColor: HUDColor
    let orientation: IconOrientation
    let state: State

    init(
        wedgeColor: HUDColor,
        iconColor: HUDColor,
        labelColor: HUDColor,
        orientation: IconOrientation = .upright,
        state: State = .normal
    ) {
        self.wedgeColor = wedgeColor
        self.iconColor = iconColor
        self.labelColor = labelColor
        self.orientation = orientation
        self.state = state
    }

    /// Compatibility presentation matching the HUD before customization.
    static func applicationDefault(
        selected: Bool = false,
        offBranch: Bool = false,
        dimOpacity: Double = 0.30
    ) -> WedgePresentation {
        WedgePresentation(
            wedgeColor: HUDColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 0.2),
            iconColor: selected ? .white : HUDColor(red: 1, green: 1, blue: 1),
            labelColor: selected ? .white : HUDColor(red: 1, green: 1, blue: 1),
            state: selected ? .selected : (offBranch ? .offBranch(opacity: dimOpacity) : .normal)
        )
    }

    var opacity: Double {
        switch state {
        case .normal, .hovered, .selected: 1
        case .disabled: 0.45
        case .offBranch(let opacity): min(max(opacity, 0), 1)
        }
    }

    var emphasisOpacity: Double {
        switch state {
        case .normal, .offBranch: 0
        case .hovered: 0.12
        case .selected: 0.24
        case .disabled: 0.06
        }
    }

    var borderOpacity: Double {
        switch state {
        case .normal, .offBranch: 0.12
        case .hovered: 0.42
        case .selected: 0.72
        case .disabled: 0.08
        }
    }
}

/// Renders only the icon transform. Keeping this separate ensures captions and
/// expandable affordances remain upright.
struct OrientedHUDIcon: View {
    let systemName: String
    let orientation: IconOrientation
    /// Final normalized wedge midpoint, clockwise from +x in view coordinates.
    let wedgeMidpoint: Angle
    let color: Color

    var body: some View {
        Image(systemName: systemName)
            .font(.title2)
            .foregroundStyle(color)
            .rotationEffect(.degrees(Self.rotationDegrees(
                orientation: orientation,
                normalizedMidpointDegrees: wedgeMidpoint.degrees
            )))
    }

    static func rotationDegrees(
        orientation: IconOrientation,
        normalizedMidpointDegrees: Double
    ) -> Double {
        let midpoint = normalized(normalizedMidpointDegrees)
        return switch orientation {
        case .upright: 0
        case .radial: midpoint
        case .tangential: normalized(midpoint + 90)
        }
    }

    private static func normalized(_ degrees: Double) -> Double {
        guard degrees.isFinite else { return 0 }
        let result = degrees.truncatingRemainder(dividingBy: 360)
        return result < 0 ? result + 360 : result
    }
}
