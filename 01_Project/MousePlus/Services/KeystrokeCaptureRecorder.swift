import AppKit
import CoreGraphics
import Observation

enum KeystrokeCaptureDisposition: Equatable {
    case passThrough
    case consume
}

enum KeystrokeCaptureEvent: Equatable {
    case keyDown(keyCode: UInt16, modifiers: UInt, isRepeat: Bool)
    case keyUp(keyCode: UInt16)
    case tapDisabled
}

struct KeystrokeCaptureReducer {
    enum Completion: Equatable {
        case captured(KeystrokePayload)
        case cancelled
    }

    struct Transition: Equatable {
        var disposition: KeystrokeCaptureDisposition
        var completion: Completion?
        var shouldReenableTap = false
    }

    private(set) var isRecording = false
    private var swallowedKeyCode: UInt16?
    private var pendingCompletion: Completion?

    mutating func start() {
        isRecording = true
        swallowedKeyCode = nil
        pendingCompletion = nil
    }

    mutating func cancel() {
        isRecording = false
        swallowedKeyCode = nil
        pendingCompletion = nil
    }

    mutating func reduce(_ event: KeystrokeCaptureEvent) -> Transition {
        guard isRecording else { return .init(disposition: .passThrough) }

        switch event {
        case .tapDisabled:
            return .init(disposition: .passThrough, shouldReenableTap: true)

        case let .keyDown(keyCode, modifiers, isRepeat):
            if let swallowedKeyCode {
                return .init(disposition: keyCode == swallowedKeyCode ? .consume : .passThrough)
            }
            // A repeat may be the first event observed if recording starts while a
            // key is already held. Consume it so an external hotkey cannot fire,
            // but wait for a fresh press before choosing a candidate.
            guard !isRepeat else { return .init(disposition: .consume) }

            swallowedKeyCode = keyCode
            if keyCode == 53 { // Escape cancels, but only after its key-up is balanced.
                pendingCompletion = .cancelled
            } else {
                pendingCompletion = .captured(.key(
                    keyCode: keyCode,
                    modifiers: modifiers & KeystrokePayload.modifierMask
                ))
            }
            return .init(disposition: .consume)

        case let .keyUp(keyCode):
            guard keyCode == swallowedKeyCode else {
                return .init(disposition: .passThrough)
            }
            let completion = pendingCompletion
            isRecording = false
            swallowedKeyCode = nil
            pendingCompletion = nil
            return .init(disposition: .consume, completion: completion)
        }
    }
}

@MainActor
protocol KeystrokeCaptureTapping: AnyObject {
    func start(
        handler: @escaping (KeystrokeCaptureEvent) -> KeystrokeCaptureDisposition
    ) throws
    func reenable()
    func stop()
}

enum KeystrokeCaptureTapError: LocalizedError, Equatable {
    case creationFailed

    var errorDescription: String? {
        switch self {
        case .creationFailed:
            "MousePlus could not intercept keyboard events for recording. Check Input Monitoring and Accessibility permissions."
        }
    }
}

protocol KeystrokeCaptureSleeping: Sendable {
    func sleep(for duration: Duration) async throws
}

struct ContinuousKeystrokeCaptureSleeper: KeystrokeCaptureSleeping {
    func sleep(for duration: Duration) async throws {
        try await ContinuousClock().sleep(for: duration)
    }
}

/// Temporary active session tap used only while the Send Keystroke editor is recording.
/// Returning nil from its callback consumes the chord before Carbon global hotkeys.
@MainActor
final class SystemKeystrokeCaptureTap: KeystrokeCaptureTapping {
    private var port: CFMachPort?
    private var source: CFRunLoopSource?
    private var handler: ((KeystrokeCaptureEvent) -> KeystrokeCaptureDisposition)?

