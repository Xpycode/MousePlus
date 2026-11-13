import AppKit
import XCTest
@testable import MousePlus

/// Scripted trust sensor. No timers, no probe, no TCC access.
@MainActor
private final class FakeSensor: RuntimeTrustSensing {
    var trustReadIsFalse = false
    var probeResults: [Bool] = [true]
    private(set) var probeReasons: [String] = []
    private(set) var startCount = 0
    private(set) var stopCount = 0
    private var onLoss: (() -> Void)?

    func start(onLoss: @escaping () -> Void) { startCount += 1; self.onLoss = onLoss }
    func stop() { stopCount += 1; onLoss = nil }
    func requestProbe(reason: String) async -> Bool {
        probeReasons.append(reason)
        return probeResults.count > 1 ? probeResults.removeFirst() : probeResults[0]
    }
    func fireLoss() { onLoss?() }
}

private struct TestClock {
    var now = Date(timeIntervalSince1970: 1_800_000_000)
}

/// Wires the coordinator to recording fakes. `events` is the ordered effect log.
@MainActor
private final class Harness {
    let sensor = FakeSensor()
    let suiteName = "RuntimeSafetyCoordinatorTests.\(UUID().uuidString)"
    let defaults: UserDefaults
    var clock = TestClock()
    private(set) var events: [String] = []
    var flushResult = true
    var launchResult = true
    /// When true, flush suspends until `releaseFlush()`.
    var holdFlush = false
    private var heldFlush: CheckedContinuation<Void, Never>?
    var resumeCount = 0
    var onStopTriggerServices: () -> Void = {}
    var onTeardownRecorders: () -> Void = {}
    var onCloseHUD: () -> Void = {}
    lazy var coordinator: RuntimeSafetyCoordinator = RuntimeSafetyCoordinator(
        monitor: sensor,
        effects: .init(
            teardownTaps: { [unowned self] in events.append("teardownTaps") },
            stopTriggerServices: { [unowned self] in events.append("stopServices"); onStopTriggerServices() },
            teardownRecorders: { [unowned self] in events.append("teardownRecorders"); onTeardownRecorders() },
            closeHUD: { [unowned self] in events.append("closeHUD"); onCloseHUD() },
            flush: { [unowned self] in
                events.append("flush")
                if holdFlush { await withCheckedContinuation { heldFlush = $0 } }
                return flushResult
            },
            launch: { [unowned self] in events.append("launch"); return launchResult },
            terminate: { [unowned self] in events.append("terminate") },
            resumeTaps: { [unowned self] in events.append("resume"); resumeCount += 1 }
        ),
        clock: { [unowned self] in clock.now },
        defaults: defaults
    )

    init() {
        defaults = UserDefaults(suiteName: suiteName)!
    }

    func releaseFlush() { heldFlush?.resume(); heldFlush = nil }
    func finish() async { await coordinator.lossTask?.value }
    func tearDown() { defaults.removePersistentDomain(forName: suiteName) }
    func index(of event: String) -> Int? { events.firstIndex(of: event) }
    var storedTimestamp: Double? { defaults.object(forKey: RuntimeSafetyCoordinator.lastRelaunchKey) as? Double }
}

final class RuntimeSafetyCoordinatorTests: XCTestCase {
    @MainActor private var harness: Harness!

    @MainActor
    override func setUp() async throws {
        harness = Harness()
    }

    @MainActor
    override func tearDown() async throws {
        harness.tearDown()
        harness = nil
        KeystrokeCaptureRecorder.teardownAllLive()
        TriggerRecorderService.teardownAllLive()
    }

    private let syncEffects = ["teardownTaps", "stopServices", "teardownRecorders", "closeHUD"]

    // MARK: Loss path

