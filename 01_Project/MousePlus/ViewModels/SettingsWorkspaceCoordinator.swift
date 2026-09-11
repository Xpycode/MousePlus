import Foundation
import Observation

protocol WorkspaceDebounceClock: Sendable {
    func sleep() async throws
}

struct ContinuousWorkspaceDebounceClock: WorkspaceDebounceClock {
    let duration: Duration

    func sleep() async throws {
        try await Task.sleep(for: duration)
    }
}

@MainActor
@Observable
final class SettingsWorkspaceCoordinator {
    private enum MenuItemsMergeError: LocalizedError {
        case appProfilesChangedExternally

        var errorDescription: String? {
            "App HUD profiles changed on disk while you were editing. "
                + "Reload Settings before saving these changes."
        }
    }

    enum AppHUDCreationResult: Equatable {
        case created
        case selectedExisting
        case rejected
    }

    enum Status: Equatable {
        case idle
        case loading
        case saving
        case saved
        case saveFailed(String)
        case loadFailed(String)
    }

    enum Field: Hashable, Sendable {
        case menuItems
        case triggers
        case appearance
        case behavior
    }

    private let persistence: any ConfigurationPersisting
    private let debounceClock: any WorkspaceDebounceClock
    private let liveApply: @MainActor (Configuration) -> Void
    private var debounceTask: Task<Void, Never>?
    private var saveTask: Task<Bool, Never>?
    private var saveTaskID: UUID?
    private var generations: [Field: UInt] = [:]
    private var menuItemsBaseline = Configuration()
    private var sessionUndoMenuItems: (configuration: Configuration, selection: HUDProfileReference)?
    private var pendingAppHUDProfileRecovery: Configuration?

    private(set) var configuration = Configuration()
    private(set) var status: Status = .idle
    private(set) var dirtyFields: Set<Field> = []
    private(set) var isLoaded = false
    private(set) var workspaceState = SettingsWorkspaceState()
    private(set) var selectedHUDProfile: HUDProfileReference = .global
    let menuEditorModel = MenuEditorModel(
        inner: RingMenuItem.sampleInnerItems,
        middle: RingMenuItem.sampleItems
    )

    init(
        persistence: any ConfigurationPersisting = ConfigurationService(),
        debounceClock: any WorkspaceDebounceClock = ContinuousWorkspaceDebounceClock(
            duration: .milliseconds(300)
        ),
        liveApply: @escaping @MainActor (Configuration) -> Void = { _ in }
    ) {
        self.persistence = persistence
        self.debounceClock = debounceClock
        self.liveApply = liveApply
    }

    /// Global is always first; app entries have deterministic bundle-ID order.
    var editableHUDProfiles: [HUDProfileReference] {
        [.global] + configuration.validAppHUDProfiles.keys.sorted().map {
            .app(bundleIdentifier: $0)
        }
    }

    var selectedAppHUDBundleIdentifier: String? {
        guard case .app(let bundleIdentifier) = selectedHUDProfile else { return nil }
        return bundleIdentifier
    }

    func load() async {
        debounceTask?.cancel()
        status = .loading
        do {
            configuration = try await persistence.loadResult().configuration
            menuItemsBaseline = configuration
            normalizeProfileSelection()
            loadSelectedProfileIntoEditor()
            dirtyFields.removeAll()
            generations.removeAll()
            sessionUndoMenuItems = nil
            pendingAppHUDProfileRecovery = nil
            isLoaded = true
            status = .saved
            workspaceState.reset = .idle
            workspaceState.durableBackupAvailable = await persistence.hasBackup()
        } catch {
            isLoaded = false
            status = .loadFailed(error.localizedDescription)
            workspaceState.durableBackupAvailable = false
        }
    }

    /// Applies an edit owned by one or more panes and schedules one serialized save.
    func edit(_ fields: Set<Field>, _ mutation: (inout Configuration) -> Void) {
        guard isLoaded, !fields.isEmpty else { return }
        if fields.contains(.menuItems) {
            synchronizeEditorIfNeeded()
        }
        mutation(&configuration)
        if fields.contains(.menuItems) {
            normalizeProfileSelection()
            loadSelectedProfileIntoEditor()
        }
        markDirty(fields)
        scheduleSave()
    }

