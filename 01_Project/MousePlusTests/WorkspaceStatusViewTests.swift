import XCTest
@testable import MousePlus

@MainActor
final class WorkspaceStatusViewTests: XCTestCase {
    func testEveryPersistenceStateHasVisibleText() {
        let cases: [(SettingsWorkspaceCoordinator.Status, String)] = [
            (.idle, "Not Loaded"),
            (.loading, "Loading…"),
            (.saving, "Saving…"),
            (.saved, "Saved"),
            (.saveFailed("Disk full"), "Save Failed"),
            (.loadFailed("Malformed JSON"), "Load Failed")
        ]

        for (status, expectedTitle) in cases {
            XCTAssertEqual(WorkspaceStatusPresentation(status: status).title, expectedTitle)
        }
    }

    func testFailuresExposeReasonAndRetry() {
        let save = WorkspaceStatusPresentation(status: .saveFailed("Read only"))
        XCTAssertEqual(save.detail, "Read only")
        XCTAssertTrue(save.isFailure)
        XCTAssertTrue(save.canRetry)

        let load = WorkspaceStatusPresentation(status: .loadFailed("Invalid data"))
        XCTAssertEqual(load.detail, "Invalid data")
        XCTAssertTrue(load.isFailure)
        XCTAssertTrue(load.canRetry)
    }

    func testCloseBarrierUsesRequiredExplicitChoices() {
        XCTAssertEqual(CloseBarrierPresentation.retryTitle, "Retry")
        XCTAssertEqual(CloseBarrierPresentation.discardTitle, "Discard Changes")
        XCTAssertEqual(CloseBarrierPresentation.cancelTitle, "Cancel Close")
        XCTAssertTrue(CloseBarrierPresentation.informativePrefix.contains("still in memory"))
    }
}
