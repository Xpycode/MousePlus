import CoreGraphics
import XCTest
@testable import MousePlus

final class MouseButtonTriggerMonitorTests: XCTestCase {
    func testQuartzTopLeftPointConvertsToCocoaBottomLeft() {
        let point = MouseButtonTriggerMonitor.cocoaScreenPoint(
            fromQuartz: CGPoint(x: 120, y: 100),
            mainDisplayHeight: 1080
        )
        XCTAssertEqual(point, CGPoint(x: 120, y: 980))
    }

    func testPointsAboveMainDisplayKeepNegativeQuartzMeaning() {
        // A secondary display above the main one has negative Quartz y.
        let point = MouseButtonTriggerMonitor.cocoaScreenPoint(
            fromQuartz: CGPoint(x: -300, y: -200),
            mainDisplayHeight: 1080
        )
        XCTAssertEqual(point, CGPoint(x: -300, y: 1280))
    }
}
