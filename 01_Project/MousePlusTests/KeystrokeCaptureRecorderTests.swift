import XCTest
@testable import MousePlus

final class KeystrokeCaptureRecorderTests: XCTestCase {
    func testReducerCapturesChordAndConsumesMatchingDownAndUp() {
        var reducer = KeystrokeCaptureReducer()
        reducer.start()

        XCTAssertEqual(
            reducer.reduce(.keyDown(keyCode: 12, modifiers: UInt.max, isRepeat: false)),
            .init(disposition: .consume)
        )
        XCTAssertEqual(
            reducer.reduce(.keyUp(keyCode: 12)),
            .init(
                disposition: .consume,
                completion: .captured(.key(
                    keyCode: 12,
                    modifiers: KeystrokePayload.modifierMask
                ))
            )
        )
        XCTAssertFalse(reducer.isRecording)
    }

    func testEscapeCancelsAndConsumesMatchingDownAndUp() {
        var reducer = KeystrokeCaptureReducer()
        reducer.start()

        XCTAssertEqual(
            reducer.reduce(.keyDown(keyCode: 53, modifiers: 0, isRepeat: false)).disposition,
            .consume
        )
        XCTAssertEqual(
            reducer.reduce(.keyUp(keyCode: 53)),
            .init(disposition: .consume, completion: .cancelled)
        )
    }

    func testUnrelatedKeyUpAndSecondKeyPassThrough() {
        var reducer = KeystrokeCaptureReducer()
        reducer.start()

        XCTAssertEqual(reducer.reduce(.keyUp(keyCode: 1)).disposition, .passThrough)
        _ = reducer.reduce(.keyDown(keyCode: 12, modifiers: 0, isRepeat: false))
        XCTAssertEqual(
            reducer.reduce(.keyDown(keyCode: 13, modifiers: 0, isRepeat: false)).disposition,
            .passThrough
        )
        XCTAssertEqual(reducer.reduce(.keyUp(keyCode: 13)).disposition, .passThrough)
    }

    func testRepeatIsConsumedWithoutBecomingCandidate() {
        var reducer = KeystrokeCaptureReducer()
        reducer.start()

        XCTAssertEqual(
            reducer.reduce(.keyDown(keyCode: 12, modifiers: 0, isRepeat: true)).disposition,
            .consume
        )
        XCTAssertEqual(reducer.reduce(.keyUp(keyCode: 12)).disposition, .passThrough)
        XCTAssertTrue(reducer.isRecording)
    }

    @MainActor
    func testServiceCaptureStopsTapAndPublishesOutcome() async {
        let tap = CaptureTapStub()
        let recorder = KeystrokeCaptureRecorder(tap: tap, timeout: .seconds(60))
        recorder.record()

        XCTAssertEqual(tap.send(.keyDown(keyCode: 8, modifiers: 1 << 20, isRepeat: false)), .consume)
        XCTAssertEqual(tap.send(.keyUp(keyCode: 8)), .consume)
        await Task.yield()

        XCTAssertEqual(recorder.outcome, .captured(.key(keyCode: 8, modifiers: 1 << 20)))
        XCTAssertFalse(recorder.isRecording)
        XCTAssertEqual(tap.stopCount, 2) // idempotent pre-start cleanup + completion
    }

    @MainActor
    func testTapDisabledIsReenabledWithoutFinishing() {
        let tap = CaptureTapStub()
        let recorder = KeystrokeCaptureRecorder(tap: tap, timeout: .seconds(60))
        recorder.record()

        XCTAssertEqual(tap.send(.tapDisabled), .passThrough)
        XCTAssertEqual(tap.reenableCount, 1)
        XCTAssertTrue(recorder.isRecording)
    }

    @MainActor
    func testCreationFailureIsPublishedAndTornDown() {
        let tap = CaptureTapStub(startError: KeystrokeCaptureTapError.creationFailed)
        let recorder = KeystrokeCaptureRecorder(tap: tap)

        recorder.record()

        guard case .failed = recorder.outcome else { return XCTFail("Expected failure") }
        XCTAssertFalse(recorder.isRecording)
        XCTAssertEqual(tap.stopCount, 2)
    }

    @MainActor
    func testCancelAndTimeoutTearDownAndAreIdempotent() async {
        let cancelledTap = CaptureTapStub()
        let cancelled = KeystrokeCaptureRecorder(tap: cancelledTap, timeout: .seconds(60))
        cancelled.record()
        cancelled.cancel()
        cancelled.cancel()
        XCTAssertEqual(cancelled.outcome, .cancelled)
        XCTAssertEqual(cancelledTap.stopCount, 2)

        let timedTap = CaptureTapStub()
        let sleeperStarted = expectation(description: "timeout sleeper started")
        let timed = KeystrokeCaptureRecorder(
            tap: timedTap,
            timeout: .seconds(60),
            sleeper: ImmediateCaptureSleeper(onSleep: { sleeperStarted.fulfill() })
        )
        timed.record()
        await fulfillment(of: [sleeperStarted], timeout: 1)
        await Task.yield()
        XCTAssertEqual(timed.outcome, .timedOut)
        XCTAssertFalse(timed.isRecording)
        XCTAssertEqual(timedTap.stopCount, 2)
    }
}

private struct ImmediateCaptureSleeper: KeystrokeCaptureSleeping {
    let onSleep: @Sendable () -> Void

    func sleep(for duration: Duration) async throws { onSleep() }
}

@MainActor
private final class CaptureTapStub: KeystrokeCaptureTapping {
    let startError: Error?
    private var handler: ((KeystrokeCaptureEvent) -> KeystrokeCaptureDisposition)?
    private(set) var stopCount = 0
    private(set) var reenableCount = 0

    init(startError: Error? = nil) { self.startError = startError }

    func start(handler: @escaping (KeystrokeCaptureEvent) -> KeystrokeCaptureDisposition) throws {
        if let startError { throw startError }
        self.handler = handler
    }

    func reenable() { reenableCount += 1 }
    func stop() { stopCount += 1; handler = nil }

    func send(_ event: KeystrokeCaptureEvent) -> KeystrokeCaptureDisposition {
        handler?(event) ?? .passThrough
    }
}
