import AppKit

/// Main-actor state captured before action execution and passed as values.
struct ActionContext: Sendable {
    var frontmostPID: pid_t?
    var screenLayout: ScreenLayout?

    init(frontmostPID: pid_t? = nil, screenLayout: ScreenLayout? = nil) {
        self.frontmostPID = frontmostPID
        self.screenLayout = screenLayout
    }
}

protocol ActionProcessRunning: Sendable {
    func run(command: String) async throws -> Int32
}

struct SystemActionProcessRunner: ActionProcessRunning {
    func run(command: String) async throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", command]

        return try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { process in
                continuation.resume(returning: process.terminationStatus)
            }
            do {
                try process.run()
            } catch {
                process.terminationHandler = nil
                continuation.resume(throwing: error)
            }
        }
    }
}

protocol ActionWorkspace: Sendable {
    func activateOrLaunch(bundleIdentifier: String) async throws -> Bool
}

struct SystemActionWorkspace: ActionWorkspace {
    @MainActor
    func activateOrLaunch(bundleIdentifier: String) async throws -> Bool {
        if let app = NSWorkspace.shared.runningApplications.first(where: {
            $0.bundleIdentifier == bundleIdentifier
        }) {
            return app.activate()
        }
        guard let url = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: bundleIdentifier
        ) else {
            throw ActionServiceError.applicationNotFound(bundleIdentifier)
        }
        return try await NSWorkspace.shared
            .openApplication(at: url, configuration: .init())
            .activate()
    }
}

protocol ActionKeystrokeSending: Sendable {
    func send(keyCode: UInt16, flags: CGEventFlags) async throws
}

extension KeystrokeService: ActionKeystrokeSending {}

protocol ActionWindowSnapping: Sendable {
    func snap(_ zone: SnapZone, pid: pid_t, layout: ScreenLayout) async throws
}

extension WindowService: ActionWindowSnapping {}

/// Executes actions without knowing how their results will be presented.
actor ActionService {
    private let processRunner: any ActionProcessRunning
    private let workspace: any ActionWorkspace
    private let keystrokeService: any ActionKeystrokeSending
    private let windowService: any ActionWindowSnapping

    init(
        processRunner: any ActionProcessRunning = SystemActionProcessRunner(),
        workspace: any ActionWorkspace = SystemActionWorkspace(),
        keystrokeService: any ActionKeystrokeSending = KeystrokeService(),
        windowService: any ActionWindowSnapping = WindowService()
    ) {
        self.processRunner = processRunner
        self.workspace = workspace
        self.keystrokeService = keystrokeService
        self.windowService = windowService
    }

    func execute(_ item: RingMenuItem, context: ActionContext = .init()) async -> ActionExecutionResult {
        let validation = ActionValidation.validate(item, context: context)
        guard validation.isValid else {
            return ActionExecutionResult(validation: validation)
        }

        do {
            switch item.actionType {
            case .appSwitch:
                guard try await workspace.activateOrLaunch(bundleIdentifier: item.actionData) else {
                    throw ActionServiceError.activationFailed(item.actionData)
                }
            case .windowSnap:
                try await windowService.snap(
                    SnapZone(rawValue: item.actionData)!,
                    pid: context.frontmostPID!,
                    layout: context.screenLayout!
                )
            case .sendKeystroke:
                guard case let .key(keyCode, modifiers)? = item.keystrokePayload else {
                    return ActionExecutionResult(validation: validation)
                }
                try await keystrokeService.send(
                    keyCode: keyCode,
                    flags: CGEventFlags(rawValue: UInt64(modifiers))
                )
            case .custom:
                let status = try await processRunner.run(command: item.actionData)
                guard status == 0 else { throw ActionServiceError.commandExited(status) }
            case .menuBar, .systemToggle, .screenshot, .unavailable:
                return ActionExecutionResult(validation: validation)
            }
            return .completed
        } catch {
            return .failed(message: Self.message(for: error))
        }
    }

    private static func message(for error: Error) -> String {
        if let localized = error as? LocalizedError,
           let description = localized.errorDescription,
           !description.isEmpty {
            return description
        }
        let description = error.localizedDescription
        return description.isEmpty ? "The action could not be completed." : description
    }
}

enum ActionServiceError: LocalizedError, Equatable {
    case applicationNotFound(String)
    case activationFailed(String)
    case commandExited(Int32)

    var errorDescription: String? {
        switch self {
        case .applicationNotFound(let bundleIdentifier):
            "Application not found: \(bundleIdentifier)"
        case .activationFailed:
            "The application could not be activated."
        case .commandExited(let status):
            "The command exited with status \(status)."
        }
    }
}
