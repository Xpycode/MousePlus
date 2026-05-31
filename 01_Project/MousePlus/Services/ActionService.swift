import AppKit

/// Context an action may need from the main actor at fire time — captured by the
/// view model (which is `@MainActor`) and passed across the actor boundary as
/// `Sendable` values (HUD_ACTIONS_PLAN §1, §B).
struct ActionContext: Sendable {
    /// Frontmost app PID captured at ring-open (window/menu actions target the
    /// user's app, not our non-activating panel).
    var frontmostPID: pid_t?
    /// Screen geometry snapshot for window snapping.
    var screenLayout: ScreenLayout?

    init(frontmostPID: pid_t? = nil, screenLayout: ScreenLayout? = nil) {
        self.frontmostPID = frontmostPID
        self.screenLayout = screenLayout
    }
}

/// Executes actions triggered from the ring menu.
actor ActionService {

    private let windowService = WindowService()

    func execute(_ item: RingMenuItem, context: ActionContext = .init()) async throws {
        switch item.actionType {
        case .appSwitch:
            try await switchToApp(bundleID: item.actionData)

        case .windowSnap:
            try await snapWindow(item.actionData, context: context)

        case .menuBar:
            // HUD Feature A — not yet implemented.
            throw ActionError.notImplemented(.menuBar)

        case .systemToggle:
            // HUD Feature D — not yet implemented.
            throw ActionError.notImplemented(.systemToggle)

        case .screenshot:
            // HUD Feature E — not yet implemented.
            throw ActionError.notImplemented(.screenshot)

        case .custom:
            try await runCommand(item.actionData)
        }
    }

    // MARK: - Window snap (HUD Feature B)

    private func snapWindow(_ rawZone: String, context: ActionContext) async throws {
        guard let zone = SnapZone(rawValue: rawZone) else { return }   // parent marker / bad data → no-op
        guard let pid = context.frontmostPID, let layout = context.screenLayout else {
            throw ActionError.missingContext
        }
        try await windowService.snap(zone, pid: pid, layout: layout)
    }

    // MARK: - App switch

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
    case missingContext
    case notImplemented(ActionType)

    var errorDescription: String? {
        switch self {
        case .appNotFound(let bundleID):
            "Application not found: \(bundleID)"
        case .commandFailed(let command):
            "Command failed: \(command)"
        case .missingContext:
            "Action is missing the context it needs (front app / screen layout)."
        case .notImplemented(let type):
            "\(type.displayName) is not implemented yet."
        }
    }
}
