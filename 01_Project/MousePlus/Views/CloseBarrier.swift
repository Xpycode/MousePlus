import AppKit
import SwiftUI

enum CloseBarrierPresentation {
    static let message = "Changes Could Not Be Saved"
    static let informativePrefix = "Your latest edits are still in memory. Retry saving, discard them, or cancel closing to keep editing."
    static let retryTitle = "Retry"
    static let discardTitle = "Discard Changes"
    static let cancelTitle = "Cancel Close"
}

struct SettingsWindowCloseBarrier: NSViewRepresentable {
    let coordinator: SettingsWorkspaceCoordinator

    func makeCoordinator() -> WindowDelegate { WindowDelegate(coordinator: coordinator) }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async { context.coordinator.attach(to: view.window) }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        context.coordinator.coordinator = coordinator
        DispatchQueue.main.async { context.coordinator.attach(to: view.window) }
    }

    static func dismantleNSView(_ view: NSView, coordinator: WindowDelegate) { coordinator.detach() }

    @MainActor
    final class WindowDelegate: NSObject, NSWindowDelegate {
        var coordinator: SettingsWorkspaceCoordinator
        private weak var window: NSWindow?
        private var previousDelegate: NSWindowDelegate?
        private var allowNextClose = false
        private var closeRequestInFlight = false

        init(coordinator: SettingsWorkspaceCoordinator) { self.coordinator = coordinator }

        func attach(to window: NSWindow?) {
            guard let window, self.window !== window else { return }
            detach()
            self.window = window
            previousDelegate = window.delegate
            window.delegate = self
        }

        func detach() {
            guard let window, window.delegate === self else { return }
            window.delegate = previousDelegate
            self.window = nil
            previousDelegate = nil
        }

        func windowShouldClose(_ sender: NSWindow) -> Bool {
            if allowNextClose {
                allowNextClose = false
                return previousDelegate?.windowShouldClose?(sender) ?? true
            }
            guard !closeRequestInFlight else { return false }
            closeRequestInFlight = true
            Task { @MainActor [weak self, weak sender] in
                guard let self, let sender else { return }
                if await coordinator.requestClose() { finishClose(sender) }
                else { presentBlockedClose(for: sender) }
            }
            return false
        }

        func windowWillClose(_ notification: Notification) {
            previousDelegate?.windowWillClose?(notification)
        }

        private func finishClose(_ window: NSWindow) {
            closeRequestInFlight = false
            allowNextClose = true
            window.performClose(nil)
        }

        private func presentBlockedClose(for window: NSWindow) {
            let suffix: String
            if case .blocked(let message) = coordinator.workspaceState.closeBarrier {
                suffix = "\n\n\(message)"
            } else { suffix = "" }
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = CloseBarrierPresentation.message
            alert.informativeText = CloseBarrierPresentation.informativePrefix + suffix
            alert.addButton(withTitle: CloseBarrierPresentation.retryTitle)
            alert.addButton(withTitle: CloseBarrierPresentation.discardTitle)
            alert.addButton(withTitle: CloseBarrierPresentation.cancelTitle)
            alert.beginSheetModal(for: window) { [weak self, weak window] response in
                guard let self, let window else { return }
                let choice: SettingsWorkspaceState.CloseChoice
                switch response {
                case .alertFirstButtonReturn: choice = .retry
                case .alertSecondButtonReturn: choice = .discardChanges
                default: choice = .cancelClose
                }
                Task { @MainActor in
                    if await self.coordinator.resolveClose(choice) { self.finishClose(window) }
                    else if choice == .retry { self.presentBlockedClose(for: window) }
                    else { self.closeRequestInFlight = false }
                }
            }
        }
    }
}
