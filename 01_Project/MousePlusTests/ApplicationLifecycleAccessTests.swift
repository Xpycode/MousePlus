import AppKit
import XCTest
@testable import MousePlus

@MainActor
final class ApplicationLifecycleAccessTests: XCTestCase {
    override func tearDown() {
        AppDelegate.quitApplication = nil
        AppDelegate.restartApplication = nil
        AppDelegate.flushPendingSettingsChanges = nil
        super.tearDown()
    }

    func testMenuQuitInvokesConfiguredCallback() {
        let controller = MenuBarController()
        var quitCount = 0
        controller.onQuitClicked = { quitCount += 1 }

        controller.performQuit()

        XCTAssertEqual(quitCount, 1)
    }

    func testMenuRestartInvokesConfiguredCallback() {
        let controller = MenuBarController()
        var restartCount = 0
        controller.onRestartClicked = { restartCount += 1 }

        controller.performRestart()

        XCTAssertEqual(restartCount, 1)
        XCTAssertEqual(MenuBarController.restartMenuItemAccessibilityIdentifier, "menuBar.restartMousePlus")
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

    func testQuitFlushesPendingSettingsBeforeTermination() async {
        var events: [String] = []

        let didQuit = await AppDelegate.performApplicationQuit(
            flush: {
                events.append("flush")
                return true
            },
            terminate: { events.append("terminate") }
        )

        XCTAssertTrue(didQuit)
        XCTAssertEqual(events, ["flush", "terminate"])
    }

    func testQuitDoesNotTerminateWhenPendingSettingsCannotBeSaved() async {
        var didTerminate = false

        let didQuit = await AppDelegate.performApplicationQuit(
            flush: { false },
            terminate: { didTerminate = true }
        )

        XCTAssertFalse(didQuit)
        XCTAssertFalse(didTerminate)
    }

    func testRestartFlushesLaunchBeforeTermination() async {
        var events: [String] = []

        let didRestart = await AppDelegate.performApplicationRestart(
            flush: { events.append("flush"); return true },
            relaunch: { events.append("launch"); return true },
            terminate: { events.append("terminate") }
        )

        XCTAssertTrue(didRestart)
        XCTAssertEqual(events, ["flush", "launch", "terminate"])
    }

    func testRestartDoesNotTerminateWhenLaunchFails() async {
        var didTerminate = false

        let didRestart = await AppDelegate.performApplicationRestart(
            flush: { true },
            relaunch: { false },
            terminate: { didTerminate = true }
        )

        XCTAssertFalse(didRestart)
        XCTAssertFalse(didTerminate)
    }
}
