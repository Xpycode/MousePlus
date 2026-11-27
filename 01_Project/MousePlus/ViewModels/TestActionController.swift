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
        contextAvailability: SettingsActionContextAvailability,
        refresh: (() -> SettingsActionContextAvailability)? = nil
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
        // Keep the recipient shown at click time even if focus or the profile changes during save.
        let latest = refresh.map { Self.resolveContext(for: item, availability: $0()) } ?? resolved
        guard !latest.blocksExecution, latest.unavailableReason == nil,
              latest.context.frontmostPID == resolved.context.frontmostPID else {
            let message = latest.unavailableReason ?? "The test recipient changed. Check the recipient and try again."
            displayedResult = await resultRouter.routeSettingsResult(.failed(message: message), for: item.id)
            return
        }
        let result = await actionService.execute(item, context: latest.context)
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
        if case .profileAppClosed(let reason) = availability {
            return ResolvedTestContext(unavailableReason: reason, blocksExecution: true)
        }
        switch item.actionType {
        case .windowSnap, .sendKeystroke:
            switch availability {
            case .available(let target, var context):
                if item.actionType == .sendKeystroke {
                    context.returnsFocusToTarget = true
                    context.keystrokeDestination = .process(target.processIdentifier)
                }
                return ResolvedTestContext(context: context, targetName: target.name)
            case .unavailable(let reason), .profileAppClosed(let reason):
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
