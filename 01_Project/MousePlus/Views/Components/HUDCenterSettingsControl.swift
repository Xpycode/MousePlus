import AppKit
import SwiftUI

/// The HUD dead-zone's dedicated Settings action, backed by a native button.
struct HUDCenterSettingsControl: NSViewRepresentable {
    static let accessibilityIdentifier = "hud.center.settings"
    static let accessibilityLabel = "Open MousePlus Settings"

    let action: @MainActor () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(action: action) }

    func makeNSView(context: Context) -> NSButton {
        let image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: Self.accessibilityLabel) ?? NSImage()
        let button = NSButton(image: image, target: context.coordinator, action: #selector(Coordinator.activate))
        button.bezelStyle = .circular
        button.imagePosition = .imageOnly
        button.toolTip = "Open Settings"
        configure(button)
        return button
    }

    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.action = action
        configure(button)
    }

    private func configure(_ button: NSButton) {
        button.setAccessibilityLabel(Self.accessibilityLabel)
        button.setAccessibilityIdentifier(Self.accessibilityIdentifier)
    }

    @MainActor final class Coordinator: NSObject {
        var action: @MainActor () -> Void
        init(action: @escaping @MainActor () -> Void) { self.action = action }
        @objc func activate() { action() }
    }
}
