import Foundation
import XCTest
@testable import MousePlus

final class ActionResultRouterTests: XCTestCase {
    func testSettingsRetainsResultsIndependentlyPerItem() async {
        let router = ActionResultRouter()
        let firstID = UUID()
        let secondID = UUID()

        await router.routeSettingsResult(.succeeded(message: "Opened"), for: firstID)
        await router.routeSettingsResult(.failed(message: "Denied"), for: secondID)

        let first = await router.settingsResult(for: firstID)
        let second = await router.settingsResult(for: secondID)
        XCTAssertEqual(first?.result, .succeeded(message: "Opened"))
        XCTAssertEqual(second?.result, .failed(message: "Denied"))
    }

    func testNewSettingsResultReplacesOldResultForSameItem() async {
        let router = ActionResultRouter()
        let itemID = UUID()

        let old = await router.routeSettingsResult(.failed(message: "First"), for: itemID)
        let new = await router.routeSettingsResult(.succeeded(message: "Retried"), for: itemID)

        XCTAssertNotEqual(old.id, new.id)
        let retained = await router.settingsResult(for: itemID)
        XCTAssertEqual(retained, new)
    }

    func testStaleDismissalDoesNotRemoveReplacement() async {
        let router = ActionResultRouter()
        let itemID = UUID()

        let old = await router.routeSettingsResult(.failed(message: "First"), for: itemID)
        let replacement = await router.routeSettingsResult(.succeeded(message: "Retried"), for: itemID)
        await router.dismissSettingsResult(id: old.id, for: itemID)

        let retained = await router.settingsResult(for: itemID)
        XCTAssertEqual(retained, replacement)
        await router.dismissSettingsResult(id: replacement.id, for: itemID)
        let dismissed = await router.settingsResult(for: itemID)
        XCTAssertNil(dismissed)
    }

    func testRuntimeFailureEmitsMessageAndSettingsRoute() async {
        let recorder = RuntimeFailureRecorder()
        let router = ActionResultRouter { failure in
            await recorder.record(failure)
        }
        let itemID = UUID()

        await router.routeRuntimeResult(.failed(message: "Command exited 1"), for: itemID)

        let failures = await recorder.failures
        XCTAssertEqual(failures, [RuntimeActionFailure(
            message: "Command exited 1",
            settingsRoute: .menuItem(itemID)
        )])
    }

    func testRuntimeSuccessEmitsNothing() async {
        let recorder = RuntimeFailureRecorder()
        let router = ActionResultRouter { failure in
            await recorder.record(failure)
        }

        await router.routeRuntimeResult(.succeeded(message: "Done"), for: UUID())

        let failures = await recorder.failures
        XCTAssertTrue(failures.isEmpty)
    }
}

private actor RuntimeFailureRecorder {
    private(set) var failures: [RuntimeActionFailure] = []

    func record(_ failure: RuntimeActionFailure) {
        failures.append(failure)
    }
}
