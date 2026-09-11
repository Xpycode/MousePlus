import AppKit

/// Stable identity of the physical control that produced an event.
enum TriggerPhysicalSource: Equatable, Hashable, Sendable {
    case keyboard(keyCode: UInt16, modifiers: UInt)
    case mouseButton(buttonNumber: Int)
}

/// Route and physical origin travel together on every event. Keeping this as
/// the existing event case's `source` value preserves source compatibility for
/// the current AppDelegate while exposing the ownership key needed by Task 3.1.
struct TriggerSource: Equatable, Hashable, Sendable {
    let route: HUDInvocationRoute
    let physicalSource: TriggerPhysicalSource

    func hash(into hasher: inout Hasher) {
        hasher.combine(route.rawValue)
        hasher.combine(physicalSource)
    }
}

/// A unified trigger event from any source.
/// `mode` tells the consumer how to interpret the press/release:
/// hold-release acts on both `.down` and `.up`; tap-toggle acts only on `.down`.
enum TriggerEvent: Sendable {
    case down(source: TriggerSource, mode: TriggerMode, pointerLocation: CGPoint)
    case moved(source: TriggerSource, mode: TriggerMode, pointerLocation: CGPoint)
    case up(source: TriggerSource, mode: TriggerMode, pointerLocation: CGPoint)
    /// A held binding was removed or replaced before its native release.
    case cancel(source: TriggerSource)
}

/// Owns the active trigger bindings and emits a unified event stream.
///
/// Replaces the older single-purpose `HotkeyService`. All three HUD monitors
/// are internal; consumers just observe `events` and react to `.down` / `.up`
/// regardless of origin.
@MainActor
final class TriggerService {
    let events: AsyncStream<TriggerEvent>
    private let continuation: AsyncStream<TriggerEvent>.Continuation

    private let contextualKeyboardMonitor: any KeyboardTriggerMonitoring
    private let globalKeyboardMonitor: any KeyboardTriggerMonitoring
    private let mouseButtonMonitor: any MouseButtonTriggerMonitoring
    private var currentConfig: TriggersConfig = .default
    private var isRunning = false
    private var activeContextualKeyboardSource: TriggerSource?
    private var activeGlobalKeyboardSource: TriggerSource?
    private var activeMouseSource: TriggerSource?

    init(
        contextualKeyboardMonitor: (any KeyboardTriggerMonitoring)? = nil,
        globalKeyboardMonitor: (any KeyboardTriggerMonitoring)? = nil,
        mouseButtonMonitor: (any MouseButtonTriggerMonitoring)? = nil
    ) {
        let (events, continuation) = AsyncStream<TriggerEvent>.makeStream()
        self.events = events
        self.continuation = continuation
        self.contextualKeyboardMonitor = contextualKeyboardMonitor ?? KeyboardTriggerMonitor()
        self.globalKeyboardMonitor = globalKeyboardMonitor ?? KeyboardTriggerMonitor()
        self.mouseButtonMonitor = mouseButtonMonitor ?? MouseButtonTriggerMonitor()
    }

    func start(config: TriggersConfig) {
        currentConfig = config
        isRunning = true
        applyConfig()
    }

    func updateConfig(_ config: TriggersConfig) {
        guard isRunning else {
            start(config: config)
            return
        }
        guard config != currentConfig else { return }
        let previous = currentConfig
        currentConfig = config

        if previous.keyboard != config.keyboard {
            if let source = takeActiveSource(&activeContextualKeyboardSource) {
                continuation.yield(.cancel(source: source))
            }
            contextualKeyboardMonitor.stop()
            startContextualKeyboardMonitor()
        }
        if previous.mouseButton != config.mouseButton {
            if let source = takeActiveSource(&activeMouseSource) {
                continuation.yield(.cancel(source: source))
            }
            mouseButtonMonitor.stop()
            startMouseButtonMonitor()
        }
        // Contextual edits restart Global only when they actually change its
        // effective binding (for example by creating/removing a collision).
        if effectiveGlobalBinding(in: previous) != effectiveGlobalBinding(in: config) {
            if let source = takeActiveSource(&activeGlobalKeyboardSource) {
                continuation.yield(.cancel(source: source))
            }
            globalKeyboardMonitor.stop()
            startGlobalKeyboardMonitor()
        }
    }

    func stop() {
        isRunning = false
        stopMonitors()
    }

