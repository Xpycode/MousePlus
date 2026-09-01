import AppKit
import ShortcutKit
import XCTest
@testable import MousePlus

final class KeystrokeShortcutKitAdapterTests: XCTestCase {
    func testCanonicalPayloadRoundTripsAndMasksModifiers() {
        let shortcut = CustomKeyboardShortcut(
            keyCode: 8,
            modifiers: [.command, .shift, .capsLock, .numericPad],
            displayName: "layout-dependent"
        )

        let payload = KeystrokePayload(shortcutKitValue: shortcut)

        XCTAssertEqual(payload, .key(keyCode: 8, modifiers: NSEvent.ModifierFlags([.command, .shift]).rawValue))
        XCTAssertEqual(payload?.shortcutKitValue.keyCode, 8)
        XCTAssertEqual(payload?.shortcutKitValue.modifiers, [.command, .shift])
        XCTAssertFalse(payload?.shortcutKitValue.displayName.isEmpty ?? true)
        XCTAssertNotEqual(payload?.shortcutKitValue.resolvedDisplayName, "None")
    }

    func testUnboundAndOutOfRangeValuesDoNotBecomePayloads() {
        XCTAssertNil(KeystrokePayload(shortcutKitValue: .none))
        XCTAssertNil(KeystrokePayload(shortcutKitValue: .init(keyCode: -2, modifiers: [], displayName: "")))
        XCTAssertNil(KeystrokePayload(shortcutKitValue: .init(keyCode: 65_536, modifiers: [], displayName: "")))
    }

    func testUnresolvedLegacyDoesNotGuessARecorderBinding() {
        XCTAssertTrue(KeystrokePayload.unresolvedLegacy("⌘C").shortcutKitValue.isUnbound)
    }

    func testSystemWideConflictBlocksButAppResponderConflictOnlyWarns() {
        let checker = KeystrokeConflictChecker(systemState: .curatedOnly)
        let spotlight = CustomKeyboardShortcut(keyCode: 49, modifiers: [.command], displayName: "⌘Space")
        let copy = CustomKeyboardShortcut(keyCode: 8, modifiers: [.command], displayName: "⌘C")

        XCTAssertEqual(checker.assessment(for: spotlight)?.severity, .blocked)
        XCTAssertEqual(checker.assessment(for: copy)?.severity, .advisory)
        XCTAssertNil(checker.assessment(for: .none))
    }
}
