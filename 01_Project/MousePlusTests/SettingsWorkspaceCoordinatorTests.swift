import Foundation
import XCTest
@testable import MousePlus

@MainActor
final class SettingsWorkspaceCoordinatorTests: XCTestCase {
    func testResetAtomicallyDefaultsItemsLayoutAndAllColorOverridesOnly() async {
        let initial = customizedHUDConfiguration()
        let persistence = RecordingConfigurationPersistence(initial)
        let coordinator = makeCoordinator(persistence)
        await coordinator.load()

        let reset = await coordinator.resetMenuItems()

        XCTAssertTrue(reset)
        let saved = await persistence.current
        XCTAssertEqual(saved.inner, RingMenuItem.sampleInnerItems)
        XCTAssertEqual(saved.middle, RingMenuItem.sampleItems)
        XCTAssertEqual(saved.hudCustomization, .default)
        XCTAssertEqual(saved.triggers, initial.triggers)
        XCTAssertEqual(saved.appearance, initial.appearance)
        XCTAssertEqual(saved.behavior, initial.behavior)
        XCTAssertEqual(coordinator.workspaceState.reset, .undoAvailable)
        XCTAssertTrue(coordinator.workspaceState.durableBackupAvailable)
    }

    func testUndoResetAtomicallyRestoresLayoutAndInheritedAndPerItemColors() async {
        let initial = customizedHUDConfiguration()
        let persistence = RecordingConfigurationPersistence(initial)
        let coordinator = makeCoordinator(persistence)
        await coordinator.load()
        let reset = await coordinator.resetMenuItems()
        XCTAssertTrue(reset)

        let undone = await coordinator.undoMenuItemsReset()

        XCTAssertTrue(undone)
        let saved = await persistence.current
        assertHUDMenuState(saved, equals: initial)
        XCTAssertEqual(saved.triggers, initial.triggers)
        XCTAssertEqual(saved.appearance, initial.appearance)
        XCTAssertEqual(saved.behavior, initial.behavior)
        XCTAssertEqual(coordinator.workspaceState.reset, .idle)
    }

    func testFailedBackupLeavesEntirePreResetHUDStateUntouched() async {
        let initial = customizedHUDConfiguration()
        let persistence = RecordingConfigurationPersistence(initial)
        await persistence.setBackupFailure(TestFailure.write)
        let coordinator = makeCoordinator(persistence)
        await coordinator.load()

        let reset = await coordinator.resetMenuItems()

        XCTAssertFalse(reset)
        assertHUDMenuState(coordinator.configuration, equals: initial)
        let saved = await persistence.current
        assertHUDMenuState(saved, equals: initial)
        XCTAssertTrue(coordinator.dirtyFields.isEmpty)
        XCTAssertFalse(coordinator.workspaceState.durableBackupAvailable)
        guard case .failed = coordinator.workspaceState.reset else {
            return XCTFail("Backup failure must report a failed reset")
        }
    }

    func testFailedResetSaveAndCloseBarrierPreserveFullRecoverablePreResetHUDState() async throws {
        let initial = customizedHUDConfiguration()
        let persistence = RecordingConfigurationPersistence(initial)
        let coordinator = makeCoordinator(persistence)
        await coordinator.load()
        await persistence.setSaveFailure(TestFailure.write)

        let reset = await coordinator.resetMenuItems()
        XCTAssertFalse(reset)
        XCTAssertEqual(coordinator.configuration.inner, RingMenuItem.sampleInnerItems)
        XCTAssertEqual(coordinator.configuration.middle, RingMenuItem.sampleItems)
        XCTAssertEqual(coordinator.configuration.hudCustomization, .default)
        XCTAssertEqual(coordinator.dirtyFields, [.menuItems])
        XCTAssertTrue(coordinator.workspaceState.durableBackupAvailable)

        let mayClose = await coordinator.requestClose()
        XCTAssertFalse(mayClose)
        guard case .blocked = coordinator.workspaceState.closeBarrier else {
            return XCTFail("A failed reset write must block close")
        }
        let backup = try await persistence.loadBackup()
        assertHUDMenuState(backup, equals: initial)

        await persistence.setSaveFailure(nil)
        let restoredBackup = await coordinator.restoreMenuItemsFromBackup()
        XCTAssertTrue(restoredBackup)
        let restored = await persistence.current
        assertHUDMenuState(restored, equals: initial)
        XCTAssertTrue(coordinator.dirtyFields.isEmpty)
    }

