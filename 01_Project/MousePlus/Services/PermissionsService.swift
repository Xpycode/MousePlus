import AppKit
import ApplicationServices

/// Tracks the Accessibility permission state and drives the onboarding flow.
///
/// Polls `AXIsProcessTrusted()` while a sheet is open because there is no
/// system notification when a TCC grant flips. The poll cancels itself once
/// granted, so it is not a long-lived cost.
@MainActor
@Observable
final class PermissionsService {
    private(set) var isGranted: Bool

    /// Called once, on the main actor, the first time the grant flips to true.
    var onGranted: (@MainActor () -> Void)?

    private var pollTask: Task<Void, Never>?

    init() {
        self.isGranted = AXIsProcessTrusted()
    }

    /// Triggers the macOS Accessibility prompt (or no-op if already granted).
    func promptAccessibility() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    /// Opens System Settings → Privacy & Security → Accessibility directly.
    func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
        NSWorkspace.shared.open(url)
    }

    func startPolling() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let now = AXIsProcessTrusted()
                if now != self.isGranted {
                    self.isGranted = now
                    if now {
                        self.onGranted?()
                        self.stopPolling()
                        return
                    }
                }
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
    }

    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }
}