    func start(
        handler: @escaping (KeystrokeCaptureEvent) -> KeystrokeCaptureDisposition
    ) throws {
        stop()
        self.handler = handler
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
            | CGEventMask(1 << CGEventType.keyUp.rawValue)
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, context in
                guard let context else { return Unmanaged.passUnretained(event) }
                return MainActor.assumeIsolated {
                    let tap = Unmanaged<SystemKeystrokeCaptureTap>
                        .fromOpaque(context).takeUnretainedValue()
                    return tap.handle(type: type, event: event)
                }
            },
            userInfo: context
        ) else {
            self.handler = nil
            throw KeystrokeCaptureTapError.creationFailed
        }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        self.port = port
        self.source = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
    }

    func reenable() {
        if let port { CGEvent.tapEnable(tap: port, enable: true) }
    }

    func stop() {
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        if let port { CGEvent.tapEnable(tap: port, enable: false) }
        source = nil
        port = nil
        handler = nil
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let input: KeystrokeCaptureEvent
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            input = .tapDisabled
        case .keyDown:
            input = .keyDown(
                keyCode: UInt16(event.getIntegerValueField(.keyboardEventKeycode)),
                modifiers: UInt(event.flags.rawValue),
                isRepeat: event.getIntegerValueField(.keyboardEventAutorepeat) != 0
            )
        case .keyUp:
            input = .keyUp(keyCode: UInt16(event.getIntegerValueField(.keyboardEventKeycode)))
        default:
            return Unmanaged.passUnretained(event)
        }
        return handler?(input) == .consume ? nil : Unmanaged.passUnretained(event)
    }
}

@MainActor
@Observable
final class KeystrokeCaptureRecorder {
    enum Outcome: Equatable {
        case captured(KeystrokePayload)
        case cancelled
        case timedOut
        case failed(String)
    }

    private(set) var isRecording = false
    private(set) var outcome: Outcome?

    private let tap: any KeystrokeCaptureTapping
    private let timeout: Duration
    private let sleeper: any KeystrokeCaptureSleeping
    private var reducer = KeystrokeCaptureReducer()
    private var timeoutTask: Task<Void, Never>?

    init(
        tap: (any KeystrokeCaptureTapping)? = nil,
        timeout: Duration = .seconds(4),
        sleeper: any KeystrokeCaptureSleeping = ContinuousKeystrokeCaptureSleeper()
    ) {
        self.tap = tap ?? SystemKeystrokeCaptureTap()
        self.timeout = timeout
        self.sleeper = sleeper
    }

    func record() {
        stopInfrastructure()
        outcome = nil
        reducer.start()
        do {
            try tap.start { [weak self] event in
                guard let self else { return .passThrough }
                let transition = self.reducer.reduce(event)
                if transition.shouldReenableTap { self.tap.reenable() }
                if let completion = transition.completion {
                    Task { @MainActor [weak self] in self?.finish(completion) }
                }
                return transition.disposition
            }
        } catch {
            reducer.cancel()
            isRecording = false
            outcome = .failed(error.localizedDescription)
            tap.stop()
            return
        }
        isRecording = true
        timeoutTask = Task { [weak self] in
            guard let self else { return }
            do { try await sleeper.sleep(for: timeout) } catch { return }
            self.timeoutReached()
        }
    }

    func cancel() {
        guard isRecording else { return }
        reducer.cancel()
        stopInfrastructure()
        isRecording = false
        outcome = .cancelled
    }

    private func finish(_ completion: KeystrokeCaptureReducer.Completion) {
        guard isRecording else { return }
        stopInfrastructure()
        isRecording = false
        switch completion {
        case .captured(let payload): outcome = .captured(payload)
        case .cancelled: outcome = .cancelled
        }
    }

    private func timeoutReached() {
        guard isRecording else { return }
        reducer.cancel()
        stopInfrastructure()
        isRecording = false
        outcome = .timedOut
    }

    private func stopInfrastructure() {
        timeoutTask?.cancel()
        timeoutTask = nil
        tap.stop()
    }
}