    /// Synchronizes mutations made directly through the workspace-owned editor model.
    func menuItemsDidChange() {
        guard isLoaded else { return }
        // SwiftUI observation also reports coordinator-driven model loads (initial
        // load, reset, restore). Treat an identical model/config pair as a no-op
        // so merely revealing the pane cannot manufacture a dirty save.
        guard editorDiffersFromSelectedProfile else { return }
        guard mergeEditorIntoSelectedProfile() else { return }
        markDirty([.menuItems])
        scheduleSave()
    }

    /// Changes only in-memory editor context. Any pending model mutation is
    /// captured first, but selecting an already-synchronized profile never saves.
    @discardableResult
    func selectHUDProfile(_ profile: HUDProfileReference) -> Bool {
        guard isLoaded else { return false }
        synchronizeEditorIfNeeded()
        guard profileExists(profile) else {
            if !profileExists(selectedHUDProfile) {
                selectedHUDProfile = .global
                loadSelectedProfileIntoEditor()
            }
            return false
        }
        selectedHUDProfile = profile
        loadSelectedProfileIntoEditor()
        workspaceState.reset = .idle
        sessionUndoMenuItems = nil
        return true
    }

    /// Creates one independent app layout from the current Global layout.
    @discardableResult
    func createAppHUD(forBundleIdentifier bundleIdentifier: String) -> AppHUDCreationResult {
        guard isLoaded else { return .rejected }
        synchronizeEditorIfNeeded()
        if configuration.appHUDProfile(forBundleIdentifier: bundleIdentifier) != nil {
            _ = selectHUDProfile(.app(bundleIdentifier: bundleIdentifier))
            return .selectedExisting
        }
        guard !configuration.hasUnavailableAppHUDProfile(
            forBundleIdentifier: bundleIdentifier
        ) else { return .rejected }
        let profile = configuration.makeAppHUDProfileFromGlobal()
        guard configuration.setAppHUDProfile(profile, forBundleIdentifier: bundleIdentifier) else {
            return .rejected
        }
        markDirty([.menuItems])
        scheduleSave()
        selectedHUDProfile = .app(bundleIdentifier: bundleIdentifier)
        loadSelectedProfileIntoEditor()
        workspaceState.reset = .idle
        sessionUndoMenuItems = nil
        return .created
    }

    /// Global cannot be deleted. Deleting any app profile keeps another valid
    /// selection when possible and otherwise returns the editor to Global.
    @discardableResult
    func deleteAppHUD(forBundleIdentifier bundleIdentifier: String) -> Bool {
        guard isLoaded else { return false }
        synchronizeEditorIfNeeded()
        guard configuration.removeAppHUDProfile(forBundleIdentifier: bundleIdentifier) else {
            normalizeProfileSelection()
            loadSelectedProfileIntoEditor()
            return false
        }
        markDirty([.menuItems])
        scheduleSave()
        if selectedHUDProfile == .app(bundleIdentifier: bundleIdentifier) {
            selectedHUDProfile = .global
        }
        loadSelectedProfileIntoEditor()
        workspaceState.reset = .idle
        sessionUndoMenuItems = nil
        return true
    }

    @discardableResult
    func flush() async -> Bool {
        debounceTask?.cancel()
        debounceTask = nil
        guard !dirtyFields.isEmpty else { return true }
        return await serializedSave()
    }

    @discardableResult
    func retry() async -> Bool {
        await flush()
    }

    /// Close/teardown barrier used by the owning Settings window.
    @discardableResult
    func teardown() async -> Bool {
        await flush()
    }

