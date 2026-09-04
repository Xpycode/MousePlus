import AppKit

/// Where a trigger event came from.
enum TriggerSource: Sendable {
    case keyboard
    case mouseButton
}

/// A unified trigger event from any source.
/// `mode` tells the consumer how to interpret the press/release:
/// hold-release acts on both `.down` and `.up`; tap-toggle acts only on `.down`.
enum TriggerEvent: Sendable {
    case down(source: TriggerSource, mode: TriggerMode, pointerLocation: CGPoint)
    case moved(source: TriggerSource, mode: TriggerMode, pointerLocation: CGPoint)
    case up(source: TriggerSource, mode: TriggerMode, pointerLocation: CGPoint)
}

/// Owns the active trigger bindings and emits a unified event stream.
///
/// Replaces the older single-purpose `HotkeyService`. Both monitors are
/// internal; consumers (AppDelegate) just observe `events` and react to
/// `.down` / `.up` regardless of origin.
@MainActor
final class TriggerService {
    let events: AsyncStream<TriggerEvent>
    private let continuation: AsyncStream<TriggerEvent>.Continuation

    private let keyboardMonitor = KeyboardTriggerMonitor()
    private let mouseButtonMonitor = MouseButtonTriggerMonitor()
    private var currentConfig: TriggersConfig = .default

    init() {
        let (events, continuation) = AsyncStream<TriggerEvent>.makeStream()
        self.events = events
        self.continuation = continuation
    }

    func start(config: TriggersConfig) {
        currentConfig = config
        applyConfig()
    }

    func updateConfig(_ config: TriggersConfig) {
        currentConfig = config
        applyConfig()
    }

    func stop() {
        keyboardMonitor.stop()
        mouseButtonMonitor.stop()
    }

    private func applyConfig() {
        keyboardMonitor.stop()
        mouseButtonMonitor.stop()

        if case let .keyboard(keyCode, modifiers, mode) = currentConfig.keyboard {
            keyboardMonitor.start(
                keyCode: keyCode,
                modifiers: modifiers,
                onDown: { [weak self] in
                    self?.continuation.yield(.down(
                        source: .keyboard, mode: mode, pointerLocation: NSEvent.mouseLocation
                    ))
                },
                onUp: { [weak self] in
                    self?.continuation.yield(.up(
                        source: .keyboard, mode: mode, pointerLocation: NSEvent.mouseLocation
                    ))
                }
            )
        }

        if case let .mouseButton(buttonNumber, mode) = currentConfig.mouseButton {
            mouseButtonMonitor.start(
                buttonNumber: buttonNumber,
                onDown: { [weak self] pointerLocation in
                    self?.continuation.yield(.down(
                        source: .mouseButton, mode: mode, pointerLocation: pointerLocation
                    ))
                },
                onDragged: { [weak self] pointerLocation in
                    self?.continuation.yield(.moved(
                        source: .mouseButton, mode: mode, pointerLocation: pointerLocation
                    ))
                },
                onUp: { [weak self] pointerLocation in
                    self?.continuation.yield(.up(
                        source: .mouseButton, mode: mode, pointerLocation: pointerLocation
                    ))
                }
            )
        }
    }
}