    @MainActor
    func testMonitoringStartsOnceAndLossAtIdleTearsDownThenRelaunches() async {
        let h = harness!
        h.coordinator.startMonitoring()
        h.coordinator.startMonitoring()
        XCTAssertEqual(h.sensor.startCount, 1)

        h.sensor.fireLoss()
        // Synchronous part, before any await.
        XCTAssertEqual(h.events, syncEffects)
        XCTAssertEqual(h.coordinator.state, .relaunching)
        XCTAssertEqual(h.sensor.stopCount, 1)

        await h.finish()
        XCTAssertEqual(h.events, syncEffects + ["flush", "launch", "terminate"])
        XCTAssertEqual(h.storedTimestamp, h.clock.now.timeIntervalSince1970)
    }

    @MainActor
    func testLossWithVisibleHUDClosesItBeforeAnyFlush() async {
        let h = harness!
        var hudVisible = true
        h.onCloseHUD = { hudVisible = false }
        h.coordinator.handleLoss(cause: "test")
        XCTAssertFalse(hudVisible)
        XCTAssertLessThan(h.index(of: "teardownTaps")!, h.index(of: "closeHUD")!)
        XCTAssertNil(h.index(of: "flush"), "no flush may run before the synchronous teardown returns")
        await h.finish()
        XCTAssertLessThan(h.index(of: "closeHUD")!, h.index(of: "flush")!)
    }

    @MainActor
    func testLossWithHeldTriggerCancelsItAndLateEventIsIgnored() async {
        let h = harness!
        let mouse = RSMouseMonitor()
        let service = TriggerService(
            contextualKeyboardMonitor: RSKeyboardMonitor(), globalKeyboardMonitor: RSKeyboardMonitor(),
            mouseButtonMonitor: mouse)
        var config = TriggersConfig.default
        config.keyboard = .none
        config.globalHUDShortcut = .none
        config.mouseButton = .mouseButton(buttonNumber: 4, mode: .holdRelease)
        service.start(config: config)
        var iterator = service.events.makeAsyncIterator()
        mouse.sendDown()
        guard case .down? = await iterator.next() else { return XCTFail("expected down") }

        let stopsBeforeLoss = mouse.stopCount
        h.onStopTriggerServices = { service.stop() }
        h.coordinator.handleLoss(cause: "test")
        XCTAssertEqual(mouse.stopCount, stopsBeforeLoss + 1)

        // `stop()` yields the cancel asynchronously; the consumer must drop it.
        var handled = 0
        guard case .cancel? = await iterator.next() else { return XCTFail("expected late cancel") }
        if !h.coordinator.isLatched { handled += 1 }
        XCTAssertEqual(handled, 0)

        // A configuration update must not restart a stopped service.
        service.updateConfig(.default)
        XCTAssertEqual(mouse.startCount, 1)
        await h.finish()
    }

    @MainActor
    func testLossDuringActiveRecordingTearsDownBothRecorders() async {
        let h = harness!
        let tap = CaptureTapStub()
        let keystroke = KeystrokeCaptureRecorder(tap: tap, timeout: .seconds(60))
        let monitors = FakeRecorderEventMonitor()
        let trigger = TriggerRecorderService(monitors: monitors)
        keystroke.record()
        trigger.record(.keyboard)
        XCTAssertTrue(keystroke.isRecording)
        XCTAssertTrue(TriggerRecorderService.isRecordingKeyboardShortcut)

        h.onTeardownRecorders = {
            KeystrokeCaptureRecorder.teardownAllLive()
            TriggerRecorderService.teardownAllLive()
        }
        h.coordinator.handleLoss(cause: "test")

        XCTAssertFalse(keystroke.isRecording)
        XCTAssertTrue(tap.isStopped)
        XCTAssertFalse(trigger.isRecording)
        XCTAssertEqual(monitors.liveCount, 0)
        XCTAssertFalse(TriggerRecorderService.isRecordingKeyboardShortcut)
        await h.finish()
    }

