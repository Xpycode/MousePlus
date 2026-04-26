import AppKit
import Combine

/// Monitors global keyboard events for hotkey activation
actor HotkeyService {
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var currentConfig: HotkeyConfig = .default

    // PassthroughSubject is thread-safe, safe to access from nonisolated context
    private nonisolated(unsafe) let hotkeyPressedSubject = PassthroughSubject<Void, Never>()
    private nonisolated(unsafe) let hotkeyReleasedSubject = PassthroughSubject<Void, Never>()

    nonisolated var hotkeyPressed: AnyPublisher<Void, Never> {
        hotkeyPressedSubject.eraseToAnyPublisher()
    }

    nonisolated var hotkeyReleased: AnyPublisher<Void, Never> {
        hotkeyReleasedSubject.eraseToAnyPublisher()
    }

    func start(with config: HotkeyConfig) {
        currentConfig = config
        startMonitoring()
    }

    func stop() {
        stopMonitoring()
    }

    func updateConfig(_ config: HotkeyConfig) {
        currentConfig = config
    }

    private func startMonitoring() {
        // Global monitor for when app is not focused
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged]) { [weak self] event in
            Task { await self?.handleEvent(event) }
        }

        // Local monitor for when app is focused
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged]) { [weak self] event in
            Task { await self?.handleEvent(event) }
            return event
        }
    }

    private func stopMonitoring() {
        if let monitor = globalMonitor {
            NSEvent.removeMonitor(monitor)
            globalMonitor = nil
        }
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
        }
    }

    private func handleEvent(_ event: NSEvent) {
        let modifiersMatch = event.modifierFlags.rawValue & currentConfig.modifiers == currentConfig.modifiers

        switch event.type {
        case .keyDown where event.keyCode == currentConfig.keyCode && modifiersMatch:
            hotkeyPressedSubject.send()

        case .keyUp where event.keyCode == currentConfig.keyCode:
            hotkeyReleasedSubject.send()

        case .flagsChanged:
            // Handle modifier-only hotkeys if needed
            break

        default:
            break
        }
    }
}
