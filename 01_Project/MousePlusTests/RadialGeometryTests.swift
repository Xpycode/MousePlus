import XCTest
import CoreGraphics
@testable import MousePlus

final class RadialGeometryTests: XCTestCase {
    private let center = CGPoint.zero
    private let radii = BandRadii(r0: 10, r1: 20, r2: 30, r3: 40)

    func testBandGeometryNormalizesOffsetAndBoundsSlotCount() {
        let geometry = RingBandGeometry(slotCount: 0, angularOffset: -.pi / 2)

        XCTAssertEqual(geometry.slotCount, 1)
        XCTAssertEqual(geometry.angularOffset, 3 * .pi / 2, accuracy: 1e-12)
        XCTAssertEqual(
            RingBandGeometry(slotCount: 4, angularOffset: 5 * .pi / 2).angularOffset,
            .pi / 2,
            accuracy: 1e-12
        )
    }

    func testAsymmetricCountsAndOffsetsProduceIndependentAnglesAndHits() {
        let geometry = TopLevelRingGeometry(
            inner: RingBandGeometry(slotCount: 4, angularOffset: .pi / 2),
            middle: RingBandGeometry(slotCount: 3, angularOffset: .pi)
        )

        let inner = RadialGeometry.wedgeAngles(
            band: .inner, index: 0, geometry: geometry,
            expandedParentIndex: nil, outerCount: 0
        )
        let middle = RadialGeometry.wedgeAngles(
            band: .middle, index: 0, geometry: geometry,
            expandedParentIndex: nil, outerCount: 0
        )
        XCTAssertEqual(inner.start.radians, Double.pi / 2, accuracy: 1e-12)
        XCTAssertEqual(inner.end.radians, Double.pi, accuracy: 1e-12)
        XCTAssertEqual(middle.start.radians, Double.pi, accuracy: 1e-12)
        XCTAssertEqual(middle.end.radians, 5 * Double.pi / 3, accuracy: 1e-12)

        XCTAssertHit(point(angle: 0, radius: 15), geometry: geometry,
                     innerItems: 4, middleItems: 3, band: .inner, index: 3)
        XCTAssertHit(point(angle: 0, radius: 25), geometry: geometry,
                     innerItems: 4, middleItems: 3, band: .middle, index: 1)
    }

    func testAngularOffsetWraparoundHasNoDiscontinuity() {
        let geometry = TopLevelRingGeometry.shared(
            spokeCount: 4, angularOffset: 7 * .pi / 4
        )

        XCTAssertHit(point(angle: 0, radius: 15), geometry: geometry,
                     innerItems: 4, middleItems: 4, band: .inner, index: 0)
        XCTAssertHit(point(angle: 3 * .pi / 2, radius: 15), geometry: geometry,
                     innerItems: 4, middleItems: 4, band: .inner, index: 3)
    }

    func testRadialAndAngularBoundariesPreserveExistingBehavior() {
        let geometry = TopLevelRingGeometry.shared(spokeCount: 4)

        XCTAssertNil(hit(point(angle: 0, radius: 10), geometry: geometry))
        XCTAssertHit(point(angle: 0, radius: 20), geometry: geometry,
                     innerItems: 4, middleItems: 4, band: .inner, index: 0)
        XCTAssertHit(point(angle: .pi / 2, radius: 25), geometry: geometry,
                     innerItems: 4, middleItems: 4, band: .middle, index: 1)
        XCTAssertNil(hit(point(angle: 0, radius: 40.001), geometry: geometry))
    }

    func testOuterArcAlignsWithRotatedMiddleParentNotInnerBand() {
        let geometry = TopLevelRingGeometry(
            inner: RingBandGeometry(slotCount: 8, angularOffset: 0),
            middle: RingBandGeometry(slotCount: 4, angularOffset: .pi / 2)
        )
        let span = RadialGeometry.outerArcSpan(
            parentIndex: 0, parentGeometry: geometry.middle, outerCount: 3
        )

        XCTAssertEqual((span.start.radians + span.end.radians) / 2,
                       3 * Double.pi / 4, accuracy: 1e-12)
        XCTAssertHit(point(angle: 3 * .pi / 4, radius: 35), geometry: geometry,
                     innerItems: 8, middleItems: 4, parent: 0, outerCount: 3,
                     band: .outer, index: 1)
    }

    func testOuterArcAcrossZeroIncludesWrappedAnglesAndExcludesEndBoundary() {
        let geometry = TopLevelRingGeometry.shared(
            spokeCount: 8, angularOffset: -.pi / 4
        )
        let span = RadialGeometry.outerArcSpan(
            parentIndex: 0, parentGeometry: geometry.middle, outerCount: 3
        )

        XCTAssertHit(point(angle: 15 * CGFloat.pi / 8, radius: 35), geometry: geometry,
                     innerItems: 8, middleItems: 8, parent: 0, outerCount: 3,
                     band: .outer, index: 1)
        XCTAssertNil(hit(point(angle: CGFloat(span.end.radians), radius: 35),
                         geometry: geometry, parent: 0, outerCount: 3))
    }

