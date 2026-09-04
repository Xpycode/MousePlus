import XCTest
import SwiftUI
@testable import MousePlus

final class HUDOuterBandMotionTests: XCTestCase {
    private let radial = HUDMotionPresentationDescriptor(effect: .radialReveal, duration: 0.15)
    private let parentMidpoint = Angle.degrees(90)
    private let finalStart = Angle.degrees(60)
    private let finalEnd = Angle.degrees(120)

    func testLocalizedRevealStartsAtParentMidpointAndInnerEdge() {
        let frame = resolve(layout: .localizedArc, descriptor: radial, progress: 0)

        XCTAssertEqual(frame.startAngle.degrees, parentMidpoint.degrees, accuracy: 0.000_001)
        XCTAssertEqual(frame.endAngle.degrees, parentMidpoint.degrees, accuracy: 0.000_001)
        XCTAssertEqual(frame.innerRadius, 150)
        XCTAssertEqual(frame.outerRadius, 150)
        XCTAssertEqual(frame.contentOpacity, 0)
    }

    func testLocalizedRevealInterpolatesToFinalGeometry() {
        let halfway = resolve(layout: .localizedArc, descriptor: radial, progress: 0.5)
        let final = resolve(layout: .localizedArc, descriptor: radial, progress: 1)

        XCTAssertEqual(halfway.startAngle.degrees, 75, accuracy: 0.000_001)
        XCTAssertEqual(halfway.endAngle.degrees, 105, accuracy: 0.000_001)
        XCTAssertEqual(halfway.outerRadius, 187)
        XCTAssertEqual(halfway.contentOpacity, 0.5)
        XCTAssertEqual(final.startAngle.degrees, finalStart.degrees, accuracy: 0.000_001)
        XCTAssertEqual(final.endAngle.degrees, finalEnd.degrees, accuracy: 0.000_001)
        XCTAssertEqual(final.outerRadius, 224)
        XCTAssertEqual(final.contentOpacity, 1)
    }

    func testFullCircleKeepsFinalAnglesWhileAllWedgesGrowOutward() {
        let initial = resolve(layout: .fullCircle, descriptor: radial, progress: 0)
        let halfway = resolve(layout: .fullCircle, descriptor: radial, progress: 0.5)

        XCTAssertEqual(initial.startAngle.degrees, finalStart.degrees, accuracy: 0.000_001)
        XCTAssertEqual(initial.endAngle.degrees, finalEnd.degrees, accuracy: 0.000_001)
        XCTAssertEqual(initial.outerRadius, 150)
        XCTAssertEqual(halfway.startAngle.degrees, finalStart.degrees, accuracy: 0.000_001)
        XCTAssertEqual(halfway.endAngle.degrees, finalEnd.degrees, accuracy: 0.000_001)
        XCTAssertEqual(halfway.outerRadius, 187)
    }

    func testReducedMotionFadeKeepsFinalGeometry() {
        let fade = HUDMotionPresentationDescriptor(effect: .fade, duration: 0.15)
        let initial = resolve(layout: .localizedArc, descriptor: fade, progress: 0)

        XCTAssertEqual(initial.startAngle.degrees, finalStart.degrees, accuracy: 0.000_001)
        XCTAssertEqual(initial.endAngle.degrees, finalEnd.degrees, accuracy: 0.000_001)
        XCTAssertEqual(initial.innerRadius, 150)
        XCTAssertEqual(initial.outerRadius, 224)
        XCTAssertEqual(initial.contentOpacity, 0)
    }

    func testInstantModeUsesFinalGeometryOnFirstFrame() {
        let initial = resolve(layout: .localizedArc, descriptor: .instant, progress: 0)

        XCTAssertEqual(initial.startAngle.degrees, finalStart.degrees, accuracy: 0.000_001)
        XCTAssertEqual(initial.endAngle.degrees, finalEnd.degrees, accuracy: 0.000_001)
        XCTAssertEqual(initial.outerRadius, 224)
        XCTAssertEqual(initial.contentOpacity, 1)
    }

    func testProgressClampsOutsideUnitInterval() {
        XCTAssertEqual(resolve(layout: .localizedArc, descriptor: radial, progress: -1).outerRadius, 150)
        XCTAssertEqual(resolve(layout: .localizedArc, descriptor: radial, progress: 2).outerRadius, 224)
    }

    private func resolve(
        layout: OuterRingLayout,
        descriptor: HUDMotionPresentationDescriptor,
        progress: CGFloat
    ) -> HUDOuterBandMotionFrame {
        HUDOuterBandMotionFrame.resolve(
            layout: layout,
            descriptor: descriptor,
            progress: progress,
            parentMidpoint: parentMidpoint,
            finalStartAngle: finalStart,
            finalEndAngle: finalEnd,
            innerRadius: 150,
            outerRadius: 224
        )
    }
}
