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
        case globalMenuChangedExternally

        var errorDescription: String? {
            switch self {
            case .appProfilesChangedExternally:
                "App HUD profiles changed on disk while you were editing. "
                    + "Reload Settings before saving these changes."
            case .globalMenuChangedExternally:
                "The Global menu changed on disk while you were editing. "
                    + "Reload Settings before saving these changes."
            }
        }
    }

    enum AppHUDCreationResult: Equatable {
        case created
        case selectedExisting
        case replacedUnavailable
        case rejected
    }

    /// One App HUD ring that resolves to more items than it can show (AC14).
    /// The view turns `bundleIdentifier` into the app's display name with the
    /// same lookup as the profile bar.
    struct AppHUDOverflowWarning: Equatable, Hashable {
        let bundleIdentifier: String
        let band: Band
        /// Items beyond the ring capacity, listed by the editor as not shown.
        let count: Int
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
    private var intentionallyReplacedUnavailableAppHUDProfiles: Set<String> = []

    private(set) var configuration = Configuration()
    private(set) var status: Status = .idle
    private(set) var dirtyFields: Set<Field> = []
    private(set) var isLoaded = false
    private(set) var workspaceState = SettingsWorkspaceState()
    private(set) var selectedHUDProfile: HUDProfileReference = .global
    /// App HUD rings that overflow in the last loaded or saved configuration,
    /// sorted by bundle identifier, inner before middle. Recomputed after every
    /// load and every successful Menu Items save, so a Global save that pushes
    /// an App HUD past 8 items publishes it and hiding or deleting there clears it.
    private(set) var overflowWarnings: [AppHUDOverflowWarning] = []
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
            overflowWarnings = Self.overflowWarnings(in: configuration)
            normalizeProfileSelection()
            loadSelectedProfileIntoEditor()
            dirtyFields.removeAll()
            generations.removeAll()
            sessionUndoMenuItems = nil
            pendingAppHUDProfileRecovery = nil
            intentionallyReplacedUnavailableAppHUDProfiles.removeAll()
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
        let previousGlobal = configuration.globalHUDActionLayout
        mutation(&configuration)
        if fields.contains(.menuItems) {
            configuration.repairAppHUDProfiles(afterGlobalChangeFrom: previousGlobal)
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

    /// Creates an App HUD that inherits every Global item in Global's order.
    @discardableResult
    func createAppHUD(forBundleIdentifier bundleIdentifier: String) -> AppHUDCreationResult {
        guard isLoaded else { return .rejected }
        synchronizeEditorIfNeeded()
        if configuration.appHUDProfile(forBundleIdentifier: bundleIdentifier) != nil {
            _ = selectHUDProfile(.app(bundleIdentifier: bundleIdentifier))
            return .selectedExisting
        }
        let replacesUnavailable = configuration.hasUnavailableAppHUDProfile(
            forBundleIdentifier: bundleIdentifier
        )
        let profile = configuration.makeAppHUDProfileFromGlobal()
        guard configuration.setAppHUDProfile(profile, forBundleIdentifier: bundleIdentifier) else {
            return .rejected
        }
        if replacesUnavailable {
            intentionallyReplacedUnavailableAppHUDProfiles.insert(bundleIdentifier)
        }
        markDirty([.menuItems])
        scheduleSave()
        selectedHUDProfile = .app(bundleIdentifier: bundleIdentifier)
        loadSelectedProfileIntoEditor()
        workspaceState.reset = .idle
        sessionUndoMenuItems = nil
        return replacesUnavailable ? .replacedUnavailable : .created
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
            let previousGlobal = configuration.globalHUDActionLayout
            configuration.inner = RingMenuItem.sampleInnerItems
            configuration.middle = RingMenuItem.sampleItems
            configuration.hudCustomization = .default
            configuration.repairAppHUDProfiles(afterGlobalChangeFrom: previousGlobal)
        case .app(let bundleIdentifier):
            guard configuration.appHUDProfile(forBundleIdentifier: bundleIdentifier) != nil else {
                selectedHUDProfile = .global
                loadSelectedProfileIntoEditor()
                workspaceState.reset = .failed("The selected App HUD is no longer available.")
                return false
            }
            // Everything inherited again; profile-level unknown fields are kept.
            guard configuration.setAppHUDInheritance(
                AppHUDRings(),
                forBundleIdentifier: bundleIdentifier
            ) else {
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
        pendingAppHUDProfileRecovery = previous.configuration
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
            if fields.contains(.menuItems) {
                overflowWarnings = Self.overflowWarnings(in: merged)
            }
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
            let freshGlobal = base.globalHUDActionLayout
            if pendingAppHUDProfileRecovery != nil {
                // Recovery owns the complete saved menu snapshot, including
                // forward-compatible raw fields attached to Global items.
                base.globalHUDActionLayout = edited.globalHUDActionLayout
            } else {
                // Ordinary edits retain raw fields from the fresh disk base.
                try reconcileGlobalMenuChanges(
                    from: menuItemsBaseline,
                    to: edited,
                    into: &base
                )
            }
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
            // After the per-profile reconcile, so its fresh-vs-baseline guards
            // compare unrepaired disk profiles. Repairs every App HUD on the
            // fresh base, including ones this workspace never loaded (AC7).
            // Without a Global deletion nothing changes (AC19). A recovery
            // snapshot's profiles belong to its own Global: load-time fallback.
            base.repairAppHUDProfiles(
                afterGlobalChangeFrom: pendingAppHUDProfileRecovery == nil
                    ? freshGlobal
                    : base.globalHUDActionLayout
            )
        }
        if fields.contains(.triggers) { base.triggers = edited.triggers }
        if fields.contains(.appearance) { base.appearance = edited.appearance }
        if fields.contains(.behavior) { base.behavior = edited.behavior }
    }

    /// True when the editor holds a change the selected profile does not.
    /// App HUDs compare storage, not visible arrays: the edit is turned back into
    /// inheritance metadata and only counts when it resolves differently from the
    /// stored profile. Merely showing a profile therefore never dirties it, even
    /// where `diff` would normalize storage (for example an anchor next to a
    /// hidden item).
    private var editorDiffersFromSelectedProfile: Bool {
        if configuration.hudCustomization != menuEditorModel.hudCustomization { return true }
        switch selectedHUDProfile {
        case .global:
            return configuration.inner != menuEditorModel.inner
                || configuration.middle != menuEditorModel.middle
        case .app(let bundleIdentifier):
            guard let profile = configuration.appHUDProfile(forBundleIdentifier: bundleIdentifier),
                  menuEditorModel.inheritanceEditState != nil else {
                // Missing profile or an editor not loaded for it: let the merge
                // path normalize the selection and reload.
                return true
            }
            return editedAppHUDProfile(from: profile) != nil
        }
    }

    /// The selected App HUD resolved against the current Global; `nil` for
    /// Global or a missing App HUD (the editor then shows Global).
    private var selectedResolvedAppLayout: ResolvedAppLayout? {
        guard let bundleIdentifier = selectedAppHUDBundleIdentifier else { return nil }
        return configuration.resolvedAppLayout(forBundleIdentifier: bundleIdentifier)
    }

    /// The editor's App HUD edits as a stored profile, or `nil` when they resolve
    /// exactly like `profile` (no change worth storing).
    private func editedAppHUDProfile(from profile: AppHUDProfile) -> AppHUDProfile? {
        guard let edit = menuEditorModel.inheritanceEditState else { return nil }
        let edited = AppHUDResolver.diff(
            edited: edit.edited,
            previous: profile,
            global: edit.global,
            origins: edit.origins,
            lockedBands: edit.lockedBands,
            customOrderBands: edit.customOrderBands,
            originsByBand: edit.originsByBand
        )
        guard edited != profile else { return nil }
        let before = AppHUDResolver.resolve(global: edit.global, profile: profile)
        let after = AppHUDResolver.resolve(global: edit.global, profile: edited)
        return before == after ? nil : edited
    }

    @discardableResult
    private func mergeEditorIntoSelectedProfile() -> Bool {
        configuration.hudCustomization = menuEditorModel.hudCustomization
        switch selectedHUDProfile {
        case .global:
            let previousGlobal = configuration.globalHUDActionLayout
            configuration.inner = menuEditorModel.inner
            configuration.middle = menuEditorModel.middle
            // Keep every App HUD consistent with the new Global in memory, so an
            // override of a deleted Global item becomes app-only before any App
            // HUD is edited (AC7). Without a deletion nothing changes (AC19).
            configuration.repairAppHUDProfiles(afterGlobalChangeFrom: previousGlobal)
            return true
        case .app(let bundleIdentifier):
            guard let profile = configuration.appHUDProfile(forBundleIdentifier: bundleIdentifier) else {
                selectedHUDProfile = .global
                loadSelectedProfileIntoEditor()
                return false
            }
            guard menuEditorModel.inheritanceEditState != nil else {
                loadSelectedProfileIntoEditor()
                return false
            }
            // A customization-only change leaves the App HUD's storage untouched.
            guard let edited = editedAppHUDProfile(from: profile) else { return true }
            guard let rings = edited.rings else { return false }
            return configuration.setAppHUDInheritance(rings, forBundleIdentifier: bundleIdentifier)
        }
    }

    private func synchronizeEditorIfNeeded() {
        guard editorDiffersFromSelectedProfile, mergeEditorIntoSelectedProfile() else { return }
        markDirty([.menuItems])
        scheduleSave()
    }

    /// Loads Global, or the selected App HUD resolved against the exact Global
    /// it is resolved from (which the editor keeps for `diff`).
    private func loadSelectedProfileIntoEditor(preservingItemSelection: Bool = false) {
        menuEditorModel.load(
            resolved: selectedResolvedAppLayout,
            global: configuration.globalHUDActionLayout,
            hudCustomization: configuration.hudCustomization,
            preservingSelection: preservingItemSelection,
            normalizeStoredValues: false
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

    /// Whether two stored profiles hold the same inheritance metadata, ignoring
    /// unknown JSON at every level (the old reconcile compared only the typed
    /// action arrays, for the same reason).
    private static func sameInheritance(_ lhs: AppHUDProfile, _ rhs: AppHUDProfile) -> Bool {
        guard let left = lhs.rings, let right = rhs.rings else { return lhs.storage == rhs.storage }
        return sameRing(left.inner, right.inner) && sameRing(left.middle, right.middle)
    }

    private static func sameRing(_ lhs: RingInheritance, _ rhs: RingInheritance) -> Bool {
        lhs.followsGlobal == rhs.followsGlobal
            && lhs.overrides == rhs.overrides
            && lhs.hidden == rhs.hidden
            && lhs.customOrder == rhs.customOrder
            && lhs.appOnly.map(\.item) == rhs.appOnly.map(\.item)
            && lhs.appOnly.map(\.after) == rhs.appOnly.map(\.after)
    }

    /// `desired`'s metadata carrying `fresh`'s unknown JSON: rings- and
    /// ring-level fields, override item JSON by ID and app-only records by ID
    /// (each occurrence matched once, in order).
    private static func rebase(_ desired: AppHUDRings, onto fresh: AppHUDRings) -> AppHUDRings {
        AppHUDRings(
            inner: rebase(desired.inner, onto: fresh.inner),
            middle: rebase(desired.middle, onto: fresh.middle),
            unknownFields: fresh.preservedUnknownFields
        )
    }

    private static func rebase(_ desired: RingInheritance, onto fresh: RingInheritance) -> RingInheritance {
        var result = RingInheritance(
            followsGlobal: desired.followsGlobal,
            hidden: desired.hidden,
            customOrder: desired.customOrder
        )
        for item in desired.overrides.values {
            result.setOverride(
                item,
                preservingJSON: fresh.preservedJSON(forOverride: item.id)
                    ?? desired.preservedJSON(forOverride: item.id)
            )
        }
        var freshAppOnly: [UUID: [AppOnlyItem]] = [:]
        for record in fresh.appOnly {
            freshAppOnly[record.id, default: []].append(record)
        }
        result.appOnly = desired.appOnly.map { record in
            guard var queue = freshAppOnly[record.id], !queue.isEmpty else { return record }
            let freshRecord = queue.removeFirst()
            freshAppOnly[record.id] = queue
            return freshRecord.updated(
                item: record.item,
                after: record.after,
                fallbackJSON: record.preservedJSON
            )
        }
        result.setUnknownFields(fresh.preservedUnknownFields)
        return result
    }

    private static func overflowWarnings(in configuration: Configuration) -> [AppHUDOverflowWarning] {
        configuration.validAppHUDProfiles.keys.sorted().flatMap { bundleIdentifier -> [AppHUDOverflowWarning] in
            guard let resolved = configuration.resolvedAppLayout(
                forBundleIdentifier: bundleIdentifier
            ) else { return [] }
            return [Band.inner, .middle].compactMap { band in
                guard !resolved.lockedBands.contains(band),
                      let count = resolved.notShown[band]?.count, count > 0 else { return nil }
                return AppHUDOverflowWarning(bundleIdentifier: bundleIdentifier, band: band, count: count)
            }
        }
    }

    private func replaceMenuItemsState(in target: inout Configuration, with source: Configuration) {
        target.globalHUDActionLayout = source.globalHUDActionLayout
        target.hudCustomization = source.hudCustomization
        target.replaceAppHUDProfileStorage(with: source)
    }

    /// Writes the Global rings only when this workspace changed them, and refuses
    /// to overwrite a Global menu that another writer changed since the baseline.
    private func reconcileGlobalMenuChanges(
        from baseline: Configuration,
        to edited: Configuration,
        into target: inout Configuration
    ) throws {
        let editedMatchesBaseline = edited.inner == baseline.inner
            && edited.middle == baseline.middle
        guard !editedMatchesBaseline else { return }
        let freshMatchesBaseline = target.inner == baseline.inner
            && target.middle == baseline.middle
        let freshMatchesEdited = target.inner == edited.inner
            && target.middle == edited.middle
        guard freshMatchesBaseline || freshMatchesEdited else {
            throw MenuItemsMergeError.globalMenuChangedExternally
        }
        target.inner = edited.inner
        target.middle = edited.middle
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
            if let freshOpaque = target.unavailableAppHUDProfile(
                forBundleIdentifier: bundleIdentifier
            ) {
                guard intentionallyReplacedUnavailableAppHUDProfiles.contains(bundleIdentifier),
                      baseline.unavailableAppHUDProfile(
                          forBundleIdentifier: bundleIdentifier
                      ) == freshOpaque,
                      original[bundleIdentifier] == nil,
                      let desiredProfile = desired[bundleIdentifier],
                      target.setAppHUDProfile(
                          desiredProfile,
                          forBundleIdentifier: bundleIdentifier
                      ) else {
                    throw MenuItemsMergeError.appProfilesChangedExternally
                }
                continue
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

            case (.some(let originalProfile), .some(let desiredProfile)):
                guard var freshProfile = target.appHUDProfile(
                    forBundleIdentifier: bundleIdentifier
                ) else {
                    throw MenuItemsMergeError.appProfilesChangedExternally
                }
                // Stored inheritance metadata, never resolved layouts: a Global
                // edit does not make an App HUD look changed here (AC19).
                // Unknown JSON is not compared, so a newer writer's additions to
                // this profile do not count as a conflicting edit.
                let freshMatchesOriginal = Self.sameInheritance(freshProfile, originalProfile)
                let freshMatchesDesired = Self.sameInheritance(freshProfile, desiredProfile)
                guard freshMatchesOriginal || freshMatchesDesired else {
                    throw MenuItemsMergeError.appProfilesChangedExternally
                }
                // Apply only the inheritance metadata to the fresh typed profile.
                // Its forward-compatible profile, rings, ring and item JSON
                // remains the merge base.
                guard let desiredRings = desiredProfile.rings else {
                    throw MenuItemsMergeError.appProfilesChangedExternally
                }
                freshProfile.setRings(
                    freshProfile.rings.map { Self.rebase(desiredRings, onto: $0) } ?? desiredRings
                )
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
