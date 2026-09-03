import SwiftUI
import MacUIKitSettings

/// Settings/Preferences view
struct SettingsView: View {
    @Binding var selection: SettingsSection?
    @Binding var requestedMenuItemID: UUID?
    @State private var coordinator: SettingsWorkspaceCoordinator

    init(
        selection: Binding<SettingsSection?>,
        requestedMenuItemID: Binding<UUID?> = .constant(nil),
        liveApply: @escaping @MainActor (Configuration) -> Void = { _ in }
    ) {
        _selection = selection
        _requestedMenuItemID = requestedMenuItemID
        _coordinator = State(initialValue: SettingsWorkspaceCoordinator(liveApply: liveApply))
    }

    var body: some View {
        HStack(spacing: 0) {
            List(selection: $selection) {
                ForEach(SettingsSection.orderedCases(), id: \.self) { section in
                    Label(section.title, systemImage: section.systemImage)
                        .tag(section)
                }
            }
            .listStyle(.sidebar)
            .frame(width: 200)

            // HSplitView extends its divider through the unified title area.
            // Start this local boundary below the title instead.
            Divider()
                .padding(.top, 52)

            Group {
                if let selection {
                    switch selection {
                    case .general:
                        GeneralSettingsPane(coordinator: coordinator)
                    case .triggers:
                        TriggersSettingsView(coordinator: coordinator)
                    case .ringAppearance:
                        RingAppearanceSettingsPane(coordinator: coordinator)
                    case .menuItems:
                        MenuItemsPane(coordinator: coordinator, requestedItemID: $requestedMenuItemID)
                    }
                } else {
                    Text("Select a category")
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 1120, minHeight: 680)
        .background(SettingsWindowCloseBarrier(coordinator: coordinator).frame(width: 0, height: 0))
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
