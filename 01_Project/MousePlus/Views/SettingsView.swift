import SwiftUI
import MacUIKitSettings

/// Settings/Preferences view
struct SettingsView: View {
    @Binding var selection: SettingsSection?
    @State private var coordinator = SettingsWorkspaceCoordinator()

    var body: some View {
        SettingsSidebarShell(selection: $selection, searchable: false) { section in
            switch section {
            case .general:
                GeneralSettingsPane(coordinator: coordinator)
            case .triggers:
                TriggersSettingsView(coordinator: coordinator)
            case .ringAppearance:
                RingAppearanceSettingsPane(coordinator: coordinator)
            case .menuItems:
                MenuSettingsView()
            }
        }
        .frame(minWidth: 1120, minHeight: 680)
        .task {
            guard !coordinator.isLoaded else { return }
            await coordinator.load()
        }
    }
}

/// Launcher tab for the standalone Menu Items editor. The full WYSIWYG-lite
/// editor lives in its own resizable window (see `MenuEditorWindowController`),
/// since the Settings content frame is too small for the band picker + ring
/// preview + form. This tab just explains and opens it.
struct MenuSettingsView: View {
    var body: some View {
        Form {
            Section("Menu Items") {
                Text("Customize the inner and middle rings — icons, labels, actions, and each middle wedge's sub-items.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button("Open Menu Editor…") {
                    AppDelegate.showMenuEditor?()
                }
                .controlSize(.large)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

#Preview {
    @Previewable @State var selection: SettingsSection? = .general
    SettingsView(selection: $selection)
}