    @MainActor
    func testLossDuringFlushIgnoresSecondLossAndTearsDownOnce() async {
        let h = harness!
        h.holdFlush = true
        h.coordinator.startMonitoring()
        h.sensor.fireLoss()
        await Task.yield()
        XCTAssertNotNil(h.index(of: "flush"))

        h.coordinator.handleLoss(cause: "second")
        _ = h.coordinator.reportDisabled(source: "x", reason: .timeout)
        XCTAssertEqual(h.events.filter { $0 == "teardownTaps" }.count, 1)

        h.releaseFlush()
        await h.finish()
        XCTAssertEqual(h.events.filter { $0 == "teardownTaps" }.count, 1)
        XCTAssertEqual(h.events.filter { $0 == "launch" }.count, 1)
    }

    // MARK: Relaunch bounds

    @MainActor
    func testRateLimitedSecondLossFlushesThenSuspendsWithoutLaunch() async {
        let h = harness!
        h.defaults.set(h.clock.now.timeIntervalSince1970 - 30, forKey: RuntimeSafetyCoordinator.lastRelaunchKey)
        h.coordinator.handleLoss(cause: "test")
        await h.finish()
        XCTAssertEqual(h.events, syncEffects + ["flush"])
        XCTAssertEqual(h.coordinator.state, .suspended)
        XCTAssertEqual(h.storedTimestamp, h.clock.now.timeIntervalSince1970 - 30, "window must not slide")
    }

    @MainActor
    func testRelaunchAllowedOnceWindowElapsed() async {
        let h = harness!
        h.defaults.set(h.clock.now.timeIntervalSince1970 - 61, forKey: RuntimeSafetyCoordinator.lastRelaunchKey)
        h.coordinator.handleLoss(cause: "test")
        await h.finish()
        XCTAssertTrue(h.events.contains("terminate"))
    }

    @MainActor
    func testFarFutureTimestampIsInvalidAndDoesNotSuppressRelaunch() async {
        let h = harness!
        h.defaults.set(h.clock.now.timeIntervalSince1970 + 3600, forKey: RuntimeSafetyCoordinator.lastRelaunchKey)
        h.coordinator.handleLoss(cause: "test")
        await h.finish()
        XCTAssertTrue(h.events.contains("terminate"))
        XCTAssertEqual(h.storedTimestamp, h.clock.now.timeIntervalSince1970)
    }

    @MainActor
    func testNearFutureTimestampStillCountsAsRecent() async {
        let h = harness!
        h.defaults.set(h.clock.now.timeIntervalSince1970 + 10, forKey: RuntimeSafetyCoordinator.lastRelaunchKey)
        h.coordinator.handleLoss(cause: "test")
        await h.finish()
        XCTAssertFalse(h.events.contains("launch"))
        XCTAssertEqual(h.coordinator.state, .suspended)
    }

    @MainActor
    func testFailedFlushSuspendsWithoutLaunch() async {
        let h = harness!
        h.flushResult = false
        h.coordinator.handleLoss(cause: "test")
        await h.finish()
        XCTAssertEqual(h.events, syncEffects + ["flush"])
        XCTAssertEqual(h.coordinator.state, .suspended)
        XCTAssertNil(h.storedTimestamp)
    }

    @MainActor
    func testFailedLaunchSuspendsWithoutTerminateAndRestoresTimestamp() async {
        let h = harness!
        h.launchResult = false
        h.coordinator.handleLoss(cause: "test")
        await h.finish()
        XCTAssertEqual(h.events, syncEffects + ["flush", "launch"])
        XCTAssertEqual(h.coordinator.state, .suspended)
        XCTAssertNil(h.storedTimestamp)
    }

    // MARK: Latched state

