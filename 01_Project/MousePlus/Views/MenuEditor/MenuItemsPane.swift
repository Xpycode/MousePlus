//
//  MenuItemsPane.swift
//  MousePlus
//
//  Embedded Menu Items workspace hosted by the unified Settings shell.
//

import AppKit
import SwiftUI

@MainActor
struct MenuItemsPane: View {
    @Bindable var coordinator: SettingsWorkspaceCoordinator
    @Binding var requestedItemID: UUID?
    @EnvironmentObject private var contextProvider: SettingsActionContextProvider
    @State private var testActionController: TestActionController
    @State private var showingAppHUDPicker = false
    @State private var profileMessage: String?
    @State private var showingHiddenItems = false

    init(coordinator: SettingsWorkspaceCoordinator, requestedItemID: Binding<UUID?> = .constant(nil)) {
        self.coordinator = coordinator
        _requestedItemID = requestedItemID
        _testActionController = State(initialValue: TestActionController(coordinator: coordinator))
    }

    var body: some View {
        VStack(spacing: 8) {
            profileBar

            MenuEditorWorkspace(
                model: coordinator.menuEditorModel,
                appearance: coordinator.configuration.appearance,
                appName: editedAppName,
                onReset: resetMenuItems,
                actionAccessory: {
                    if let selectedItem {
                        TestActionControl(
                            item: selectedItem,
                            contextAvailability: contextProvider.availability,
                            controller: testActionController,
                            sourceLabel: selectedItemSourceLabel
                        )
                    }
                },
                menuAccessory: {
                    recoveryAndStatus
                }
            )
            .frame(minHeight: 520)
            // Rebuild the editor when the configuration finishes loading. The ring
            // preview keeps a private copy of the items that starts as the built-in
            // samples; if Settings opens directly on this pane, the load can land
            // before that copy starts tracking the editor, leaving the samples on
            // screen next to a "Saved" status. A fresh mount always starts from
            // the loaded items.
            .id(coordinator.isLoaded)
        }
        // The item form and customization column scroll independently. The band
        // selector, preview, spoke count, and actions remain pinned.
        .frame(minWidth: 880, minHeight: 600)
        .onChange(of: coordinator.menuEditorModel.inner) { _, _ in
            dismissTestResultForEditedSelection()
            coordinator.menuItemsDidChange()
        }
        .onChange(of: coordinator.menuEditorModel.middle) { _, _ in
            dismissTestResultForEditedSelection()
            coordinator.menuItemsDidChange()
        }
        .onChange(of: coordinator.menuEditorModel.hudCustomization) { _, _ in
            coordinator.menuItemsDidChange()
        }
        .sheet(isPresented: $showingAppHUDPicker) {
            AppPickerSheet(
                excludedBundleIdentifiers: Set([Bundle.main.bundleIdentifier].compactMap { $0 }),
                onPick: addAppHUD,
                onCancel: { showingAppHUDPicker = false }
            )
        }
        .onAppear { selectRequestedItemIfAvailable() }
        .onChange(of: requestedItemID) { _, _ in selectRequestedItemIfAvailable() }
        .onChange(of: coordinator.isLoaded) { _, _ in selectRequestedItemIfAvailable() }
    }

    private var profileBar: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                Text("HUD Profile")

                AppKitPopup(
                    options: coordinator.editableHUDProfiles.map(profileSelectorTitle),
                    selection: profileSelection,
                    isEnabled: coordinator.isLoaded,
                    accessibilityLabel: "HUD profile",
                    accessibilityIdentifier: "menuItems.profile.selector"
                )
                .frame(minWidth: 180, maxWidth: 260)

                AppKitButton(
                    title: "Add App HUD…",
                    isEnabled: coordinator.isLoaded,
                    accessibilityLabel: "Add App HUD",
                    accessibilityIdentifier: "menuItems.profile.add"
                ) {
                    profileMessage = nil
                    showingAppHUDPicker = true
                }

