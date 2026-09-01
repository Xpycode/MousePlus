import XCTest
@testable import MousePlus

final class ActionTypeCodingTests: XCTestCase {
    func testKnownActionTypesRoundTrip() throws {
        for actionType in ActionType.allCases {
            let data = try JSONEncoder().encode(actionType)
            XCTAssertEqual(try JSONDecoder().decode(ActionType.self, from: data), actionType)
        }
        XCTAssertTrue(ActionType.allCases.contains(.sendKeystroke))
    }

    func testLegacyClipboardRoundTripsWithoutBecomingCustom() throws {
        try assertUnavailableRoundTrip("clipboard")
    }

    func testArbitraryFutureValueRoundTripsLosslessly() throws {
        try assertUnavailableRoundTrip("future.action/v2")
    }

    func testSelectableCasesAreSeparateFromKnownDecodableCases() {
        XCTAssertFalse(ActionType.selectableCases.contains(.sendKeystroke))
        XCTAssertFalse(ActionType.selectableCases.contains(.menuBar))
        XCTAssertFalse(ActionType.selectableCases.contains(.systemToggle))
        XCTAssertFalse(ActionType.selectableCases.contains(.screenshot))
        XCTAssertTrue(ActionType.allCases.contains(.menuBar))
    }

    private func assertUnavailableRoundTrip(_ rawValue: String) throws {
        let encoded = try JSONEncoder().encode(rawValue)
        let decoded = try JSONDecoder().decode(ActionType.self, from: encoded)
        XCTAssertEqual(decoded, .unavailable(rawValue))
        XCTAssertEqual(try JSONDecoder().decode(String.self, from: JSONEncoder().encode(decoded)), rawValue)
    }
}
