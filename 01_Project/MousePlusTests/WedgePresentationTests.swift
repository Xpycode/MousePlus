import XCTest
@testable import MousePlus

final class WedgePresentationTests: XCTestCase {
    func testUprightOrientationNeverRotates() {
        for midpoint in [-450.0, 0, 90, 180, 270, 720] {
            XCTAssertEqual(
                OrientedHUDIcon.rotationDegrees(
                    orientation: .upright,
                    normalizedMidpointDegrees: midpoint
                ),
                0
            )
        }
    }

    func testRadialOrientationUsesNormalizedFinalMidpointInEveryQuadrant() {
        XCTAssertEqual(rotation(.radial, 45), 45)
        XCTAssertEqual(rotation(.radial, 135), 135)
        XCTAssertEqual(rotation(.radial, 225), 225)
        XCTAssertEqual(rotation(.radial, 315), 315)
        XCTAssertEqual(rotation(.radial, -45), 315)
        XCTAssertEqual(rotation(.radial, 405), 45)
    }

    func testTangentialOrientationIsQuarterTurnFromFinalMidpoint() {
        XCTAssertEqual(rotation(.tangential, 0), 90)
        XCTAssertEqual(rotation(.tangential, 90), 180)
        XCTAssertEqual(rotation(.tangential, 180), 270)
        XCTAssertEqual(rotation(.tangential, 270), 0)
        XCTAssertEqual(rotation(.tangential, 350), 80)
    }

    func testInteractionStatesHaveDistinctPresentation() {
        let normal = makePresentation(.normal)
        let hovered = makePresentation(.hovered)
        let selected = makePresentation(.selected)
        let disabled = makePresentation(.disabled)
        let offBranch = makePresentation(.offBranch(opacity: 0.3))

        XCTAssertEqual(normal.opacity, 1)
        XCTAssertEqual(hovered.opacity, 1)
        XCTAssertEqual(selected.opacity, 1)
        XCTAssertEqual(disabled.opacity, 0.45)
        XCTAssertEqual(offBranch.opacity, 0.3)
        XCTAssertLessThan(normal.emphasisOpacity, hovered.emphasisOpacity)
        XCTAssertLessThan(hovered.emphasisOpacity, selected.emphasisOpacity)
        XCTAssertLessThan(normal.borderOpacity, hovered.borderOpacity)
        XCTAssertLessThan(hovered.borderOpacity, selected.borderOpacity)
        XCTAssertNotEqual(disabled.emphasisOpacity, normal.emphasisOpacity)
    }

    func testResolvedCustomColorsRemainSeparateFromStateEmphasis() {
        let wedge = HUDColor(red: 0.1, green: 0.2, blue: 0.3)
        let icon = HUDColor(red: 0.9, green: 0.8, blue: 0.7)
        let label = HUDColor.white
        let presentation = WedgePresentation(
            wedgeColor: wedge,
            iconColor: icon,
            labelColor: label,
            orientation: .radial,
            state: .selected
        )

        XCTAssertEqual(presentation.wedgeColor, wedge)
        XCTAssertEqual(presentation.iconColor, icon)
        XCTAssertEqual(presentation.labelColor, label)
        XCTAssertEqual(presentation.orientation, .radial)
        XCTAssertGreaterThan(presentation.emphasisOpacity, 0)
    }

    private func rotation(_ orientation: IconOrientation, _ degrees: Double) -> Double {
        OrientedHUDIcon.rotationDegrees(
            orientation: orientation,
            normalizedMidpointDegrees: degrees
        )
    }

    private func makePresentation(_ state: WedgePresentation.State) -> WedgePresentation {
        WedgePresentation(
            wedgeColor: .black,
            iconColor: .white,
            labelColor: .white,
            state: state
        )
    }
}
