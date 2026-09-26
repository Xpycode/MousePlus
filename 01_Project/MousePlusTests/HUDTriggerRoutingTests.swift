import AppKit
import XCTest
@testable import MousePlus

@MainActor
final class HUDTriggerRoutingTests: XCTestCase {
    func testMissingGlobalShortcutKeepsLegacyConfigurationCompatibleAndUnbound() throws {
        let json = """
        {
          "keyboard": { "keyboard": { "keyCode": 96, "modifiers": 1048576, "mode": "holdRelease" } },
          "mouseButton": { "none": {} },
          "openSettings": { "keyboard": { "keyCode": 43, "modifiers": 1572864, "mode": "holdRelease" } }
        }
        """

        let decoded = try JSONDecoder().decode(TriggersConfig.self, from: Data(json.utf8))

        XCTAssertEqual(decoded.globalHUDShortcut, .none)
        XCTAssertEqual(
            decoded.keyboard,
            .keyboard(keyCode: 96, modifiers: 1_048_576, mode: .holdRelease)
        )
    }

    func testIndependentMonitorsEmitRouteModeAndStablePhysicalIdentity() async throws {
        let contextual = TestKeyboardTriggerMonitor()
        let global = TestKeyboardTriggerMonitor()
        let mouse = TestMouseButtonTriggerMonitor()
        let service = TriggerService(
            contextualKeyboardMonitor: contextual,
            globalKeyboardMonitor: global,
            mouseButtonMonitor: mouse
        )
        service.start(config: TriggersConfig(
            keyboard: .keyboard(keyCode: 96, modifiers: 1, mode: .holdRelease),
            mouseButton: .mouseButton(buttonNumber: 4, mode: .holdRelease),
            globalHUDShortcut: .keyboard(keyCode: 97, modifiers: 2, mode: .tapToggle)
        ))
        var iterator = service.events.makeAsyncIterator()

        contextual.sendDown()
        let contextualDown = await iterator.next()
        assertEvent(
            try XCTUnwrap(contextualDown), phase: .down,
            source: TriggerSource(
                route: .contextual,
                physicalSource: .keyboard(keyCode: 96, modifiers: 1)
            ),
            mode: .holdRelease
        )
        contextual.sendUp()
        let contextualUp = await iterator.next()
        assertEvent(
            try XCTUnwrap(contextualUp), phase: .up,
            source: TriggerSource(
                route: .contextual,
                physicalSource: .keyboard(keyCode: 96, modifiers: 1)
            ),
            mode: .holdRelease
        )
        global.sendDown()
        let globalDown = await iterator.next()
        assertEvent(
            try XCTUnwrap(globalDown), phase: .down,
            source: TriggerSource(
                route: .global,
                physicalSource: .keyboard(keyCode: 97, modifiers: 2)
            ),
            mode: .tapToggle
        )
        global.sendUp()
        let globalUp = await iterator.next()
        assertEvent(
            try XCTUnwrap(globalUp), phase: .up,
            source: TriggerSource(
                route: .global,
                physicalSource: .keyboard(keyCode: 97, modifiers: 2)
            ),
            mode: .tapToggle
        )

        let downPoint = CGPoint(x: 10, y: 20)
        let movePoint = CGPoint(x: 11, y: 21)
        let upPoint = CGPoint(x: 12, y: 22)
        mouse.sendDown(at: downPoint)
        let mouseDown = await iterator.next()
        assertEvent(
            try XCTUnwrap(mouseDown), phase: .down,
            source: TriggerSource(route: .contextual, physicalSource: .mouseButton(buttonNumber: 4)),
            mode: .holdRelease, point: downPoint
        )
        mouse.sendDragged(at: movePoint)
        let mouseMoved = await iterator.next()
        assertEvent(
            try XCTUnwrap(mouseMoved), phase: .moved,
            source: TriggerSource(route: .contextual, physicalSource: .mouseButton(buttonNumber: 4)),
            mode: .holdRelease, point: movePoint
        )
        mouse.sendUp(at: upPoint)
        let mouseUp = await iterator.next()
        assertEvent(
            try XCTUnwrap(mouseUp), phase: .up,
            source: TriggerSource(route: .contextual, physicalSource: .mouseButton(buttonNumber: 4)),
            mode: .holdRelease, point: upPoint
        )
    }

