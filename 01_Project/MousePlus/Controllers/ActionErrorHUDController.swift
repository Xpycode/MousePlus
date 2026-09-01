import AppKit

/// Brief, non-activating presentation for a failed live-ring action.
@MainActor
final class ActionErrorHUDController: NSObject {
    typealias RouteHandler = (ActionSettingsRoute) -> Void

    private let displayDuration: Duration
    private let routeHandler: RouteHandler
    private let presentsWindows: Bool
    private var dismissalTask: Task<Void, Never>?
    private(set) var panel: NSPanel?
    private(set) var displayedFailure: RuntimeActionFailure?

    init(displayDuration: Duration = .seconds(4),
         presentsWindows: Bool = true,
         routeHandler: @escaping RouteHandler) {
        self.displayDuration = displayDuration
        self.presentsWindows = presentsWindows
        self.routeHandler = routeHandler
    }

    func show(_ failure: RuntimeActionFailure) {
        dismissalTask?.cancel()
        panel?.orderOut(nil)
        displayedFailure = failure
        let panel = makePanel(for: failure)
        self.panel = panel
        if presentsWindows {
            position(panel)
            panel.orderFrontRegardless()
        }
        let displayDuration = displayDuration
        dismissalTask = Task { [weak self] in
            try? await Task.sleep(for: displayDuration)
            guard !Task.isCancelled else { return }
            self?.dismiss()
        }
    }

    func dismiss() {
        dismissalTask?.cancel()
        dismissalTask = nil
        panel?.orderOut(nil)
        panel = nil
        displayedFailure = nil
    }

    func openSettings() {
        guard let route = displayedFailure?.settingsRoute else { return }
        dismiss()
        routeHandler(route)
    }

    private func makePanel(for failure: RuntimeActionFailure) -> NSPanel {
        let panel = NonActivatingHUDPanel(
            contentRect: NSRect(x: 0, y: 0, width: 390, height: 112),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false
        )
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let effect = NSVisualEffectView(frame: panel.contentView?.bounds ?? .zero)
        effect.autoresizingMask = [.width, .height]
        effect.material = .hudWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 14
        effect.layer?.masksToBounds = true

        let icon = NSImageView(image: NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: "Action failed") ?? NSImage())
        icon.contentTintColor = .systemOrange
        icon.translatesAutoresizingMaskIntoConstraints = false
        let message = NSTextField(wrappingLabelWithString: failure.message)
        message.maximumNumberOfLines = 3
        message.lineBreakMode = .byTruncatingTail
        let button = NSButton(title: "Open Settings", target: self, action: #selector(openSettingsButtonPressed))
        button.bezelStyle = .rounded
        button.setAccessibilityIdentifier("actionErrorHUD.openSettings")
        let stack = NSStackView(views: [message, button])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        effect.addSubview(icon)
        effect.addSubview(stack)
        panel.contentView = effect
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: effect.leadingAnchor, constant: 16),
            icon.topAnchor.constraint(equalTo: effect.topAnchor, constant: 18),
            icon.widthAnchor.constraint(equalToConstant: 24),
            icon.heightAnchor.constraint(equalToConstant: 24),
            stack.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: effect.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: effect.topAnchor, constant: 14),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: effect.bottomAnchor, constant: -14)
        ])
        return panel
    }

    private func position(_ panel: NSPanel) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main
        guard let visibleFrame = screen?.visibleFrame else { return }
        panel.setFrameOrigin(NSPoint(x: visibleFrame.maxX - panel.frame.width - 18,
                                     y: visibleFrame.minY + 18))
    }

    @objc private func openSettingsButtonPressed() { openSettings() }
}

private final class NonActivatingHUDPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
