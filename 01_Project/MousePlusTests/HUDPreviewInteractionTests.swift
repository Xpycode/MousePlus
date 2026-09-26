import XCTest
import CoreGraphics
@testable import MousePlus

final class HUDPreviewInteractionTests: XCTestCase {
    private let center = CGPoint.zero
    private let radii = BandRadii(r0: 10, r1: 20, r2: 30, r3: 40)

    func testOuterVisibilityStateMatrixMatchesSharedPolicy() {
        for policy in OuterRingVisibility.allCases {
            for parent in [nil, 0] {
                for outerCount in [0, 2] {
                    var state = HUDPreviewInteractionState()
                    let snapshot = makeSnapshot(
                        visibility: policy, parent: parent, outerCount: outerCount
                    )
                    _ = state.pointerMoved(
                        to: point(angle: 0, radius: 20), center: center, snapshot: snapshot
                    )
                    _ = state.pointerMoved(
                        to: point(angle: 0, radius: 21), center: center, snapshot: snapshot
                    )
                    let expected = OuterRingPolicyState()
                        .transition(
                            policy: policy,
                            hasExpandedParent: parent != nil,
                            itemCount: outerCount,
                            pointerIsAtOrInsideInnerBoundary: true
                        ).state
                        .transition(
                            policy: policy,
                            hasExpandedParent: parent != nil,
                            itemCount: outerCount,
                            pointerIsAtOrInsideInnerBoundary: false
                        ).isVisible
                    XCTAssertEqual(
                        state.outerIsVisible(snapshot: snapshot), expected,
                        "policy: \(policy), parent: \(String(describing: parent)), count: \(outerCount)"
                    )
                }
            }
        }
    }

    func testEveryVisibleBandProducesOnlyEditorIntent() {
        let state = HUDPreviewInteractionState()
        let snapshot = makeSnapshot(visibility: .alwaysVisible, parent: 0, outerCount: 2)

        XCTAssertEqual(state.intent(at: point(angle: .pi / 4, radius: 15), center: center,
                                    snapshot: snapshot), .selectTopLevel(.inner, 0))
        XCTAssertEqual(state.intent(at: point(angle: .pi / 4, radius: 25), center: center,
                                    snapshot: snapshot), .selectTopLevel(.middle, 0))

        let outer = RadialGeometry.centroid(
            band: .outer, index: 0, center: center, radii: radii,
            geometry: snapshot.geometry, expandedParentIndex: 0, outerCount: 2
        )
        XCTAssertEqual(state.intent(at: outer, center: center, snapshot: snapshot),
                       .selectOuter(0))
    }

    func testCenterOutsideAndInvisibleFixedSlotsHaveZeroEffects() {
        let state = HUDPreviewInteractionState()
        let geometry = TopLevelRingGeometry(
            inner: RingBandGeometry(slotCount: 6),
            middle: RingBandGeometry(slotCount: 5, angularOffset: .pi / 3)
        )
        let snapshot = makeSnapshot(geometry: geometry, innerCount: 2, middleCount: 2)
        var emitted: [HUDPreviewIntent] = []
        for location in [
            CGPoint.zero,
            point(angle: 11 * .pi / 6, radius: 15),
            point(angle: 0, radius: 25),
            point(angle: 0, radius: 41)
        ] {
            if let intent = state.intent(at: location, center: center, snapshot: snapshot) {
                emitted.append(intent)
            }
        }
        XCTAssertTrue(emitted.isEmpty)
    }

    func testConditionalRevealShowsOuterSelectionOnDirectArrival() {
        var state = HUDPreviewInteractionState()
        let snapshot = makeSnapshot(visibility: .revealBeyondInnerRing,
                                    parent: 0, outerCount: 2)
        let outer = RadialGeometry.centroid(
            band: .outer, index: 0, center: center, radii: radii,
            geometry: snapshot.geometry, expandedParentIndex: 0, outerCount: 2
        )

        XCTAssertEqual(
            state.pointerMoved(to: outer, center: center, snapshot: snapshot),
            ActiveSelection(band: .outer, index: 0)
        )
        XCTAssertTrue(state.outerIsVisible(snapshot: snapshot))
        XCTAssertEqual(state.intent(at: outer, center: center, snapshot: snapshot),
                       .selectOuter(0))
        _ = state.pointerMoved(to: point(angle: 0, radius: 15), center: center,
                               snapshot: snapshot)
        XCTAssertTrue(state.outerIsVisible(snapshot: snapshot))
    }

    func testFullCirclePreviewOuterRingSelectsAcrossFromParent() {
        let state = HUDPreviewInteractionState()
        let snapshot = makeSnapshot(
            geometry: .shared(spokeCount: 4), innerCount: 4, middleCount: 4,
            visibility: .alwaysVisible, parent: 0, outerCount: 4,
            outerLayout: .fullCircle
        )

        XCTAssertEqual(
            state.intent(at: point(angle: 5 * .pi / 4, radius: 35),
                         center: center, snapshot: snapshot),
            .selectOuter(2)
        )
    }

