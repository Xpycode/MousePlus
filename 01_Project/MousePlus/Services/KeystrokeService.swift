import CoreGraphics
import Foundation

protocol KeystrokeClock: Sendable {
    func sleep(for duration: Duration) async throws
}

struct ContinuousKeystrokeClock: KeystrokeClock {
    func sleep(for duration: Duration) async throws {
        try await ContinuousClock().sleep(for: duration)
    }
}

enum KeystrokeError: LocalizedError, Equatable {
    case postEventAccessDenied

    var errorDescription: String? {
        switch self {
        case .postEventAccessDenied:
            "Permission to post keyboard events is required."
        }
    }
}

/// Serializes synthetic chords and applies the timing required after the ring
/// is dismissed: 50 ms before key-down, then 10 ms before key-up.
actor KeystrokeService {
    static let preKeyDownDelay: Duration = .milliseconds(50)
    static let keyDownToKeyUpDelay: Duration = .milliseconds(10)

    private let poster: any CGEventPosting
    private let clock: any KeystrokeClock

    init(
        poster: any CGEventPosting = SystemCGEventPoster(),
        clock: any KeystrokeClock = ContinuousKeystrokeClock()
    ) {
        self.poster = poster
        self.clock = clock
    }

    func send(keyCode: UInt16, flags: CGEventFlags) async throws {
        guard poster.preflightPostEventAccess() else {
            throw KeystrokeError.postEventAccessDenied
        }

        try await clock.sleep(for: Self.preKeyDownDelay)
        try Task.checkCancellation()
        try poster.postKeyboardEvent(
            keyCode: keyCode,
            keyDown: true,
            flags: flags,
            sourceStateID: .privateState,
            tap: .cghidEventTap
        )

        try await clock.sleep(for: Self.keyDownToKeyUpDelay)
        try Task.checkCancellation()
        try poster.postKeyboardEvent(
            keyCode: keyCode,
            keyDown: false,
            flags: flags,
            sourceStateID: .privateState,
            tap: .cghidEventTap
        )
    }
}
