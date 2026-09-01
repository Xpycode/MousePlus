import Foundation
import XCTest
@testable import MousePlus

@MainActor
final class TestActionControllerTests: XCTestCase {
    func testDirtyEditIsSavedBeforeActionExecution() async {
        let events = TestActionEvents()
        let persistence = TestActionPersistence(configuration: Configuration(), events: events)
        let coordinator = makeCoordinator(persistence)
        await coordinator.load()
        coordinator.edit([.behavior]) { $0.behavior.dismissOnEscape.toggle() }
        let executor = TestActionExecutor(events: events, result: .completed)
        let controller = TestActionController(coordinator: coordinator, actionService: executor)
        let item = directItem()

        await controller.test(item, contextAvailability: .unavailable(reason: "unused"))

        let recordedEvents = await events.snapshot()
        XCTAssertEqual(recordedEvents, ["save", "execute"])
        XCTAssertEqual(controller.displayedResult?.result, .completed)
    }

    func testSaveFailurePreventsExecutionAndKeepsWorkspaceFailure() async {
        let events = TestActionEvents()
        let persistence = TestActionPersistence(
            configuration: Configuration(),
            events: events,
            saveError: TestActionFailure.write
        )
        let coordinator = makeCoordinator(persistence)
        await coordinator.load()
        coordinator.edit([.behavior]) { $0.behavior.dismissOnEscape.toggle() }
        let executor = TestActionExecutor(events: events, result: .completed)
        let controller = TestActionController(coordinator: coordinator, actionService: executor)

        await controller.test(directItem(), contextAvailability: .unavailable(reason: "unused"))

        let recordedEvents = await events.snapshot()
        XCTAssertEqual(recordedEvents, ["save"])
        XCTAssertNil(controller.displayedResult)
        XCTAssertFalse(controller.saveFailureMessage?.isEmpty ?? true)
        guard case .saveFailed = coordinator.status else { return XCTFail("Expected save failure") }
    }

    func testContextualPresentationNamesTargetAndExplainsUnavailableTarget() {
        let coordinator = makeCoordinator(TestActionPersistence(configuration: Configuration()))
        let controller = TestActionController(coordinator: coordinator)
        let item = RingMenuItem(
            label: "Left",
            icon: "rectangle.lefthalf.inset.filled",
            actionType: .windowSnap,
            actionData: SnapZone.left.rawValue
        )
        let layout = ScreenLayout(screens: [], primaryMaxY: 0, cursorPoint: .zero)
        let available = controller.presentation(
            for: item,
            contextAvailability: .available(
                target: SettingsActionTarget(name: "Notes", processIdentifier: 42),
                context: ActionContext(frontmostPID: 42, screenLayout: layout)
            )
        )
        XCTAssertTrue(available.isEnabled)
        XCTAssertEqual(available.targetName, "Notes")

        let unavailable = controller.presentation(
            for: item,
            contextAvailability: .unavailable(reason: "Return from another app first.")
        )
        XCTAssertFalse(unavailable.isEnabled)
        XCTAssertEqual(unavailable.explanation, "Return from another app first.")
    }

    func testContainersAndUnavailableActionsCannotExecuteOrReportSuccess() async {
        let events = TestActionEvents()
        let coordinator = makeCoordinator(TestActionPersistence(configuration: Configuration()))
        await coordinator.load()
        let executor = TestActionExecutor(events: events, result: .completed)
        let controller = TestActionController(coordinator: coordinator, actionService: executor)
        let child = directItem()
        let container = RingMenuItem(
            label: "Apps", icon: "square.grid.2x2", actionType: .appSwitch, subItems: [child]
        )
        let unavailable = RingMenuItem(
            label: "Future", icon: "questionmark", actionType: .unavailable("future")
        )

        await controller.test(container, contextAvailability: .unavailable(reason: "unused"))
        await controller.test(unavailable, contextAvailability: .unavailable(reason: "unused"))

        let recordedEvents = await events.snapshot()
        XCTAssertTrue(recordedEvents.isEmpty)
        XCTAssertNil(controller.displayedResult)
        XCTAssertFalse(controller.presentation(for: container, contextAvailability: .unavailable(reason: "unused")).isEnabled)
        XCTAssertFalse(controller.presentation(for: unavailable, contextAvailability: .unavailable(reason: "unused")).isEnabled)
    }

    func testResultPersistsUntilEditRetryOrDismiss() async {
        let events = TestActionEvents()
        let coordinator = makeCoordinator(TestActionPersistence(configuration: Configuration()))
        await coordinator.load()
        let item = directItem()
        let executor = TestActionExecutor(events: events, result: .failed(message: "Denied"))
        let router = ActionResultRouter()
        let controller = TestActionController(
            coordinator: coordinator,
            actionService: executor,
            resultRouter: router
        )
        await controller.test(item, contextAvailability: .unavailable(reason: "unused"))
        XCTAssertEqual(controller.displayedResult?.result, .failed(message: "Denied"))

        let secondController = TestActionController(
            coordinator: coordinator,
            actionService: executor,
            resultRouter: router
        )
        await secondController.restoreResult(for: item.id)
        XCTAssertEqual(secondController.displayedResult?.result, .failed(message: "Denied"))
        await secondController.itemDidEdit(item.id)
        XCTAssertNil(secondController.displayedResult)
        let retained = await router.settingsResult(for: item.id)
        XCTAssertNil(retained)
    }

    private func directItem() -> RingMenuItem {
        RingMenuItem(label: "Command", icon: "terminal", actionType: .custom, actionData: "true")
    }

    private func makeCoordinator(_ persistence: TestActionPersistence) -> SettingsWorkspaceCoordinator {
        SettingsWorkspaceCoordinator(
            persistence: persistence,
            debounceClock: TestActionLongClock()
        )
    }
}

private struct TestActionLongClock: WorkspaceDebounceClock {
    func sleep() async throws { try await Task.sleep(for: .seconds(60)) }
}

private enum TestActionFailure: Error { case write }

private actor TestActionEvents {
    private(set) var values: [String] = []
    func append(_ value: String) { values.append(value) }
    func snapshot() -> [String] { values }
}

private actor TestActionPersistence: ConfigurationPersisting {
    private var configuration: Configuration
    private let events: TestActionEvents?
    private let saveError: Error?

    init(configuration: Configuration, events: TestActionEvents? = nil, saveError: Error? = nil) {
        self.configuration = configuration
        self.events = events
        self.saveError = saveError
    }

    func loadResult() -> ConfigurationService.LoadResult { .loaded(configuration) }

    func save(_ configuration: Configuration) async throws {
        await events?.append("save")
        if let saveError { throw saveError }
        self.configuration = configuration
    }
}

private actor TestActionExecutor: TestActionExecuting {
    let events: TestActionEvents
    let result: ActionExecutionResult

    init(events: TestActionEvents, result: ActionExecutionResult) {
        self.events = events
        self.result = result
    }

    func execute(_ item: RingMenuItem, context: ActionContext) async -> ActionExecutionResult {
        await events.append("execute")
        return result
    }
}