    func testHUDCustomizationAndItemOverrideSurviveConcurrentFieldEditRetryAndReload() async throws {
        let persistence = RecordingConfigurationPersistence(Configuration())
        let recorder = LiveApplyRecorder()
        let coordinator = makeCoordinator(persistence, recorder: recorder)
        await coordinator.load()
        let itemID = try XCTUnwrap(coordinator.menuEditorModel.middle.first?.id)
        coordinator.menuEditorModel.selection = SlotSelection(band: .middle, itemID: itemID, subItemID: nil)
        coordinator.menuEditorModel.hudCustomization.middle.layout.angularOffset = 73
        let binding = try XCTUnwrap(coordinator.menuEditorModel.binding(forItem: itemID, band: .middle))
        binding.wrappedValue.iconColor = HUDColor(red: 0.8, green: 0.2, blue: 0.1)
        coordinator.menuItemsDidChange()
        coordinator.edit([.behavior]) { $0.behavior.dismissOnEscape = false }
        await persistence.setSaveFailure(TestFailure.write)

        let firstFlush = await coordinator.flush()
        XCTAssertFalse(firstFlush)
        XCTAssertEqual(coordinator.dirtyFields, [.menuItems, .behavior])
        XCTAssertEqual(coordinator.menuEditorModel.selection?.itemID, itemID)
        XCTAssertTrue(recorder.events.isEmpty)

        await persistence.setSaveFailure(nil)
        let retried = await coordinator.retry()
        XCTAssertTrue(retried)
        let saved = await persistence.current
        XCTAssertEqual(saved.hudCustomization.middle.layout.angularOffset, 73)
        XCTAssertEqual(saved.middle.first(where: { $0.id == itemID })?.iconColor, HUDColor(red: 0.8, green: 0.2, blue: 0.1))
        XCTAssertFalse(saved.behavior.dismissOnEscape)
        XCTAssertEqual(recorder.events.last?.hudCustomization, saved.hudCustomization)
        XCTAssertEqual(coordinator.menuEditorModel.selection?.itemID, itemID)

        await coordinator.load()
        XCTAssertEqual(coordinator.menuEditorModel.hudCustomization.middle.layout.angularOffset, 73)
        XCTAssertEqual(coordinator.menuEditorModel.middle.first(where: { $0.id == itemID })?.iconColor, HUDColor(red: 0.8, green: 0.2, blue: 0.1))
    }

    func testBackupRestoreRestoresHUDCustomizationAndItemOverrides() async throws {
        var backup = Configuration()
        backup.hudCustomization.outerRingVisibility = .alwaysHidden
        backup.middle[0].wedgeColor = HUDColor(red: 0.1, green: 0.4, blue: 0.7)
        let persistence = RecordingConfigurationPersistence(backup)
        let coordinator = makeCoordinator(persistence)
        await coordinator.load()
        try await persistence.createBackup()
        await coordinator.load()
        coordinator.menuEditorModel.hudCustomization.outerRingVisibility = .alwaysVisible
        coordinator.menuEditorModel.middle[0].wedgeColor = nil
        coordinator.menuItemsDidChange()
        let savedEdit = await coordinator.flush()
        XCTAssertTrue(savedEdit)

        let restoredBackup = await coordinator.restoreMenuItemsFromBackup()
        XCTAssertTrue(restoredBackup)
        let restored = await persistence.current
        XCTAssertEqual(restored.hudCustomization.outerRingVisibility, .alwaysHidden)
        XCTAssertEqual(restored.middle[0].wedgeColor, HUDColor(red: 0.1, green: 0.4, blue: 0.7))
    }

    private func customizedHUDConfiguration() -> Configuration {
        var configuration = Configuration()
        configuration.triggers.mouseButton = .mouseButton(buttonNumber: 7, mode: .tapToggle)
        configuration.appearance.deadZone = 37
        configuration.behavior.dismissOnEscape = false
        configuration.hudCustomization.inner.layout = HUDRingLayout(
            slotCountMode: .fixed,
            fixedSlotCount: 7,
            angularOffset: 31
        )
        configuration.hudCustomization.middle.layout = HUDRingLayout(
            slotCountMode: .fixed,
            fixedSlotCount: 8,
            angularOffset: 73
        )
        configuration.hudCustomization.outerRingVisibility = .alwaysHidden
        configuration.hudCustomization.iconOrientation = .radial
        configuration.hudCustomization.wedgeColor = HUDColor(red: 0.1, green: 0.2, blue: 0.3)
        configuration.hudCustomization.iconColor = HUDColor(red: 0.9, green: 0.8, blue: 0.7)
        configuration.hudCustomization.inner.appearance.wedgeColor = HUDColor(red: 0.2, green: 0.3, blue: 0.4)
        configuration.hudCustomization.middle.appearance.iconColor = HUDColor(red: 0.7, green: 0.6, blue: 0.5)
        configuration.hudCustomization.outerAppearance.iconOrientation = .tangential
        configuration.hudCustomization.outerAppearance.wedgeColor = HUDColor(red: 0.4, green: 0.3, blue: 0.2)
        configuration.inner[0].wedgeColor = HUDColor(red: 0.3, green: 0.5, blue: 0.7)
        configuration.middle[0].iconColor = HUDColor(red: 0.8, green: 0.4, blue: 0.2)
        configuration.middle[0].subItems?[0].wedgeColor = HUDColor(red: 0.6, green: 0.2, blue: 0.4)
        return configuration
    }