    func testUpdateAndStopDeterministicallyStopEveryMonitor() {
        let contextual = TestKeyboardTriggerMonitor()
        let global = TestKeyboardTriggerMonitor()
        let mouse = TestMouseButtonTriggerMonitor()
        let service = TriggerService(
            contextualKeyboardMonitor: contextual,
            globalKeyboardMonitor: global,
            mouseButtonMonitor: mouse
        )

        service.start(config: TriggersConfig(
            keyboard: .keyboard(keyCode: 1, modifiers: 2, mode: .holdRelease),
            mouseButton: .mouseButton(buttonNumber: 4, mode: .tapToggle),
            globalHUDShortcut: .keyboard(keyCode: 3, modifiers: 4, mode: .tapToggle)
        ))
        XCTAssertEqual([contextual.startCount, global.startCount, mouse.startCount], [1, 1, 1])
        XCTAssertEqual([contextual.stopCount, global.stopCount, mouse.stopCount], [1, 1, 1])

        service.updateConfig(TriggersConfig(
            globalHUDShortcut: .keyboard(keyCode: 8, modifiers: 16, mode: .holdRelease)
        ))
        XCTAssertEqual([contextual.stopCount, global.stopCount, mouse.stopCount], [2, 2, 2])
        XCTAssertEqual([contextual.startCount, global.startCount, mouse.startCount], [1, 2, 1])

        service.stop()
        XCTAssertEqual([contextual.stopCount, global.stopCount, mouse.stopCount], [3, 3, 3])
    }

    func testUnchangedLiveApplyDoesNotRestartHeldTriggerMonitors() {
        let contextual = TestKeyboardTriggerMonitor()
        let global = TestKeyboardTriggerMonitor()
        let mouse = TestMouseButtonTriggerMonitor()
        let service = TriggerService(
            contextualKeyboardMonitor: contextual,
            globalKeyboardMonitor: global,
            mouseButtonMonitor: mouse
        )
        let config = TriggersConfig(
            keyboard: .keyboard(keyCode: 1, modifiers: 2, mode: .holdRelease),
            mouseButton: .mouseButton(buttonNumber: 4, mode: .holdRelease),
            globalHUDShortcut: .keyboard(keyCode: 3, modifiers: 4, mode: .tapToggle)
        )
        service.start(config: config)
        contextual.sendDown()

        service.updateConfig(config)
        contextual.sendUp()

        XCTAssertEqual([contextual.startCount, global.startCount, mouse.startCount], [1, 1, 1])
        XCTAssertEqual([contextual.stopCount, global.stopCount, mouse.stopCount], [1, 1, 1])
    }

    func testChangingGlobalBindingDoesNotRestartHeldContextualMonitor() {
        let contextual = TestKeyboardTriggerMonitor()
        let global = TestKeyboardTriggerMonitor()
        let mouse = TestMouseButtonTriggerMonitor()
        let service = TriggerService(
            contextualKeyboardMonitor: contextual,
            globalKeyboardMonitor: global,
            mouseButtonMonitor: mouse
        )
        let initial = TriggersConfig(
            keyboard: .keyboard(keyCode: 1, modifiers: 2, mode: .holdRelease),
            mouseButton: .mouseButton(buttonNumber: 4, mode: .holdRelease),
            globalHUDShortcut: .keyboard(keyCode: 3, modifiers: 4, mode: .tapToggle)
        )
        service.start(config: initial)
        contextual.sendDown()

        var changed = initial
        changed.globalHUDShortcut = .keyboard(keyCode: 5, modifiers: 6, mode: .tapToggle)
        service.updateConfig(changed)
        contextual.sendUp()

        XCTAssertEqual([contextual.startCount, global.startCount, mouse.startCount], [1, 2, 1])
        XCTAssertEqual([contextual.stopCount, global.stopCount, mouse.stopCount], [1, 2, 1])
    }

