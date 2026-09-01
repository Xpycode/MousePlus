//
//  MenuItemsPane.swift
//  MousePlus
//
//  Embedded Menu Items workspace hosted by the unified Settings shell.
//

import SwiftUI

@MainActor
struct MenuItemsPane: View {
    @Bindable var coordinator: SettingsWorkspaceCoordinator
    @EnvironmentObject private var contextProvider: SettingsActionContextProvider
    @State private var testActionController: TestActionController

    init(coordinator: SettingsWorkspaceCoordinator) {
        self.coordinator = coordinator
        _testActionController = State(initialValue: TestActionController(coordinator: coordinator))
    }

    var body: some View {
        MenuEditorWorkspace(
            model: coordinator.menuEditorModel,
            onReset: resetMenuItems,
            trailingToolbar: {
                if let selectedItem {
                    TestActionControl(
                        item: selectedItem,
                        contextAvailability: contextProvider.availability,
                        controller: testActionController
                    )
                }
                saveStatus
            }
        )
        // Only the selected-item form inside MenuEditorWorkspace scrolls. The
        // band selector, preview, spoke count, and actions remain pinned.
        .frame(minWidth: 790, minHeight: 600)
        .onChange(of: coordinator.menuEditorModel.inner) { _, _ in
            dismissTestResultForEditedSelection()
            coordinator.menuItemsDidChange()
        }
        .onChange(of: coordinator.menuEditorModel.middle) { _, _ in
            dismissTestResultForEditedSelection()
            coordinator.menuItemsDidChange()
        }
    }

    private var selectedItem: RingMenuItem? {
        guard let selection = coordinator.menuEditorModel.selection,
              let itemID = selection.itemID else { return nil }
        let items = selection.band == .inner
            ? coordinator.menuEditorModel.inner
            : coordinator.menuEditorModel.middle
        guard let parent = items.first(where: { $0.id == itemID }) else { return nil }
        guard let subItemID = selection.subItemID else { return parent }
        return parent.subItems?.first(where: { $0.id == subItemID })
    }

    private func dismissTestResultForEditedSelection() {
        guard let itemID = selectedItem?.id else { return }
        Task { @MainActor in await testActionController.itemDidEdit(itemID) }
    }

    private func resetMenuItems() {
        Task { @MainActor in
            _ = await coordinator.resetMenuItems()
        }
    }

    @ViewBuilder
    private var saveStatus: some View {
        switch coordinator.status {
        case .idle:
            EmptyView()
        case .loading:
            Text("Loading…")
                .foregroundStyle(.secondary)
        case .saving:
            Text("Saving…")
                .foregroundStyle(.secondary)
        case .saved:
            Text("Saved")
                .foregroundStyle(.secondary)
        case .saveFailed:
            Text("Save failed")
                .foregroundStyle(.red)
        case .loadFailed:
            Text("Load failed")
                .foregroundStyle(.red)
        }
    }
}
