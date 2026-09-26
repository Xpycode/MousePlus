import AppKit
import SwiftUI

/// Trigger recording and permission polling remain local UI concerns. Durable
/// edits flow exclusively through the workspace coordinator.
struct TriggersSettingsView: View {
    let coordinator: SettingsWorkspaceCoordinator

    @State private var recorder = TriggerRecorderService()
    @State private var recordingSlot: Slot?
    @State private var interceptionWarning = false
    @State private var bindingCollision: HUDTriggerBindingCollision?

    @State private var permissions = PermissionsService()
    @State private var postEventPermissions: PostEventPermissionsState

    @MainActor
    init(coordinator: SettingsWorkspaceCoordinator) {
        self.coordinator = coordinator
        _postEventPermissions = State(initialValue: PostEventPermissionsState())
    }

    @MainActor
    init(coordinator: SettingsWorkspaceCoordinator, postEventPermissions: PostEventPermissionsState) {
        self.coordinator = coordinator
        _postEventPermissions = State(initialValue: postEventPermissions)
    }

    private enum Slot {
        case keyboard, mouse, globalHUDShortcut, openSettings

        var identifier: String {
            switch self {
            case .keyboard: "keyboard"
            case .mouse: "mouse"
            case .globalHUDShortcut: "globalHUDShortcut"
            case .openSettings: "openSettings"
            }
        }

        var accessibilityLabel: String {
            switch self {
            case .keyboard: "Contextual keyboard trigger"
            case .mouse: "Contextual mouse trigger"
            case .globalHUDShortcut: "Global HUD shortcut"
            case .openSettings: "Open Settings shortcut"
            }
        }
    }

