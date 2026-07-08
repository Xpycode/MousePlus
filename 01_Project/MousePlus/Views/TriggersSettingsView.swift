import SwiftUI

/// Settings → Triggers tab (W4).
///
/// Lets the user bind the ring to a keyboard shortcut and/or a mouse button, each
/// with its own interpretation mode (hold-release vs tap-toggle). Recording uses
/// `TriggerRecorderService` ("press the trigger you want"); a recorder timeout
/// surfaces the vendor-interception warning. Edits persist to `Configuration.triggers`
/// (debounced) and live-apply to the running `TriggerService` via `AppDelegate.applyTriggers`.
struct TriggersSettingsView: View {
    private let configService = ConfigurationService()

    @State private var triggers: TriggersConfig = .default
    @State private var loaded = false
    @State private var saveTask: Task<Void, Never>?

    @State private var recorder = TriggerRecorderService()
    @State private var recordingSlot: Slot?
    @State private var interceptionWarning = false

    @State private var permissions = PermissionsService()

    private enum Slot { case keyboard, mouse, openSettings }

    var body: some View {
        Form {
            if !permissions.isGranted {
                permissionBanner
            }

            Section("Keyboard Trigger") {
                bindingRow(slot: .keyboard, binding: $triggers.keyboard)
            }

            Section("Mouse Button Trigger") {
                bindingRow(slot: .mouse, binding: $triggers.mouseButton)
            }

            Section("Open Settings Shortcut") {
                bindingRow(slot: .openSettings, binding: $triggers.openSettings)
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
        .task {
            guard !loaded else { return }
            if let config = try? await configService.load() {
                triggers = config.triggers
            }
            loaded = true
        }
        .onChange(of: triggers) { _, newValue in
            guard loaded else { return }
            scheduleSave(newValue)
        }
        .onChange(of: recorder.outcome) { _, outcome in
            handleRecorderOutcome(outcome)
        }
        .onAppear { permissions.startPolling() }
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
                Text(binding.wrappedValue.displayString)
                    .font(.title3.weight(.medium))
                    .foregroundStyle(binding.wrappedValue.isActive ? .primary : .secondary)
            }

            Spacer()

            Button(isRecording ? "Cancel" : "Record") {
                if isRecording {
                    recorder.cancel()
                } else {
                    interceptionWarning = false
                    recordingSlot = slot
                    recorder.record(slot == .mouse ? .mouseButton : .keyboard)
                }
            }

            Button("Clear") {
                binding.wrappedValue = .none
            }
            .disabled(!binding.wrappedValue.isActive || isRecording)
        }

        // The Settings hotkey fires once on key-down — hold-release vs tap-toggle is
        // meaningless for it, so the mode picker is only shown for the ring triggers.
        if slot != .openSettings {
            Picker("Mode", selection: Binding(
                get: { binding.wrappedValue.mode },
                set: { binding.wrappedValue = binding.wrappedValue.withMode($0) }
            )) {
                Text("Hold-release").tag(TriggerMode.holdRelease)
                Text("Tap-toggle").tag(TriggerMode.tapToggle)
            }
            .pickerStyle(.segmented)
            .disabled(!binding.wrappedValue.isActive)
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
                    Button("Open System Settings…") {
                        permissions.openAccessibilitySettings()
                    }
                    .controlSize(.small)
                }
            } icon: {
                Image(systemName: "lock.shield")
                    .foregroundStyle(.orange)
            }
        }
    }

    // MARK: - Recorder plumbing

    private func handleRecorderOutcome(_ outcome: TriggerRecorderService.Outcome?) {
        guard let outcome, let slot = recordingSlot else { return }

        switch outcome {
        case let .captured(captured):
            switch slot {
            case .keyboard:
                // Preserve the slot's mode; the recorder only knows the key/button.
                triggers.keyboard = captured.withMode(triggers.keyboard.mode)
            case .mouse:
                triggers.mouseButton = captured.withMode(triggers.mouseButton.mode)
            case .openSettings:
                // Mode is irrelevant for the Settings hotkey — store the raw capture.
                triggers.openSettings = captured
            }
        case .timedOut:
            interceptionWarning = true
        case .cancelled:
            break
        }

        recordingSlot = nil
        recorder.outcome = nil
    }

    // MARK: - Persistence

    /// Debounced save: load the full config, swap in the edited triggers, persist,
    /// then live-apply to the running `TriggerService`.
    private func scheduleSave(_ newTriggers: TriggersConfig) {
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            var config = (try? await configService.load()) ?? Configuration()
            config.triggers = newTriggers
            try? await configService.save(config)
            await MainActor.run {
                AppDelegate.applyTriggers?(newTriggers)
            }
        }
    }
}

#Preview {
    TriggersSettingsView()
        .frame(width: 460, height: 460)
}
