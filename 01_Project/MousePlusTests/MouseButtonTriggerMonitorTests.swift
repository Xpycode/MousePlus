import AppKit
import XCTest
@testable import MousePlus

final class MouseButtonTriggerMonitorTests: XCTestCase {
    @MainActor
    func testConsumesConfiguredPressDragReleaseButLeavesOtherButtonsAlone() async throws {
        let tap = FakeMouseTriggerTap()
        let monitor = MouseButtonTriggerMonitor(tap: tap)
        var received: [String] = []
        var points: [CGPoint] = []
        monitor.start(buttonNumber: 4, onDown: { received.append("down"); points.append($0) },
                      onDragged: { received.append("drag"); points.append($0) },
                      onUp: { received.append("up"); points.append($0) })
        defer { monitor.stop() }
        XCTAssertFalse(try tap.send(.otherMouseUp, button: 4))
        XCTAssertFalse(try tap.send(.otherMouseDragged, button: 4))
        XCTAssertFalse(try tap.send(.otherMouseDown, button: 3))
        XCTAssertFalse(try tap.send(.leftMouseDown, button: 0))
        XCTAssertTrue(try tap.send(.otherMouseDown, button: 4))
        XCTAssertTrue(try tap.send(.otherMouseDown, button: 4))
        XCTAssertTrue(try tap.send(.otherMouseDragged, button: 4))
        XCTAssertFalse(try tap.send(.otherMouseUp, button: 3))
        XCTAssertTrue(try tap.send(.otherMouseUp, button: 4))
        XCTAssertFalse(try tap.send(.otherMouseUp, button: 4))
        XCTAssertEqual(received, ["down", "drag", "up"])
        XCTAssertEqual(points, Array(repeating: CGPoint(x: 125, y: (NSScreen.screens.first?.frame.maxY ?? 0) - 250), count: 3))
    }

    @MainActor
    func testReenablesTapAndStopsCleanly() async throws {
        let tap = FakeMouseTriggerTap()
        let monitor = MouseButtonTriggerMonitor(tap: tap)
        monitor.start(buttonNumber: 2, onDown: { _ in }, onDragged: { _ in }, onUp: { _ in })
        XCTAssertFalse(try tap.send(.tapDisabledByTimeout, button: 2))
        XCTAssertEqual(tap.reenableCount, 1)
        XCTAssertTrue(try tap.send(.otherMouseDown, button: 2))
        monitor.stop()
        XCTAssertNil(tap.handler)
        monitor.start(buttonNumber: 2, onDown: { _ in }, onDragged: { _ in }, onUp: { _ in })
        XCTAssertFalse(try tap.send(.otherMouseUp, button: 2))
        monitor.stop()
    }

    @MainActor
    func testTapFailureDoesNotInstallPassiveFallback() async {
        let tap = FakeMouseTriggerTap()
        tap.failStart = true
        let monitor = MouseButtonTriggerMonitor(tap: tap)
        monitor.start(buttonNumber: 4, onDown: { _ in XCTFail() },
                      onDragged: { _ in XCTFail() }, onUp: { _ in XCTFail() })
        XCTAssertNil(tap.handler)
    }

    @MainActor
    func testMouseRecorderFlagClearsOnCancel() async {
        let recorder = TriggerRecorderService()
        recorder.record(.mouseButton)
        XCTAssertTrue(TriggerRecorderService.isRecordingMouseButton)
        recorder.cancel()
        XCTAssertFalse(TriggerRecorderService.isRecordingMouseButton)
    }

    @MainActor
    func testExistingBindingPassesToRecorderWithoutOpeningHUD() async throws {
        let tap = FakeMouseTriggerTap()
        let monitor = MouseButtonTriggerMonitor(tap: tap)
        monitor.start(buttonNumber: 4, onDown: { _ in XCTFail("Recorder must own press") },
                      onDragged: { _ in XCTFail() }, onUp: { _ in XCTFail() })
        let recorder = TriggerRecorderService()
        recorder.record(.mouseButton)
        defer { recorder.cancel(); monitor.stop() }
        XCTAssertFalse(try tap.send(.otherMouseDown, button: 4))
        XCTAssertFalse(try tap.send(.otherMouseUp, button: 4))
    }
}

@MainActor
private final class FakeMouseTriggerTap: MouseButtonTriggerTapping {
    var handler: ((CGEventType, CGEvent) -> Bool)?
    var reenableCount = 0
    var failStart = false
    func start(handler: @escaping (CGEventType, CGEvent) -> Bool) throws {
        if failStart { throw NSError(domain: "test", code: 1) }
        self.handler = handler
    }
    func reenable() { reenableCount += 1 }
    func stop() { handler = nil }
    // Construct events without posting them. The fake replaces only the OS tap;
    // routing/consumption and recorder state use production code.
    func send(_ type: CGEventType, button: Int) throws -> Bool {
        let event = try XCTUnwrap(CGEvent(mouseEventSource: nil, mouseType: .otherMouseDown,
                                              mouseCursorPosition: .zero, mouseButton: .center))
        event.location = CGPoint(x: 125, y: 250)
        event.setIntegerValueField(.mouseEventButtonNumber, value: Int64(button))
        return handler?(type, event) ?? false
    }
}