    func testTraversalBeforeParentExpansionIsRetainedForInvocation() {
        var state = HUDPreviewInteractionState()
        let root = makeSnapshot(visibility: .revealBeyondInnerRing)
        _ = state.pointerMoved(to: .zero, center: center, snapshot: root)
        _ = state.pointerMoved(to: point(angle: 0, radius: 25),
                               center: center, snapshot: root)
        XCTAssertFalse(state.outerIsVisible(snapshot: root))

        let expanded = makeSnapshot(
            visibility: .revealBeyondInnerRing, parent: 0, outerCount: 2
        )
        XCTAssertTrue(state.outerIsVisible(snapshot: expanded))
    }

    @MainActor
    func testCoordinatorPublishesRetainedRevealWhenParentExpands() {
        let root = makeSnapshot(visibility: .revealBeyondInnerRing)
        let coordinator = HUDPreviewInteractionView.Coordinator(snapshot: root)
        var visibilityChanges: [Bool] = []
        coordinator.onRevealChange = { visibilityChanges.append($0) }

        coordinator.moved(.zero, center: center)
        coordinator.moved(point(angle: 0, radius: 25), center: center)
        coordinator.update(snapshot: makeSnapshot(
            visibility: .revealBeyondInnerRing, parent: 0, outerCount: 2
        ))

        XCTAssertEqual(visibilityChanges, [true])
    }

    func testAlwaysHiddenOuterHasNoIntent() {
        let state = HUDPreviewInteractionState()
        let snapshot = makeSnapshot(visibility: .alwaysHidden, parent: 0, outerCount: 2)
        let outer = RadialGeometry.centroid(
            band: .outer, index: 0, center: center, radii: radii,
            geometry: snapshot.geometry, expandedParentIndex: 0, outerCount: 2
        )
        XCTAssertNil(state.intent(at: outer, center: center, snapshot: snapshot))
    }

    func testFixedEmptyRingRegionsNeverAddOrSelectItems() {
        let state = HUDPreviewInteractionState()
        let fixedGeometry = TopLevelRingGeometry(
            inner: RingBandGeometry(slotCount: 4),
            middle: RingBandGeometry(slotCount: 2)
        )
        let fixed = makeSnapshot(
            geometry: fixedGeometry, innerCount: 2, middleCount: 2
        )
        let emptyPoint = RadialGeometry.centroid(
            band: .inner, index: 2, center: center, radii: radii,
            geometry: fixedGeometry, expandedParentIndex: nil, outerCount: 0
        )
        XCTAssertNil(state.intent(at: emptyPoint, center: center, snapshot: fixed))
    }

    func testFitScalePreservesLogicalGeometryAndOnlyShrinksCanvas() {
        XCTAssertEqual(HUDPreviewInteractionSnapshot.fitScale(logicalSide: 800,
                                                              canvasSide: 400), 0.5)
        XCTAssertEqual(HUDPreviewInteractionSnapshot.fitScale(logicalSide: 300,
                                                              canvasSide: 400), 1)
    }

    func testRotatedFixedMiddleWedgesMapRenderedCentroidsToTheirOwnItems() {
        let geometry = TopLevelRingGeometry(
            inner: RingBandGeometry(slotCount: 5, angularOffset: 99.768 * .pi / 180),
            middle: RingBandGeometry(slotCount: 8, angularOffset: 185.437 * .pi / 180)
        )
        let snapshot = makeSnapshot(
            geometry: geometry, innerCount: 5, middleCount: 6,
            visibility: .revealBeyondInnerRing
        )
        let state = HUDPreviewInteractionState()

        for index in 0..<6 {
            let renderedCentroid = RadialGeometry.centroid(
                band: .middle, index: index, center: center, radii: radii,
                geometry: geometry, expandedParentIndex: nil, outerCount: 0
            )
            XCTAssertEqual(
                state.intent(at: renderedCentroid, center: center, snapshot: snapshot),
                .selectTopLevel(.middle, index),
                "Rendered middle wedge \(index) must select that same item"
            )
        }
    }

    private func makeSnapshot(
        geometry: TopLevelRingGeometry = .shared(spokeCount: 2),
        innerCount: Int = 2,
        middleCount: Int = 2,
        visibility: OuterRingVisibility = .alwaysVisible,
        parent: Int? = nil,
        outerCount: Int = 0,
        outerLayout: OuterRingLayout = .localizedArc
    ) -> HUDPreviewInteractionSnapshot {
        HUDPreviewInteractionSnapshot(
            geometry: geometry, radii: radii,
            innerCount: innerCount, middleCount: middleCount,
            expandedParentIndex: parent, outerCount: outerCount,
            outerVisibility: visibility, outerLayout: outerLayout
        )
    }

    private func point(angle: CGFloat, radius: CGFloat) -> CGPoint {
        CGPoint(x: radius * cos(angle), y: radius * sin(angle))
    }
}