    func testChangingNoncollidingContextualBindingDoesNotRestartHeldGlobalMonitor() {
        let contextual = TestKeyboardTriggerMonitor()
        let global = TestKeyboardTriggerMonitor()
        let service = TriggerService(
            contextualKeyboardMonitor: contextual,
            globalKeyboardMonitor: global,
            mouseButtonMonitor: TestMouseButtonTriggerMonitor()
        )
        let initial = TriggersConfig(
            keyboard: .keyboard(keyCode: 1, modifiers: 2, mode: .tapToggle),
            globalHUDShortcut: .keyboard(keyCode: 3, modifiers: 4, mode: .holdRelease)
        )
        service.start(config: initial)
        global.sendDown()

        var changed = initial
        changed.keyboard = .keyboard(keyCode: 5, modifiers: 6, mode: .tapToggle)
        service.updateConfig(changed)
        global.sendUp()

        XCTAssertEqual(contextual.startCount, 2)
        XCTAssertEqual(global.startCount, 1)
        XCTAssertEqual(global.stopCount, 1)
    }

    func testCollisionDrivenShutdownCancelsHeldGlobalBinding() async throws {
        let contextual = TestKeyboardTriggerMonitor()
        let global = TestKeyboardTriggerMonitor()
        let service = TriggerService(
            contextualKeyboardMonitor: contextual,
            globalKeyboardMonitor: global,
            mouseButtonMonitor: TestMouseButtonTriggerMonitor()
        )
        let globalBinding = TriggerBinding.keyboard(
            keyCode: 3, modifiers: 4, mode: .holdRelease
        )
        service.start(config: TriggersConfig(
            keyboard: .none,
            globalHUDShortcut: globalBinding
        ))
        var iterator = service.events.makeAsyncIterator()
        global.sendDown()
        _ = await iterator.next()

        service.updateConfig(TriggersConfig(
            keyboard: globalBinding,
            globalHUDShortcut: globalBinding
        ))

        let next = await iterator.next()
        guard case .cancel(let source) = try XCTUnwrap(next) else {
            return XCTFail("a held Global binding must be cancelled before its monitor stops")
        }
        XCTAssertEqual(source.route, .global)
        XCTAssertEqual(global.stopCount, 2)
    }

    func testExactKeyboardCollisionIgnoresModeAndRetainsPreviousGlobalBinding() {
        let contextual = TriggerBinding.keyboard(
            keyCode: 96, modifiers: 1_048_576, mode: .holdRelease
        )
        let previous = TriggerBinding.keyboard(
            keyCode: 97, modifiers: 524_288, mode: .tapToggle
        )
        let candidate = TriggerBinding.keyboard(
            keyCode: 96, modifiers: 1_048_576, mode: .tapToggle
        )

        XCTAssertEqual(
            HUDTriggerRouting.validateGlobalHUDShortcut(
                candidate, previous: previous, contextualKeyboard: contextual
            ),
            .rejected(collision: .contextualKeyboard, retained: previous)
        )
        XCTAssertFalse(HUDTriggerBindingCollision.contextualKeyboard.explanation.isEmpty)
    }

