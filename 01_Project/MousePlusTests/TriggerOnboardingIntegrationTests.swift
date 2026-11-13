import Foundation
import XCTest
@testable import MousePlus

@MainActor
final class TriggerOnboardingIntegrationTests: XCTestCase {
    func testSettingsLoadRecoveryDoesNotApplyEditsMadeDuringBackupCheck() async {
        let backupCheckStarted = expectation(description: "Backup check suspended")
        let persistence = BackupCheckGatedPersistence(started: backupCheckStarted)
        var applied: [TriggersConfig] = []
        let delegate = AppDelegate(onboardingEffects: .init(
            applyRuntime: { applied.append($0.triggers) },
            showPermission: {}, showTriggers: {}, showSettings: {}
        ))
        delegate.beginTriggerOnboarding(accessibilityGranted: true)
        delegate.triggerOnboardingConfigurationLoaded(.failure(BackupCheckGatedPersistence.Failure.write))
        let previous = AppDelegate.recoverLoadedSettingsConfiguration
        defer { AppDelegate.recoverLoadedSettingsConfiguration = previous }
        var recovered: [TriggersConfig] = []
        AppDelegate.recoverLoadedSettingsConfiguration = {
            recovered.append($0.triggers)
            delegate.recoverLoadedSettingsConfiguration($0)
        }
        let workspace = SettingsWorkspaceCoordinator(
            persistence: persistence,
            debounceClock: IntegrationLongDebounceClock(),
            liveApply: { delegate.applySavedConfiguration($0) }
        )
        let loading = Task { await SettingsView.loadWorkspace(workspace) }
        await fulfillment(of: [backupCheckStarted], timeout: 2)
        XCTAssertTrue(workspace.isLoaded)
        let binding = TriggerBinding.mouseButton(buttonNumber: 4, mode: .tapToggle)
        workspace.edit([.triggers]) { $0.triggers.mouseButton = binding }
        await persistence.releaseBackupCheck()
        await loading.value
        XCTAssertTrue(recovered.isEmpty, "Load recovery must not forward the dirty editor snapshot")
        XCTAssertTrue(applied.isEmpty)
        XCTAssertEqual(workspace.savedTriggers?.mouseButton, TriggerBinding.none)
        let saved = await workspace.flush()
        XCTAssertFalse(saved)
        XCTAssertTrue(applied.isEmpty, "A failed save must not make the pending binding active")
        XCTAssertEqual(workspace.configuration.triggers.mouseButton, binding)
    }

    func testRepairBeforeInitialSettingsLoadRecoversWithoutAnEdit() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = ConfigurationStore(directoryURL: directory)
        try Data("broken".utf8).write(to: store.configurationURL)
        let service = ConfigurationService(store: store)
        var applied: [TriggersConfig] = []
        var routes: [String] = []
        let delegate = AppDelegate(onboardingEffects: .init(
            applyRuntime: { applied.append($0.triggers) },
            showPermission: { routes.append("permission") },
            showTriggers: { routes.append("triggers") },
            showSettings: { routes.append("settings") }
        ))
        delegate.beginTriggerOnboarding(accessibilityGranted: false)
        do {
            _ = try await service.loadResult()
            XCTFail("Fixture must fail")
        } catch {
            delegate.triggerOnboardingConfigurationLoaded(.failure(error))
        }
        var repaired = Configuration()
        repaired.triggers.mouseButton = .mouseButton(buttonNumber: 2, mode: .tapToggle)
        try await service.save(repaired)
        delegate.triggerOnboardingPermissionGranted()
        delegate.continueTriggerOnboarding()
        XCTAssertEqual(routes, ["permission", "triggers"])
        XCTAssertTrue(applied.isEmpty)

