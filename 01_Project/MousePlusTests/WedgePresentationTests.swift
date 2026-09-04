import XCTest
@testable import MousePlus

final class WedgePresentationTests: XCTestCase {
    func testPersistentMaterialStopsAtMiddleEdgeWithoutOuterSurface() {
        let radii = BandRadii(r0: 10, r1: 20, r2: 30, r3: 40)
        let presentation = RingSurfacePresentation(radii: radii, isOuterRingVisible: false)

        XCTAssertEqual(presentation.persistentOuterRadius, 30)
        XCTAssertNil(presentation.localizedOuterInnerRadius)
        XCTAssertNil(presentation.localizedOuterOuterRadius)
    }

    func testVisibleOuterSurfaceIsLocalizedFromMiddleToOuterEdge() {
        let radii = BandRadii(r0: 10, r1: 20, r2: 30, r3: 40)
        let presentation = RingSurfacePresentation(radii: radii, isOuterRingVisible: true)

        XCTAssertEqual(presentation.persistentOuterRadius, 30)
        XCTAssertEqual(presentation.localizedOuterInnerRadius, 30)
        XCTAssertEqual(presentation.localizedOuterOuterRadius, 40)
    }

    func testEditorGuideSubtlyDescribesEmptyOuterBand() {
        let radii = BandRadii(r0: 10, r1: 20, r2: 30, r3: 40)

        for visibility in [
            OuterRingVisibility.alwaysVisible,
            OuterRingVisibility.revealBeyondInnerRing
        ] {
            let guide = EditorOuterRingGuidePresentation(
                radii: radii,
                visibility: visibility,
                hasLocalizedOuterSurface: false
            )

            XCTAssertTrue(guide.isVisible)
            XCTAssertEqual(guide.innerRadius, radii.r2)
            XCTAssertEqual(guide.outerRadius, radii.r3)
            XCTAssertGreaterThan(guide.fillOpacity, 0)
            XCTAssertLessThan(guide.fillOpacity, 0.1)
            XCTAssertGreaterThan(guide.boundaryOpacity, guide.fillOpacity)
            XCTAssertLessThan(guide.boundaryOpacity, 0.25)
        }
    }

    func testEditorGuideNeverCompetesWithPolicyHiddenOrLocalizedOuterSurface() {
        let radii = BandRadii(r0: 10, r1: 20, r2: 30, r3: 40)
        let hidden = EditorOuterRingGuidePresentation(
            radii: radii,
            visibility: .alwaysHidden,
            hasLocalizedOuterSurface: false
        )
        let populated = EditorOuterRingGuidePresentation(
            radii: radii,
            visibility: .alwaysVisible,
            hasLocalizedOuterSurface: true
        )
        let revealed = EditorOuterRingGuidePresentation(
            radii: radii,
            visibility: .revealBeyondInnerRing,
            hasLocalizedOuterSurface: true
        )

        XCTAssertFalse(hidden.isVisible)
        XCTAssertFalse(populated.isVisible)
        XCTAssertFalse(revealed.isVisible)
    }

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

    func testPersistentEditorSelectionIsNeutralUntilActuallyHovered() {
        let selected = WedgeInteractionPresentation(
            hovered: false, persistentlySelected: true, offBranch: false, dimOpacity: 0.3
        )
        let hovered = WedgeInteractionPresentation(
            hovered: true, persistentlySelected: true, offBranch: false, dimOpacity: 0.3
        )

        XCTAssertEqual(selected.state, .normal)
        XCTAssertTrue(selected.showsSelectionMarker)
        XCTAssertEqual(hovered.state, .hovered)
        XCTAssertTrue(hovered.showsSelectionMarker)
    }

    func testHoverEmphasisPreservesResolvedWedgeAndIconColors() {
        let wedge = HUDColor(red: 0.12, green: 0.34, blue: 0.56)
        let icon = HUDColor(red: 0.93, green: 0.82, blue: 0.71)
        let normal = WedgePresentation(
            wedgeColor: wedge, iconColor: icon, labelColor: icon, state: .normal
        )
        let hovered = WedgePresentation(
            wedgeColor: wedge, iconColor: icon, labelColor: icon, state: .hovered
        )

        XCTAssertEqual(normal.wedgeColor, hovered.wedgeColor)
        XCTAssertEqual(normal.iconColor, hovered.iconColor)
        XCTAssertEqual(normal.labelColor, hovered.labelColor)
        XCTAssertGreaterThan(hovered.emphasisOpacity, normal.emphasisOpacity)
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