    func testNonExactAndEstablishedCrossSlotBindingsRemainAccepted() {
        let contextual = TriggerBinding.keyboard(
            keyCode: 96,
            modifiers: NSEvent.ModifierFlags.command.rawValue,
            mode: .holdRelease
        )
        let previous = TriggerBinding.none

        for candidate in [
            TriggerBinding.none,
            .keyboard(
                keyCode: 97,
                modifiers: NSEvent.ModifierFlags.command.rawValue,
                mode: .holdRelease
            ),
            .keyboard(
                keyCode: 96,
                modifiers: NSEvent.ModifierFlags.option.rawValue,
                mode: .holdRelease
            ),
            .mouseButton(buttonNumber: 4, mode: .tapToggle)
        ] {
            XCTAssertEqual(
                HUDTriggerRouting.validateGlobalHUDShortcut(
                    candidate, previous: previous, contextualKeyboard: contextual
                ),
                .accepted(candidate)
            )
        }
    }

    func testKeyboardMonitorRequiresExactNormalizedModifiersAndPairsRelease() throws {
        let tap = KeyboardTriggerEventTapStub()
        let monitor = KeyboardTriggerMonitor(eventTap: tap)
        var downCount = 0
        var upCount = 0
        monitor.start(
            keyCode: 96,
            modifiers: NSEvent.ModifierFlags.option.rawValue,
            onDown: { downCount += 1 },
            onUp: { upCount += 1 }
        )
        defer { monitor.stop() }

        XCTAssertEqual(
            tap.send(.keyDown(
                keyCode: 96,
                modifiers: NSEvent.ModifierFlags([.option, .shift]).rawValue,
                isRepeat: false
            )),
            .passThrough
        )
        XCTAssertEqual(tap.send(.keyUp(keyCode: 96)), .passThrough)
        XCTAssertEqual(downCount, 0)
        XCTAssertEqual(upCount, 0, "a rejected chord must not manufacture a release")

        XCTAssertEqual(
            tap.send(.keyDown(
                keyCode: 96,
                modifiers: NSEvent.ModifierFlags([.option, .capsLock, .function]).rawValue,
                isRepeat: false
            )),
            .consume
        )
        XCTAssertEqual(
            tap.send(.keyDown(
                keyCode: 96,
                modifiers: NSEvent.ModifierFlags.option.rawValue,
                isRepeat: true
            )),
            .consume
        )
        XCTAssertEqual(downCount, 1, "key repeat must not create a second ownership down")
        XCTAssertEqual(tap.send(.keyUp(keyCode: 96)), .consume)
        XCTAssertEqual(tap.send(.keyUp(keyCode: 96)), .passThrough)
        XCTAssertEqual(upCount, 1)

        XCTAssertEqual(tap.send(.tapDisabled), .passThrough)
        XCTAssertEqual(tap.reenableCount, 1)
    }

    func testKeyboardRecorderTakesPriorityOverActiveTriggerTap() {
        let tap = KeyboardTriggerEventTapStub()
        let monitor = KeyboardTriggerMonitor(eventTap: tap)
        var downCount = 0
        monitor.start(
            keyCode: 96,
            modifiers: NSEvent.ModifierFlags.option.rawValue,
            onDown: { downCount += 1 },
            onUp: {}
        )
        defer { monitor.stop() }

        let recorder = TriggerRecorderService()
        recorder.record(.keyboard)
        XCTAssertEqual(
            tap.send(.keyDown(
                keyCode: 96,
                modifiers: NSEvent.ModifierFlags.option.rawValue,
                isRepeat: false
            )),
            .passThrough
        )
        XCTAssertEqual(downCount, 0)
        recorder.cancel()

        XCTAssertEqual(
            tap.send(.keyDown(
                keyCode: 96,
                modifiers: NSEvent.ModifierFlags.option.rawValue,
                isRepeat: false
            )),
            .consume
        )
        XCTAssertEqual(downCount, 1)
    }

