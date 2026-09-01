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

    var body: some View {
        MenuEditorWorkspace(
            model: coordinator.menuEditorModel,
            onReset: resetMenuItems,
            trailingToolbar: { saveStatus }
        )
        // Only the selected-item form inside MenuEditorWorkspace scrolls. The
        // band selector, preview, spoke count, and actions remain pinned.
        .frame(minWidth: 790, minHeight: 600)
        .onChange(of: coordinator.menuEditorModel.inner) { _, _ in
            coordinator.menuItemsDidChange()
        }
        .onChange(of: coordinator.menuEditorModel.middle) { _, _ in
            coordinator.menuItemsDidChange()
        }
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