    private func assertHUDMenuState(
        _ actual: Configuration,
        equals expected: Configuration,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(actual.inner, expected.inner, file: file, line: line)
        XCTAssertEqual(actual.middle, expected.middle, file: file, line: line)
        XCTAssertEqual(actual.hudCustomization, expected.hudCustomization, file: file, line: line)
    }

    func testRapidEditsCoalesceIntoOneSave() async {
        let persistence = RecordingConfigurationPersistence(Configuration())
        let coordinator = makeCoordinator(persistence)
        await coordinator.load()

        coordinator.edit([.appearance]) { $0.appearance.deadZone = 30 }
        coordinator.edit([.appearance]) { $0.appearance.deadZone = 31 }
        coordinator.edit([.appearance]) { $0.appearance.deadZone = 32 }
        let flushed = await coordinator.flush()
        XCTAssertTrue(flushed)

        let saveCount = await persistence.saveCount
        let saved = await persistence.current
        XCTAssertEqual(saveCount, 1)
        XCTAssertEqual(saved.appearance.deadZone, 32)
        XCTAssertEqual(coordinator.status, .saved)
    }

    func testTeardownFlushesPendingEdit() async {
        let persistence = RecordingConfigurationPersistence(Configuration())
        let coordinator = makeCoordinator(persistence)
        await coordinator.load()
        coordinator.edit([.behavior]) { $0.behavior.dismissOnEscape.toggle() }

        let flushed = await coordinator.teardown()
        XCTAssertTrue(flushed)

        let saveCount = await persistence.saveCount
        XCTAssertEqual(saveCount, 1)
        XCTAssertTrue(coordinator.dirtyFields.isEmpty)
    }

    func testFreshBasePreservesOverlappingPaneAndExternalEdits() async {
        let persistence = RecordingConfigurationPersistence(Configuration())
        let coordinator = makeCoordinator(persistence)
        await coordinator.load()
        coordinator.edit([.appearance]) { $0.appearance.deadZone = 41 }
        coordinator.edit([.triggers]) { $0.triggers.mouseButton = .mouseButton(buttonNumber: 7, mode: .tapToggle) }

        await persistence.mutateCurrent { $0.behavior.dismissOnEscape = false }
        let flushed = await coordinator.flush()
        XCTAssertTrue(flushed)

        let saved = await persistence.current
        XCTAssertEqual(saved.appearance.deadZone, 41)
        XCTAssertEqual(saved.triggers.mouseButton, .mouseButton(buttonNumber: 7, mode: .tapToggle))
        XCTAssertFalse(saved.behavior.dismissOnEscape)
    }

    func testMidSessionCorruptionPreventsOverwrite() async {
        let persistence = RecordingConfigurationPersistence(Configuration())
        let coordinator = makeCoordinator(persistence)
        await coordinator.load()
        coordinator.edit([.appearance]) { $0.appearance.deadZone = 43 }
        await persistence.setLoadFailure(makeDecodingError())

        let flushed = await coordinator.flush()
        XCTAssertFalse(flushed)

        let saveCount = await persistence.saveCount
        XCTAssertEqual(saveCount, 0)
        XCTAssertEqual(coordinator.dirtyFields, [.appearance])
        guard case .loadFailed = coordinator.status else {
            return XCTFail("A corrupt fresh base must become Load Failed")
        }
    }

