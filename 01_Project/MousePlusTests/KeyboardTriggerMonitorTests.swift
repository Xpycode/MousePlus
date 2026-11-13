import AppKit
import XCTest
@testable import MousePlus

final class KeyboardTriggerMonitorTests: XCTestCase {
    private let option = NSEvent.ModifierFlags.option.rawValue

    @MainActor
    func testMatchingDownUpPairIsConsumedAndCommitsOnce() {
        let tap = FakeKeyboardTap()
        let monitor = KeyboardTriggerMonitor(eventTap: tap)
        var downs = 0, ups = 0
        monitor.start(keyCode: 96, modifiers: option, onDown: { downs += 1 }, onUp: { ups += 1 })
        defer { monitor.stop() }

        XCTAssertEqual(tap.send(.keyDown(keyCode: 96, modifiers: option, isRepeat: false)), .consume)
        XCTAssertEqual(tap.send(.keyDown(keyCode: 96, modifiers: option, isRepeat: true)), .consume)
        XCTAssertEqual(tap.send(.keyUp(keyCode: 96)), .consume)
        XCTAssertEqual(tap.send(.keyUp(keyCode: 96)), .passThrough)
        XCTAssertEqual(tap.send(.keyDown(keyCode: 12, modifiers: option, isRepeat: false)), .passThrough)
        XCTAssertEqual([downs, ups], [1, 1])
    }

    @MainActor
    func testDisableClearsPressedStateReportsReasonAndDoesNotReenable() {
        for reason in [InputTapDisableReason.timeout, .userInput] {
            let tap = FakeKeyboardTap()
            let monitor = KeyboardTriggerMonitor(eventTap: tap)
            var ups = 0
            var reasons: [InputTapDisableReason] = []
            monitor.onDisabled = { reasons.append($0) }
            monitor.start(keyCode: 96, modifiers: option, onDown: {}, onUp: { ups += 1 })
            _ = tap.send(.keyDown(keyCode: 96, modifiers: option, isRepeat: false))

            XCTAssertEqual(tap.send(.tapDisabled(reason)), .passThrough)
            XCTAssertEqual(reasons, [reason])
            XCTAssertEqual(tap.reenableCount, 0)
            XCTAssertEqual(tap.send(.keyUp(keyCode: 96)), .passThrough)
            XCTAssertEqual(ups, 0, "pressed state must be cleared by the disable")
            monitor.stop()
        }
    }

    @MainActor
    func testDisableIsReportedWhileKeyboardRecorderOwnsCapture() {
        let tap = FakeKeyboardTap()
        let monitor = KeyboardTriggerMonitor(eventTap: tap)
        var reasons: [InputTapDisableReason] = []
        monitor.onDisabled = { reasons.append($0) }
        monitor.start(keyCode: 96, modifiers: option, onDown: {}, onUp: {})
        let recorder = TriggerRecorderService(monitors: FakeRecorderEventMonitor())
        recorder.record(.keyboard)
        defer { recorder.teardown(); monitor.stop() }

        XCTAssertEqual(tap.send(.tapDisabled(.userInput)), .passThrough)
        XCTAssertEqual(reasons, [.userInput])
    }

    @MainActor
    func testResumeReenablesTap() {
        let tap = FakeKeyboardTap()
        let monitor = KeyboardTriggerMonitor(eventTap: tap)
        monitor.start(keyCode: 96, modifiers: option, onDown: {}, onUp: {})
        monitor.resume()
        XCTAssertEqual(tap.reenableCount, 1)
        monitor.stop()
    }

    @MainActor
    func testInstallFailureReportsAndInstallsNoFallback() {
        let tap = FakeKeyboardTap()
        tap.failStart = true
        let monitor = KeyboardTriggerMonitor(eventTap: tap)
        var failures = 0
        monitor.onInstallFailed = { failures += 1 }
        monitor.start(keyCode: 96, modifiers: option,
                      onDown: { XCTFail("no fallback may deliver events") }, onUp: { XCTFail() })
        XCTAssertEqual(failures, 1)
        XCTAssertFalse(tap.isInstalled)
        XCTAssertEqual(tap.startAttempts, 1)
    }
}

@MainActor
private final class FakeKeyboardTap: KeystrokeCaptureTapping {
    private var handler: ((KeystrokeCaptureEvent) -> KeystrokeCaptureDisposition)?
    var failStart = false
    private(set) var reenableCount = 0
    private(set) var startAttempts = 0
    var isInstalled: Bool { handler != nil }

    func start(handler: @escaping (KeystrokeCaptureEvent) -> KeystrokeCaptureDisposition) throws {
        startAttempts += 1
        if failStart { throw KeystrokeCaptureTapError.creationFailed }
        self.handler = handler
    }

    func reenable() { reenableCount += 1 }
    func stop() { handler = nil }

    func send(_ event: KeystrokeCaptureEvent) -> KeystrokeCaptureDisposition {
        handler?(event) ?? .passThrough
    }
}
