import AppKit
import SwiftUI

/// Hosts the permission onboarding sheet in a standalone titled window
/// (the app is `LSUIElement`, so it has no main window otherwise).
@MainActor
final class OnboardingWindowController {
    private var window: NSWindow?

    func show(service: PermissionsService, onDone: @escaping () -> Void) {
        guard window == nil else {
            window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let view = PermissionOnboardingView(service: service) { [weak self] in
            self?.close()
            onDone()
        }
        let host = NSHostingView(rootView: view)

        let w = NSWindow(
            contentRect: NSRect(origin: .zero, size: host.fittingSize),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        w.title = "MousePlus Setup"
        w.contentView = host
        w.center()
        w.isReleasedWhenClosed = false
        w.level = .floating
        // .canJoinAllSpaces and .moveToActiveSpace are mutually exclusive —
        // pick the latter so the sheet follows the user across spaces.
        w.collectionBehavior = [.moveToActiveSpace]

        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
        self.window = w
    }

    func close() {
        window?.close()
        window = nil
    }
}
