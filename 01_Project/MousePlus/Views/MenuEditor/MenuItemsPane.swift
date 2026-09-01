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
    @Binding var requestedItemID: UUID?
    @EnvironmentObject private var contextProvider: SettingsActionContextProvider
    @State private var testActionController: TestActionController
    @State private var showRestoreConfirm = false

    init(coordinator: SettingsWorkspaceCoordinator, requestedItemID: Binding<UUID?> = .constant(nil)) {
        self.coordinator = coordinator
        _requestedItemID = requestedItemID
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
                recoveryAndStatus
            }
        )
        // Only the selected-item form inside MenuEditorWorkspace scrolls. The
        // band selector, preview, spoke count, and actions remain pinned.
        .frame(minWidth: 860, minHeight: 600)
        .onChange(of: coordinator.menuEditorModel.inner) { _, _ in
            dismissTestResultForEditedSelection()
            coordinator.menuItemsDidChange()
        }
        .onChange(of: coordinator.menuEditorModel.middle) { _, _ in
            dismissTestResultForEditedSelection()
            coordinator.menuItemsDidChange()
        }
        .confirmationDialog(
            "Restore Menu Items from the pre-reset backup? Only inner and middle ring items will change.",
            isPresented: $showRestoreConfirm,
            titleVisibility: .visible
        ) {
            Button("Restore Menu Items") {
                Task { _ = await coordinator.restoreMenuItemsFromBackup() }
            }
            Button("Cancel", role: .cancel) {}
        }
        .onAppear { selectRequestedItemIfAvailable() }
        .onChange(of: requestedItemID) { _, _ in selectRequestedItemIfAvailable() }
        .onChange(of: coordinator.isLoaded) { _, _ in selectRequestedItemIfAvailable() }
    }

    private func selectRequestedItemIfAvailable() {
        guard coordinator.isLoaded, let requestedItemID else { return }
        let model = coordinator.menuEditorModel
        if model.inner.contains(where: { $0.id == requestedItemID }) {
            model.activeBand = .inner
            model.selection = SlotSelection(band: .inner, itemID: requestedItemID, subItemID: nil)
        } else if model.middle.contains(where: { $0.id == requestedItemID }) {
            model.activeBand = .middle
            model.selection = SlotSelection(band: .middle, itemID: requestedItemID, subItemID: nil)
        } else if let parent = model.middle.first(where: {
            $0.subItems?.contains(where: { $0.id == requestedItemID }) == true
        }) {
            model.activeBand = .middle
            model.selection = SlotSelection(band: .middle, itemID: parent.id, subItemID: requestedItemID)
        } else {
            return
        }
        self.requestedItemID = nil
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

    private var recoveryAndStatus: some View {
        HStack(spacing: 8) {
            if coordinator.workspaceState.reset == .undoAvailable {
                AppKitButton(
                    title: "Undo Reset",
                    accessibilityIdentifier: "menuItems.undoReset"
                ) {
                    Task { _ = await coordinator.undoMenuItemsReset() }
                }
            }
            if coordinator.workspaceState.durableBackupAvailable {
                AppKitButton(
                    title: "Restore Backup…",
                    accessibilityIdentifier: "menuItems.restoreBackup"
                ) {
                    showRestoreConfirm = true
                }
            }
            resetStatus
            WorkspaceStatusView(status: coordinator.status) {
                Task {
                    if case .loadFailed = coordinator.status {
                        await coordinator.load()
                    } else {
                        _ = await coordinator.retry()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var resetStatus: some View {
        switch coordinator.workspaceState.reset {
        case .resetting:
            Text("Resetting Menu Items…")
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("menuItems.reset.status")
        case .failed(let message):
            Text("Reset Failed: \(message)")
                .font(.caption)
                .foregroundStyle(.red)
                .lineLimit(2)
                .help(message)
                .accessibilityLabel("Reset Failed: \(message)")
                .accessibilityIdentifier("menuItems.reset.status")
        case .idle, .undoAvailable:
            EmptyView()
        }
    }
}