    func testFailedWriteStaysDirtyAndRetryAppliesAfterSuccess() async {
        let persistence = RecordingConfigurationPersistence(Configuration())
        let recorder = LiveApplyRecorder()
        let coordinator = makeCoordinator(persistence, recorder: recorder)
        await coordinator.load()
        await persistence.setSaveFailure(TestFailure.write)
        coordinator.edit([.appearance]) { $0.appearance.deadZone = 45 }

        let firstFlush = await coordinator.flush()
        XCTAssertFalse(firstFlush)
        XCTAssertEqual(coordinator.dirtyFields, [.appearance])
        XCTAssertTrue(recorder.events.isEmpty)
        guard case .saveFailed = coordinator.status else {
            return XCTFail("Expected Save Failed")
        }

        await persistence.setSaveFailure(nil)
        let retrySucceeded = await coordinator.retry()
        let saved = await persistence.current
        XCTAssertTrue(retrySucceeded)
        XCTAssertEqual(saved.appearance.deadZone, 45)
        XCTAssertEqual(recorder.events.count, 1)
        XCTAssertEqual(coordinator.status, .saved)
    }

    func testLiveApplyReceivesCompletePersistedRuntimeSnapshot() async throws {
        var initial = Configuration()
        initial.behavior.dismissOnEscape = false
        let persistence = RecordingConfigurationPersistence(initial)
        let recorder = LiveApplyRecorder()
        let coordinator = makeCoordinator(persistence, recorder: recorder)
        await coordinator.load()

        coordinator.edit([.appearance]) { $0.appearance.deadZone = 51 }
        let flushed = await coordinator.flush()
        XCTAssertTrue(flushed)

        let snapshot = try XCTUnwrap(recorder.events.last)
        XCTAssertEqual(snapshot.appearance.deadZone, 51)
        XCTAssertFalse(snapshot.behavior.dismissOnEscape)
        XCTAssertEqual(snapshot.inner, initial.inner)
        XCTAssertEqual(snapshot.middle, initial.middle)
        XCTAssertEqual(snapshot.triggers, initial.triggers)
        let persisted = await persistence.current
        XCTAssertEqual(snapshot.appearance, persisted.appearance)
        XCTAssertEqual(snapshot.behavior.holdToActivate, persisted.behavior.holdToActivate)
        XCTAssertEqual(snapshot.behavior.tapToActivate, persisted.behavior.tapToActivate)
        XCTAssertEqual(snapshot.behavior.dismissOnClickOutside, persisted.behavior.dismissOnClickOutside)
        XCTAssertEqual(snapshot.behavior.dismissOnEscape, persisted.behavior.dismissOnEscape)
        XCTAssertEqual(snapshot.inner, persisted.inner)
        XCTAssertEqual(snapshot.middle, persisted.middle)
        XCTAssertEqual(snapshot.triggers, persisted.triggers)
    }

    func testNoOpClosePerformsNoPersistenceWork() async {
        let persistence = RecordingConfigurationPersistence(Configuration())
        let coordinator = makeCoordinator(persistence)
        await coordinator.load()
        let loadsAfterOpen = await persistence.loadCount

        let closed = await coordinator.teardown()
        XCTAssertTrue(closed)

        let finalLoadCount = await persistence.loadCount
        let saveCount = await persistence.saveCount
        XCTAssertEqual(finalLoadCount, loadsAfterOpen)
        XCTAssertEqual(saveCount, 0)
    }

    func testCancelledDebounceNeverReportsSavedOrLiveApplies() async {
        let persistence = RecordingConfigurationPersistence(Configuration())
        let recorder = LiveApplyRecorder()
        let coordinator = makeCoordinator(persistence, recorder: recorder)
        await coordinator.load()
        coordinator.edit([.appearance]) { $0.appearance.deadZone = 46 }
        coordinator.edit([.appearance]) { $0.appearance.deadZone = 47 }
        await Task.yield()

        XCTAssertEqual(coordinator.status, .saving)
        let saveCountBeforeFlush = await persistence.saveCount
        XCTAssertEqual(saveCountBeforeFlush, 0)
        XCTAssertTrue(recorder.events.isEmpty)

        let flushed = await coordinator.flush()
        XCTAssertTrue(flushed)
        XCTAssertEqual(coordinator.status, .saved)
        let saveCountAfterFlush = await persistence.saveCount
        XCTAssertEqual(saveCountAfterFlush, 1)
        XCTAssertEqual(recorder.events.count, 1)
    }

    func testSuccessfulAutosavePreservesSelectedMenuItemIdentity() async throws {
        let persistence = RecordingConfigurationPersistence(Configuration())
        let coordinator = makeCoordinator(persistence)
        await coordinator.load()
        let itemID = try XCTUnwrap(coordinator.menuEditorModel.middle.first?.id)
        coordinator.menuEditorModel.selection = SlotSelection(
            band: .middle,
            itemID: itemID,
            subItemID: nil
        )

        let binding = try XCTUnwrap(
            coordinator.menuEditorModel.binding(forItem: itemID, band: .middle)
        )
        var edited = binding.wrappedValue
        edited.label = "Still selected after save"
        binding.wrappedValue = edited
        coordinator.menuItemsDidChange()

        let flushed = await coordinator.flush()
        XCTAssertTrue(flushed)
        XCTAssertEqual(coordinator.menuEditorModel.selection?.itemID, itemID)
        XCTAssertEqual(
            coordinator.menuEditorModel.middle.first(where: { $0.id == itemID })?.label,
            "Still selected after save"
        )
    }

