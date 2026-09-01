import XCTest
@testable import MousePlus

@MainActor
final class PostEventPermissionsStateTests: XCTestCase {
    func testRefreshOnlyPreflightsAndNeverRequests() {
        let checker = PostEventPermissionCheckerStub(granted: false)
        let state = PostEventPermissionsState(checker: checker)

        state.refresh()

        XCTAssertFalse(state.isGranted)
        XCTAssertEqual(checker.preflightCount, 2)
        XCTAssertEqual(checker.requestCount, 0)
    }

    func testExplicitUserRequestRequestsOnceAndRefreshes() {
        let checker = PostEventPermissionCheckerStub(granted: false)
        let state = PostEventPermissionsState(checker: checker)
        checker.granted = true

        state.requestFromUserAction()

        XCTAssertTrue(state.isGranted)
        XCTAssertEqual(checker.requestCount, 1)
        XCTAssertEqual(checker.preflightCount, 2)
    }
}

private final class PostEventPermissionCheckerStub: PostEventPermissionChecking {
    var granted: Bool
    private(set) var preflightCount = 0
    private(set) var requestCount = 0

    init(granted: Bool) { self.granted = granted }

    func preflight() -> Bool {
        preflightCount += 1
        return granted
    }

    func request() -> Bool {
        requestCount += 1
        return granted
    }
}
