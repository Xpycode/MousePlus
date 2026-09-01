import CoreGraphics
import Observation

protocol PostEventPermissionChecking {
    func preflight() -> Bool
    func request() -> Bool
}

struct SystemPostEventPermissionChecker: PostEventPermissionChecking {
    func preflight() -> Bool { CGPreflightPostEventAccess() }
    func request() -> Bool { CGRequestPostEventAccess() }
}

/// UI-facing state for the separate permission that gates synthetic keystrokes.
/// Merely refreshing this state never prompts; requesting is reserved for an
/// explicit user action in Settings.
@MainActor
@Observable
final class PostEventPermissionsState {
    private(set) var isGranted: Bool
    private let checker: any PostEventPermissionChecking

    init(checker: any PostEventPermissionChecking = SystemPostEventPermissionChecker()) {
        self.checker = checker
        self.isGranted = checker.preflight()
    }

    func refresh() {
        isGranted = checker.preflight()
    }

    func requestFromUserAction() {
        _ = checker.request()
        refresh()
    }
}
