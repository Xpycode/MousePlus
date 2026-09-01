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
                MenuItemsPane(coordinator: coordinator)
            }
        }
        .frame(minWidth: 1120, minHeight: 680)
        .task {
            guard !coordinator.isLoaded else { return }
            await coordinator.load()
        }
    }
}

#Preview {
    @Previewable @State var selection: SettingsSection? = .general
    SettingsView(selection: $selection)
}
