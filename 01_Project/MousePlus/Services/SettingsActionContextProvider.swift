import AppKit
import Combine

/// A safe external application target for actions tested from Settings.
struct SettingsActionTarget: Equatable, Sendable {
    let name: String
    let processIdentifier: pid_t
}

/// The current availability of the Settings Test Action context.
enum SettingsActionContextAvailability: Sendable {
    case available(target: SettingsActionTarget, context: ActionContext)
    case unavailable(reason: String)
}

struct SettingsRunningApplication: Equatable, Sendable {
    let name: String?
    let bundleIdentifier: String?
    let processIdentifier: pid_t
    let isTerminated: Bool
}

@MainActor
protocol SettingsWorkspaceProviding: AnyObject {
    var frontmostApplication: SettingsRunningApplication? { get }
    func runningApplication(processIdentifier: pid_t) -> SettingsRunningApplication?
    func observeApplicationActivations(_ handler: @escaping (SettingsRunningApplication) -> Void) -> AnyObject
}

@MainActor
private final class SystemSettingsWorkspace: SettingsWorkspaceProviding {
    private let workspace = NSWorkspace.shared

    var frontmostApplication: SettingsRunningApplication? {
        workspace.frontmostApplication.map(SettingsRunningApplication.init)
    }

    func runningApplication(processIdentifier: pid_t) -> SettingsRunningApplication? {
        NSRunningApplication(processIdentifier: processIdentifier).map(SettingsRunningApplication.init)
    }

    func observeApplicationActivations(
        _ handler: @escaping (SettingsRunningApplication) -> Void
    ) -> AnyObject {
        workspace.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: workspace,
            queue: .main
        ) { notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                    as? NSRunningApplication else { return }
            MainActor.assumeIsolated { handler(SettingsRunningApplication(app)) }
        } as NSObjectProtocol
    }
}

private extension SettingsRunningApplication {
    init(_ app: NSRunningApplication) {
        name = app.localizedName
        bundleIdentifier = app.bundleIdentifier
        processIdentifier = app.processIdentifier
        isTerminated = app.isTerminated
    }
}

/// Remembers the last safe non-MousePlus app for contextual actions tested in Settings.
///
/// The candidate is captured synchronously before Settings activates MousePlus, then
/// refreshed whenever another app activates. Context access revalidates the PID and
/// takes a fresh screen snapshot so stale processes and display changes are safe.
@MainActor
final class SettingsActionContextProvider: ObservableObject {
    static let noExternalTargetReason = "Open another application, then return to Settings to choose a safe test target."
    static let staleTargetReason = "The previously active application is no longer running."

    @Published private(set) var target: SettingsActionTarget?
    @Published private(set) var unavailableReason = noExternalTargetReason

    private let workspace: SettingsWorkspaceProviding
    private let ownProcessIdentifier: pid_t
    private let ownBundleIdentifier: String?
    private let captureScreens: @MainActor () -> ScreenLayout
    private var activationObserver: AnyObject?

    convenience init() {
        self.init(
            workspace: SystemSettingsWorkspace(),
            ownProcessIdentifier: ProcessInfo.processInfo.processIdentifier,
            ownBundleIdentifier: Bundle.main.bundleIdentifier,
            captureScreens: ScreenLayout.capture
        )
    }

    init(
        workspace: SettingsWorkspaceProviding,
        ownProcessIdentifier: pid_t,
        ownBundleIdentifier: String?,
        captureScreens: @escaping @MainActor () -> ScreenLayout
    ) {
        self.workspace = workspace
        self.ownProcessIdentifier = ownProcessIdentifier
        self.ownBundleIdentifier = ownBundleIdentifier
        self.captureScreens = captureScreens
        activationObserver = workspace.observeApplicationActivations { [weak self] app in
            self?.recordIfSafe(app)
        }
    }

    /// Call immediately before activating MousePlus to open Settings.
    func recordFrontmostApplicationBeforeSettingsActivation() {
        guard let app = workspace.frontmostApplication else {
            markUnavailable(Self.noExternalTargetReason)
            return
        }
        recordIfSafe(app)
    }

    var availability: SettingsActionContextAvailability {
        guard let target else {
            return .unavailable(reason: unavailableReason)
        }
        guard let app = workspace.runningApplication(processIdentifier: target.processIdentifier),
              !app.isTerminated, isExternal(app) else {
            self.target = nil
            unavailableReason = Self.staleTargetReason
            return .unavailable(reason: Self.staleTargetReason)
        }
        return .available(
            target: target,
            context: ActionContext(
                frontmostPID: target.processIdentifier,
                screenLayout: captureScreens()
            )
        )
    }

    private func recordIfSafe(_ app: SettingsRunningApplication) {
        guard !app.isTerminated, isExternal(app) else { return }
        let name = app.name?.trimmingCharacters(in: .whitespacesAndNewlines)
        target = SettingsActionTarget(
            name: name?.isEmpty == false ? name! : "Application",
            processIdentifier: app.processIdentifier
        )
        unavailableReason = Self.noExternalTargetReason
    }

    private func isExternal(_ app: SettingsRunningApplication) -> Bool {
        guard app.processIdentifier != ownProcessIdentifier else { return false }
        if let ownBundleIdentifier, app.bundleIdentifier == ownBundleIdentifier { return false }
        return true
    }

    private func markUnavailable(_ reason: String) {
        target = nil
        unavailableReason = reason
    }
}
