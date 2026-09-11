import AppKit
import SwiftUI

/// Invocation-frozen identity shown by the center Settings control.
struct HUDCenterContextPresentation: Equatable {
    let name: String
    let bundleIdentifier: String?

    static let global = HUDCenterContextPresentation(name: "Global", bundleIdentifier: nil)

    init(name: String, bundleIdentifier: String?) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.name = trimmedName.isEmpty ? bundleIdentifier ?? "Global" : trimmedName
        self.bundleIdentifier = bundleIdentifier
    }

    init(resolved profile: ResolvedHUDProfile?) {
        guard let profile,
              case .app(let bundleIdentifier) = profile.profileReference else {
            self = .global
            return
        }
        self.init(
            name: profile.targetApplication.localizedName ?? bundleIdentifier,
            bundleIdentifier: bundleIdentifier
        )
    }

    var accessibilityLabel: String {
        "Open MousePlus Settings — \(name) HUD active"
    }
}

/// The HUD dead-zone's dedicated Settings action, backed by a native button.
struct HUDCenterSettingsControl: NSViewRepresentable {
    static let accessibilityIdentifier = "hud.center.settings"
    static let accessibilityLabel = "Open MousePlus Settings"

    var presentation: HUDCenterContextPresentation = .global
    var applicationIcon: @MainActor (String) -> NSImage? = Self.workspaceApplicationIcon
    let action: @MainActor () -> Void
    var draggingEnabled = false
    var onDrag: @MainActor (CGSize) -> Void = { _ in }

    func makeCoordinator() -> Coordinator { Coordinator(action: action, onDrag: onDrag) }

    func makeNSView(context: Context) -> NSButton {
        let button = HUDCenterTrackingButton(
            title: presentation.name,
            target: context.coordinator,
            action: #selector(Coordinator.activate)
        )
        button.bezelStyle = .circular
        button.imagePosition = .imageAbove
        button.imageScaling = .scaleProportionallyDown
        button.contentTintColor = .labelColor
        button.font = .systemFont(ofSize: 9, weight: .medium)
        (button.cell as? NSButtonCell)?.lineBreakMode = .byTruncatingTail
        button.onDrag = { [weak coordinator = context.coordinator] delta in
            coordinator?.drag(delta)
        }
        button.draggingEnabled = draggingEnabled
        configure(button)
        return button
    }

    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.action = action
        context.coordinator.onDrag = onDrag
        if let button = button as? HUDCenterTrackingButton {
            button.draggingEnabled = draggingEnabled
        }
        configure(button)
    }

    private func configure(_ button: NSButton) {
        if let button = button as? HUDCenterTrackingButton {
            button.apply(presentation, applicationIcon: applicationIcon)
        }
        button.toolTip = presentation.accessibilityLabel
        button.setAccessibilityLabel(presentation.accessibilityLabel)
        button.setAccessibilityIdentifier(Self.accessibilityIdentifier)
    }

    @MainActor
    static func workspaceApplicationIcon(bundleIdentifier: String) -> NSImage? {
        guard let url = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: bundleIdentifier
        ) else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }

    @MainActor final class Coordinator: NSObject {
        var action: @MainActor () -> Void
        var onDrag: @MainActor (CGSize) -> Void
        init(action: @escaping @MainActor () -> Void,
             onDrag: @escaping @MainActor (CGSize) -> Void) {
            self.action = action
            self.onDrag = onDrag
        }
        @objc func activate() { action() }
        func drag(_ delta: CGSize) { onDrag(delta) }
    }
}

/// Pure click/drag arbitration used by the native center control.
struct HUDCenterDragState {
    static let threshold: CGFloat = 4

    private(set) var isDragging = false
    private var start: CGPoint?
    private var previous: CGPoint?

    mutating func begin(at point: CGPoint) {
        isDragging = false
        start = point
        previous = point
    }

    mutating func move(to point: CGPoint) -> CGSize? {
        guard let start, let previous else { return nil }
        if !isDragging {
            guard hypot(point.x - start.x, point.y - start.y) > Self.threshold else { return nil }
            isDragging = true
        }
        self.previous = point
        return CGSize(width: point.x - previous.x, height: point.y - previous.y)
    }

    mutating func end() -> Bool {
        let shouldClick = !isDragging
        isDragging = false
        start = nil
        previous = nil
        return shouldClick
    }
}

/// Tracks in global coordinates so moving the panel beneath the pointer does not
/// perturb subsequent drag deltas.
private final class HUDCenterTrackingButton: NSButton {
    /// Match the original image-only circular button's native hit target. The
    /// context title must never make AppKit resize the action between profiles.
    override var intrinsicContentSize: NSSize { NSSize(width: 38, height: 38) }

    var draggingEnabled = false
    var onDrag: @MainActor (CGSize) -> Void = { _ in }
    private var dragState = HUDCenterDragState()
    private var appliedPresentation: HUDCenterContextPresentation?

    @MainActor
    func apply(
        _ presentation: HUDCenterContextPresentation,
        applicationIcon: @MainActor (String) -> NSImage?
    ) {
        guard appliedPresentation != presentation else { return }
        appliedPresentation = presentation
        title = presentation.name

        let identityIcon: NSImage
        if let bundleIdentifier = presentation.bundleIdentifier,
           let resolvedIcon = applicationIcon(bundleIdentifier) {
            identityIcon = resolvedIcon
        } else {
            identityIcon = NSImage(
                systemSymbolName: presentation.bundleIdentifier == nil ? "globe" : "app",
                accessibilityDescription: nil
            ) ?? NSImage()
        }
        image = identityIcon
    }

    private let gearBadge: HUDCenterGearBadge = {
        let view = HUDCenterGearBadge()
        let configuration = NSImage.SymbolConfiguration(pointSize: 7, weight: .semibold)
        view.image = NSImage(
            systemSymbolName: "gearshape.fill",
            accessibilityDescription: nil
        )?.withSymbolConfiguration(configuration)
        view.imageScaling = .scaleProportionallyDown
        view.contentTintColor = .labelColor
        view.wantsLayer = true
        view.setAccessibilityElement(false)
        return view
    }()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configureGearBadge()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureGearBadge()
    }

    override func layout() {
        super.layout()
        let side: CGFloat = 11
        gearBadge.frame = NSRect(
            x: bounds.maxX - side - 2,
            y: isFlipped ? bounds.minY + 2 : bounds.maxY - side - 2,
            width: side,
            height: side
        )
        gearBadge.layer?.cornerRadius = side / 2
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateGearBadgeAppearance()
    }

    private func configureGearBadge() {
        addSubview(gearBadge)
        updateGearBadgeAppearance()
    }

    private func updateGearBadgeAppearance() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            gearBadge.layer?.backgroundColor = NSColor.windowBackgroundColor
                .withAlphaComponent(0.92).cgColor
        }
    }

    override func mouseDown(with event: NSEvent) {
        guard draggingEnabled, let window else {
            super.mouseDown(with: event)
            return
        }

        dragState.begin(at: NSEvent.mouseLocation)
        highlight(true)
        defer { highlight(false) }

        while let next = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
            switch next.type {
            case .leftMouseDragged:
                if let delta = dragState.move(to: NSEvent.mouseLocation) {
                    onDrag(delta)
                }
            case .leftMouseUp:
                if dragState.end() {
                    sendAction(action, to: target)
                }
                return
            default:
                break
            }
        }
    }
}

/// Decorative only: the containing native button must own every click and drag.
private final class HUDCenterGearBadge: NSImageView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
