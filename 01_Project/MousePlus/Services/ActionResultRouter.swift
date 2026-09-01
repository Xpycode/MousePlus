import Foundation

/// A presentation-neutral destination that the app layer can translate into
/// selection and window activation.
enum ActionSettingsRoute: Equatable, Sendable {
    case menuItem(UUID)
}

struct SettingsActionResult: Equatable, Identifiable, Sendable {
    let id: UUID
    let itemID: UUID
    let result: ActionExecutionResult

    init(id: UUID = UUID(), itemID: UUID, result: ActionExecutionResult) {
        self.id = id
        self.itemID = itemID
        self.result = result
    }
}

struct RuntimeActionFailure: Equatable, Sendable {
    let message: String
    let settingsRoute: ActionSettingsRoute
}

/// Routes action results while remaining independent of any presentation
/// framework. Settings results are retained per item. Runtime failures are
/// forwarded to a sink (for example, an error HUD); runtime successes are
/// intentionally silent.
actor ActionResultRouter {
    typealias RuntimeFailureSink = @Sendable (RuntimeActionFailure) async -> Void

    private var settingsResults: [UUID: SettingsActionResult] = [:]
    private let runtimeFailureSink: RuntimeFailureSink

    init(runtimeFailureSink: @escaping RuntimeFailureSink = { _ in }) {
        self.runtimeFailureSink = runtimeFailureSink
    }

    @discardableResult
    func routeSettingsResult(
        _ result: ActionExecutionResult,
        for itemID: UUID
    ) -> SettingsActionResult {
        let retained = SettingsActionResult(itemID: itemID, result: result)
        settingsResults[itemID] = retained
        return retained
    }

    func settingsResult(for itemID: UUID) -> SettingsActionResult? {
        settingsResults[itemID]
    }

    func dismissSettingsResult(for itemID: UUID) {
        settingsResults[itemID] = nil
    }

    /// Dismisses only the result the caller actually displayed. A delayed
    /// dismissal cannot erase a newer retry result for the same item.
    func dismissSettingsResult(id resultID: UUID, for itemID: UUID) {
        guard settingsResults[itemID]?.id == resultID else { return }
        settingsResults[itemID] = nil
    }

    func routeRuntimeResult(
        _ result: ActionExecutionResult,
        for itemID: UUID
    ) async {
        guard !result.isSuccess else { return }
        await runtimeFailureSink(RuntimeActionFailure(
            message: result.userFacingText,
            settingsRoute: .menuItem(itemID)
        ))
    }
}
