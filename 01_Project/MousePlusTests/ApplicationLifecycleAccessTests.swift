import AppKit
import XCTest
@testable import MousePlus

@MainActor
final class ApplicationLifecycleAccessTests: XCTestCase {
    override func tearDown() {
        AppDelegate.quitApplication = nil
        super.tearDown()
    }

    func testMenuQuitInvokesConfiguredCallback() {
        let controller = MenuBarController()
        var quitCount = 0
        controller.onQuitClicked = { quitCount += 1 }

        controller.performQuit()

        XCTAssertEqual(quitCount, 1)
    }

    func testGeneralQuitBridgeInvokesConfiguredCallback() {
        var quitCount = 0
        AppDelegate.quitApplication = { quitCount += 1 }

        GeneralSettingsPane.performQuit()

        XCTAssertEqual(quitCount, 1)
        XCTAssertEqual(GeneralSettingsPane.quitAccessibilityIdentifier, "general.quitMousePlus")
    }

    func testStatusImageIsExplicitlySizedAndTemplateRendered() throws {
        let image = try XCTUnwrap(MenuBarController.makeStatusImage())

        XCTAssertEqual(image.size, NSSize(width: 18, height: 18))
        XCTAssertTrue(image.isTemplate)
        XCTAssertEqual(MenuBarController.statusButtonAccessibilityIdentifier, "menuBar.statusItem")
        XCTAssertEqual(MenuBarController.quitMenuItemAccessibilityIdentifier, "menuBar.quitMousePlus")
    }
}
