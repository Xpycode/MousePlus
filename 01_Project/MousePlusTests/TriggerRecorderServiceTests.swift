import XCTest
@testable import MousePlus

/// Fake NSEvent monitor installer: records installs/removals, creates no live monitor.
@MainActor
final class FakeRecorderEventMonitor: TriggerRecorderEventMonitoring {
    private(set) var installed: [Int] = []
    private(set) var removed: [Int] = []
    private var next = 0

    var liveCount: Int { installed.count - removed.count }

    func addLocal(matching mask: NSEvent.EventTypeMask, handler: @escaping (NSEvent) -> NSEvent?) -> Any? {
        next += 1; installed.append(next); return next
    }

    func addGlobal(matching mask: NSEvent.EventTypeMask, handler: @escaping (NSEvent) -> Void) -> Any? {
        next += 1; installed.append(next); return next
    }

    func remove(_ monitor: Any) {
        removed.append(monitor as! Int)
    }
}

final class TriggerRecorderServiceTests: XCTestCase {
    @MainActor
    func testRecordInstallsThroughSeamAndCancelRemovesAndClearsFlags() {
        let monitors = FakeRecorderEventMonitor()
        let recorder = TriggerRecorderService(monitors: monitors)
        recorder.record(.keyboard)
        XCTAssertEqual(monitors.liveCount, 2)
        XCTAssertTrue(TriggerRecorderService.isRecordingKeyboardShortcut)
        XCTAssertFalse(TriggerRecorderService.isRecordingMouseButton)

        recorder.cancel()
        XCTAssertEqual(monitors.liveCount, 0)
        XCTAssertEqual(recorder.outcome, .cancelled)
        XCTAssertFalse(TriggerRecorderService.isRecordingKeyboardShortcut)
    }

    @MainActor
    func testTeardownClearsStaticFlagsAndCancelsRecording() {
        let monitors = FakeRecorderEventMonitor()
        let recorder = TriggerRecorderService(monitors: monitors)
        recorder.record(.mouseButton)
        XCTAssertTrue(TriggerRecorderService.isRecordingMouseButton)

        recorder.teardown()
        XCTAssertEqual(monitors.liveCount, 0)
        XCTAssertFalse(recorder.isRecording)
        XCTAssertEqual(recorder.outcome, .cancelled)
        XCTAssertFalse(TriggerRecorderService.isRecordingMouseButton)
        XCTAssertFalse(TriggerRecorderService.isRecordingKeyboardShortcut)

        recorder.teardown() // idempotent when idle
        XCTAssertEqual(monitors.liveCount, 0)
    }

    @MainActor
    func testRerecordReplacesMonitors() {
        let monitors = FakeRecorderEventMonitor()
        let recorder = TriggerRecorderService(monitors: monitors)
        recorder.record(.keyboard)
        recorder.record(.mouseButton)
        XCTAssertEqual(monitors.liveCount, 2)
        XCTAssertTrue(TriggerRecorderService.isRecordingMouseButton)
        XCTAssertFalse(TriggerRecorderService.isRecordingKeyboardShortcut)
        recorder.teardown()
    }
}
