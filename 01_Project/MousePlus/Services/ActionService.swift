import AppKit

/// Executes actions triggered from the ring menu
actor ActionService {

    func execute(_ item: RingMenuItem) async throws {
        switch item.actionType {
        case .appSwitch:
            try await switchToApp(bundleID: item.actionData)

        case .clipboard:
            // TODO: Implement clipboard actions
            break

        case .menuBar:
            // TODO: Implement menu bar access
            break

        case .custom:
            try await runCommand(item.actionData)
        }
    }

    private func switchToApp(bundleID: String) async throws {
        guard !bundleID.isEmpty else { return }

        let workspace = NSWorkspace.shared

        // Try to activate existing instance first
        if let app = workspace.runningApplications.first(where: { $0.bundleIdentifier == bundleID }) {
            app.activate()
            return
        }

        // Launch if not running
        guard let url = workspace.urlForApplication(withBundleIdentifier: bundleID) else {
            throw ActionError.appNotFound(bundleID)
        }

        try await workspace.openApplication(at: url, configuration: .init())
    }

    private func runCommand(_ command: String) async throws {
        guard !command.isEmpty else { return }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", command]

        try process.run()
    }
}

enum ActionError: LocalizedError {
    case appNotFound(String)
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .appNotFound(let bundleID):
            "Application not found: \(bundleID)"
        case .commandFailed(let command):
            "Command failed: \(command)"
        }
    }
}
