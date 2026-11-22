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
            isEnabled: validation.isValid && !isRunning && !resolved.blocksExecution,
            explanation: resolved.unavailableReason ?? validation.userFacingText,
            targetName: resolved.targetName
        )
    }

    /// Accessibility value for the Test Action button. `sourceLabel` names where
    /// the item comes from (for example "from Global" or "only in Safari") and is
    /// only added to a shown result; `nil` keeps the plain Global wording.
    func accessibilityValue(
        for displayedResult: SettingsActionResult?,
        presentation: TestActionPresentation,
        sourceLabel: String? = nil
    ) -> String {
        if let displayedResult {
            let source = sourceLabel.map { " Item \($0)." } ?? ""
            return "\(displayedResult.result.userFacingText).\(source) Activate to dismiss."
        }
        return presentation.explanation ?? (isRunning ? "Testing" : "Ready")
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
        guard validation.isValid, !resolved.blocksExecution else { return }

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
    ) -> ResolvedTestContext {
        switch item.actionType {
        case .windowSnap:
            switch availability {
            case .available(let target, let context):
                return ResolvedTestContext(context: context, targetName: target.name)
            case .unavailable(let reason):
                return ResolvedTestContext(unavailableReason: reason)
            }
        case .sendKeystroke:
            // Settings is frontmost while testing, so the keystroke would land on
            // MousePlus itself. Hand focus to the remembered app before posting.
            switch availability {
            case .available(let target, var context):
                context.returnsFocusToTarget = true
                return ResolvedTestContext(context: context, targetName: target.name)
            case .unavailable(let reason):
                return ResolvedTestContext(unavailableReason: reason, blocksExecution: true)
            }
        default:
            return ResolvedTestContext()
        }
    }
}

private struct ResolvedTestContext {
    var context = ActionContext()
    var targetName: String?
    var unavailableReason: String?
    /// Validation alone cannot reject a keystroke without a target, because the
    /// live ring may legitimately post one to whatever is frontmost.
    var blocksExecution = false
}

struct TestActionPresentation: Equatable {
    let isEnabled: Bool
    let explanation: String?
    let targetName: String?
}
