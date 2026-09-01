import Foundation
import Observation

protocol TestActionExecuting: Sendable {
    func execute(_ item: RingMenuItem, context: ActionContext) async -> ActionExecutionResult
}

extension ActionService: TestActionExecuting {}

@MainActor
@Observable
final class TestActionController {
    private let coordinator: SettingsWorkspaceCoordinator
    private let actionService: any TestActionExecuting
    private let resultRouter: ActionResultRouter

    private(set) var displayedResult: SettingsActionResult?
    private(set) var saveFailureMessage: String?
    private(set) var isRunning = false

    init(
        coordinator: SettingsWorkspaceCoordinator,
        actionService: any TestActionExecuting = ActionService(),
        resultRouter: ActionResultRouter = ActionResultRouter()
    ) {
        self.coordinator = coordinator
        self.actionService = actionService
        self.resultRouter = resultRouter
    }

    func presentation(
        for item: RingMenuItem,
        contextAvailability: SettingsActionContextAvailability
    ) -> TestActionPresentation {
        let resolved = Self.resolveContext(for: item, availability: contextAvailability)
        let validation = ActionValidation.validate(item, context: resolved.context)
        return TestActionPresentation(
            isEnabled: validation.isValid && !isRunning,
            explanation: resolved.unavailableReason ?? validation.userFacingText,
            targetName: resolved.targetName
        )
    }

    /// The persistence flush is deliberately part of this orchestration method:
    /// no caller can accidentally execute a dirty editor value first.
    func test(
        _ item: RingMenuItem,
        contextAvailability: SettingsActionContextAvailability
    ) async {
        guard !isRunning else { return }
        let resolved = Self.resolveContext(for: item, availability: contextAvailability)
        let validation = ActionValidation.validate(item, context: resolved.context)
        guard validation.isValid else { return }

        isRunning = true
        saveFailureMessage = nil
        defer { isRunning = false }

        guard await coordinator.flush() else {
            switch coordinator.status {
            case .saveFailed(let message), .loadFailed(let message):
                saveFailureMessage = message
            default:
                saveFailureMessage = "The latest changes could not be saved, so the action was not tested."
            }
            return
        }
        // Context can become stale while a save is in flight. The provider gives
        // us value snapshots, so the service still validates the exact snapshot
        // that the pane named before performing any side effect.
        let result = await actionService.execute(item, context: resolved.context)
        displayedResult = await resultRouter.routeSettingsResult(result, for: item.id)
    }

    func restoreResult(for itemID: UUID) async {
        displayedResult = await resultRouter.settingsResult(for: itemID)
    }

    func itemDidEdit(_ itemID: UUID) async {
        saveFailureMessage = nil
        await resultRouter.dismissSettingsResult(for: itemID)
        if displayedResult?.itemID == itemID { displayedResult = nil }
    }

    func dismissResult() async {
        saveFailureMessage = nil
        guard let displayedResult else { return }
        await resultRouter.dismissSettingsResult(
            id: displayedResult.id,
            for: displayedResult.itemID
        )
        if self.displayedResult?.id == displayedResult.id {
            self.displayedResult = nil
        }
    }

    private static func resolveContext(
        for item: RingMenuItem,
        availability: SettingsActionContextAvailability
    ) -> (context: ActionContext, targetName: String?, unavailableReason: String?) {
        guard item.actionType == .windowSnap else { return (.init(), nil, nil) }
        switch availability {
        case .available(let target, let context): return (context, target.name, nil)
        case .unavailable(let reason): return (.init(), nil, reason)
        }
    }
}

struct TestActionPresentation: Equatable {
    let isEnabled: Bool
    let explanation: String?
    let targetName: String?
}
