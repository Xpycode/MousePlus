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
    private let liveApply: @MainActor (Configuration, Set<Field>) -> Void
    private var debounceTask: Task<Void, Never>?
    private var saveTask: Task<Bool, Never>?
    private var saveTaskID: UUID?
    private var generations: [Field: UInt] = [:]
    private var sessionUndoMenuItems: (inner: [RingMenuItem], middle: [RingMenuItem])?

    private(set) var configuration = Configuration()
    private(set) var status: Status = .idle
    private(set) var dirtyFields: Set<Field> = []
    private(set) var isLoaded = false
    private(set) var workspaceState = SettingsWorkspaceState()
    let menuEditorModel = MenuEditorModel(
        inner: RingMenuItem.sampleInnerItems,
        middle: RingMenuItem.sampleItems
    )

    init(
        persistence: any ConfigurationPersisting = ConfigurationService(),
        debounceClock: any WorkspaceDebounceClock = ContinuousWorkspaceDebounceClock(
            duration: .milliseconds(300)
        ),
        liveApply: @escaping @MainActor (Configuration, Set<Field>) -> Void = { _, _ in }
    ) {
        self.persistence = persistence
        self.debounceClock = debounceClock
        self.liveApply = liveApply
    }

    func load() async {
        debounceTask?.cancel()
        status = .loading
        do {
            configuration = try await persistence.loadResult().configuration
            menuEditorModel.load(from: configuration)
            dirtyFields.removeAll()
            generations.removeAll()
            sessionUndoMenuItems = nil
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
        mutation(&configuration)
        if fields.contains(.menuItems) {
            menuEditorModel.load(from: configuration)
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
        guard configuration.inner != menuEditorModel.inner ||
                configuration.middle != menuEditorModel.middle else { return }
        configuration = menuEditorModel.merged(into: configuration)
        markDirty([.menuItems])
        scheduleSave()
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

        guard await flush() else {
            workspaceState.reset = .failed(statusMessage)
            return false
        }

        let previous = (inner: configuration.inner, middle: configuration.middle)
        do {
            try await persistence.createBackup()
            workspaceState.durableBackupAvailable = true
        } catch {
            workspaceState.reset = .failed(error.localizedDescription)
            return false
        }

        edit([.menuItems]) {
            $0.inner = RingMenuItem.sampleInnerItems
            $0.middle = RingMenuItem.sampleItems
        }
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
        edit([.menuItems]) {
            $0.inner = previous.inner
            $0.middle = previous.middle
        }
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

        edit([.menuItems]) {
            $0.inner = backup.inner
            $0.middle = backup.middle
        }
        guard await flush() else {
            workspaceState.reset = .failed(statusMessage)
            return false
        }
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
            merge(fields: fields, from: edited, into: &merged)
            try await persistence.save(merged)

            for field in fields where generations[field] == savedGenerations[field] {
                dirtyFields.remove(field)
            }
            configuration = mergingUnsavedFields(from: configuration, into: merged)
            menuEditorModel.load(from: configuration)
            liveApply(merged, fields)

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
    ) -> Configuration {
        var result = persisted
        merge(fields: dirtyFields, from: edited, into: &result)
        return result
    }

    private func merge(
        fields: Set<Field>,
        from edited: Configuration,
        into base: inout Configuration
    ) {
        if fields.contains(.menuItems) {
            base.inner = edited.inner
            base.middle = edited.middle
        }
        if fields.contains(.triggers) { base.triggers = edited.triggers }
        if fields.contains(.appearance) { base.appearance = edited.appearance }
        if fields.contains(.behavior) { base.behavior = edited.behavior }
    }
}
