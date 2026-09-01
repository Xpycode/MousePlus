import XCTest
import CoreGraphics
@testable import MousePlus

final class MousePlusTests: XCTestCase {
    func testTestTargetLoadsMousePlusModule() {
        XCTAssertTrue(true)
    }

    func testKeystrokePermissionFailurePostsNothing() async {
        let poster = RecordingEventPoster(hasAccess: false)
        let clock = RecordingKeystrokeClock()
        let service = KeystrokeService(poster: poster, clock: clock)

        do {
            try await service.send(keyCode: 12, flags: [.maskCommand])
            XCTFail("Expected permission failure")
        } catch {
            XCTAssertEqual(error as? KeystrokeError, .postEventAccessDenied)
        }

        XCTAssertEqual(poster.preflightCount, 1)
        XCTAssertTrue(poster.events.isEmpty)
        XCTAssertTrue(clock.durations.isEmpty)
    }

    func testKeystrokePostsDownThenUpWithExplicitFlagsAtHIDTap() async throws {
        let poster = RecordingEventPoster(hasAccess: true)
        let clock = RecordingKeystrokeClock()
        let service = KeystrokeService(poster: poster, clock: clock)
        let flags: CGEventFlags = [.maskControl, .maskAlternate, .maskCommand]

        try await service.send(keyCode: 12, flags: flags)

        XCTAssertEqual(clock.durations, [.milliseconds(50), .milliseconds(10)])
        XCTAssertEqual(poster.events, [
            .init(keyCode: 12, keyDown: true, flags: flags,
                  sourceStateID: .privateState, tap: .cghidEventTap),
            .init(keyCode: 12, keyDown: false, flags: flags,
                  sourceStateID: .privateState, tap: .cghidEventTap),
        ])
    }

    func testEmptyFlagsAreExplicitOnBothEvents() async throws {
        let poster = RecordingEventPoster(hasAccess: true)
        let service = KeystrokeService(poster: poster, clock: RecordingKeystrokeClock())

        try await service.send(keyCode: 0, flags: [])

        XCTAssertEqual(poster.events.map(\.flags), [[], []])
    }

    func testCancellationBeforeKeyDownPostsNothing() async {
        let poster = RecordingEventPoster(hasAccess: true)
        let service = KeystrokeService(
            poster: poster,
            clock: CancellingKeystrokeClock(cancelOnSleep: 1)
        )

        do {
            try await service.send(keyCode: 12, flags: [.maskCommand])
            XCTFail("Expected cancellation")
        } catch is CancellationError {
            // Expected.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertTrue(poster.events.isEmpty)
    }

    func testCancellationBetweenEventsDoesNotPostKeyUp() async {
        let poster = RecordingEventPoster(hasAccess: true)
        let service = KeystrokeService(
            poster: poster,
            clock: CancellingKeystrokeClock(cancelOnSleep: 2)
        )

        do {
            try await service.send(keyCode: 12, flags: [.maskCommand])
            XCTFail("Expected cancellation")
        } catch is CancellationError {
            // Expected.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertEqual(poster.events.map(\.keyDown), [true])
    }
}

private final class RecordingEventPoster: CGEventPosting, @unchecked Sendable {
    struct Event: Equatable {
        let keyCode: UInt16
        let keyDown: Bool
        let flags: CGEventFlags
        let sourceStateID: CGEventSourceStateID
        let tap: CGEventTapLocation
    }

    let hasAccess: Bool
    private(set) var preflightCount = 0
    private(set) var events: [Event] = []

    init(hasAccess: Bool) {
        self.hasAccess = hasAccess
    }

    func preflightPostEventAccess() -> Bool {
        preflightCount += 1
        return hasAccess
    }

    func postKeyboardEvent(
        keyCode: UInt16,
        keyDown: Bool,
        flags: CGEventFlags,
        sourceStateID: CGEventSourceStateID,
        tap: CGEventTapLocation
    ) throws {
        events.append(.init(
            keyCode: keyCode,
            keyDown: keyDown,
            flags: flags,
            sourceStateID: sourceStateID,
            tap: tap
        ))
    }
}

private final class RecordingKeystrokeClock: KeystrokeClock, @unchecked Sendable {
    private(set) var durations: [Duration] = []

    func sleep(for duration: Duration) async throws {
        durations.append(duration)
    }
}

private final class CancellingKeystrokeClock: KeystrokeClock, @unchecked Sendable {
    private let cancelOnSleep: Int
    private var sleepCount = 0

    init(cancelOnSleep: Int) {
        self.cancelOnSleep = cancelOnSleep
    }

    func sleep(for duration: Duration) async throws {
        sleepCount += 1
        if sleepCount == cancelOnSleep {
            throw CancellationError()
        }
    }
}