    @MainActor
    func testLatchedCoordinatorDoesNotRearmMonitoringOrReactToFaults() async {
        let h = harness!
        h.flushResult = false
        h.coordinator.startMonitoring()
        h.coordinator.handleLoss(cause: "test")
        await h.finish()
        XCTAssertTrue(h.coordinator.isLatched)

        // A configuration save or permission grant calls startMonitoring/start again.
        h.coordinator.startMonitoring()
        XCTAssertEqual(h.sensor.startCount, 1)
        XCTAssertNil(h.coordinator.reportDisabled(source: "x", reason: .timeout))
        XCTAssertNil(h.coordinator.reportInstallFailure(source: "x"))
        XCTAssertEqual(h.resumeCount, 0)
        XCTAssertEqual(h.events.filter { $0 == "teardownTaps" }.count, 1)
    }

    // MARK: Tap faults

    @MainActor
    func testThreeDisablesInTenSecondsProbeFourthIsLoss() async {
        let h = harness!
        for _ in 0..<3 {
            let task = h.coordinator.reportDisabled(source: "trigger", reason: .timeout)
            await task?.value
            h.clock.now.addTimeInterval(2)
        }
        XCTAssertEqual(h.sensor.probeReasons.count, 3)
        XCTAssertEqual(h.coordinator.state, .running)

        let fourth = h.coordinator.reportDisabled(source: "trigger", reason: .timeout)
        XCTAssertNil(fourth, "burst loss is handled synchronously")
        XCTAssertEqual(h.coordinator.state, .relaunching)
        XCTAssertEqual(h.sensor.probeReasons.count, 3)
        await h.finish()
    }

    @MainActor
    func testDisablesOutsideTenSecondsDoNotCountAsBurst() async {
        let h = harness!
        for _ in 0..<5 {
            await h.coordinator.reportDisabled(source: "trigger", reason: .userInput)?.value
            h.clock.now.addTimeInterval(11)
        }
        XCTAssertEqual(h.coordinator.state, .running)
        XCTAssertEqual(h.resumeCount, 5)
    }

    @MainActor
    func testProbeTrueResumes() async {
        let h = harness!
        h.sensor.probeResults = [true]
        await h.coordinator.reportDisabled(source: "settings-hotkey", reason: .timeout)?.value
        XCTAssertEqual(h.sensor.probeReasons, ["tap-disabled:settings-hotkey"])
        XCTAssertEqual(h.resumeCount, 1)
        XCTAssertEqual(h.coordinator.state, .running)
        XCTAssertFalse(h.events.contains("teardownTaps"))
    }

    @MainActor
    func testProbeFalseIsLoss() async {
        let h = harness!
        h.sensor.probeResults = [false]
        await h.coordinator.reportDisabled(source: "trigger", reason: .timeout)?.value
        XCTAssertEqual(h.resumeCount, 0)
        XCTAssertEqual(h.coordinator.state, .relaunching)
        XCTAssertEqual(Array(h.events.prefix(4)), syncEffects)
        await h.finish()
    }

    @MainActor
    func testTrustReadFalseIsLossWithoutProbe() async {
        let h = harness!
        h.sensor.trustReadIsFalse = true
        let task = h.coordinator.reportDisabled(source: "trigger", reason: .userInput)
        XCTAssertNil(task)
        XCTAssertTrue(h.sensor.probeReasons.isEmpty)
        XCTAssertEqual(h.events, syncEffects)
        await h.finish()
    }

    @MainActor
    func testLossLatchedDuringProbeSuppressesResume() async {
        let h = harness!
        let task = h.coordinator.reportDisabled(source: "trigger", reason: .timeout)
        h.coordinator.handleLoss(cause: "monitor")
        await task?.value
        XCTAssertEqual(h.resumeCount, 0)
        await h.finish()
    }

    @MainActor
    func testInstallFailureRequestsProbeAndTrueDoesNotRetryOrResume() async {
        let h = harness!
        h.sensor.probeResults = [true]
        await h.coordinator.reportInstallFailure(source: "trigger-service")?.value
        XCTAssertEqual(h.sensor.probeReasons, ["install-failed:trigger-service"])
        XCTAssertEqual(h.resumeCount, 0)
        XCTAssertEqual(h.coordinator.state, .running)
    }

