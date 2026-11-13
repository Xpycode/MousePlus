import SwiftUI
import MacUIKitSettings

/// Settings/Preferences view
struct SettingsView: View {
    private static let sidebarWidth: CGFloat = 200
    private static let titleHeight: CGFloat = 32
    @Binding var selection: SettingsSection?
    @Binding var requestedMenuItemID: UUID?
    @State private var profilesExpanded = true
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
            VStack(spacing: 0) {
                SettingsHeaderDragSurface()
                    // Leave native traffic-light controls outside the drag surface.
                    .padding(.leading, 80)
                    .frame(height: Self.titleHeight)

                List(selection: sidebarSelection) {
                    ForEach(SettingsSection.orderedCases().filter { $0 != .menuItems }, id: \.self) { section in
                        Label(section.title, systemImage: section.systemImage)
                            .tag(SidebarSelection.section(section))
                    }
                    DisclosureGroup(isExpanded: $profilesExpanded) {
                        ForEach(coordinator.editableHUDProfiles, id: \.self) { profile in
                            Label(coordinator.profileTitle(profile),
                                  systemImage: profile == .global ? "globe" : "app")
                                .tag(SidebarSelection.profile(profile))
                                .help(coordinator.profileTitle(profile))
                        }
                    } label: {
                        Label("Menu Items", systemImage: "circle.hexagongrid")
                    }
                    .tag(SidebarSelection.section(.menuItems))
                }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)
            }
            .background(Color(nsColor: .controlBackgroundColor))
            .frame(width: Self.sidebarWidth)

            // HSplitView extends its divider through the unified title area.
            // Start this local boundary below the title instead.
            Divider()
                .padding(.top, Self.titleHeight)

            VStack(spacing: 0) {
                Text("MousePlus Settings")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .frame(height: Self.titleHeight)
                    .allowsHitTesting(false)
                    .overlay(SettingsHeaderDragSurface())

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
        }
        // Own the compact title row instead of creating a Settings toolbar,
        // whose preference-style chrome adds a second, oversized header.
        .ignoresSafeArea(.container, edges: .top)
        .frame(minWidth: 1120, minHeight: 680)
        .background(SettingsWindowTitleVisibility().frame(width: 0, height: 0))
        .background(SettingsWindowCloseBarrier(coordinator: coordinator).frame(width: 0, height: 0))
        .task {
            AppDelegate.flushPendingSettingsChanges = { [weak coordinator] in
                guard let coordinator else { return true }
                return await coordinator.teardown()
            }
            guard !coordinator.isLoaded else { return }
            await Self.loadWorkspace(coordinator)
        }
    }

    private enum SidebarSelection: Hashable {
        case section(SettingsSection)
        case profile(HUDProfileReference)
    }

    private var sidebarSelection: Binding<SidebarSelection?> {
        Binding(
            get: {
                guard let selection else { return nil }
                return selection == .menuItems
                    ? .profile(coordinator.selectedHUDProfile) : .section(selection)
            },
            set: { destination in
                switch destination {
                case .section(let section):
                    selection = section
                    if section == .menuItems { profilesExpanded = true }
                case .profile(let profile):
                    guard coordinator.selectHUDProfile(profile) else { return }
                    selection = .menuItems
                case nil:
                    break
                }
            }
        )
    }

    @MainActor
    static func loadWorkspace(_ coordinator: SettingsWorkspaceCoordinator) async {
        await coordinator.load()
        if coordinator.isLoaded, coordinator.dirtyFields.isEmpty {
            // A file may have been repaired since startup failed. This bridge only
            // recovers a waiting/failed launch; it cannot replace a newer saved edit.
            AppDelegate.recoverLoadedSettingsConfiguration?(coordinator.configuration)
        }
    }
}

/// Full-size content replaces the native title-bar hit region. Hand only header
/// mouse-downs to AppKit so controls and lists retain their normal interactions.
private struct SettingsHeaderDragSurface: NSViewRepresentable {
    func makeNSView(context: Context) -> DragView { DragView() }
    func updateNSView(_ view: DragView, context: Context) {}

    final class DragView: NSView {
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func mouseDown(with event: NSEvent) {
            window?.performDrag(with: event)
        }
    }
}

/// Keep the native window title for accessibility and window menus, but draw
/// only the fixed-height content header rather than a duplicate native title.
private struct SettingsWindowTitleVisibility: NSViewRepresentable {
    func makeNSView(context: Context) -> TitleView { TitleView() }

    func updateNSView(_ view: TitleView, context: Context) {
        view.configureWindow()
    }

    final class TitleView: NSView {
        func configureWindow() {
            guard let window else { return }
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.styleMask.insert(.fullSizeContentView)
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            configureWindow()
        }
    }
}

#Preview {
    @Previewable @State var selection: SettingsSection? = .general
    SettingsView(selection: $selection)
}
