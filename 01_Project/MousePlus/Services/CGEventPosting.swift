import CoreGraphics
import Foundation

/// The Core Graphics operations used by `KeystrokeService`.
///
/// Keeping this boundary above `CGEvent` construction means tests never need to
/// create (and can never accidentally post) a synthetic system event.
protocol CGEventPosting: Sendable {
    func preflightPostEventAccess() -> Bool

    func postKeyboardEvent(
        keyCode: UInt16,
        keyDown: Bool,
        flags: CGEventFlags,
        sourceStateID: CGEventSourceStateID,
        tap: CGEventTapLocation
    ) throws
}

enum CGEventPostingError: LocalizedError {
    case eventSourceCreationFailed
    case eventCreationFailed

    var errorDescription: String? {
        switch self {
        case .eventSourceCreationFailed:
            "MousePlus could not create a private keyboard event source."
        case .eventCreationFailed:
            "MousePlus could not create a keyboard event."
        }
    }
}

/// Live Core Graphics implementation. A private source is retained and reused
/// so posted chords do not inherit the user's physically held modifiers.
final class SystemCGEventPoster: CGEventPosting, @unchecked Sendable {
    private let lock = NSLock()
    private var privateSource: CGEventSource?

    func preflightPostEventAccess() -> Bool {
        CGPreflightPostEventAccess()
    }

    func postKeyboardEvent(
        keyCode: UInt16,
        keyDown: Bool,
        flags: CGEventFlags,
        sourceStateID: CGEventSourceStateID,
        tap: CGEventTapLocation
    ) throws {
        let source = try eventSource(for: sourceStateID)
        guard let event = CGEvent(
            keyboardEventSource: source,
            virtualKey: CGKeyCode(keyCode),
            keyDown: keyDown
        ) else {
            throw CGEventPostingError.eventCreationFailed
        }

        // Set flags even for an empty chord. Leaving this unset can allow
        // physically held modifiers to contaminate the synthetic event.
        event.flags = flags
        event.post(tap: tap)
    }

    private func eventSource(for stateID: CGEventSourceStateID) throws -> CGEventSource {
        lock.lock()
        defer { lock.unlock() }

        if stateID == .privateState, let privateSource {
            return privateSource
        }
        guard let source = CGEventSource(stateID: stateID) else {
            throw CGEventPostingError.eventSourceCreationFailed
        }
        if stateID == .privateState {
            privateSource = source
        }
        return source
    }
}