    func testContextualRecorderRejectsCollisionAndRetainsPreviousBinding() async throws {
        var initial = Configuration()
        let previous = TriggerBinding.keyboard(
            keyCode: 96, modifiers: NSEvent.ModifierFlags.command.rawValue, mode: .holdRelease
        )
        let global = TriggerBinding.keyboard(
            keyCode: 97, modifiers: NSEvent.ModifierFlags.option.rawValue, mode: .tapToggle
        )
        initial.triggers.keyboard = previous
        initial.triggers.globalHUDShortcut = global
        let persistence = RecordingConfigurationPersistenceForTrigger(initial)
        let coordinator = SettingsWorkspaceCoordinator(
            persistence: persistence,
            debounceClock: TriggerTestDebounceClock()
        )
        await coordinator.load()

        let collision = TriggersSettingsView.applyContextualKeyboard(
            global.withMode(.holdRelease),
            coordinator: coordinator
        )

        XCTAssertEqual(collision, .contextualKeyboard)
        XCTAssertEqual(coordinator.configuration.triggers.keyboard, previous)
        XCTAssertTrue(coordinator.dirtyFields.isEmpty)
    }

    func testCollidingPersistedConfigurationDoesNotArmAmbiguousGlobalMonitor() {
        let contextual = TestKeyboardTriggerMonitor()
        let global = TestKeyboardTriggerMonitor()
        let mouse = TestMouseButtonTriggerMonitor()
        let service = TriggerService(
            contextualKeyboardMonitor: contextual,
            globalKeyboardMonitor: global,
            mouseButtonMonitor: mouse
        )
        service.start(config: TriggersConfig(
            keyboard: .keyboard(keyCode: 96, modifiers: 1, mode: .holdRelease),
            globalHUDShortcut: .keyboard(keyCode: 96, modifiers: 1, mode: .tapToggle)
        ))

        XCTAssertEqual(contextual.startCount, 1)
        XCTAssertEqual(global.startCount, 0)
    }

    func testSettingsAcceptedShortcutSavesAndLiveAppliesWhileCollisionDoesNeither() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let persistence = ConfigurationService(store: ConfigurationStore(directoryURL: directory))
        var initial = Configuration()
        initial.triggers.keyboard = .keyboard(keyCode: 96, modifiers: 1, mode: .holdRelease)
        initial.triggers.globalHUDShortcut = .keyboard(keyCode: 97, modifiers: 2, mode: .tapToggle)
        try await persistence.save(initial)
        let liveApply = TriggerLiveApplyRecorder()
        let coordinator = SettingsWorkspaceCoordinator(
            persistence: persistence,
            debounceClock: TriggerTestDebounceClock(),
            liveApply: { liveApply.configurations.append($0) }
        )
        await coordinator.load()

        let accepted = TriggerBinding.keyboard(keyCode: 98, modifiers: 4, mode: .holdRelease)
        XCTAssertNil(TriggersSettingsView.applyGlobalHUDShortcut(accepted, coordinator: coordinator))
        XCTAssertEqual(coordinator.dirtyFields, [.triggers])
        let acceptedFlush = await coordinator.flush()
        XCTAssertTrue(acceptedFlush)
        let savedAccepted = try await persistence.load()
        XCTAssertEqual(savedAccepted.triggers.globalHUDShortcut, accepted)
        XCTAssertEqual(liveApply.configurations.last?.triggers.globalHUDShortcut, accepted)

        let eventCount = liveApply.configurations.count
        let collision = TriggerBinding.keyboard(keyCode: 96, modifiers: 1, mode: .tapToggle)
        XCTAssertEqual(
            TriggersSettingsView.applyGlobalHUDShortcut(collision, coordinator: coordinator),
            .contextualKeyboard
        )
        XCTAssertEqual(coordinator.configuration.triggers.globalHUDShortcut, accepted)
        XCTAssertTrue(coordinator.dirtyFields.isEmpty)
        let rejectedFlush = await coordinator.flush()
        XCTAssertTrue(rejectedFlush)
        let savedAfterRejection = try await persistence.load()
        XCTAssertEqual(savedAfterRejection.triggers.globalHUDShortcut, accepted)
        XCTAssertEqual(liveApply.configurations.count, eventCount)
    }

    private enum Phase: Equatable { case down, moved, up }

    private func assertEvent(
        _ event: TriggerEvent,
        phase: Phase,
        source: TriggerSource,
        mode: TriggerMode,
        point: CGPoint? = nil,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let actual: (Phase, TriggerSource, TriggerMode, CGPoint)
        switch event {
        case let .down(source, mode, point): actual = (.down, source, mode, point)
        case let .moved(source, mode, point): actual = (.moved, source, mode, point)
        case let .up(source, mode, point): actual = (.up, source, mode, point)
        case .cancel:
            return XCTFail("Expected a pointer event, received cancellation", file: file, line: line)
        }
        XCTAssertEqual(actual.0, phase, file: file, line: line)
        XCTAssertEqual(actual.1, source, file: file, line: line)
        XCTAssertEqual(actual.2, mode, file: file, line: line)
        if let point { XCTAssertEqual(actual.3, point, file: file, line: line) }
    }
}

