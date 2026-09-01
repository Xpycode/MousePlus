import Foundation
import XCTest
@testable import MousePlus

final class ConfigurationServiceTests: XCTestCase {
    private var temporaryDirectories: [URL] = []

    override func tearDownWithError() throws {
        for directory in temporaryDirectories {
            try? FileManager.default.removeItem(at: directory)
        }
    }

    func testAbsentFileReturnsExplicitDefaults() async throws {
        let service = makeService()

        let result = try await service.loadResult()

        guard case .defaults = result else {
            return XCTFail("An absent file must be distinguished from a loaded file")
        }
    }

    func testValidFileLoadsAsPersistedConfiguration() async throws {
        let service = makeService()
        let expected = Configuration()
        try await service.save(expected)

        let result = try await service.loadResult()

        guard case .loaded = result else {
            return XCTFail("Expected a persisted configuration")
        }
    }

    func testCorruptFileThrowsInsteadOfReturningDefaults() async throws {
        let service = makeService()
        let store = await service.store
        try FileManager.default.createDirectory(
            at: store.configurationURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("not json".utf8).write(to: store.configurationURL)

        do {
            _ = try await service.loadResult()
            XCTFail("Expected corrupt configuration to fail")
        } catch is DecodingError {
            // Expected.
        }
    }

    func testSaveFailsWhenStoreDirectoryCannotBeCreated() async throws {
        let baseDirectory = makeTemporaryDirectory()
        try FileManager.default.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
        let directory = baseDirectory.appendingPathComponent("not-a-directory")
        try Data().write(to: directory)
        let service = ConfigurationService(store: ConfigurationStore(directoryURL: directory))

        do {
            try await service.save(Configuration())
            XCTFail("Expected save to fail")
        } catch {
            // The store must surface the filesystem failure to its caller.
        }
    }

    func testFailedBackupReplacementPreservesPreviousBackup() async throws {
        let store = ConfigurationStore(directoryURL: makeTemporaryDirectory())
        let service = ConfigurationService(
            store: store,
            replaceItem: { _, _ in throw CocoaError(.fileWriteUnknown) }
        )
        try await service.save(Configuration())
        try Data("previous-backup".utf8).write(to: store.backupURL)

        do {
            try await service.createBackup()
            XCTFail("Expected injected backup replacement failure")
        } catch {
            XCTAssertEqual(try Data(contentsOf: store.backupURL), Data("previous-backup".utf8))
        }
    }

    func testBackupDiscoveryAndRestore() async throws {
        let service = makeService()
        let initiallyHasBackup = await service.hasBackup()
        XCTAssertFalse(initiallyHasBackup)
        try await service.save(Configuration())
        try await service.createBackup()
        let hasCreatedBackup = await service.hasBackup()
        XCTAssertTrue(hasCreatedBackup)

        let store = await service.store
        try Data("corrupt current file".utf8).write(to: store.configurationURL)
        _ = try await service.restoreBackup()

        guard case .loaded = try await service.loadResult() else {
            return XCTFail("Restore should atomically replace the current configuration")
        }
        let stillHasBackup = await service.hasBackup()
        XCTAssertTrue(stillHasBackup)
    }

    private func makeService() -> ConfigurationService {
        ConfigurationService(store: ConfigurationStore(directoryURL: makeTemporaryDirectory()))
    }

    private func makeTemporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("MousePlusTests-\(UUID().uuidString)", isDirectory: true)
        temporaryDirectories.append(url)
        return url
    }
}
