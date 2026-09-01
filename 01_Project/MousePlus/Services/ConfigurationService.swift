import Foundation

/// Handles loading and saving configuration to disk
protocol ConfigurationPersisting: Sendable {
    func loadResult() async throws -> ConfigurationService.LoadResult
    func save(_ configuration: Configuration) async throws
    func hasBackup() async -> Bool
    func createBackup() async throws
    func loadBackup() async throws -> Configuration
}

enum ConfigurationRecoveryError: Error {
    case unsupported
}

extension ConfigurationPersisting {
    func hasBackup() async -> Bool { false }
    func createBackup() async throws { throw ConfigurationRecoveryError.unsupported }
    func loadBackup() async throws -> Configuration { throw ConfigurationRecoveryError.unsupported }
}

actor ConfigurationService: ConfigurationPersisting {
    enum LoadResult: Sendable {
        case defaults(Configuration)
        case loaded(Configuration)

        var configuration: Configuration {
            switch self {
            case .defaults(let configuration), .loaded(let configuration):
                configuration
            }
        }
    }

    private let fileManager: FileManager
    private let replaceItem: @Sendable (URL, URL) throws -> Void
    let store: ConfigurationStore

    init(
        store: ConfigurationStore = .production(),
        fileManager: FileManager = .default,
        replaceItem: (@Sendable (URL, URL) throws -> Void)? = nil
    ) {
        self.store = store
        self.fileManager = fileManager
        self.replaceItem = replaceItem ?? { original, replacement in
            _ = try FileManager.default.replaceItemAt(original, withItemAt: replacement)
        }
    }

    func load() async throws -> Configuration {
        try loadResult().configuration
    }

    /// Loads configuration while explicitly distinguishing a first run from an
    /// unreadable or undecodable existing file (which is thrown to the caller).
    func loadResult() throws -> LoadResult {
        guard fileManager.fileExists(atPath: store.configurationURL.path) else {
            return .defaults(Configuration())
        }

        return .loaded(try decode(at: store.configurationURL))
    }

    func save(_ configuration: Configuration) async throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(configuration)

        // Ensure directory exists
        let directory = store.configurationURL.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: directory.path) {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }

        try data.write(to: store.configurationURL, options: .atomic)
    }

    func reset() async throws {
        if fileManager.fileExists(atPath: store.configurationURL.path) {
            try fileManager.removeItem(at: store.configurationURL)
        }
    }

    /// Whether a durable pre-reset recovery point is available.
    func hasBackup() async -> Bool {
        fileManager.fileExists(atPath: store.backupURL.path)
    }

    /// Creates a validated backup without removing the previous backup first.
    func createBackup() async throws {
        let data = try Data(contentsOf: store.configurationURL)
        _ = try JSONDecoder().decode(Configuration.self, from: data)

        let directory = store.backupURL.deletingLastPathComponent()
        let stagedURL = directory.appendingPathComponent(
            ".\(store.backupURL.lastPathComponent).\(UUID().uuidString).tmp"
        )

        try data.write(to: stagedURL, options: [.atomic])
        do {
            if fileManager.fileExists(atPath: store.backupURL.path) {
                try replaceItem(store.backupURL, stagedURL)
            } else {
                try fileManager.moveItem(at: stagedURL, to: store.backupURL)
            }
        } catch {
            try? fileManager.removeItem(at: stagedURL)
            throw error
        }
    }

    /// Decodes the durable backup. Restoring is explicit and uses the normal
    /// atomic save path; the recovery point remains available afterward.
    func restoreBackup() async throws -> Configuration {
        let configuration = try await loadBackup()
        try await save(configuration)
        return configuration
    }

    func loadBackup() async throws -> Configuration {
        try decode(at: store.backupURL)
    }

    private func decode(at url: URL) throws -> Configuration {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(Configuration.self, from: data)
    }
}
