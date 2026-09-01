import Foundation
import XCTest
@testable import MousePlus

@MainActor
final class SettingsWorkspaceStateTests: XCTestCase {
    func testResetBacksUpBeforeChangingOnlyMenuItemsAndOffersUndo() async {
        var original = Configuration()
        original.middle[0].label = "Before Reset"
        original.appearance.deadZone = 37
        let persistence = RecoveryPersistence(original)
        let recorder = RecoveryLiveApplyRecorder()
        let coordinator = makeCoordinator(persistence, recorder)
        await coordinator.load()

        let reset = await coordinator.resetMenuItems()
        XCTAssertTrue(reset)

        let saved = await persistence.current
        let backup = await persistence.backup
        XCTAssertEqual(backup?.middle[0].label, "Before Reset")
        XCTAssertEqual(saved.middle[0].label, RingMenuItem.sampleItems[0].label)
        XCTAssertEqual(saved.appearance.deadZone, 37)
        XCTAssertEqual(coordinator.workspaceState.reset, .undoAvailable)
        XCTAssertEqual(recorder.count, 1)

        let undone = await coordinator.undoMenuItemsReset()
        let afterUndo = await persistence.current
        XCTAssertTrue(undone)
        XCTAssertEqual(afterUndo.middle[0].label, "Before Reset")
        XCTAssertEqual(recorder.count, 2)
        XCTAssertEqual(coordinator.workspaceState.reset, .idle)
    }

    func testBackupFailureDoesNotMutateOrLiveApply() async {
        var original = Configuration()
        original.middle[0].label = "Protected"
        let persistence = RecoveryPersistence(original)
        await persistence.setBackupFailure(RecoveryTestError.backup)
        let recorder = RecoveryLiveApplyRecorder()
        let coordinator = makeCoordinator(persistence, recorder)
        await coordinator.load()

        let reset = await coordinator.resetMenuItems()
        XCTAssertFalse(reset)

        let disk = await persistence.current
        XCTAssertEqual(disk.middle[0].label, "Protected")
        XCTAssertEqual(coordinator.configuration.middle[0].label, "Protected")
        XCTAssertEqual(recorder.count, 0)
        guard case .failed = coordinator.workspaceState.reset else {
            return XCTFail("Expected reset failure state")
        }
    }

    func testResetSaveFailureDoesNotLiveApplyOrChangeDisk() async {
        var original = Configuration()
        original.middle[0].label = "On Disk"
        let persistence = RecoveryPersistence(original)
        let recorder = RecoveryLiveApplyRecorder()
        let coordinator = makeCoordinator(persistence, recorder)
        await coordinator.load()
        await persistence.setSaveFailure(RecoveryTestError.write)

        let reset = await coordinator.resetMenuItems()
        XCTAssertFalse(reset)

        let disk = await persistence.current
        let backup = await persistence.backup
        XCTAssertEqual(disk.middle[0].label, "On Disk")
        XCTAssertNotNil(backup)
        XCTAssertEqual(recorder.count, 0)
        XCTAssertEqual(coordinator.dirtyFields, [.menuItems])
    }

    func testDurableRestoreAfterRelaunchUsesSafeMenuOnlySave() async {
        var original = Configuration()
        original.middle[0].label = "Recover Me"
        let persistence = RecoveryPersistence(original)
        let first = makeCoordinator(persistence, RecoveryLiveApplyRecorder())
        await first.load()
        let reset = await first.resetMenuItems()
        XCTAssertTrue(reset)

        await persistence.mutateCurrent { $0.appearance.deadZone = 49 }
        let recorder = RecoveryLiveApplyRecorder()
        let relaunched = makeCoordinator(persistence, recorder)
        await relaunched.load()
        XCTAssertTrue(relaunched.workspaceState.durableBackupAvailable)

        let restoredSuccessfully = await relaunched.restoreMenuItemsFromBackup()
        XCTAssertTrue(restoredSuccessfully)

        let restored = await persistence.current
        XCTAssertEqual(restored.middle[0].label, "Recover Me")
        XCTAssertEqual(restored.appearance.deadZone, 49)
        XCTAssertEqual(recorder.count, 1)
    }

