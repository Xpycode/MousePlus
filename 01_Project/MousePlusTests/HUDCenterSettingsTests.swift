import XCTest
@testable import MousePlus

@MainActor
final class HUDCenterSettingsTests: XCTestCase {
    func testActivationResetsBeforeRequestingCloseAndSettings() {
        let viewModel = RingViewModel()
        viewModel.activeSelection = ActiveSelection(band: .inner, index: 0)
        viewModel.expandedParentIndex = 0
        viewModel.outerItems = [RingMenuItem.sampleItems[0]]
        var events: [String] = []
        viewModel.requestClose = {
            XCTAssertNil(viewModel.activeSelection)
            XCTAssertNil(viewModel.expandedParentIndex)
            XCTAssertTrue(viewModel.outerItems.isEmpty)
            events.append("close")
        }
        viewModel.requestOpenMenuItemsSettings = {
            XCTAssertNil(viewModel.activeSelection)
            events.append("settings")
        }

        viewModel.activateCenterSettings()

        XCTAssertEqual(events, ["close", "settings"])
    }

    func testReleaseAfterCenterActivationCannotCommitPreviouslyActiveItem() {
        let viewModel = RingViewModel()
        viewModel.activeSelection = ActiveSelection(band: .inner, index: 0)
        var closeCount = 0
        var settingsCount = 0
        viewModel.requestClose = { closeCount += 1 }
        viewModel.requestOpenMenuItemsSettings = { settingsCount += 1 }

        viewModel.activateCenterSettings()
        viewModel.commitActive() // subsequent hold-release delivery

        XCTAssertEqual(closeCount, 1)
        XCTAssertEqual(settingsCount, 1)
        XCTAssertNil(viewModel.activeSelection)
    }

    func testTapToggleActivationUsesOnlyCenterCallbacks() {
        let viewModel = RingViewModel()
        viewModel.activeSelection = ActiveSelection(band: .middle, index: 0)
        var events: [String] = []
        viewModel.requestClose = { events.append("close") }
        viewModel.requestOpenMenuItemsSettings = { events.append("settings") }

        viewModel.activateCenterSettings()

        XCTAssertEqual(events, ["close", "settings"])
        XCTAssertNil(viewModel.activeSelection)
    }

    func testControlHasStableAccessibilityMetadata() {
        XCTAssertEqual(HUDCenterSettingsControl.accessibilityIdentifier, "hud.center.settings")
        XCTAssertEqual(HUDCenterSettingsControl.accessibilityLabel, "Open MousePlus Settings")
    }

    func testMovementAtThresholdRemainsAClick() {
        var state = HUDCenterDragState()
        state.begin(at: .zero)

        XCTAssertNil(state.move(to: CGPoint(x: 4, y: 0)))
        XCTAssertTrue(state.end())
    }

    func testMovementBeyondThresholdBecomesDragAndCannotClick() {
        var state = HUDCenterDragState()
        state.begin(at: CGPoint(x: 10, y: 10))

        XCTAssertEqual(state.move(to: CGPoint(x: 13, y: 14)), CGSize(width: 3, height: 4))
        XCTAssertTrue(state.isDragging)
        XCTAssertEqual(state.move(to: CGPoint(x: 15, y: 17)), CGSize(width: 2, height: 3))
        XCTAssertFalse(state.end())
    }

    func testPanelOriginClampsToVisibleFrameIncludingOffsetScreens() {
        let visible = CGRect(x: -1200, y: 30, width: 1000, height: 800)
        let size = CGSize(width: 472, height: 472)

        XCTAssertEqual(
            HUDPanelGeometry.clampedOrigin(CGPoint(x: -1400, y: -100), size: size, in: visible),
            CGPoint(x: -1200, y: 30)
        )
        XCTAssertEqual(
            HUDPanelGeometry.clampedOrigin(CGPoint(x: 0, y: 900), size: size, in: visible),
            CGPoint(x: -672, y: 358)
        )
    }

    func testPanelLargerThanScreenPinsToMinimumEdges() {
        XCTAssertEqual(
            HUDPanelGeometry.clampedOrigin(
                CGPoint(x: 100, y: 100),
                size: CGSize(width: 600, height: 700),
                in: CGRect(x: 20, y: 40, width: 500, height: 500)
            ),
            CGPoint(x: 20, y: 40)
        )
    }
}
