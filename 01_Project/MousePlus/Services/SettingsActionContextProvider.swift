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
    case profileAppClosed(reason: String)
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
    func runningApplications(bundleIdentifier: String) -> [SettingsRunningApplication]
    var runningApplicationsChanged: AnyPublisher<Void, Never> { get }
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

    func runningApplications(bundleIdentifier: String) -> [SettingsRunningApplication] {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
            .map(SettingsRunningApplication.init)
    }

    var runningApplicationsChanged: AnyPublisher<Void, Never> {
        let center = workspace.notificationCenter
        return center.publisher(for: NSWorkspace.didLaunchApplicationNotification)
            .merge(with: center.publisher(for: NSWorkspace.didTerminateApplicationNotification))
            .map { _ in () }
            .receive(on: DispatchQueue.main)
            .eraseToAnyPublisher()
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
    private var runningAppsObserver: AnyCancellable?
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
        runningAppsObserver = workspace.runningApplicationsChanged.sink { [weak self] in
            guard let self else { return }
            if let target, workspace.runningApplication(processIdentifier: target.processIdentifier)?.isTerminated != false {
                markUnavailable(Self.staleTargetReason)
            } else {
                objectWillChange.send()
            }
        }
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

    func availability(for profile: HUDProfileReference, appName: String?) -> SettingsActionContextAvailability {
        guard case .app(let identifier) = profile else { return availability }
        let name = appName ?? identifier
        guard let app = workspace.runningApplications(bundleIdentifier: identifier).first(where: {
            !$0.isTerminated && isExternal($0)
        }) else {
            return .profileAppClosed(reason: "Open \(name) to test actions in this profile.")
        }
        return availableContext(for: SettingsActionTarget(
            name: app.name ?? name, processIdentifier: app.processIdentifier
        ))
    }

    var availability: SettingsActionContextAvailability {
        guard let target else {
            return .unavailable(reason: unavailableReason)
        }
        guard let app = workspace.runningApplication(processIdentifier: target.processIdentifier),
              !app.isTerminated, isExternal(app) else {
            return .unavailable(reason: Self.staleTargetReason)
        }
        return availableContext(for: target)
    }

    private func availableContext(for target: SettingsActionTarget) -> SettingsActionContextAvailability {
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