        let previous = AppDelegate.recoverLoadedSettingsConfiguration
        defer { AppDelegate.recoverLoadedSettingsConfiguration = previous }
        AppDelegate.recoverLoadedSettingsConfiguration = { delegate.recoverLoadedSettingsConfiguration($0) }
        let workspace = SettingsWorkspaceCoordinator(persistence: service)
        await SettingsView.loadWorkspace(workspace)
        XCTAssertEqual(applied, [repaired.triggers])
        XCTAssertEqual(workspace.savedTriggers, repaired.triggers)
        XCTAssertEqual(workspace.status, .saved)

        var newer = repaired
        newer.triggers.mouseButton = .mouseButton(buttonNumber: 4, mode: .holdRelease)
        delegate.applySavedConfiguration(newer)
        delegate.recoverLoadedSettingsConfiguration(repaired)
        XCTAssertEqual(applied.last, newer.triggers, "A later Settings load must not replace a saved edit")
        XCTAssertEqual(applied.count, 2)
        _ = await workspace.teardown()
    }

    func testSettingsGrantResumesRuntimeAfterPermissionWindowWasClosed() {
        var routes: [String] = []
        var applied: [TriggersConfig] = []
        let delegate = AppDelegate(onboardingEffects: .init(
            applyRuntime: { applied.append($0.triggers) },
            showPermission: { routes.append("permission") },
            showTriggers: { routes.append("triggers") },
            showSettings: { routes.append("settings") }
        ))
        var configuration = Configuration()
        configuration.triggers.mouseButton = .mouseButton(buttonNumber: 2, mode: .tapToggle)
        delegate.beginTriggerOnboarding(accessibilityGranted: false)
        delegate.triggerOnboardingConfigurationLoaded(.success(.loaded(configuration)))
        XCTAssertTrue(applied.isEmpty)
        // A closed permission window has no Continue callback. Settings reports a grant
        // independently; runtime should resume without another setup window or an edit.
        delegate.triggerOnboardingPermissionGranted()
        delegate.triggerOnboardingPermissionGranted()
        XCTAssertEqual(applied, [configuration.triggers])
        XCTAssertEqual(routes, ["permission"])
    }

    func testFirstRunRecordingPersistsBeforeRuntimeAndSuppressesSetupOnRelaunch() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let service = ConfigurationService(store: ConfigurationStore(directoryURL: directory))
        var routes: [String] = []
        var applied: [TriggersConfig] = []
        let delegate = AppDelegate(onboardingEffects: .init(
            applyRuntime: { applied.append($0.triggers) },
            showPermission: { routes.append("permission") },
            showTriggers: { routes.append("triggers") },
            showSettings: { routes.append("settings") }
        ))
        delegate.beginTriggerOnboarding(accessibilityGranted: true)
        XCTAssertTrue(routes.isEmpty)
        delegate.triggerOnboardingConfigurationLoaded(.success(try await service.loadResult()))
        XCTAssertEqual(routes, ["triggers"])

        let workspace = SettingsWorkspaceCoordinator(persistence: service) {
            delegate.applySavedConfiguration($0)
        }
        await workspace.load()
        let binding = TriggerBinding.keyboard(keyCode: 0, modifiers: 1 << 19, mode: .tapToggle)
        // Enters the same binding-acceptance path as the recorder. Physical input capture
        // and cross-app event delivery remain the signed live acceptance gate.
        XCTAssertNil(TriggersSettingsView.applyContextualKeyboard(binding, coordinator: workspace))
        XCTAssertEqual(workspace.savedTriggers?.keyboard, TriggerBinding.none)
        XCTAssertEqual(applied.last?.keyboard, TriggerBinding.none)
        let saved = await workspace.flush()
        XCTAssertTrue(saved)
        XCTAssertEqual(workspace.savedTriggers?.keyboard, binding)
        XCTAssertEqual(applied.last?.keyboard, binding)
        XCTAssertEqual(routes, ["triggers"], "Saving must not open another setup window")

        let reloaded = try await service.loadResult()
        XCTAssertEqual(reloaded.configuration.triggers.keyboard, binding)
        var relaunchRoutes: [String] = []
        var relaunchedBinding: TriggerBinding?
        let relaunched = AppDelegate(onboardingEffects: .init(
            applyRuntime: { relaunchedBinding = $0.triggers.keyboard },
            showPermission: { relaunchRoutes.append("permission") },
            showTriggers: { relaunchRoutes.append("triggers") },
            showSettings: { relaunchRoutes.append("settings") }
        ))
        relaunched.beginTriggerOnboarding(accessibilityGranted: true)
        relaunched.triggerOnboardingConfigurationLoaded(.success(reloaded))
        XCTAssertTrue(relaunchRoutes.isEmpty)
        XCTAssertEqual(relaunchedBinding, binding)
        _ = await workspace.teardown()
    }

    func testCorruptConfigurationRemainsIntactAndRetryRecoversRuntime() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = ConfigurationStore(directoryURL: directory)
        let corrupt = Data("not valid configuration".utf8)
        try corrupt.write(to: store.configurationURL)
        let service = ConfigurationService(store: store)
        var routes: [String] = []
        var applied: [TriggersConfig] = []
        let delegate = AppDelegate(onboardingEffects: .init(
            applyRuntime: { applied.append($0.triggers) },
            showPermission: { routes.append("permission") },
            showTriggers: { routes.append("triggers") },
            showSettings: { routes.append("settings") }
        ))
        delegate.beginTriggerOnboarding(accessibilityGranted: true)
        do {
            delegate.triggerOnboardingConfigurationLoaded(.success(try await service.loadResult()))
            XCTFail("Corrupt fixture must fail loading")
        } catch {
            delegate.triggerOnboardingConfigurationLoaded(.failure(error))
        }
        XCTAssertEqual(routes, ["triggers"])
        XCTAssertTrue(applied.isEmpty)

        let workspace = SettingsWorkspaceCoordinator(persistence: service) {
            delegate.applySavedConfiguration($0)
        }
        await workspace.load()
        XCTAssertFalse(workspace.isLoaded)
        XCTAssertNil(workspace.savedTriggers)
        workspace.edit([.triggers]) { $0.triggers.keyboard = .keyboard(keyCode: 0, modifiers: 0, mode: .holdRelease) }
        _ = await workspace.flush()
        XCTAssertEqual(try Data(contentsOf: store.configurationURL), corrupt)

        // Simulates explicit external repair of an isolated fixture, not automatic recovery.
        let binding = TriggerBinding.mouseButton(buttonNumber: 2, mode: .tapToggle)
        var repaired = Configuration()
        repaired.triggers.mouseButton = binding
        try await service.save(repaired)
        let recovered = await workspace.retry()
        XCTAssertTrue(recovered)
        XCTAssertEqual(workspace.savedTriggers?.mouseButton, binding)
        XCTAssertEqual(applied.last?.mouseButton, binding)
        XCTAssertEqual(routes, ["triggers"])
        _ = await workspace.teardown()
    }
}

private struct IntegrationLongDebounceClock: WorkspaceDebounceClock {
    func sleep() async throws {
        try await Task.sleep(for: .seconds(60))
    }
}

private actor BackupCheckGatedPersistence: ConfigurationPersisting {
    enum Failure: Error { case write }
    let started: XCTestExpectation
    private var continuation: CheckedContinuation<Void, Never>?
    private var released = false

    init(started: XCTestExpectation) { self.started = started }

    func loadResult() async throws -> ConfigurationService.LoadResult { .loaded(Configuration()) }
    func save(_ configuration: Configuration) async throws { throw Failure.write }

    func hasBackup() async -> Bool {
        await withCheckedContinuation { continuation in
            if released {
                continuation.resume()
            } else {
                self.continuation = continuation
            }
            started.fulfill()
        }
        return false
    }

    func releaseBackupCheck() {
        released = true
        continuation?.resume()
        continuation = nil
    }
}