    var body: some View {
        Form {
            if !permissions.isGranted {
                permissionBanner
            }

            if !postEventPermissions.isGranted {
                postEventPermissionRow
            }

            Section("Keyboard Trigger") {
                bindingRow(slot: .keyboard, binding: triggerBinding(\.keyboard))
            }

            Section("Mouse Button Trigger") {
                bindingRow(slot: .mouse, binding: triggerBinding(\.mouseButton))
            }

            Section("Global HUD Shortcut") {
                bindingRow(
                    slot: .globalHUDShortcut,
                    binding: triggerBinding(\.globalHUDShortcut)
                )
                Text("Always opens the Global HUD, bypassing the frontmost app profile.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Open Settings Shortcut") {
                bindingRow(slot: .openSettings, binding: triggerBinding(\.openSettings))
                Text("Opens this Settings window from anywhere — a reliable way in when the menu bar icon isn't showing. Defaults to ⌥⌘,.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if interceptionWarning {
                Section {
                    Label {
                        Text("Didn't detect anything. The button may be captured by Logi Options+, "
                             + "SteerMouse, or Karabiner before MousePlus sees it. Set it to "
                             + "“No Action” / “Default” in that app, then record again.")
                            .font(.caption)
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                }
            }

            Section {
                Text("Hold-release: hold the trigger, move to a slice, release to pick. "
                     + "Tap-toggle: tap to open, click a slice to pick.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
        .onChange(of: recorder.outcome) { _, outcome in
            handleRecorderOutcome(outcome)
        }
        .onAppear {
            permissions.startPolling()
            postEventPermissions.refresh()
        }
        .onDisappear {
            permissions.stopPolling()
            recorder.cancel()
        }
    }

    // MARK: - Rows

    @ViewBuilder
    private func bindingRow(slot: Slot, binding: Binding<TriggerBinding>) -> some View {
        let isRecording = recordingSlot == slot && recorder.isRecording

        HStack {
            if isRecording {
                Text(slot == .mouse ? "Press a button… (Esc to cancel)" : "Press a key… (Esc to cancel)")
                    .foregroundStyle(.secondary)
            } else {
                TriggerBindingAppKitLabel(
                    value: binding.wrappedValue.displayString,
                    isActive: binding.wrappedValue.isActive,
                    accessibilityLabel: slot.accessibilityLabel,
                    accessibilityIdentifier: "triggers.\(slot.identifier).binding"
                )
            }

            Spacer()

            AppKitButton(
                title: isRecording ? "Cancel" : "Record",
                isEnabled: coordinator.isLoaded,
                accessibilityIdentifier: "triggers.\(slot.identifier).record"
            ) {
                if isRecording {
                    recorder.cancel()
                } else {
                    interceptionWarning = false
                    bindingCollision = nil
                    recordingSlot = slot
                    recorder.record(slot == .mouse ? .mouseButton : .keyboard)
                }
            }

            AppKitButton(
                title: "Clear",
                isEnabled: binding.wrappedValue.isActive && !isRecording && coordinator.isLoaded,
                accessibilityIdentifier: "triggers.\(slot.identifier).clear"
            ) {
                binding.wrappedValue = .none
            }
        }

        if slot == .globalHUDShortcut, let displayedBindingCollision {
            TriggerCollisionAppKitLabel(text: displayedBindingCollision.explanation)
        }

        // The Settings hotkey fires once on key-down — hold-release vs tap-toggle is
        // meaningless for it, so the mode picker is only shown for the ring triggers.
        if slot != .openSettings {
            AppKitSegmentedControl(
                labels: ["Hold-release", "Tap-toggle"],
                selection: Binding(
                    get: { binding.wrappedValue.mode == .holdRelease ? 0 : 1 },
                    set: { binding.wrappedValue = binding.wrappedValue.withMode($0 == 0 ? .holdRelease : .tapToggle) }
                ),
                isEnabled: binding.wrappedValue.isActive && coordinator.isLoaded,
                accessibilityLabel: "\(slot.accessibilityLabel) mode",
                accessibilityIdentifier: "triggers.\(slot.identifier).mode"
            )
        }
    }

    private var permissionBanner: some View {
        Section {
            Label {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Accessibility permission required")
                        .font(.callout.weight(.semibold))
                    Text("MousePlus needs Accessibility access to detect your trigger system-wide.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    AppKitButton(
                        title: "Open System Settings…",
                        accessibilityIdentifier: "triggers.openAccessibilitySettings"
                    ) {
                        permissions.openAccessibilitySettings()
                    }
                }
            } icon: {
                Image(systemName: "lock.shield")
                    .foregroundStyle(.orange)
            }
        }
    }

    private var postEventPermissionRow: some View {
        Section("Keystroke posting") {
            Label {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Keystroke posting permission required")
                        .font(.callout.weight(.semibold))
                    Text("Allow MousePlus to send configured keystrokes to other apps.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    AppKitButton(
                        title: "Request Access…",
                        accessibilityIdentifier: "triggers.requestKeystrokePostingAccess"
                    ) {
                        postEventPermissions.requestFromUserAction()
                    }
                }
            } icon: {
                Image(systemName: "keyboard.badge.ellipsis")
                    .foregroundStyle(.orange)
            }
        }
    }

    // MARK: - Recorder plumbing

    private var displayedBindingCollision: HUDTriggerBindingCollision? {
        bindingCollision ?? HUDTriggerRouting.collision(
            globalHUDShortcut: coordinator.configuration.triggers.globalHUDShortcut,
            contextualKeyboard: coordinator.configuration.triggers.keyboard
        )
    }

    private func handleRecorderOutcome(_ outcome: TriggerRecorderService.Outcome?) {
        guard let outcome, let slot = recordingSlot else { return }

        switch outcome {
        case let .captured(captured):
            switch slot {
            case .keyboard:
                // Preserve the slot's mode; the recorder only knows the key/button.
                let current = coordinator.configuration.triggers.keyboard
                bindingCollision = Self.applyContextualKeyboard(
                    captured.withMode(current.mode),
                    coordinator: coordinator
                )
            case .mouse:
                let current = coordinator.configuration.triggers.mouseButton
                setTrigger(\.mouseButton, captured.withMode(current.mode))
            case .globalHUDShortcut:
                let current = coordinator.configuration.triggers.globalHUDShortcut
                bindingCollision = Self.applyGlobalHUDShortcut(
                    captured.withMode(current.mode),
                    coordinator: coordinator
                )
            case .openSettings:
                // Mode is irrelevant for the Settings hotkey — store the raw capture.
                setTrigger(\.openSettings, captured)
            }
        case .timedOut:
            interceptionWarning = true
        case .cancelled:
            break
        }

        recordingSlot = nil
        recorder.outcome = nil
    }

    private func triggerBinding(_ keyPath: WritableKeyPath<TriggersConfig, TriggerBinding>) -> Binding<TriggerBinding> {
        Binding(
            get: { coordinator.configuration.triggers[keyPath: keyPath] },
            set: { setTrigger(keyPath, $0) }
        )
    }

    private func setTrigger(
        _ keyPath: WritableKeyPath<TriggersConfig, TriggerBinding>,
        _ value: TriggerBinding
    ) {
        coordinator.edit([.triggers]) { $0.triggers[keyPath: keyPath] = value }
    }

    /// Shared by the recorder path and focused tests. Only accepted candidates
    /// enter the workspace's normal save/live-apply pipeline.
    @discardableResult
    static func applyGlobalHUDShortcut(
        _ candidate: TriggerBinding,
        coordinator: SettingsWorkspaceCoordinator
    ) -> HUDTriggerBindingCollision? {
        let triggers = coordinator.configuration.triggers
        switch HUDTriggerRouting.validateGlobalHUDShortcut(
            candidate,
            previous: triggers.globalHUDShortcut,
            contextualKeyboard: triggers.keyboard
        ) {
        case .accepted(let binding):
            coordinator.edit([.triggers]) { $0.triggers.globalHUDShortcut = binding }
            return nil
        case .rejected(let collision, _):
            return collision
        }
    }

    @discardableResult
    static func applyContextualKeyboard(
        _ candidate: TriggerBinding,
        coordinator: SettingsWorkspaceCoordinator
    ) -> HUDTriggerBindingCollision? {
        let triggers = coordinator.configuration.triggers
        switch HUDTriggerRouting.validateContextualKeyboard(
            candidate,
            previous: triggers.keyboard,
            globalHUDShortcut: triggers.globalHUDShortcut
        ) {
        case .accepted(let binding):
            coordinator.edit([.triggers]) { $0.triggers.keyboard = binding }
            return nil
        case .rejected(let collision, _):
            return collision
        }
    }
}

/// The binding value is an AppKit text field so the new row exposes stable
/// native accessibility metadata just like its buttons and mode control.
private struct TriggerBindingAppKitLabel: NSViewRepresentable {
    let value: String
    let isActive: Bool
    let accessibilityLabel: String
    let accessibilityIdentifier: String

    func makeNSView(context: Context) -> NSTextField {
        NSTextField(labelWithString: value)
    }

    func updateNSView(_ label: NSTextField, context: Context) {
        label.stringValue = value
        label.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .medium)
        label.textColor = isActive ? .labelColor : .secondaryLabelColor
        label.setAccessibilityLabel(accessibilityLabel)
        label.setAccessibilityValue(value)
        label.setAccessibilityIdentifier(accessibilityIdentifier)
    }
}

private struct TriggerCollisionAppKitLabel: NSViewRepresentable {
    let text: String

    func makeNSView(context: Context) -> NSTextField {
        NSTextField(wrappingLabelWithString: text)
    }

    func updateNSView(_ label: NSTextField, context: Context) {
        label.stringValue = text
        label.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        label.textColor = .systemOrange
        label.setAccessibilityLabel(text)
        label.setAccessibilityIdentifier("triggers.globalHUDShortcut.conflict")
    }
}
