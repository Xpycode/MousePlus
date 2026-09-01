import XCTest
@testable import MousePlus

final class KeystrokePayloadCodingTests: XCTestCase {
    private let id = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!

    func testCanonicalPayloadRoundTrips() throws {
        let item = makeItem(payload: .key(keyCode: 8, modifiers: 1 << 20))
        XCTAssertEqual(try roundTrip(item).keystrokePayload, item.keystrokePayload)
    }

    func testCanonicalModifiersAreMaskedOnEncodeAndDecode() throws {
        let encoded = try JSONEncoder().encode(KeystrokePayload.key(keyCode: 8, modifiers: UInt.max))
        XCTAssertEqual(
            try JSONDecoder().decode(KeystrokePayload.self, from: encoded),
            .key(keyCode: 8, modifiers: KeystrokePayload.modifierMask)
        )
        let data = Data(#"{"kind":"key","keyCode":8,"modifiers":18446744073709551615}"#.utf8)
        XCTAssertEqual(
            try JSONDecoder().decode(KeystrokePayload.self, from: data),
            .key(keyCode: 8, modifiers: KeystrokePayload.modifierMask)
        )
    }

    func testCanonicalPayloadWinsOverLegacyField() throws {
        let json = itemJSON(extra: #", "keystrokePayload":{"kind":"key","keyCode":9,"modifiers":0}, "keyboardShortcut":"⌘C""#)
        XCTAssertEqual(try decode(json).keystrokePayload, .key(keyCode: 9, modifiers: 0))
    }

    func testExplicitNumericLegacyPayloadMigrates() throws {
        let legacy = #"{"keyCode":8,"modifiers":1048576}"#
        let json = itemJSON(extra: #", "keyboardShortcut":"\#(escaped(legacy))""#)
        XCTAssertEqual(try decode(json).keystrokePayload, .key(keyCode: 8, modifiers: 1 << 20))
    }

    func testAmbiguousLegacyPayloadRemainsUnresolvedAndIsNotReencodedAsLegacy() throws {
        let item = try decode(itemJSON(extra: #", "keyboardShortcut":"⌘C""#))
        XCTAssertEqual(item.keystrokePayload, .unresolvedLegacy("⌘C"))

        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(item)) as? [String: Any])
        XCTAssertNil(object["keyboardShortcut"])
        XCTAssertNotNil(object["keystrokePayload"])
    }

    func testMissingAndEmptyLegacyFieldsProduceNoPayload() throws {
        XCTAssertNil(try decode(itemJSON()).keystrokePayload)
        XCTAssertNil(try decode(itemJSON(extra: #", "keyboardShortcut":"""#)).keystrokePayload)
    }

    func testNestedSubItemsMigrateRecursively() throws {
        let child = itemJSON(extra: #", "keyboardShortcut":"⌘V""#)
        let parent = itemJSON(extra: #", "subItems":[\#(child)]"#)
        XCTAssertEqual(try decode(parent).subItems?.first?.keystrokePayload, .unresolvedLegacy("⌘V"))
    }

    private func makeItem(payload: KeystrokePayload?) -> RingMenuItem {
        RingMenuItem(id: id, label: "Copy", icon: "doc.on.doc", actionType: .custom, keystrokePayload: payload)
    }

    private func roundTrip(_ item: RingMenuItem) throws -> RingMenuItem {
        try JSONDecoder().decode(RingMenuItem.self, from: JSONEncoder().encode(item))
    }

    private func decode(_ json: String) throws -> RingMenuItem {
        try JSONDecoder().decode(RingMenuItem.self, from: Data(json.utf8))
    }

    private func itemJSON(extra: String = "") -> String {
        #"{"id":"\#(id.uuidString)","label":"Copy","icon":"doc.on.doc","actionType":"custom","actionData":""\#(extra)}"#
    }

    private func escaped(_ value: String) -> String {
        let data = try! JSONEncoder().encode(value)
        return String(decoding: data.dropFirst().dropLast(), as: UTF8.self)
    }
}
