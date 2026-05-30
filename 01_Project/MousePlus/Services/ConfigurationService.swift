import Foundation

/// Handles loading and saving configuration to disk
actor ConfigurationService {
    private let fileManager = FileManager.default

    private var configURL: URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appFolder = appSupport.appendingPathComponent("MousePlus", isDirectory: true)
        return appFolder.appendingPathComponent("config.json")
    }

    func load() async throws -> Configuration {
        guard fileManager.fileExists(atPath: configURL.path) else {
            return Configuration()
        }

        let data = try Data(contentsOf: configURL)
        let decoder = JSONDecoder()
        return try decoder.decode(Configuration.self, from: data)
    }

    func save(_ configuration: Configuration) async throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(configuration)

        // Ensure directory exists
        let directory = configURL.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: directory.path) {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }

        try data.write(to: configURL, options: .atomic)
    }

    func reset() async throws {
        if fileManager.fileExists(atPath: configURL.path) {
            try fileManager.removeItem(at: configURL)
        }
    }
}