    func testFullCircleOuterRingAlignsFirstItemWithParentAndCoversEveryAngle() {
        let geometry = TopLevelRingGeometry.shared(spokeCount: 4)
        let span = RadialGeometry.outerArcSpan(
            parentIndex: 0, parentGeometry: geometry.middle, outerCount: 4,
            layout: .fullCircle
        )
        let first = RadialGeometry.wedgeAngles(
            band: .outer, index: 0, geometry: geometry,
            expandedParentIndex: 0, outerCount: 4, outerLayout: .fullCircle
        )

        XCTAssertEqual(span.end.radians - span.start.radians,
                       2 * Double.pi, accuracy: 1e-12)
        XCTAssertEqual((first.start.radians + first.end.radians) / 2,
                       Double.pi / 4, accuracy: 1e-12)
        XCTAssertHit(point(angle: .pi / 4, radius: 35), geometry: geometry,
                     innerItems: 4, middleItems: 4, parent: 0, outerCount: 4,
                     outerLayout: .fullCircle, band: .outer, index: 0)
        XCTAssertHit(point(angle: 5 * .pi / 4, radius: 35), geometry: geometry,
                     innerItems: 4, middleItems: 4, parent: 0, outerCount: 4,
                     outerLayout: .fullCircle, band: .outer, index: 2)
    }

    func testUnusedFixedSlotsRemainInGeometryButAreInert() {
        let geometry = TopLevelRingGeometry(
            inner: RingBandGeometry(slotCount: 6),
            middle: RingBandGeometry(slotCount: 4)
        )
        let emptyInnerSlotMidpoint = 11 * CGFloat.pi / 6 // slot 5 of 6
        let emptyMiddleSlotMidpoint = 7 * CGFloat.pi / 4 // slot 3 of 4

        XCTAssertNil(hit(point(angle: emptyInnerSlotMidpoint, radius: 15),
                         geometry: geometry, innerItems: 2, middleItems: 3))
        XCTAssertNil(hit(point(angle: emptyMiddleSlotMidpoint, radius: 25),
                         geometry: geometry, innerItems: 2, middleItems: 3))

        let angles = RadialGeometry.wedgeAngles(
            band: .inner, index: 5, geometry: geometry,
            expandedParentIndex: nil, outerCount: 0
        )
        XCTAssertEqual(angles.start.radians, 5 * Double.pi / 3, accuracy: 1e-12)
        XCTAssertEqual(angles.end.radians, 2 * Double.pi, accuracy: 1e-12)
    }

    func testCentroidUsesEachBandsOwnRotation() {
        let geometry = TopLevelRingGeometry(
            inner: RingBandGeometry(slotCount: 4),
            middle: RingBandGeometry(slotCount: 4, angularOffset: .pi / 2)
        )
        let inner = RadialGeometry.centroid(
            band: .inner, index: 0, center: center, radii: radii,
            geometry: geometry, expandedParentIndex: nil, outerCount: 0
        )
        let middle = RadialGeometry.centroid(
            band: .middle, index: 0, center: center, radii: radii,
            geometry: geometry, expandedParentIndex: nil, outerCount: 0
        )

        XCTAssertEqual(inner.x, 15 / sqrt(2), accuracy: 1e-10)
        XCTAssertEqual(inner.y, 15 / sqrt(2), accuracy: 1e-10)
        XCTAssertEqual(middle.x, -25 / sqrt(2), accuracy: 1e-10)
        XCTAssertEqual(middle.y, 25 / sqrt(2), accuracy: 1e-10)
    }

    func testAlignedIndexUsesAngularContainmentInsteadOfSharedIndex() {
        let middle = RingBandGeometry(slotCount: 4, angularOffset: .pi / 2)
        let inner = RingBandGeometry(slotCount: 8)

        XCTAssertEqual(
            RadialGeometry.alignedIndex(
                sourceIndex: 0, sourceGeometry: middle, targetGeometry: inner
            ),
            3
        )
    }

    private func point(angle: CGFloat, radius: CGFloat) -> CGPoint {
        CGPoint(x: radius * cos(angle), y: radius * sin(angle))
    }

    private func hit(_ point: CGPoint,
                     geometry: TopLevelRingGeometry,
                     innerItems: Int = 4,
                     middleItems: Int = 4,
                     parent: Int? = nil,
                     outerCount: Int = 0,
                     outerLayout: OuterRingLayout = .localizedArc) -> (band: Band, index: Int)? {
        RadialGeometry.hitTest(
            point: point, center: center, radii: radii, geometry: geometry,
            innerItemCount: innerItems, middleItemCount: middleItems,
            expandedParentIndex: parent, outerCount: outerCount,
            outerLayout: outerLayout
        )
    }

    private func XCTAssertHit(_ point: CGPoint,
                              geometry: TopLevelRingGeometry,
                              innerItems: Int,
                              middleItems: Int,
                              parent: Int? = nil,
                              outerCount: Int = 0,
                              outerLayout: OuterRingLayout = .localizedArc,
                              band: Band,
                              index: Int,
                              file: StaticString = #filePath,
                              line: UInt = #line) {
        let result = hit(point, geometry: geometry, innerItems: innerItems,
                         middleItems: middleItems, parent: parent,
                         outerCount: outerCount, outerLayout: outerLayout)
        XCTAssertEqual(result?.band, band, file: file, line: line)
        XCTAssertEqual(result?.index, index, file: file, line: line)
    }
}