                AppKitButton(
                    title: "Delete…",
                    isEnabled: coordinator.selectedAppHUDBundleIdentifier != nil,
                    accessibilityLabel: deleteAccessibilityLabel,
                    accessibilityIdentifier: "menuItems.profile.delete"
                ) {
                    confirmDeleteSelectedAppHUD()
                }

                if coordinator.menuEditorModel.isEditingAppHUD {
                    hiddenItemsButton
                }

                Spacer(minLength: 8)

                MenuItemsProfileLabel(
                    text: "Editing \(selectedProfileTitle) HUD",
                    style: .headline,
                    accessibilityIdentifier: "menuItems.profile.editing"
                )
            }

            MenuItemsProfileLabel(
                text: "App HUDs follow Global until you edit an item.",
                style: .secondary,
                accessibilityIdentifier: "menuItems.profile.copyExplanation"
            )

            MenuItemsProfileLabel(
                text: profileSemantics,
                style: .secondaryWrapping,
                accessibilityIdentifier: "menuItems.profile.semantics"
            )

            ForEach(coordinator.overflowWarnings, id: \.self) { warning in
                overflowWarningRow(warning)
            }

            if let profileMessage {
                Text(profileMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("menuItems.profile.status")
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private var profileSelection: Binding<Int> {
        Binding(
            get: {
                coordinator.editableHUDProfiles.firstIndex(of: coordinator.selectedHUDProfile) ?? 0
            },
            set: { index in
                let profiles = coordinator.editableHUDProfiles
                guard profiles.indices.contains(index) else { return }
                profileMessage = nil
                showingHiddenItems = false
                _ = coordinator.selectHUDProfile(profiles[index])
            }
        )
    }

    private var selectedProfileTitle: String {
        profileSelectorTitle(coordinator.selectedHUDProfile)
    }

    private func profileSelectorTitle(_ profile: HUDProfileReference) -> String {
        let title = profileTitle(profile)
        guard case .app(let bundleIdentifier) = profile else { return title }
        let duplicateCount = coordinator.editableHUDProfiles.filter {
            $0 != profile && profileTitle($0) == title
        }.count
        return duplicateCount > 0 ? "\(title) — \(bundleIdentifier)" : title
    }

    private func profileTitle(_ profile: HUDProfileReference) -> String {
        switch profile {
        case .global:
            return "Global"
        case .app(let bundleIdentifier):
            guard let url = NSWorkspace.shared.urlForApplication(
                withBundleIdentifier: bundleIdentifier
            ) else {
                return "Missing App — \(bundleIdentifier)"
            }
            let displayed = FileManager.default.displayName(atPath: url.path)
            let name = displayed.hasSuffix(".app")
                ? String(displayed.dropLast(4))
                : displayed
            return name.isEmpty ? bundleIdentifier : name
        }
    }

    /// Opens the list of Global items hidden in the selected App HUD (AC10, AC11).
    private var hiddenItemsButton: some View {
        let count = coordinator.menuEditorModel.hiddenItems.count
        return AppKitButton(
            title: "Hidden Items (\(count))…",
            isEnabled: count > 0,
            accessibilityLabel: "Hidden Items in \(selectedProfileTitle) HUD, \(count)",
            accessibilityIdentifier: "menuItems.profile.hiddenItems"
        ) {
            showingHiddenItems = true
        }
        .fixedSize()
        .popover(isPresented: $showingHiddenItems, arrowEdge: .bottom) {
            hiddenItemsList
        }
    }

    private var hiddenItemsList: some View {
        let model = coordinator.menuEditorModel
        let rows = [EditorBand.inner, .middle].flatMap { band in
            model.hiddenItems(band: band).map { (band: band, item: $0) }
        }
        return VStack(alignment: .leading, spacing: 8) {
            MenuItemsProfileLabel(
                text: "Hidden in \(selectedProfileTitle) HUD",
                style: .headline,
                accessibilityIdentifier: "menuItems.profile.hiddenItems.title"
            )
            if rows.isEmpty {
                MenuItemsProfileLabel(
                    text: "No hidden items.",
                    style: .secondary,
                    accessibilityIdentifier: "menuItems.profile.hiddenItems.empty"
                )
            }
            ForEach(rows, id: \.item.id) { row in
                let name = row.item.label.isEmpty ? "(no label)" : row.item.label
                let ring = row.band == .inner ? "inner" : "middle"
                HStack(spacing: 8) {
                    MenuItemsProfileLabel(
                        text: "\(name) (\(ring) ring)",
                        style: .body,
                        accessibilityIdentifier: "menuItems.profile.hiddenItems.label.\(row.item.id.uuidString)"
                    )
                    Spacer(minLength: 12)
                    AppKitButton(
                        title: "Show",
                        accessibilityLabel: "Show \(name) in \(selectedProfileTitle) HUD",
                        accessibilityIdentifier: "menuItems.profile.hiddenItems.show.\(row.item.id.uuidString)"
                    ) {
                        model.show(hidden: row.item)
                        if model.hiddenItems.isEmpty { showingHiddenItems = false }
                    }
                    .fixedSize()
                }
            }
        }
        .padding(12)
        .frame(minWidth: 260, alignment: .leading)
    }

    private func overflowWarningRow(_ warning: SettingsWorkspaceCoordinator.AppHUDOverflowWarning) -> some View {
        let app = profileTitle(.app(bundleIdentifier: warning.bundleIdentifier))
        let ring = warning.band == .inner ? "inner" : warning.band == .middle ? "middle" : "outer"
        let noun = warning.count == 1 ? "item" : "items"
        let text = "Not enough space in \(app) HUD's \(ring) ring: \(warning.count) \(noun) not shown"
        return HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            MenuItemsProfileLabel(
                text: text,
                style: .secondaryWrapping,
                accessibilityIdentifier: "menuItems.profile.overflow.\(warning.bundleIdentifier).\(ring)"
            )
        }
    }

    /// The selected App HUD's name for preview labels; `nil` in Global.
    private var editedAppName: String? {
        coordinator.menuEditorModel.isEditingAppHUD ? profileTitle(coordinator.selectedHUDProfile) : nil
    }

    /// Where the selected item comes from, for Test Action (AC12b); `nil` in Global.
    /// A sub-item reports its top-level item's origin.
    private var selectedItemSourceLabel: String? {
        let model = coordinator.menuEditorModel
        guard model.isEditingAppHUD,
              let itemID = model.selection?.itemID,
              let origin = model.origin(of: itemID) else { return nil }
        let app = profileTitle(coordinator.selectedHUDProfile)
        switch origin {
        case .inherited: return "from Global"
        case .customized: return "customized for \(app)"
        case .appOnly: return "only in \(app)"
        }
    }

    private var profileSemantics: String {
        if coordinator.selectedAppHUDBundleIdentifier == nil {
            return "Reset restores Global items and shared HUD customization to defaults. "
                + "Restore Backup replaces Global items, every App HUD, and shared HUD customization."
        }
        return "Reset makes \(selectedProfileTitle) HUD follow Global again, removing its customized, hidden and app-only items and its own order; shared HUD customization is unchanged. "
            + "Restore Backup replaces Global items, every App HUD, and shared HUD customization."
    }

    private var deleteAccessibilityLabel: String {
        coordinator.selectedAppHUDBundleIdentifier == nil
            ? "Delete App HUD, unavailable for Global"
            : "Delete \(selectedProfileTitle) HUD"
    }

    private func addAppHUD(bundleIdentifier: String, name: String, suggestedSymbol _: String) {
        showingAppHUDPicker = false
        switch coordinator.createAppHUD(forBundleIdentifier: bundleIdentifier) {
        case .created:
            profileMessage = "Added \(name) HUD. It follows Global until you edit an item, and will apply after Saved."
        case .selectedExisting:
            profileMessage = "\(selectedProfileTitle) HUD already existed and was selected without being overwritten."
        case .replacedUnavailable:
            profileMessage = "Replaced the unreadable \(name) HUD with one that follows Global. It will apply after Saved."
        case .rejected:
            profileMessage = "Could not add an App HUD for \(bundleIdentifier). No changes were saved."
        }
    }

    private func confirmDeleteSelectedAppHUD() {
        guard let bundleIdentifier = coordinator.selectedAppHUDBundleIdentifier else { return }
        let title = selectedProfileTitle
        presentConfirmation(
            message: "Delete \(title) HUD?",
            information: "\(title) will use the Global HUD on its next invocation. Global and other App HUDs will not change.",
            confirmTitle: "Delete App HUD"
        ) {
            if coordinator.deleteAppHUD(forBundleIdentifier: bundleIdentifier) {
                profileMessage = "Removed \(title) HUD from this edit. It will use Global after Saved."
            }
        }
    }

    private func confirmRestoreBackup() {
        presentConfirmation(
            message: "Restore the Menu Items backup?",
            information: "This replaces Global items, every App HUD, and shared HUD customization with the pre-reset backup. Triggers, general appearance, and behavior will not change.",
            confirmTitle: "Restore Menu Items"
        ) {
            Task { _ = await coordinator.restoreMenuItemsFromBackup() }
        }
    }

    private func presentConfirmation(
        message: String,
        information: String,
        confirmTitle: String,
        confirmed: @escaping @MainActor () -> Void
    ) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = message
        alert.informativeText = information
        alert.addButton(withTitle: confirmTitle)
        alert.buttons.first?.hasDestructiveAction = true
        alert.addButton(withTitle: "Cancel")

        if let window = NSApp.keyWindow ?? NSApp.mainWindow {
            alert.beginSheetModal(for: window) { response in
                guard response == .alertFirstButtonReturn else { return }
                confirmed()
            }
        } else if alert.runModal() == .alertFirstButtonReturn {
            confirmed()
        }
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
                    confirmRestoreBackup()
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

private struct MenuItemsProfileLabel: NSViewRepresentable {
    enum Style {
        case headline
        case secondary
        case secondaryWrapping
        case body
    }

    let text: String
    let style: Style
    let accessibilityIdentifier: String

    func makeNSView(context: Context) -> NSTextField {
        style == .secondaryWrapping
            ? NSTextField(wrappingLabelWithString: text)
            : NSTextField(labelWithString: text)
    }

    func updateNSView(_ label: NSTextField, context: Context) {
        label.stringValue = text
        switch style {
        case .headline:
            label.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .semibold)
            label.textColor = .labelColor
        case .body:
            label.font = .systemFont(ofSize: NSFont.systemFontSize)
            label.textColor = .labelColor
        case .secondary, .secondaryWrapping:
            label.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
            label.textColor = .secondaryLabelColor
        }
        label.maximumNumberOfLines = wraps ? 0 : 1
        label.lineBreakMode = wraps ? .byWordWrapping : .byTruncatingTail
        label.cell?.wraps = wraps
        label.cell?.truncatesLastVisibleLine = !wraps
        // A truncated single-line label (for example a long app name) still
        // exposes its full text on hover and to VoiceOver.
        label.toolTip = wraps ? nil : text
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        label.setAccessibilityLabel(text)
        label.setAccessibilityIdentifier(accessibilityIdentifier)
    }

    /// An `NSTextField` reports a single-line intrinsic size, so SwiftUI would
    /// lay it out on one line and clip it. Measure against the offered width
    /// instead: wrapping labels grow taller, single-line labels truncate.
    func sizeThatFits(_ proposal: ProposedViewSize, nsView label: NSTextField, context: Context) -> CGSize? {
        guard let width = proposal.width, width.isFinite, width > 0, let cell = label.cell else {
            return nil
        }
        if wraps {
            let fitted = cell.cellSize(
                forBounds: NSRect(x: 0, y: 0, width: width, height: .greatestFiniteMagnitude)
            )
            return CGSize(width: width, height: ceil(fitted.height))
        }
        let natural = cell.cellSize
        return CGSize(width: min(ceil(natural.width), width), height: ceil(natural.height))
    }

    private var wraps: Bool { style == .secondaryWrapping }
}
