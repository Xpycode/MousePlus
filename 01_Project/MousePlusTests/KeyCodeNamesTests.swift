import AppKit
import XCTest
@testable import MousePlus

/// Key labels must follow the user's keyboard layout, not a US table.
/// Regression: on a German keyboard, key 42 (#) displayed as "\".
final class KeyCodeNamesTests: XCTestCase {
    /// Stand-in for a German layout's unmodified output.
    private let german: (UInt16) -> String? = { code in
        [42: "#", 6: "y", 16: "z", 27: "ß", 24: "´", 33: "ü", 82: "0", 65: ","][code]
    }
    private let noLayout: (UInt16) -> String? = { _ in nil }

    func testLayoutLabelReplacesUSTable() {
        XCTAssertEqual(KeyCodeNames.key(42, layoutLabel: german), "#")
        XCTAssertEqual(KeyCodeNames.key(24, layoutLabel: german), "´")
    }

    func testLettersAreLabelledByPhysicalPosition() {
        // Bindings store physical key codes: code 16 is the key a German keyboard labels Z.
        XCTAssertEqual(KeyCodeNames.key(16, layoutLabel: german), "Z")
        XCTAssertEqual(KeyCodeNames.key(6, layoutLabel: german), "Y")
        XCTAssertEqual(KeyCodeNames.key(33, layoutLabel: german), "Ü")
    }

    func testKeyCapThatCannotUppercaseToOneCharacterIsKept() {
        XCTAssertEqual(KeyCodeNames.key(27, layoutLabel: german), "ß")
    }

    func testFixedKeysIgnoreTheLayout() {
        let garbage: (UInt16) -> String? = { _ in "?" }
        XCTAssertEqual(KeyCodeNames.key(36, layoutLabel: garbage), "Return")
        XCTAssertEqual(KeyCodeNames.key(49, layoutLabel: garbage), "Space")
        XCTAssertEqual(KeyCodeNames.key(96, layoutLabel: garbage), "F5")
        XCTAssertEqual(KeyCodeNames.key(123, layoutLabel: garbage), "←")
    }

    func testKeypadKeysAreDistinguishedFromTheMainRow() {
        XCTAssertEqual(KeyCodeNames.key(82, layoutLabel: german), "Keypad 0")
        XCTAssertEqual(KeyCodeNames.key(65, layoutLabel: german), "Keypad ,")
        XCTAssertEqual(KeyCodeNames.key(65, layoutLabel: noLayout), "Keypad .")
        XCTAssertEqual(KeyCodeNames.key(76, layoutLabel: german), "Keypad Enter")
    }

    func testFallsBackToUSTableThenToKeyNumber() {
        XCTAssertEqual(KeyCodeNames.key(42, layoutLabel: noLayout), "\\")
        XCTAssertEqual(KeyCodeNames.key(200, layoutLabel: noLayout), "Key 200")
    }

    @MainActor
    func testLiveLayoutNamesPrintableKeysAndSkipsNonPrintingOnes() {
        // Whatever layout this Mac uses, key 0 prints one visible character and Return prints none.
        XCTAssertEqual(KeyCodeNames.currentLayoutLabel(0)?.count, 1)
        XCTAssertNil(KeyCodeNames.currentLayoutLabel(36))
    }

    func testBindingDisplayStringKeepsModifierPrefix() {
        let flags = NSEvent.ModifierFlags([.command, .shift]).rawValue
        let binding = TriggerBinding.keyboard(keyCode: 36, modifiers: flags, mode: .holdRelease)
        XCTAssertEqual(binding.displayString, "Shift+Cmd+Return")
    }
}
