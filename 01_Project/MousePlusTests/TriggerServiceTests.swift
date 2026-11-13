import AppKit
import XCTest
@testable import MousePlus

final class TriggerServiceTests: XCTestCase {
    private let key = TriggerBinding.keyboard(keyCode: 96, modifiers: NSEvent.ModifierFlags.option.rawValue, mode: .holdRelease)
    private let button = TriggerBinding.mouseButton(buttonNumber: 4, mode: .holdRelease)

    @MainActor
    private func make() -> (TriggerService, SvcKeyboardMonitor, SvcKeyboardMonitor, SvcMouseMonitor) {
        let ctx = SvcKeyboardMonitor(), glob = SvcKeyboardMonitor(), mouse = SvcMouseMonitor()
        let service = TriggerService(
            contextualKeyboardMonitor: ctx, globalKeyboardMonitor: glob, mouseButtonMonitor: mouse
        )
        return (service, ctx, glob, mouse)
    }

    private func config(keyboard: TriggerBinding = .none, mouse: TriggerBinding = .none) -> TriggersConfig {
        var c = TriggersConfig.default
        c.keyboard = keyboard
        c.mouseButton = mouse
        c.globalHUDShortcut = .none
        return c
    }

    private func isCancel(_ e: TriggerEvent?) -> TriggerSource? {
        if case let .cancel(source)? = e { return source }
        return nil
    }

    @MainActor
    func testDisableCancelsHeldSourceReportsReasonAndDoesNotResume() async {
        let (service, ctx, _, mouse) = make()
        var reasons: [InputTapDisableReason] = []
        service.onDisabled = { reasons.append($0) }
        service.start(config: config(keyboard: key, mouse: button))
        var it = service.events.makeAsyncIterator()

        mouse.sendDown(at: .zero)
        guard case let .down(mouseSource, _, _)? = await it.next() else { return XCTFail() }
        ctx.sendDown()
        guard case let .down(keySource, _, _)? = await it.next() else { return XCTFail() }

        mouse.fireDisabled(.timeout)
        let next1 = await it.next()
        XCTAssertEqual(isCancel(next1), mouseSource)
        ctx.fireDisabled(.userInput)
        let next2 = await it.next()
        XCTAssertEqual(isCancel(next2), keySource)
        XCTAssertEqual(reasons, [.timeout, .userInput])
        XCTAssertEqual(mouse.resumeCount + ctx.resumeCount, 0)

        // Cleared: a second disable yields nothing more; next event is the sentinel down.
        mouse.fireDisabled(.timeout)
        mouse.sendDown(at: .zero)
        guard case .down? = await it.next() else { return XCTFail("unexpected cancel after cleared source") }
    }

    @MainActor
    func testInstallFailureIsForwarded() {
        let (service, _, _, mouse) = make()
        var failures = 0
        service.onInstallFailed = { failures += 1 }
        service.start(config: config(mouse: button))
        mouse.fireInstallFailed()
        XCTAssertEqual(failures, 1)
    }

    @MainActor
    func testResumeForwardsToMonitorsOnlyWhileRunning() {
        let (service, ctx, glob, mouse) = make()
        service.resume()
        XCTAssertEqual(ctx.resumeCount + glob.resumeCount + mouse.resumeCount, 0)
        service.start(config: config(keyboard: key, mouse: button))
        service.resume()
        XCTAssertEqual([ctx.resumeCount, glob.resumeCount, mouse.resumeCount], [1, 1, 1])
    }

    @MainActor
    func testStopClearsActiveSourcesAndCancelsHeldInvocation() async {
        let (service, _, _, mouse) = make()
        service.start(config: config(mouse: button))
        var it = service.events.makeAsyncIterator()
        mouse.sendDown(at: .zero)
        guard case let .down(source, _, _)? = await it.next() else { return XCTFail() }

        service.stop()
        let next3 = await it.next()
        XCTAssertEqual(isCancel(next3), source)
        XCTAssertGreaterThan(mouse.stopCount, 0)

        // The cleared source must not be cancelled again by a rebind or a disable.
        mouse.fireDisabled(.timeout)
        service.start(config: config(mouse: button))
        mouse.sendDown(at: .zero)
        guard case .down? = await it.next() else { return XCTFail("stale source cancelled") }
    }

    @MainActor
    func testUpdateConfigDoesNotStartStoppedService() {
        let (service, ctx, glob, mouse) = make()
        service.updateConfig(config(keyboard: key, mouse: button))
        XCTAssertEqual(ctx.startCount + glob.startCount + mouse.startCount, 0)

        service.start(config: config())
        service.stop()
        service.updateConfig(config(keyboard: key, mouse: button))
        XCTAssertEqual(ctx.startCount + glob.startCount + mouse.startCount, 0)

        // The stored config applies on the next explicit start.
        service.start(config: config(keyboard: key, mouse: button))
        XCTAssertEqual(ctx.startCount, 1)
        XCTAssertEqual(mouse.startCount, 1)
    }

    @MainActor
    func testRebindingStillCancelsHeldSource() async {
        let (service, _, _, mouse) = make()
        service.start(config: config(mouse: button))
        var it = service.events.makeAsyncIterator()
        mouse.sendDown(at: .zero)
        guard case let .down(source, _, _)? = await it.next() else { return XCTFail() }
        service.updateConfig(config(mouse: .mouseButton(buttonNumber: 5, mode: .holdRelease)))
        let next4 = await it.next()
        XCTAssertEqual(isCancel(next4), source)
        XCTAssertEqual(mouse.startCount, 2)
    }
}

@MainActor
private final class SvcKeyboardMonitor: KeyboardTriggerMonitoring {
    private var onDown: (() -> Void)?
    private var onDisabled: ((InputTapDisableReason) -> Void)?
    private var onInstallFailed: (() -> Void)?
    private(set) var startCount = 0, stopCount = 0, resumeCount = 0

    func start(keyCode: UInt16, modifiers: UInt, onDown: @escaping () -> Void, onUp: @escaping () -> Void) {
        startCount += 1; self.onDown = onDown
    }
    func stop() { stopCount += 1; onDown = nil }
    func resume() { resumeCount += 1 }
    func setFaultHandlers(onDisabled: @escaping (InputTapDisableReason) -> Void,
                          onInstallFailed: @escaping () -> Void) {
        self.onDisabled = onDisabled; self.onInstallFailed = onInstallFailed
    }
    func sendDown() { onDown?() }
    func fireDisabled(_ r: InputTapDisableReason) { onDisabled?(r) }
}

@MainActor
private final class SvcMouseMonitor: MouseButtonTriggerMonitoring {
    private var onDown: ((CGPoint) -> Void)?
    private var onDisabled: ((InputTapDisableReason) -> Void)?
    private var onInstallFailed: (() -> Void)?
    private(set) var startCount = 0, stopCount = 0, resumeCount = 0

    func start(buttonNumber: Int, onDown: @escaping (CGPoint) -> Void,
               onDragged: @escaping (CGPoint) -> Void, onUp: @escaping (CGPoint) -> Void) {
        startCount += 1; self.onDown = onDown
    }
    func stop() { stopCount += 1; onDown = nil }
    func resume() { resumeCount += 1 }
    func setFaultHandlers(onDisabled: @escaping (InputTapDisableReason) -> Void,
                          onInstallFailed: @escaping () -> Void) {
        self.onDisabled = onDisabled; self.onInstallFailed = onInstallFailed
    }
    func sendDown(at p: CGPoint) { onDown?(p) }
    func fireDisabled(_ r: InputTapDisableReason) { onDisabled?(r) }
    func fireInstallFailed() { onInstallFailed?() }
}
