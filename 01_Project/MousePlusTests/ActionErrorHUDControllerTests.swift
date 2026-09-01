import AppKit
import XCTest
@testable import MousePlus

@MainActor
final class ActionErrorHUDControllerTests: XCTestCase {
    func testHUDUsesNonActivatingPanelAndRetainsFailureRoute() {
        let failure = RuntimeActionFailure(message: "Permission denied", settingsRoute: .menuItem(UUID()))
        let controller = ActionErrorHUDController(presentsWindows: false) { _ in }
        controller.show(failure)
        XCTAssertEqual(controller.displayedFailure, failure)
        XCTAssertTrue(controller.panel?.styleMask.contains(.nonactivatingPanel) == true)
        XCTAssertEqual(controller.panel?.canBecomeKey, false)
        controller.dismiss()
    }

    func testOpenSettingsDismissesAndForwardsExactRoute() {
        let itemID = UUID()
        var received: ActionSettingsRoute?
        let controller = ActionErrorHUDController(presentsWindows: false) { received = $0 }
        controller.show(RuntimeActionFailure(message: "Unavailable", settingsRoute: .menuItem(itemID)))
        controller.openSettings()
        XCTAssertEqual(received, .menuItem(itemID))
        XCTAssertNil(controller.panel)
        XCTAssertNil(controller.displayedFailure)
    }

    func testReplacementShowsNewestFailure() {
        let controller = ActionErrorHUDController(presentsWindows: false) { _ in }
        let newest = RuntimeActionFailure(message: "Newest", settingsRoute: .menuItem(UUID()))
        controller.show(RuntimeActionFailure(message: "Old", settingsRoute: .menuItem(UUID())))
        controller.show(newest)
        XCTAssertEqual(controller.displayedFailure, newest)
        controller.dismiss()
    }
}