    @MainActor
    func testInstallFailureWithFalseProbeIsLoss() async {
        let h = harness!
        h.sensor.probeResults = [false]
        await h.coordinator.reportInstallFailure(source: "trigger-service")?.value
        XCTAssertEqual(h.coordinator.state, .relaunching)
        await h.finish()
    }

    // MARK: Registry seal and recorder reach

    @MainActor
    func testTeardownAllSealsRegistryAndRefusesNewHandles() {
        let registry = InputTapRegistry()
        XCTAssertFalse(registry.isSealed)
        registry.teardownAll()
        XCTAssertTrue(registry.isSealed)

        let late = FakeTapHandle()
        registry.register(late)
        XCTAssertEqual(registry.registeredCount, 0)
        XCTAssertTrue(late.isInvalidated)
    }

    @MainActor
    func testSealedRegistryRefusesSystemTapCreationBeforeTouchingCoreGraphics() {
        let registry = InputTapRegistry()
        registry.seal()
        let handle = SystemEventTapHandle.create(
            mask: 0, callback: { _, _, event, _ in Unmanaged.passUnretained(event) },
            userInfo: Unmanaged.passUnretained(registry).toOpaque(), registry: registry)
        XCTAssertNil(handle)
    }

    @MainActor
    func testTeardownAllLiveReachesViewOwnedRecordersAndClearsFlagsWithNoneAlive() {
        let tap = CaptureTapStub()
        let keystroke = KeystrokeCaptureRecorder(tap: tap, timeout: .seconds(60))
        keystroke.record()
        XCTAssertTrue(keystroke.isRecording)
        KeystrokeCaptureRecorder.teardownAllLive()
        XCTAssertFalse(keystroke.isRecording)
        XCTAssertTrue(tap.isStopped)

        // Flag stuck true after the owning view (and recorder) went away.
        autoreleasepool {
            let monitors = FakeRecorderEventMonitor()
            let trigger = TriggerRecorderService(monitors: monitors)
            trigger.record(.mouseButton)
        }
        TriggerRecorderService.teardownAllLive()
        XCTAssertFalse(TriggerRecorderService.isRecordingMouseButton)
        XCTAssertFalse(TriggerRecorderService.isRecordingKeyboardShortcut)
    }

    @MainActor
    func testKeystrokeRecorderFaultsReachStaticReporter() {
        var faults: [KeystrokeCaptureRecorder.Fault] = []
        KeystrokeCaptureRecorder.faultReporter = { faults.append($0) }
        defer { KeystrokeCaptureRecorder.faultReporter = nil }

        let tap = CaptureTapStub()
        let recorder = KeystrokeCaptureRecorder(tap: tap, timeout: .seconds(60))
        recorder.record()
        _ = tap.send(.tapDisabled(.timeout))

        let failing = KeystrokeCaptureRecorder(tap: CaptureTapStub(startError: KeystrokeCaptureTapError.creationFailed))
        failing.record()
        XCTAssertEqual(faults, [.disabled(.timeout), .installFailed])
    }
}

// MARK: - Minimal trigger monitor fakes (no taps)

@MainActor
private final class RSKeyboardMonitor: KeyboardTriggerMonitoring {
    func start(keyCode: UInt16, modifiers: UInt, onDown: @escaping () -> Void, onUp: @escaping () -> Void) {}
    func stop() {}
}

@MainActor
private final class RSMouseMonitor: MouseButtonTriggerMonitoring {
    private var onDown: ((CGPoint) -> Void)?
    private(set) var startCount = 0
    private(set) var stopCount = 0
    func start(buttonNumber: Int, onDown: @escaping (CGPoint) -> Void,
               onDragged: @escaping (CGPoint) -> Void, onUp: @escaping (CGPoint) -> Void) {
        startCount += 1; self.onDown = onDown
    }
    func stop() { stopCount += 1; onDown = nil }
    func sendDown() { onDown?(.zero) }
}
