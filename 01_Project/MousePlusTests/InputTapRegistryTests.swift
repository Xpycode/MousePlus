import XCTest
@testable import MousePlus

/// Fake tap handle: never creates a CGEventTap or mach port.
@MainActor
final class FakeTapHandle: InputTapHandle {
    private(set) var isEnabled = false
    private(set) var isInvalidated = false
    private(set) var invalidateCount = 0

    func setEnabled(_ enabled: Bool) {
        guard !isInvalidated else { return }
        isEnabled = enabled
    }

    func invalidate() {
        invalidateCount += 1
        isInvalidated = true
        isEnabled = false
    }
}

final class InputTapRegistryTests: XCTestCase {
    @MainActor
    func testRegisterUnregister() {
        let registry = InputTapRegistry()
        let a = FakeTapHandle(), b = FakeTapHandle()
        registry.register(a)
        registry.register(b)
        registry.register(a)
        XCTAssertEqual(registry.registeredCount, 2)
        registry.unregister(a)
        XCTAssertEqual(registry.registeredCount, 1)
    }

    @MainActor
    func testTeardownAllDisablesAndInvalidatesEveryHandleAndIsIdempotent() {
        let registry = InputTapRegistry()
        let handles = (0..<3).map { _ in FakeTapHandle() }
        for h in handles { registry.register(h); h.setEnabled(true) }
        XCTAssertEqual(registry.enabledCount, 3)

        registry.teardownAll()
        XCTAssertEqual(registry.registeredCount, 0)
        XCTAssertEqual(registry.enabledCount, 0)
        XCTAssertTrue(handles.allSatisfy { $0.isInvalidated && !$0.isEnabled })

        registry.teardownAll()
        XCTAssertTrue(handles.allSatisfy { $0.invalidateCount == 1 })
    }

    @MainActor
    func testMouseTriggerTapRegistersAndUnregisters() throws {
        let registry = InputTapRegistry()
        let handle = FakeTapHandle()
        let tap = SystemMouseButtonTriggerTap(registry: registry, factory: { _, _, _ in handle })
        try tap.start { _, _ in false }
        XCTAssertEqual(registry.registeredCount, 1)
        XCTAssertTrue(handle.isEnabled)

        registry.teardownAll()
        XCTAssertEqual(registry.enabledCount, 0)
        XCTAssertTrue(handle.isInvalidated)
        tap.stop()
        XCTAssertEqual(registry.registeredCount, 0)

        try tap.start { _, _ in false }
        tap.stop()
        XCTAssertEqual(registry.registeredCount, 0)
    }

    @MainActor
    func testMouseTriggerTapCreationFailureRegistersNothing() {
        let registry = InputTapRegistry()
        let tap = SystemMouseButtonTriggerTap(registry: registry, factory: { _, _, _ in nil })
        XCTAssertThrowsError(try tap.start { _, _ in false })
        XCTAssertEqual(registry.registeredCount, 0)
    }

    @MainActor
    func testReenableAfterDisableOnlyHappensOnExplicitCall() throws {
        let registry = InputTapRegistry()
        let handle = FakeTapHandle()
        let tap = SystemMouseButtonTriggerTap(registry: registry, factory: { _, _, _ in handle })
        try tap.start { _, _ in false }
        handle.setEnabled(false) // what macOS does on a disable event
        XCTAssertFalse(handle.isEnabled)
        tap.reenable()
        XCTAssertTrue(handle.isEnabled)
        tap.stop()
    }

    func testDisableReasonMapping() {
        XCTAssertEqual(InputTapDisableReason(eventType: .tapDisabledByTimeout), .timeout)
        XCTAssertEqual(InputTapDisableReason(eventType: .tapDisabledByUserInput), .userInput)
        XCTAssertNil(InputTapDisableReason(eventType: .otherMouseDown))
    }
}
