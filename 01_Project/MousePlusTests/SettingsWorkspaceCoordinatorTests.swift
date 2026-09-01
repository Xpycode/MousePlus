import Foundation
import XCTest
@testable import MousePlus

@MainActor
final class SettingsWorkspaceCoordinatorTests: XCTestCase {
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
    private var gatedSaveFailure: Error?
    private var gatedSaveContinuation: CheckedContinuation<Void, Never>?

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

    func mutateCurrent(_ mutation: (inout Configuration) -> Void) {
        mutation(&current)
    }

    func setLoadFailure(_ error: Error?) {
        loadFailure = error
    }

    func setSaveFailure(_ error: Error?) {
        saveFailure = error
    }

    func gateNextSaveWithFailure(_ error: Error) {
        gatedSaveFailure = error
    }

    func releaseGatedSave() {
        gatedSaveContinuation?.resume()
        gatedSaveContinuation = nil
    }
}
