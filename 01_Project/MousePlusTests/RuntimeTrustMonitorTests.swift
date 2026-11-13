import XCTest
@testable import MousePlus

@MainActor
private final class FakeTimer: RuntimeTrustTimer {
    var cancelled = false
    func cancel() { cancelled = true }
}

@MainActor
private final class FakeScheduler: RuntimeTrustScheduling {
    struct Entry {
        let timer: FakeTimer
        var due: TimeInterval
        let interval: TimeInterval
        let repeating: Bool
        let action: @MainActor () -> Void
    }
    private(set) var now: TimeInterval = 0
    private var entries: [Entry] = []

    func schedule(
        after interval: TimeInterval, repeating: Bool, _ action: @escaping @MainActor () -> Void
    ) -> any RuntimeTrustTimer {
        let timer = FakeTimer()
        entries.append(Entry(timer: timer, due: now + interval, interval: interval,
                             repeating: repeating, action: action))
        return timer
    }

    func advance(by delta: TimeInterval) {
        let target = now + delta
        while true {
            entries.removeAll { $0.timer.cancelled }
            guard let index = entries.indices.filter({ entries[$0].due <= target })
                .min(by: { entries[$0].due < entries[$1].due }) else { break }
            let entry = entries[index]
            now = entry.due
            if entry.repeating { entries[index].due += entry.interval } else { entries.remove(at: index) }
            entry.action()
        }
        now = target
    }
}

@MainActor
private final class FakeNotificationSource: RuntimeTrustNotificationSource {
    private var handler: (@MainActor () -> Void)?
    private(set) var stopCount = 0
    func start(_ handler: @escaping @MainActor () -> Void) { self.handler = handler }
    func stop() { stopCount += 1; handler = nil }
    func fire() { handler?() }
    var isActive: Bool { handler != nil }
}

/// Scripted probe. `results` are consumed in order (last one repeats); `hang` never returns.
@MainActor
private final class FakeProbe {
    var results: [Bool] = [true]
    var hang = false
    private(set) var callCount = 0
    private var hung: [CheckedContinuation<Bool, Never>] = []

    func run() async -> Bool {
        callCount += 1
        if hang { return await withCheckedContinuation { hung.append($0) } }
        return results.count > 1 ? results.removeFirst() : results[0]
    }

    func releaseHung() { hung.forEach { $0.resume(returning: true) }; hung = [] }
}

@MainActor
private final class Harness {
    let scheduler = FakeScheduler()
    let source = FakeNotificationSource()
    let probe = FakeProbe()
    var trusted = true
    var lossCount = 0
    lazy var monitor = RuntimeTrustMonitor(
        trustReader: { [unowned self] in self.trusted },
        probe: { [probe] in await probe.run() },
        notificationSource: source,
        scheduler: scheduler)

    func start() { monitor.start { [unowned self] in self.lossCount += 1 } }
    func settle() async { for _ in 0..<20 { await Task.yield() } }
    func advance(_ seconds: TimeInterval) async { scheduler.advance(by: seconds); await settle() }
    func teardown() { monitor.stop(); probe.releaseHung() }
}

final class RuntimeTrustMonitorTests: XCTestCase {
    @MainActor
    func testNotificationThenFailedProbeDeclaresLoss() async {
        let h = Harness(); defer { h.teardown() }
        h.probe.results = [false]
        h.start()
        h.source.fire()
        await h.advance(RuntimeTrustMonitor.notificationCoalescingWindow + 0.01)
        XCTAssertEqual(h.probe.callCount, 1)
        XCTAssertEqual(h.lossCount, 1)
        XCTAssertEqual(h.monitor.lossReason, .probeFailed)
    }

    @MainActor
    func testNotificationWithHealthyProbeDoesNotDeclareLoss() async {
        let h = Harness(); defer { h.teardown() }
        h.start()
        h.source.fire()
        await h.advance(RuntimeTrustMonitor.notificationCoalescingWindow + 0.01)
        XCTAssertEqual(h.probe.callCount, 1)
        XCTAssertEqual(h.lossCount, 0)
    }

    @MainActor
    func testBackstopProbeDeclaresLoss() async {
        let h = Harness(); defer { h.teardown() }
        h.probe.results = [false]
        h.start()
        await h.advance(RuntimeTrustMonitor.backstopProbeInterval - 0.1)
        XCTAssertEqual(h.probe.callCount, 0)
        await h.advance(0.2)
        XCTAssertEqual(h.probe.callCount, 1)
        XCTAssertEqual(h.lossCount, 1)
    }

    @MainActor
    func testStaleTrueTrustReadWithFailingProbeDeclaresLoss() async {
        let h = Harness(); defer { h.teardown() }
        h.probe.results = [false]
        h.start()
        h.trusted = true // trust read never flips; only the probe can see the loss
        await h.advance(RuntimeTrustMonitor.backstopProbeInterval + 0.1)
        XCTAssertEqual(h.lossCount, 1)
        XCTAssertEqual(h.monitor.lossReason, .probeFailed)
        XCTAssertFalse(h.monitor.trustReadIsFalse)
    }