    func testOverlappingFlushSharesInFlightFailureWithoutImplicitRetry() async {
        let persistence = RecordingConfigurationPersistence(Configuration())
        let coordinator = makeCoordinator(persistence)
        await coordinator.load()
        await persistence.gateNextSaveWithFailure(TestFailure.write)
        coordinator.edit([.appearance]) { $0.appearance.deadZone = 48 }

        let firstFlush = Task { @MainActor in await coordinator.flush() }
        while await persistence.saveCount == 0 {
            await Task.yield()
        }
        let overlappingFlush = Task { @MainActor in await coordinator.flush() }
        await Task.yield()
        await persistence.releaseGatedSave()

        let firstResult = await firstFlush.value
        let overlappingResult = await overlappingFlush.value
        let saveCount = await persistence.saveCount
        XCTAssertFalse(firstResult)
        XCTAssertFalse(overlappingResult)
        XCTAssertEqual(saveCount, 1)
        XCTAssertEqual(coordinator.dirtyFields, [.appearance])
        guard case .saveFailed = coordinator.status else {
            return XCTFail("The shared failed write must remain Save Failed")
        }
    }

    private func makeCoordinator(
        _ persistence: RecordingConfigurationPersistence,
        recorder: LiveApplyRecorder? = nil
    ) -> SettingsWorkspaceCoordinator {
        let recorder = recorder ?? LiveApplyRecorder()
        return SettingsWorkspaceCoordinator(
            persistence: persistence,
            debounceClock: LongWorkspaceDebounceClock(),
            liveApply: { configuration in recorder.events.append(configuration) }
        )
    }

    private func makeDecodingError() -> Error {
        do {
            _ = try JSONDecoder().decode(Configuration.self, from: Data("{".utf8))
            return TestFailure.expectedDecodeFailure
        } catch {
            return error
        }
    }
}

private struct LongWorkspaceDebounceClock: WorkspaceDebounceClock {
    func sleep() async throws {
        try await Task.sleep(for: .seconds(60))
    }
}

@MainActor
private final class LiveApplyRecorder {
    var events: [Configuration] = []
}

private enum TestFailure: Error {
    case write
    case expectedDecodeFailure
}

private actor RecordingConfigurationPersistence: ConfigurationPersisting {
    private(set) var current: Configuration
    private(set) var loadCount = 0
    private(set) var saveCount = 0
    private var loadFailure: Error?
    private var saveFailure: Error?
    private var backupFailure: Error?
    private var gatedSaveFailure: Error?
    private var gatedSaveContinuation: CheckedContinuation<Void, Never>?
    private var backup: Configuration?

    init(_ configuration: Configuration) {
        current = configuration
    }

    func loadResult() throws -> ConfigurationService.LoadResult {
        loadCount += 1
        if let loadFailure { throw loadFailure }
        return .loaded(current)
    }

    func save(_ configuration: Configuration) async throws {
        saveCount += 1
        if let gatedSaveFailure {
            await withCheckedContinuation { continuation in
                gatedSaveContinuation = continuation
            }
            self.gatedSaveFailure = nil
            throw gatedSaveFailure
        }
        if let saveFailure { throw saveFailure }
        current = configuration
    }

    func hasBackup() async -> Bool {
        backup != nil
    }

    func createBackup() async throws {
        if let backupFailure { throw backupFailure }
        backup = current
    }

    func loadBackup() async throws -> Configuration {
        guard let backup else { throw TestFailure.write }
        return backup
    }

    func mutateCurrent(_ mutation: (inout Configuration) -> Void) {
        mutation(&current)
    }

    func setLoadFailure(_ error: Error?) {
        loadFailure = error
    }

    func setSaveFailure(_ error: Error?) {
        saveFailure = error
    }

    func setBackupFailure(_ error: Error?) {
        backupFailure = error
    }

    func gateNextSaveWithFailure(_ error: Error) {
        gatedSaveFailure = error
    }

    func releaseGatedSave() {
        gatedSaveContinuation?.resume()
        gatedSaveContinuation = nil
    }
}
