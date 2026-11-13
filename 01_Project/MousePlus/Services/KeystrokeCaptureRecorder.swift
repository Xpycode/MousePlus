import AppKit
import CoreGraphics
import Observation
import OSLog

enum KeystrokeCaptureDisposition: Equatable {
    case passThrough
    case consume
}

enum KeystrokeCaptureEvent: Equatable {
    case keyDown(keyCode: UInt16, modifiers: UInt, isRepeat: Bool)
    case keyUp(keyCode: UInt16)
    case tapDisabled(InputTapDisableReason)
}

struct KeystrokeCaptureReducer {
    enum Completion: Equatable {
        case captured(KeystrokePayload)
        case cancelled
    }

    struct Transition: Equatable {
        var disposition: KeystrokeCaptureDisposition
        var completion: Completion?
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
            isRecording = false
            swallowedKeyCode = nil
            pendingCompletion = nil
            return .init(disposition: .passThrough, completion: .cancelled)

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
    /// Explicit re-enable after a reported disable; never called implicitly.
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

private let keystrokeCaptureTapCallback: CGEventTapCallBack = { _, type, event, context in
    guard let context else { return Unmanaged.passUnretained(event) }
    return MainActor.assumeIsolated {
        let tap = Unmanaged<SystemKeystrokeCaptureTap>
            .fromOpaque(context).takeUnretainedValue()
        return tap.handle(type: type, event: event)
    }
}

/// Active session tap shared by the Send Keystroke recorder and the keyboard
/// trigger monitors. Returning nil from its callback consumes the chord before
/// Carbon global hotkeys.
@MainActor
final class SystemKeystrokeCaptureTap: KeystrokeCaptureTapping {
    private var handle: (any InputTapHandle)?
    private var handler: ((KeystrokeCaptureEvent) -> KeystrokeCaptureDisposition)?
    private let registry: InputTapRegistry
    private let factory: InputTapFactory

    init(
        registry: InputTapRegistry? = nil,
        factory: @escaping InputTapFactory = { mask, callback, userInfo in
            SystemEventTapHandle.create(mask: mask, callback: callback, userInfo: userInfo)
        }
    ) {
        self.registry = registry ?? .shared
        self.factory = factory
    }

    func start(
        handler: @escaping (KeystrokeCaptureEvent) -> KeystrokeCaptureDisposition
    ) throws {
        stop()
        self.handler = handler
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
            | CGEventMask(1 << CGEventType.keyUp.rawValue)
        guard let handle = factory(
            mask, keystrokeCaptureTapCallback, Unmanaged.passUnretained(self).toOpaque()
        ) else {
            self.handler = nil
            throw KeystrokeCaptureTapError.creationFailed
        }
        self.handle = handle
        registry.register(handle)
        handle.setEnabled(true)
    }

    func reenable() {
        handle?.setEnabled(true)
    }

    func stop() {
        if let handle {
            handle.setEnabled(false)
            handle.invalidate()
            registry.unregister(handle)
        }
        handle = nil
        handler = nil
    }

    fileprivate func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let input: KeystrokeCaptureEvent
        switch type {
        case .tapDisabledByTimeout:
            input = .tapDisabled(.timeout)
        case .tapDisabledByUserInput:
            input = .tapDisabled(.userInput)
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
    private static let logger = Logger(subsystem: "com.xpycode.MousePlus", category: "KeystrokeRecorder")
    private var keyDownCount = 0
    private var keyUpCount = 0
    private var disabledCount = 0
    enum Outcome: Equatable {
        case captured(KeystrokePayload)
        case cancelled
        case timedOut
        case failed(String)
    }

    private(set) var isRecording = false
    private(set) var outcome: Outcome?

    /// Called after the recording was cancelled because macOS disabled the tap.
    /// The recorder never re-enables the tap by itself.
    @ObservationIgnored var onDisabled: ((InputTapDisableReason) -> Void)?
    @ObservationIgnored var onInstallFailed: (() -> Void)?

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
        keyDownCount = 0
        keyUpCount = 0
        disabledCount = 0
        reducer.start()
        do {
            try tap.start { [weak self] event in
                guard let self else { return .passThrough }
                switch event {
                case .keyDown: self.keyDownCount += 1
                case .keyUp: self.keyUpCount += 1
                case .tapDisabled(let reason):
                    self.disabledCount += 1
                    Self.logger.notice("Recording tap disabled; cancelling recording")
                    // Synchronous: the tap must stop being a live consumer now.
                    guard self.isRecording else { return .passThrough }
                    self.reducer.cancel()
                    self.stopInfrastructure()
                    self.isRecording = false
                    self.outcome = .cancelled
                    self.onDisabled?(reason)
                    return .passThrough
                }
                let transition = self.reducer.reduce(event)
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
            onInstallFailed?()
            return
        }
        isRecording = true
        Self.logger.notice("Keystroke recording started")
        timeoutTask = Task { [weak self] in
            guard let self else { return }
            do { try await sleeper.sleep(for: timeout) } catch { return }
            self.timeoutReached()
        }
    }

    func cancel() {
        guard isRecording else { return }
        Self.logger.notice("Keystroke recording cancelled")
        reducer.cancel()
        stopInfrastructure()
        isRecording = false
        outcome = .cancelled
    }

    /// Stops the tap and clears recording state without publishing an outcome
    /// when nothing was recording. Safe to call repeatedly.
    func teardown() {
        if isRecording {
            reducer.cancel()
            isRecording = false
            outcome = .cancelled
        }
        stopInfrastructure()
    }

    /// Explicit re-enable of the tap after a reported disable.
    func resume() {
        tap.reenable()
    }

    private func finish(_ completion: KeystrokeCaptureReducer.Completion) {
        guard isRecording else { return }
        stopInfrastructure()
        isRecording = false
        switch completion {
        case .captured(let payload):
            Self.logger.notice("Keystroke recording captured a key")
            outcome = .captured(payload)
        case .cancelled:
            Self.logger.notice("Keystroke recording cancelled with Escape")
            outcome = .cancelled
        }
    }

    private func timeoutReached() {
        guard isRecording else { return }
        Self.logger.notice("Keystroke recording timed out: down=\(self.keyDownCount), up=\(self.keyUpCount), disabled=\(self.disabledCount)")
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