    @MainActor
    func testProbeDeadlineExceededDeclaresLoss() async {
        let h = Harness(); defer { h.teardown() }
        h.probe.hang = true
        h.start()
        h.source.fire()
        await h.advance(RuntimeTrustMonitor.notificationCoalescingWindow + 0.01)
        XCTAssertEqual(h.probe.callCount, 1)
        XCTAssertEqual(h.lossCount, 0)
        await h.advance(RuntimeTrustMonitor.probeDeadline - 0.1)
        XCTAssertEqual(h.lossCount, 0)
        await h.advance(0.2)
        XCTAssertEqual(h.lossCount, 1)
        XCTAssertEqual(h.monitor.lossReason, .probeDeadlineExceeded)
    }

    @MainActor
    func testLateProbeResultAfterDeadlineIsIgnored() async {
        let h = Harness(); defer { h.teardown() }
        h.probe.hang = true
        h.start()
        let result = Task { await h.monitor.requestProbe(reason: "test") }
        await h.settle()
        await h.advance(RuntimeTrustMonitor.probeDeadline + 0.1)
        let value = await result.value
        XCTAssertFalse(value)
        h.probe.releaseHung() // would report true
        await h.settle()
        XCTAssertEqual(h.lossCount, 1)
    }

    @MainActor
    func testNotificationBurstCoalescesIntoOneProbe() async {
        let h = Harness(); defer { h.teardown() }
        h.start()
        for _ in 0..<10 { h.source.fire() }
        await h.advance(RuntimeTrustMonitor.notificationCoalescingWindow / 2)
        h.source.fire()
        await h.advance(RuntimeTrustMonitor.notificationCoalescingWindow)
        XCTAssertEqual(h.probe.callCount, 1)
        XCTAssertEqual(h.lossCount, 0)
    }

    @MainActor
    func testTrustReadFalseDeclaresLossWithoutProbe() async {
        let h = Harness(); defer { h.teardown() }
        h.start()
        await h.advance(RuntimeTrustMonitor.trustReadInterval + 0.01)
        XCTAssertEqual(h.lossCount, 0)
        h.trusted = false
        XCTAssertTrue(h.monitor.trustReadIsFalse)
        await h.advance(RuntimeTrustMonitor.trustReadInterval)
        XCTAssertEqual(h.lossCount, 1)
        XCTAssertEqual(h.monitor.lossReason, .trustReadFalse)
        XCTAssertEqual(h.probe.callCount, 0)
    }

    @MainActor
    func testLossCallbackFiresExactlyOnceAcrossMultipleSignals() async {
        let h = Harness(); defer { h.teardown() }
        h.probe.results = [false]
        h.start()
        h.trusted = false
        h.source.fire()
        await h.advance(RuntimeTrustMonitor.backstopProbeInterval + 1)
        await h.advance(RuntimeTrustMonitor.backstopProbeInterval)
        XCTAssertEqual(h.lossCount, 1)
        let again = await h.monitor.requestProbe(reason: "after-loss")
        XCTAssertFalse(again)
        h.start() // a monitor that has lost never re-arms
        await h.advance(RuntimeTrustMonitor.backstopProbeInterval * 2)
        XCTAssertEqual(h.lossCount, 1)
    }

    @MainActor
    func testRequestProbeReturnsProbeResult() async {
        let h = Harness(); defer { h.teardown() }
        h.start()
        h.probe.results = [true]
        let ok = await h.monitor.requestProbe(reason: "test")
        XCTAssertTrue(ok)
        XCTAssertEqual(h.lossCount, 0)
        h.probe.results = [false]
        let lost = await h.monitor.requestProbe(reason: "test")
        XCTAssertFalse(lost)
        XCTAssertEqual(h.lossCount, 1)
    }

    @MainActor
    func testConcurrentRequestsShareOneProbe() async {
        let h = Harness(); defer { h.teardown() }
        h.start()
        async let a = h.monitor.requestProbe(reason: "a")
        async let b = h.monitor.requestProbe(reason: "b")
        let (ra, rb) = await (a, b)
        XCTAssertTrue(ra && rb)
        XCTAssertEqual(h.probe.callCount, 1)
    }

    @MainActor
    func testStopCancelsSensingAndSuppressesLoss() async {
        let h = Harness()
        h.probe.results = [false]
        h.start()
        XCTAssertTrue(h.source.isActive)
        h.monitor.stop()
        XCTAssertFalse(h.source.isActive)
        h.source.fire()
        h.trusted = false
        await h.advance(RuntimeTrustMonitor.backstopProbeInterval * 2)
        XCTAssertEqual(h.probe.callCount, 0)
        XCTAssertEqual(h.lossCount, 0)
    }
}
