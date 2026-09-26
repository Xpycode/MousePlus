import XCTest
@testable import MousePlus

final class HUDOpeningPreviewTests: XCTestCase {
    func testReplayAvailabilityRequiresLoadedEnabledNonOffStyle() {
        XCTAssertFalse(HUDOpeningPreviewPresentation(
            style: .bloom, motionEnabled: true, isLoaded: false, reduceMotion: false
        ).canReplay)
        XCTAssertFalse(HUDOpeningPreviewPresentation(
            style: .bloom, motionEnabled: false, isLoaded: true, reduceMotion: false
        ).canReplay)
        XCTAssertFalse(HUDOpeningPreviewPresentation(
            style: .off, motionEnabled: true, isLoaded: true, reduceMotion: false
        ).canReplay)
        XCTAssertTrue(HUDOpeningPreviewPresentation(
            style: .bloom, motionEnabled: true, isLoaded: true, reduceMotion: false
        ).canReplay)
    }

    func testReduceMotionDescribesEffectiveFadeWithoutChangingSavedChoice() {
        let presentation = HUDOpeningPreviewPresentation(
            style: .circularSweep,
            motionEnabled: true,
            isLoaded: true,
            reduceMotion: true
        )

        XCTAssertEqual(presentation.selectedStyleTitle, "Circular Sweep")
        XCTAssertEqual(presentation.effectiveStyleTitle, "Fade")
        XCTAssertEqual(presentation.caption, "Reduce Motion preview: Fade")
        XCTAssertTrue(presentation.canReplay)
    }

    func testFadeIsUnchangedByReduceMotionAndOffIsDescribedAsStatic() {
        XCTAssertEqual(HUDOpeningPreviewPresentation(
            style: .fade, motionEnabled: true, isLoaded: true, reduceMotion: true
        ).caption, "Preview: Fade")
        XCTAssertEqual(HUDOpeningPreviewPresentation(
            style: .off, motionEnabled: true, isLoaded: true, reduceMotion: false
        ).caption, "Preview: Off")
    }
}
