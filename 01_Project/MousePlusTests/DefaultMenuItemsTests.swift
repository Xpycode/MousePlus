import Foundation
import XCTest
@testable import MousePlus

final class DefaultMenuItemsTests: XCTestCase {
    func testFreshInnerDefaultsHaveExecutablePayloads() {
        let items = Dictionary(
            uniqueKeysWithValues: RingMenuItem.sampleInnerItems.map { ($0.label, $0) }
        )

        assertKeystroke(items["Copy"], keyCode: 8)
        assertKeystroke(items["Paste"], keyCode: 9)
        assertKeystroke(items["Spotlight"], keyCode: 49)

        XCTAssertEqual(items["Mission Control"]?.actionType, .custom)
        XCTAssertEqual(
            items["Mission Control"]?.actionData,
            "open -b com.apple.exposelauncher"
        )
        XCTAssertNil(items["Mission Control"]?.keystrokePayload)
    }

    func testPersistedInnerItemsAreNotReseededFromFreshDefaults() throws {
        let savedItem = RingMenuItem(
            id: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
            label: "Saved custom item",
            icon: "star",
            actionType: .custom,
            actionData: "echo preserved"
        )
        let saved = Configuration(inner: [savedItem])

        let decoded = try JSONDecoder().decode(
            Configuration.self,
            from: JSONEncoder().encode(saved)
        )

        XCTAssertEqual(decoded.inner, [savedItem])
        XCTAssertNotEqual(decoded.inner, RingMenuItem.sampleInnerItems)
    }

    private func assertKeystroke(
        _ item: RingMenuItem?,
        keyCode: UInt16,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(item?.actionType, .sendKeystroke, file: file, line: line)
        XCTAssertEqual(
            item?.keystrokePayload,
            .key(keyCode: keyCode, modifiers: 1 << 20),
            file: file,
            line: line
        )
        XCTAssertEqual(item?.actionData, "", file: file, line: line)
    }
}
