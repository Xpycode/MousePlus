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
}
