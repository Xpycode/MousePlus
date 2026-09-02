import AppKit
import ShortcutKit
import SwiftUI

/// Edits a menu item's action type and its type-specific data payload.
///
/// Drops into a `Form`/`VStack`. The top control is an action-type `Picker`
/// and below it a control whose shape depends on
/// the selected `ActionType`:
/// - `.appSwitch` — shows the chosen app + a "Choose…" button (presents `AppPickerSheet`).
/// - `.custom`    — multiline command field with an empty-command warning.
/// - `.windowSnap`— `SnapZone` picker, stored as the zone's `rawValue`.
/// - `.menuBar` / `.systemToggle` / `.screenshot` — disabled "coming soon" placeholder.
///
struct ActionDataEditor: View {
    @Binding var item: RingMenuItem

    /// Drives the `AppPickerSheet` presentation for `.appSwitch`.
    @State private var showingAppPicker = false
    @State private var commandFocused = false
    @State private var keystrokeCandidate: CustomKeyboardShortcut?
    @State private var keystrokeRecorder = KeystrokeCaptureRecorder()
    @State private var recordingItemID: UUID?
    @State private var keystrokeCaptureMessage: String?
    private let keystrokeConflicts = KeystrokeConflictChecker()

    private var offeredActionTypes: [ActionType] {
        item.actionType.isSelectable
            ? ActionType.selectableCases
            : [item.actionType] + ActionType.selectableCases
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Keep an existing unavailable value visible, but offer only supported
            // actions as replacements.
            AppKitPopup(
                options: offeredActionTypes.map(actionOptionTitle),
                selection: actionSelection,
                disabledOptions: item.actionType.isSelectable ? [] : [0],
                accessibilityLabel: "Action type",
                accessibilityIdentifier: "menuItems.editor.actionType"
            )

            // 2. Type-aware data control.
            dataControl
        }
        .onChange(of: keystrokeRecorder.outcome) { _, outcome in
            handleKeystrokeCapture(outcome)
        }
        .onChange(of: item.id) { _, _ in cancelKeystrokeCapture() }
        .onChange(of: item.actionType) { _, _ in cancelKeystrokeCapture() }
        .onDisappear { cancelKeystrokeCapture() }
    }

    // MARK: - Type-aware data control

    @ViewBuilder
    private var dataControl: some View {
        switch item.actionType {
        case .appSwitch:
            appSwitchControl
        case .custom:
            customControl
        case .windowSnap:
            windowSnapControl
        case .sendKeystroke:
            sendKeystrokeControl
        case .menuBar, .systemToggle, .screenshot, .unavailable:
            comingSoonControl
        }
    }

    // MARK: - Send keystroke

    @ViewBuilder
    private var sendKeystrokeControl: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Keystroke")

                Spacer()

                Text(keystrokeRecorder.isRecording
                     ? "Press a key… (Esc to cancel)"
                     : committedKeystrokeDisplay)
                    .foregroundStyle(keystrokeRecorder.isRecording || item.keystrokePayload == nil ? .secondary : .primary)
                    .accessibilityLabel(keystrokeRecorder.isRecording
                                        ? "Recording keystroke. Press a key, or Escape to cancel."
                                        : "Current keystroke: \(committedKeystrokeDisplay)")

                AppKitButton(
                    title: keystrokeRecorder.isRecording ? "Cancel" : "Record",
                    accessibilityLabel: keystrokeRecorder.isRecording ? "Cancel keystroke recording" : "Record keystroke",
                    accessibilityIdentifier: keystrokeRecorder.isRecording
                        ? "menuItems.editor.keystroke.cancel"
                        : "menuItems.editor.keystroke.record"
                ) {
                    if keystrokeRecorder.isRecording {
                        cancelKeystrokeCapture()
                    } else {
                        recordingItemID = item.id
                        keystrokeCandidate = nil
                        keystrokeCaptureMessage = nil
                        keystrokeRecorder.record()
                    }
                }

                AppKitButton(
                    title: "Clear",
                    isEnabled: item.keystrokePayload != nil && !keystrokeRecorder.isRecording,
                    accessibilityIdentifier: "menuItems.editor.keystroke.clear"
                ) {
                    item.keystrokePayload = nil
                    keystrokeCandidate = nil
                    keystrokeCaptureMessage = nil
                }
            }

            if case let .unresolvedLegacy(value) = item.keystrokePayload {
                Label("The legacy shortcut “\(value)” can't be interpreted safely. Record it again.", systemImage: "exclamationmark.circle.fill")
                    .foregroundStyle(.red)
                    .accessibilityLabel("Can't use legacy shortcut. Record it again.")
            } else if let keystrokeCaptureMessage {
                Label(keystrokeCaptureMessage, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .accessibilityLabel("Keystroke recording failed. \(keystrokeCaptureMessage)")
            } else if let conflictCaption {
                Label(conflictCaption.message, systemImage: conflictCaption.severity == .blocked ? "exclamationmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(conflictCaption.severity == .blocked ? .red : .orange)
                    .accessibilityLabel((conflictCaption.severity == .blocked ? "Can't save. " : "Warning. ") + conflictCaption.message)
            }
        }
        .font(.caption)
    }

    private var committedKeystrokeDisplay: String {
        guard let shortcut = item.keystrokePayload?.shortcutKitValue,
              !shortcut.isUnbound else { return "None" }
        return shortcut.resolvedDisplayName
    }

    private func handleKeystrokeCapture(_ outcome: KeystrokeCaptureRecorder.Outcome?) {
        guard let outcome else { return }
        let armedItemID = recordingItemID
        recordingItemID = nil

        guard armedItemID == item.id, item.actionType == .sendKeystroke else {
            keystrokeCandidate = nil
            return
        }

        switch outcome {
        case let .captured(payload):
            let shortcut = payload.shortcutKitValue
            if assessment(for: shortcut)?.severity == .blocked {
                // Keep the rejected chord visible in the explanatory caption,
                // but never replace the item's committed payload.
                keystrokeCandidate = shortcut
            } else {
                item.keystrokePayload = payload
                keystrokeCandidate = nil
            }
            keystrokeCaptureMessage = nil
        case .cancelled:
            keystrokeCandidate = nil
            keystrokeCaptureMessage = nil
        case .timedOut:
            keystrokeCandidate = nil
            keystrokeCaptureMessage = "No keystroke was detected. Try recording again."
        case let .failed(message):
            keystrokeCandidate = nil
            keystrokeCaptureMessage = message
        }
    }

    private func cancelKeystrokeCapture() {
        // Invalidate the binding target before cancellation publishes its outcome.
        recordingItemID = nil
        keystrokeRecorder.cancel()
        keystrokeCandidate = nil
        keystrokeCaptureMessage = nil
    }

    private var conflictCaption: KeystrokeConflictAssessment? {
        if let keystrokeCandidate { return assessment(for: keystrokeCandidate) }
        guard let shortcut = item.keystrokePayload?.shortcutKitValue,
              !shortcut.isUnbound
        else { return nil }
        return assessment(for: shortcut)
    }

    private func assessment(for shortcut: CustomKeyboardShortcut) -> KeystrokeConflictAssessment? {
        keystrokeConflicts.assessment(for: shortcut)
    }

    // MARK: - App Switch

    @ViewBuilder
    private var appSwitchControl: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(resolvedAppName)
                    .foregroundStyle(item.actionData.isEmpty ? .secondary : .primary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer()

                AppKitButton(title: "Choose…", accessibilityIdentifier: "menuItems.editor.chooseApplication") {
                    showingAppPicker = true
                }
            }

            // Plan nuance: the ring renders the chosen SF Symbol, not the live app icon.
            Text("Shows the chosen SF Symbol, not the app's real icon (yet).")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .sheet(isPresented: $showingAppPicker) {
            AppPickerSheet(
                onPick: { bundleID, name, suggestedSymbol in
                    item.actionData = bundleID
                    // Suggest sensible defaults without clobbering real user choices.
                    if item.label.isEmpty {
                        item.label = name
                    }
                    if item.icon.isEmpty || item.icon == "questionmark" {
                        item.icon = suggestedSymbol
                    }
                    showingAppPicker = false
                },
                onCancel: {
                    showingAppPicker = false
                }
            )
        }
    }

    /// Human-readable name for the currently bound app bundle id, with safe fallbacks.
    private var resolvedAppName: String {
        let bundleID = item.actionData
        guard !bundleID.isEmpty else { return "No app chosen" }

        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            let name = FileManager.default.displayName(atPath: url.path)
            if !name.isEmpty { return name }
        }
        // Fall back to the raw bundle id if we can't resolve a friendly name.
        return bundleID
    }

    // MARK: - Custom command

    @ViewBuilder
    private var customControl: some View {
        VStack(alignment: .leading, spacing: 4) {
            AppKitMultilineTextField(
                text: $item.actionData,
                isFocused: $commandFocused,
                accessibilityLabel: "Command",
                accessibilityIdentifier: "menuItems.editor.command"
            )
            .frame(minHeight: 52, maxHeight: 110)

            if item.actionData.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text("Command is empty")
                    .font(.caption)
                    .foregroundStyle(.orange)
            } else {
                Text("e.g. open -a Calculator")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Window snap

    @ViewBuilder
    private var windowSnapControl: some View {
        AppKitPopup(
            options: SnapZone.allCases.map(\.displayName),
            selection: snapZoneSelection,
            accessibilityLabel: "Snap to",
            accessibilityIdentifier: "menuItems.editor.snapZone"
        )
    }

    /// Maps `item.actionData` (a `SnapZone.rawValue`) ⇄ `SnapZone`.
    ///
    /// If the stored value isn't a known zone, the selection defaults to `.left`
    /// for display, but we only write that back once the user actually changes it.
    private var snapZoneBinding: Binding<SnapZone> {
        Binding(
            get: { SnapZone(rawValue: item.actionData) ?? .left },
            set: { item.actionData = $0.rawValue }
        )
    }

    private var snapZoneSelection: Binding<Int> {
        Binding(
            get: { SnapZone.allCases.firstIndex(of: snapZoneBinding.wrappedValue) ?? 0 },
            set: { index in
                guard SnapZone.allCases.indices.contains(index) else { return }
                snapZoneBinding.wrappedValue = SnapZone.allCases[index]
            }
        )
    }

    private var actionSelection: Binding<Int> {
        Binding(
            get: { offeredActionTypes.firstIndex(of: item.actionType) ?? 0 },
            set: { index in
                guard offeredActionTypes.indices.contains(index) else { return }
                let selected = offeredActionTypes[index]
                guard selected.isSelectable else { return }
                item.actionType = selected
            }
        )
    }

    private func actionOptionTitle(_ type: ActionType) -> String {
        type.isSelectable ? type.displayName : "\(type.displayName) — Unavailable"
    }

    // MARK: - Coming soon (not-yet-implemented action types)

    @ViewBuilder
    private var comingSoonControl: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Disabled, greyed placeholder so the layout stays stable.
            HStack {
                Text("(coming soon)")
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
            .disabled(true)

            Text("\(item.actionType.displayName) isn't available in this version. Its saved value and payload will remain unchanged until you choose a supported action.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