    private func stopMonitors() {
        contextualKeyboardMonitor.stop()
        globalKeyboardMonitor.stop()
        mouseButtonMonitor.stop()
    }

    private func takeActiveSource(_ source: inout TriggerSource?) -> TriggerSource? {
        let active = source
        source = nil
        return active
    }

    private func effectiveGlobalBinding(in config: TriggersConfig) -> TriggerBinding {
        guard HUDTriggerRouting.collision(
            globalHUDShortcut: config.globalHUDShortcut,
            contextualKeyboard: config.keyboard
        ) == nil else { return .none }
        return config.globalHUDShortcut
    }

    private func applyConfig() {
        stopMonitors()

        startContextualKeyboardMonitor()
        startGlobalKeyboardMonitor()
        startMouseButtonMonitor()
    }

    private func startContextualKeyboardMonitor() {
        if case let .keyboard(keyCode, modifiers, mode) = currentConfig.keyboard {
            let source = TriggerSource(
                route: .contextual,
                physicalSource: .keyboard(keyCode: keyCode, modifiers: modifiers)
            )
            contextualKeyboardMonitor.start(
                keyCode: keyCode,
                modifiers: modifiers,
                onDown: { [weak self] in
                    self?.activeContextualKeyboardSource = source
                    self?.continuation.yield(.down(
                        source: source, mode: mode, pointerLocation: NSEvent.mouseLocation
                    ))
                },
                onUp: { [weak self] in
                    self?.activeContextualKeyboardSource = nil
                    self?.continuation.yield(.up(
                        source: source, mode: mode, pointerLocation: NSEvent.mouseLocation
                    ))
                }
            )
        }
    }

    private func startGlobalKeyboardMonitor() {
        if case let .keyboard(keyCode, modifiers, mode) = currentConfig.globalHUDShortcut,
           HUDTriggerRouting.collision(
               globalHUDShortcut: currentConfig.globalHUDShortcut,
               contextualKeyboard: currentConfig.keyboard
           ) == nil {
            let source = TriggerSource(
                route: .global,
                physicalSource: .keyboard(keyCode: keyCode, modifiers: modifiers)
            )
            globalKeyboardMonitor.start(
                keyCode: keyCode,
                modifiers: modifiers,
                onDown: { [weak self] in
                    self?.activeGlobalKeyboardSource = source
                    self?.continuation.yield(.down(
                        source: source, mode: mode, pointerLocation: NSEvent.mouseLocation
                    ))
                },
                onUp: { [weak self] in
                    self?.activeGlobalKeyboardSource = nil
                    self?.continuation.yield(.up(
                        source: source, mode: mode, pointerLocation: NSEvent.mouseLocation
                    ))
                }
            )
        }
    }

    private func startMouseButtonMonitor() {
        if case let .mouseButton(buttonNumber, mode) = currentConfig.mouseButton {
            let source = TriggerSource(
                route: .contextual,
                physicalSource: .mouseButton(buttonNumber: buttonNumber)
            )
            mouseButtonMonitor.start(
                buttonNumber: buttonNumber,
                onDown: { [weak self] pointerLocation in
                    self?.activeMouseSource = source
                    self?.continuation.yield(.down(
                        source: source, mode: mode, pointerLocation: pointerLocation
                    ))
                },
                onDragged: { [weak self] pointerLocation in
                    self?.continuation.yield(.moved(
                        source: source, mode: mode, pointerLocation: pointerLocation
                    ))
                },
                onUp: { [weak self] pointerLocation in
                    self?.activeMouseSource = nil
                    self?.continuation.yield(.up(
                        source: source, mode: mode, pointerLocation: pointerLocation
                    ))
                }
            )
        }
    }
}

@MainActor
protocol KeyboardTriggerMonitoring: AnyObject {
    func start(
        keyCode: UInt16,
        modifiers: UInt,
        onDown: @escaping () -> Void,
        onUp: @escaping () -> Void
    )
    func stop()
}

extension KeyboardTriggerMonitor: KeyboardTriggerMonitoring {}

@MainActor
protocol MouseButtonTriggerMonitoring: AnyObject {
    func start(
        buttonNumber: Int,
        onDown: @escaping (CGPoint) -> Void,
        onDragged: @escaping (CGPoint) -> Void,
        onUp: @escaping (CGPoint) -> Void
    )
    func stop()
}

extension MouseButtonTriggerMonitor: MouseButtonTriggerMonitoring {}
