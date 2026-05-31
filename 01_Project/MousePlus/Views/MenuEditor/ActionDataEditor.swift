import AppKit
import SwiftUI

/// Edits a menu item's action type and its type-specific data payload.
///
/// Drops into a `Form`/`VStack`. The top control is an action-type `Picker`
/// (clipboard is never offered), and below it a control whose shape depends on
/// the selected `ActionType`:
/// - `.appSwitch` — shows the chosen app + a "Choose…" button (presents `AppPickerSheet`).
/// - `.custom`    — multiline command field with an empty-command warning.
/// - `.windowSnap`— `SnapZone` picker, stored as the zone's `rawValue`.
/// - `.menuBar` / `.systemToggle` / `.screenshot` — disabled "coming soon" placeholder.
///
/// Note: the dropped `.clipboard` value is *not* a real enum case (it decodes to
/// `.custom`), so it is never offered in the picker and never reaches the switch.
struct ActionDataEditor: View {
    @Binding var item: RingMenuItem

    /// Drives the `AppPickerSheet` presentation for `.appSwitch`.
    @State private var showingAppPicker = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 1. Action type picker.
            //
            // The legacy `.clipboard` value isn't a real enum case here — it's mapped
            // to `.custom` during decode (see `ActionType.init(from:)`), so it can never
            // appear in `allCases` and needs no explicit filtering.
            Picker("Action", selection: $item.actionType) {
                ForEach(ActionType.allCases, id: \.self) { type in
                    Text(type.displayName).tag(type)
                }
            }
            .pickerStyle(.menu)

            // 2. Type-aware data control.
            dataControl
        }
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
        case .menuBar, .systemToggle, .screenshot:
            // `.clipboard` is intentionally absent — it decodes to `.custom`, so it
            // can never reach this switch.
            comingSoonControl
        }
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

                Button("Choose…") {
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
            TextField("Command", text: $item.actionData, axis: .vertical)
                .lineLimit(2...5)
                .textFieldStyle(.roundedBorder)

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
        Picker("Snap to", selection: snapZoneBinding) {
            ForEach(SnapZone.allCases, id: \.self) { zone in
                Label {
                    Text(zone.displayName)
                } icon: {
                    Image(systemName: zone.systemImage)
                }
                .tag(zone)
            }
        }
        .pickerStyle(.menu)
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

            Text("This action type isn't implemented yet.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