@MainActor
private final class TestKeyboardTriggerMonitor: KeyboardTriggerMonitoring {
    private var onDown: (() -> Void)?
    private var onUp: (() -> Void)?
    private(set) var startCount = 0
    private(set) var stopCount = 0

    func start(
        keyCode: UInt16,
        modifiers: UInt,
        onDown: @escaping () -> Void,
        onUp: @escaping () -> Void
    ) {
        startCount += 1
        self.onDown = onDown
        self.onUp = onUp
    }

    func stop() {
        stopCount += 1
        onDown = nil
        onUp = nil
    }

    func sendDown() { onDown?() }
    func sendUp() { onUp?() }
}

@MainActor
private final class KeyboardTriggerEventTapStub: KeystrokeCaptureTapping {
    private var handler: ((KeystrokeCaptureEvent) -> KeystrokeCaptureDisposition)?
    private(set) var reenableCount = 0

    func start(
        handler: @escaping (KeystrokeCaptureEvent) -> KeystrokeCaptureDisposition
    ) throws {
        self.handler = handler
    }

    func reenable() {
        reenableCount += 1
    }

    func stop() {
        handler = nil
    }

    func send(_ event: KeystrokeCaptureEvent) -> KeystrokeCaptureDisposition {
        handler?(event) ?? .passThrough
    }
}

@MainActor
private final class TestMouseButtonTriggerMonitor: MouseButtonTriggerMonitoring {
    private var onDown: ((CGPoint) -> Void)?
    private var onDragged: ((CGPoint) -> Void)?
    private var onUp: ((CGPoint) -> Void)?
    private(set) var startCount = 0
    private(set) var stopCount = 0

    func start(
        buttonNumber: Int,
        onDown: @escaping (CGPoint) -> Void,
        onDragged: @escaping (CGPoint) -> Void,
        onUp: @escaping (CGPoint) -> Void
    ) {
        startCount += 1
        self.onDown = onDown
        self.onDragged = onDragged
        self.onUp = onUp
    }

    func stop() {
        stopCount += 1
        onDown = nil
        onDragged = nil
        onUp = nil
    }

    func sendDown(at point: CGPoint) { onDown?(point) }
    func sendDragged(at point: CGPoint) { onDragged?(point) }
    func sendUp(at point: CGPoint) { onUp?(point) }
}

private struct TriggerTestDebounceClock: WorkspaceDebounceClock {
    func sleep() async throws { try await Task.sleep(for: .seconds(60)) }
}

@MainActor
private final class TriggerLiveApplyRecorder {
    var configurations: [Configuration] = []
}

private actor RecordingConfigurationPersistenceForTrigger: ConfigurationPersisting {
    private var configuration: Configuration

    init(_ configuration: Configuration) {
        self.configuration = configuration
    }

    func loadResult() -> ConfigurationService.LoadResult {
        .loaded(configuration)
    }

    func save(_ configuration: Configuration) {
        self.configuration = configuration
    }

    func hasBackup() -> Bool { false }
    func createBackup() throws {}
    func loadBackup() throws -> Configuration { configuration }
}
