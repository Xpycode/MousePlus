import Foundation

/// The filesystem locations used for configuration persistence.
///
/// Keeping these paths in a value makes production and isolated test stores use
/// exactly the same persistence implementation.
struct ConfigurationStore: Sendable {
    let configurationURL: URL
    let backupURL: URL

    init(
        directoryURL: URL,
        configurationFilename: String = "config.json",
        backupFilename: String = "config.pre-reset.json"
    ) {
        configurationURL = directoryURL.appendingPathComponent(configurationFilename)
        backupURL = directoryURL.appendingPathComponent(backupFilename)
    }

    static func production(fileManager: FileManager = .default) -> ConfigurationStore {
        let applicationSupport = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        return ConfigurationStore(
            directoryURL: applicationSupport.appendingPathComponent("MousePlus", isDirectory: true)
        )
    }
}