    /// Creates a durable recovery point before replacing only Menu Items.
    @discardableResult
    func resetMenuItems() async -> Bool {
        guard isLoaded else { return false }
        workspaceState.reset = .resetting

        synchronizeEditorIfNeeded()
        guard await flush() else {
            workspaceState.reset = .failed(statusMessage)
            return false
        }

        let previous = (configuration: configuration, selection: selectedHUDProfile)
        do {
            try await persistence.createBackup()
            workspaceState.durableBackupAvailable = true
        } catch {
            workspaceState.reset = .failed(error.localizedDescription)
            return false
        }

        switch selectedHUDProfile {
        case .global:
            configuration.inner = RingMenuItem.sampleInnerItems
            configuration.middle = RingMenuItem.sampleItems
            configuration.hudCustomization = .default
        case .app(let bundleIdentifier):
            guard var profile = configuration.appHUDProfile(forBundleIdentifier: bundleIdentifier) else {
                selectedHUDProfile = .global
                loadSelectedProfileIntoEditor()
                workspaceState.reset = .failed("The selected App HUD is no longer available.")
                return false
            }
            profile.inner = configuration.inner
            profile.middle = configuration.middle
            guard configuration.setAppHUDProfile(profile, forBundleIdentifier: bundleIdentifier) else {
                workspaceState.reset = .failed("The selected App HUD could not be reset.")
                return false
            }
        }
        loadSelectedProfileIntoEditor()
        markDirty([.menuItems])
        scheduleSave()
        guard await flush() else {
            workspaceState.reset = .failed(statusMessage)
            return false
        }

        sessionUndoMenuItems = previous
        workspaceState.reset = .undoAvailable
        return true
    }

    @discardableResult
    func undoMenuItemsReset() async -> Bool {
        guard let previous = sessionUndoMenuItems, isLoaded else { return false }
        replaceMenuItemsState(in: &configuration, with: previous.configuration)
        selectedHUDProfile = profileExists(previous.selection) ? previous.selection : .global
        loadSelectedProfileIntoEditor()
        markDirty([.menuItems])
        scheduleSave()
        guard await flush() else {
            workspaceState.reset = .failed(statusMessage)
            return false
        }
        sessionUndoMenuItems = nil
        workspaceState.reset = .idle
        return true
    }

    /// Restores backed-up Menu Items through the same fresh-base safe-save path.
    @discardableResult
    func restoreMenuItemsFromBackup() async -> Bool {
        guard isLoaded, workspaceState.durableBackupAvailable else { return false }
        let backup: Configuration
        do {
            backup = try await persistence.loadBackup()
        } catch {
            workspaceState.reset = .failed(error.localizedDescription)
            return false
        }

        replaceMenuItemsState(in: &configuration, with: backup)
        pendingAppHUDProfileRecovery = backup
        normalizeProfileSelection()
        loadSelectedProfileIntoEditor()
        markDirty([.menuItems])
        scheduleSave()
        guard await flush() else {
            workspaceState.reset = .failed(statusMessage)
            return false
        }
        sessionUndoMenuItems = nil
        workspaceState.reset = .idle
        return true
    }

    /// Returns true only when the owning window may dismiss.
    func requestClose() async -> Bool {
        guard !dirtyFields.isEmpty else { return true }
        workspaceState.closeBarrier = .flushing
        if await flush() {
            workspaceState.closeBarrier = .idle
            return true
        }
        workspaceState.closeBarrier = .blocked(statusMessage)
        return false
    }

    /// Resolves a failed close barrier. Cancel never dismisses or loses edits.
    func resolveClose(_ choice: SettingsWorkspaceState.CloseChoice) async -> Bool {
        switch choice {
        case .retry:
            workspaceState.closeBarrier = .flushing
            if await retry() {
                workspaceState.closeBarrier = .idle
                return true
            }
            workspaceState.closeBarrier = .blocked(statusMessage)
            return false
        case .discardChanges:
            await load()
            if isLoaded {
                workspaceState.closeBarrier = .idle
                return true
            }
            workspaceState.closeBarrier = .blocked(statusMessage)
            return false
        case .cancelClose:
            workspaceState.closeBarrier = .idle
            return false
        }
    }

    private var statusMessage: String {
        switch status {
        case .saveFailed(let message), .loadFailed(let message): message
        default: "The latest changes could not be saved."
        }
    }

    private func markDirty(_ fields: Set<Field>) {
        for field in fields {
            generations[field, default: 0] &+= 1
        }
        dirtyFields.formUnion(fields)
    }