    func testFailedCloseCancelPreservesDirtyAndPreventsDismissal() async {
        let persistence = RecoveryPersistence(Configuration())
        let coordinator = makeCoordinator(persistence, RecoveryLiveApplyRecorder())
        await coordinator.load()
        await persistence.setSaveFailure(RecoveryTestError.write)
        coordinator.edit([.appearance]) { $0.appearance.deadZone = 51 }

        let closeAllowed = await coordinator.requestClose()
        XCTAssertFalse(closeAllowed)
        guard case .blocked = coordinator.workspaceState.closeBarrier else {
            return XCTFail("Expected close barrier")
        }
        let cancelDismisses = await coordinator.resolveClose(.cancelClose)
        XCTAssertFalse(cancelDismisses)
        XCTAssertEqual(coordinator.dirtyFields, [.appearance])
    }

    func testFailedCloseRetryDismissesOnlyAfterSuccessfulSave() async {
        let persistence = RecoveryPersistence(Configuration())
        let coordinator = makeCoordinator(persistence, RecoveryLiveApplyRecorder())
        await coordinator.load()
        await persistence.setSaveFailure(RecoveryTestError.write)
        coordinator.edit([.appearance]) { $0.appearance.deadZone = 52 }
        let initialClose = await coordinator.requestClose()
        XCTAssertFalse(initialClose)

        let failedRetry = await coordinator.resolveClose(.retry)
        XCTAssertFalse(failedRetry)
        await persistence.setSaveFailure(nil)
        let successfulRetry = await coordinator.resolveClose(.retry)
        XCTAssertTrue(successfulRetry)

        let disk = await persistence.current
        XCTAssertEqual(disk.appearance.deadZone, 52)
        XCTAssertTrue(coordinator.dirtyFields.isEmpty)
    }

    func testFailedCloseDiscardReloadsDiskAndClearsDirtyState() async {
        var disk = Configuration()
        disk.appearance.deadZone = 29
        let persistence = RecoveryPersistence(disk)
        let coordinator = makeCoordinator(persistence, RecoveryLiveApplyRecorder())
        await coordinator.load()
        await persistence.setSaveFailure(RecoveryTestError.write)
        coordinator.edit([.appearance]) { $0.appearance.deadZone = 53 }
        let initialClose = await coordinator.requestClose()
        XCTAssertFalse(initialClose)

        await persistence.setSaveFailure(nil)
        let discarded = await coordinator.resolveClose(.discardChanges)
        XCTAssertTrue(discarded)

        XCTAssertEqual(coordinator.configuration.appearance.deadZone, 29)
        XCTAssertTrue(coordinator.dirtyFields.isEmpty)
        XCTAssertEqual(coordinator.workspaceState.closeBarrier, .idle)
    }

    private func makeCoordinator(
        _ persistence: RecoveryPersistence,
        _ recorder: RecoveryLiveApplyRecorder
    ) -> SettingsWorkspaceCoordinator {
        SettingsWorkspaceCoordinator(
            persistence: persistence,
            debounceClock: RecoveryLongClock(),
            liveApply: { _, _ in recorder.count += 1 }
        )
    }

}

private struct RecoveryLongClock: WorkspaceDebounceClock {
    func sleep() async throws { try await Task.sleep(for: .seconds(60)) }
}

@MainActor
private final class RecoveryLiveApplyRecorder {
    var count = 0
}

private enum RecoveryTestError: Error {
    case backup
    case write
}

private actor RecoveryPersistence: ConfigurationPersisting {
    private(set) var current: Configuration
    private(set) var backup: Configuration?
    private var backupFailure: Error?
    private var saveFailure: Error?

    init(_ configuration: Configuration) { current = configuration }

    func loadResult() -> ConfigurationService.LoadResult { .loaded(current) }

    func save(_ configuration: Configuration) throws {
        if let saveFailure { throw saveFailure }
        current = configuration
    }

    func hasBackup() -> Bool { backup != nil }

    func createBackup() throws {
        if let backupFailure { throw backupFailure }
        backup = current
    }

    func loadBackup() throws -> Configuration {
        guard let backup else { throw ConfigurationRecoveryError.unsupported }
        return backup
    }

    func setBackupFailure(_ error: Error?) { backupFailure = error }
    func setSaveFailure(_ error: Error?) { saveFailure = error }
    func mutateCurrent(_ mutation: (inout Configuration) -> Void) { mutation(&current) }
}
