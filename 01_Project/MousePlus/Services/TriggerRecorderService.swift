import AppKit

/// One-shot "press the trigger you want" recorder for the Triggers settings tab.
///
/// Unlike `InputRecorderService` (a running diagnostic that logs a history), this
/// captures exactly ONE candidate binding and then stops. It watches the relevant
/// event types via both local and global monitors so it works whether or not the
/// Settings window holds focus, and it arms a timeout: if nothing arrives, the
/// outcome becomes `.timedOut` — the signal that the press was likely swallowed by
/// vendor software (Logi Options+ / SteerMouse / Karabiner) before macOS saw it.
///
/// The captured binding carries a placeholder `.holdRelease` mode; the caller swaps
/// in the slot's current mode (mode is chosen separately in the UI).
@MainActor
@Observable
final class TriggerRecorderService {
    enum Target: Equatable {
        case keyboard
        case mouseButton
    }

    enum Outcome: Equatable {
        case captured(TriggerBinding)
        case timedOut
        case cancelled
    }

    private(set) var isRecording = false
    /// Set once when recording finishes (captured / timed out / cancelled). The view
    /// observes this and clears it after consuming.
    var outcome: Outcome?

    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var timeoutTask: Task<Void, Never>?
    private var target: Target = .keyboard

    /// Seconds to wait for a press before declaring `.timedOut`.
    private let timeout: Duration = .seconds(4)

    func record(_ target: Target) {
        stopMonitors()
        self.target = target
        outcome = nil
        isRecording = true

        let mask: NSEvent.EventTypeMask = target == .keyboard
            ? [.keyDown]
            : [.otherMouseDown]

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            Task { @MainActor in self?.handle(event) }
            // Swallow the event locally so the recorded key/click doesn't also act on
            // the Settings window (e.g. Return triggering a default button).
            return nil
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
            Task { @MainActor in self?.handle(event) }
        }

        timeoutTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: timeout)
            guard !Task.isCancelled else { return }
            self.finish(.timedOut)
        }
    }

    /// User dismissed the recorder (e.g. clicked "Cancel") without pressing anything.
    func cancel() {
        guard isRecording else { return }
        finish(.cancelled)
    }

    private func handle(_ event: NSEvent) {
        guard isRecording else { return }

        switch target {
        case .keyboard:
            // Escape aborts recording rather than binding Escape itself.
            if event.keyCode == 53 {
                finish(.cancelled)
                return
            }
            // Keep only real chord modifiers (⌃⌥⇧⌘). macOS sets `.function` on every
            // F-row / arrow key and `.capsLock` from lock state — storing those would
            // require them to be re-present at match time, which breaks F-keys injected
            // by a mouse-button mapping (Logi Options+/BetterMouse) that omit `.function`.
            let chordMask = NSEvent.ModifierFlags([.control, .option, .shift, .command])
            let mods = event.modifierFlags.intersection(chordMask).rawValue
            finish(.captured(.keyboard(keyCode: event.keyCode, modifiers: mods, mode: .holdRelease)))

        case .mouseButton:
            // Only buttons 2+ reach `.otherMouseDown`; left/right stay usable for clicking.
            finish(.captured(.mouseButton(buttonNumber: event.buttonNumber, mode: .holdRelease)))
        }
    }

    private func finish(_ outcome: Outcome) {
        stopMonitors()
        isRecording = false
        self.outcome = outcome
    }

    private func stopMonitors() {
        timeoutTask?.cancel()
        timeoutTask = nil
        if let m = localMonitor { NSEvent.removeMonitor(m); localMonitor = nil }
        if let m = globalMonitor { NSEvent.removeMonitor(m); globalMonitor = nil }
    }
}