    private func scheduleSave() {
        debounceTask?.cancel()
        status = .saving
        debounceTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await debounceClock.sleep()
                try Task.checkCancellation()
            } catch {
                return
            }
            debounceTask = nil
            _ = await serializedSave()
        }
    }

    private func serializedSave() async -> Bool {
        if let saveTask {
            let taskID = saveTaskID
            let result = await saveTask.value
            if saveTaskID == taskID {
                self.saveTask = nil
                saveTaskID = nil
            }
            guard result else { return false }
            return dirtyFields.isEmpty ? true : await serializedSave()
        }
        guard !dirtyFields.isEmpty else { return true }

        let task = Task { @MainActor [weak self] in
            guard let self else { return false }
            return await performSave()
        }
        let taskID = UUID()
        saveTask = task
        saveTaskID = taskID
        let result = await task.value
        if saveTaskID == taskID {
            saveTask = nil
            saveTaskID = nil
        }
        return result
    }

    private func performSave() async -> Bool {
        guard isLoaded, !dirtyFields.isEmpty else { return true }
        status = .saving

        let fields = dirtyFields
        let savedGenerations = generations
        let edited = configuration

        do {
            var merged = try await persistence.loadResult().configuration
            try merge(fields: fields, from: edited, into: &merged)
            try await persistence.save(merged)

            for field in fields where generations[field] == savedGenerations[field] {
                dirtyFields.remove(field)
            }
            if fields.contains(.menuItems),
               generations[.menuItems] == savedGenerations[.menuItems] {
                pendingAppHUDProfileRecovery = nil
            }
            menuItemsBaseline = merged
            configuration = try mergingUnsavedFields(from: configuration, into: merged)
            normalizeProfileSelection()
            loadSelectedProfileIntoEditor(preservingItemSelection: true)
            // The runtime receives the exact complete snapshot that was made durable,
            // never a field fragment or the still-dirty editor configuration.
            liveApply(merged)

            if dirtyFields.isEmpty {
                status = .saved
            } else {
                scheduleSave()
            }
            return true
        } catch {
            status = error is DecodingError
                ? .loadFailed(error.localizedDescription)
                : .saveFailed(error.localizedDescription)
            return false
        }
    }

    private func mergingUnsavedFields(
        from edited: Configuration,
        into persisted: Configuration
    ) throws -> Configuration {
        var result = persisted
        try merge(fields: dirtyFields, from: edited, into: &result)
        return result
    }

    private func merge(
        fields: Set<Field>,
        from edited: Configuration,
        into base: inout Configuration
    ) throws {
        if fields.contains(.menuItems) {
            base.inner = edited.inner
            base.middle = edited.middle
            base.hudCustomization = edited.hudCustomization
            let profileBaseline: Configuration
            if let recovery = pendingAppHUDProfileRecovery {
                base.replaceAppHUDProfileStorage(with: recovery)
                profileBaseline = recovery
            } else {
                profileBaseline = menuItemsBaseline
            }
            try reconcileAppHUDProfileChanges(
                from: profileBaseline,
                to: edited,
                into: &base
            )
        }
        if fields.contains(.triggers) { base.triggers = edited.triggers }
        if fields.contains(.appearance) { base.appearance = edited.appearance }
        if fields.contains(.behavior) { base.behavior = edited.behavior }
    }

    private var editorDiffersFromSelectedProfile: Bool {
        let layout = selectedActionLayout
        return layout.inner != menuEditorModel.inner ||
            layout.middle != menuEditorModel.middle ||
            configuration.hudCustomization != menuEditorModel.hudCustomization
    }

    private var selectedActionLayout: HUDActionLayout {
        switch selectedHUDProfile {
        case .global:
            return configuration.globalHUDActionLayout
        case .app(let bundleIdentifier):
            return configuration.appHUDProfile(forBundleIdentifier: bundleIdentifier)?.layout
                ?? configuration.globalHUDActionLayout
        }
    }

    @discardableResult
    private func mergeEditorIntoSelectedProfile() -> Bool {
        configuration.hudCustomization = menuEditorModel.hudCustomization
        switch selectedHUDProfile {
        case .global:
            configuration.inner = menuEditorModel.inner
            configuration.middle = menuEditorModel.middle
            return true
        case .app(let bundleIdentifier):
            guard var profile = configuration.appHUDProfile(forBundleIdentifier: bundleIdentifier) else {
                selectedHUDProfile = .global
                loadSelectedProfileIntoEditor()
                return false
            }
            profile.inner = menuEditorModel.inner
            profile.middle = menuEditorModel.middle
            return configuration.setAppHUDProfile(profile, forBundleIdentifier: bundleIdentifier)
        }
    }

    private func synchronizeEditorIfNeeded() {
        guard editorDiffersFromSelectedProfile, mergeEditorIntoSelectedProfile() else { return }
        markDirty([.menuItems])
        scheduleSave()
    }

    private func loadSelectedProfileIntoEditor(preservingItemSelection: Bool = false) {
        menuEditorModel.load(
            actionLayout: selectedActionLayout,
            hudCustomization: configuration.hudCustomization,
            preservingSelection: preservingItemSelection
        )
    }

    private func profileExists(_ profile: HUDProfileReference) -> Bool {
        switch profile {
        case .global: true
        case .app(let bundleIdentifier):
            configuration.appHUDProfile(forBundleIdentifier: bundleIdentifier) != nil
        }
    }

    private func normalizeProfileSelection() {
        if !profileExists(selectedHUDProfile) {
            selectedHUDProfile = .global
        }
    }

    private func replaceMenuItemsState(in target: inout Configuration, with source: Configuration) {
        target.inner = source.inner
        target.middle = source.middle
        target.hudCustomization = source.hudCustomization
        target.replaceAppHUDProfileStorage(with: source)
    }

    /// Applies only this workspace's app-profile differences to a fresh disk
    /// base, so external additions or edits to untouched profiles survive.
    private func reconcileAppHUDProfileChanges(
        from baseline: Configuration,
        to edited: Configuration,
        into target: inout Configuration
    ) throws {
        let original = baseline.validAppHUDProfiles
        let desired = edited.validAppHUDProfiles
        let changedBundleIdentifiers = Set(original.keys).union(desired.keys).filter {
            original[$0] != desired[$0]
        }
        guard !changedBundleIdentifiers.isEmpty else { return }
        guard !target.hasUnavailableAppHUDProfilesCollection else {
            throw MenuItemsMergeError.appProfilesChangedExternally
        }

        for bundleIdentifier in changedBundleIdentifiers {
            guard original[bundleIdentifier] != desired[bundleIdentifier] else { continue }
            guard !target.hasUnavailableAppHUDProfile(
                forBundleIdentifier: bundleIdentifier
            ) else {
                throw MenuItemsMergeError.appProfilesChangedExternally
            }

            switch (original[bundleIdentifier], desired[bundleIdentifier]) {
            case (nil, .some(let desiredProfile)):
                if let freshProfile = target.appHUDProfile(forBundleIdentifier: bundleIdentifier) {
                    guard freshProfile == desiredProfile else {
                        throw MenuItemsMergeError.appProfilesChangedExternally
                    }
                } else if !target.setAppHUDProfile(
                    desiredProfile,
                    forBundleIdentifier: bundleIdentifier
                ) {
                    throw MenuItemsMergeError.appProfilesChangedExternally
                }

            case (.some(let originalProfile), nil):
                if let freshProfile = target.appHUDProfile(forBundleIdentifier: bundleIdentifier) {
                    guard freshProfile == originalProfile,
                          target.removeAppHUDProfile(
                              forBundleIdentifier: bundleIdentifier
                          ) else {
                        throw MenuItemsMergeError.appProfilesChangedExternally
                    }
                }

            case (.some, .some(let desiredProfile)):
                guard var freshProfile = target.appHUDProfile(
                    forBundleIdentifier: bundleIdentifier
                ) else {
                    throw MenuItemsMergeError.appProfilesChangedExternally
                }
                // Apply only the action arrays to the fresh typed profile. Its
                // forward-compatible profile/layout/item JSON remains the merge base.
                freshProfile.inner = desiredProfile.inner
                freshProfile.middle = desiredProfile.middle
                guard target.setAppHUDProfile(
                    freshProfile,
                    forBundleIdentifier: bundleIdentifier
                ) else {
                    throw MenuItemsMergeError.appProfilesChangedExternally
                }

            case (nil, nil):
                break
            }
        }
    }
}
