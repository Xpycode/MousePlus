import AppKit
import OSLog

// MARK: - Injectable dependencies

@MainActor
protocol RuntimeTrustTimer: AnyObject {
    func cancel()
}

/// Clock and timer source. Production fires on the main queue; tests drive it manually.
@MainActor
protocol RuntimeTrustScheduling: AnyObject {
    var now: TimeInterval { get }
    func schedule(
        after interval: TimeInterval, repeating: Bool, _ action: @escaping @MainActor () -> Void
    ) -> any RuntimeTrustTimer
}

/// A trigger only: the probe and the trust read decide whether access is lost.
@MainActor
protocol RuntimeTrustNotificationSource: AnyObject {
    func start(_ handler: @escaping @MainActor () -> Void)
    func stop()
}

/// Returns true when the process can still create a session-level default tap.
/// Must not block the main thread; the monitor enforces a deadline regardless.
typealias RuntimeTrustProbe = @Sendable () async -> Bool

// MARK: - Production wiring (never exercised by tests)

@MainActor
private final class DispatchRuntimeTrustTimer: RuntimeTrustTimer {
    private let source: DispatchSourceTimer
    init(source: DispatchSourceTimer) { self.source = source }
    func cancel() { source.cancel() }
}

@MainActor
final class SystemRuntimeTrustScheduler: RuntimeTrustScheduling {
    var now: TimeInterval { ProcessInfo.processInfo.systemUptime }

    func schedule(
        after interval: TimeInterval, repeating: Bool, _ action: @escaping @MainActor () -> Void
    ) -> any RuntimeTrustTimer {
        let source = DispatchSource.makeTimerSource(queue: .main)
        source.schedule(deadline: .now() + interval, repeating: repeating ? interval : .infinity)
        source.setEventHandler { MainActor.assumeIsolated { action() } }
        source.resume()
        return DispatchRuntimeTrustTimer(source: source)
    }
}

/// Darwin notification posted by tccd when any TCC grant changes. Carries no payload.
@MainActor
final class DarwinTCCNotificationSource: RuntimeTrustNotificationSource {
    nonisolated static let name = "com.apple.tcc.access.changed"
    private var handler: (@MainActor () -> Void)?
    private var registered = false

    func start(_ handler: @escaping @MainActor () -> Void) {
        stop()
        self.handler = handler
        registered = true
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            Unmanaged.passUnretained(self).toOpaque(),
            { _, observer, _, _, _ in
                guard let observer else { return }
                let address = UInt(bitPattern: observer)
                DispatchQueue.main.async {
                    // The observer is removed in stop()/deinit before self is released.
                    guard let pointer = UnsafeRawPointer(bitPattern: address) else { return }
                    MainActor.assumeIsolated {
                        Unmanaged<DarwinTCCNotificationSource>.fromOpaque(pointer)
                            .takeUnretainedValue().handler?()
                    }
                }
            },
            Self.name as CFString, nil, .deliverImmediately)
    }

    func stop() {
        removeObserver()
        handler = nil
    }

    private func removeObserver() {
        guard registered else { return }
        registered = false
        CFNotificationCenterRemoveObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            Unmanaged.passUnretained(self).toOpaque(),
            CFNotificationName(Self.name as CFString), nil)
    }

    deinit {
        if registered {
            CFNotificationCenterRemoveObserver(
                CFNotificationCenterGetDarwinNotifyCenter(),
                Unmanaged.passUnretained(self).toOpaque(),
                CFNotificationName(Self.name as CFString), nil)
        }
    }
}

enum SystemRuntimeTrust {
    /// Never the prompting variant (AXIsProcessTrustedWithOptions).
    static func isTrusted() -> Bool { AXIsProcessTrusted() }

    /// Creates a session-level head-insert default tap with a narrow mask, never attaches it to a
    /// run loop, and invalidates it before returning. A nil port means the process lacks access.
    /// Caveat: `tapCreate` returns the tap already enabled, so between creation and invalidation
    /// (microseconds) an `otherMouseUp` could be routed to this unserviced port and be delayed.
    /// The window is kept minimal by invalidating immediately; tracked for the R5 review.
    static func probeNow() -> Bool {
        let mask = CGEventMask(1) << CGEventType.otherMouseUp.rawValue
        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, _, event, _ in Unmanaged.passUnretained(event) },
            userInfo: nil
        ) else { return false }
        CFMachPortInvalidate(port)
        return true
    }

    static let utilityQueue = DispatchQueue(label: "com.xpycode.MousePlus.trust-probe", qos: .utility)

    static func probe() async -> Bool {
        await withCheckedContinuation { continuation in
            utilityQueue.async { continuation.resume(returning: probeNow()) }
        }
    }
}

// MARK: - Monitor

/// Detects loss of Accessibility/Input Monitoring trust while global event taps are live.
/// Signals, any of which declares loss (callback fires at most once per instance, ever):
///   - the `AXIsProcessTrusted` read returns false (polled every `trustReadInterval`);
///   - a probe returns false (on TCC notification, on request, and every `backstopProbeInterval`);
///   - a probe has not returned within `probeDeadline` (a hung probe must not be waited on).
/// The probe runs off the main thread; only timers and bookkeeping run on the main actor.
@MainActor
final class RuntimeTrustMonitor {
    enum LossReason: String {
        case trustReadFalse
        case probeFailed
        case probeDeadlineExceeded
    }

    /// Poll period for the synchronous trust read; bounds detection when no notification arrives.
    static let trustReadInterval: TimeInterval = 0.5
    /// Probe period independent of notifications; catches a stale-true trust read.
    static let backstopProbeInterval: TimeInterval = 5
    /// A probe slower than this counts as loss: a tap-creation call blocked in WindowServer
    /// is the same failure that hangs input for the live taps.
    static let probeDeadline: TimeInterval = 1
    /// Trailing window that folds a burst of TCC notifications into one probe.
    static let notificationCoalescingWindow: TimeInterval = 0.1

    private static let log = Logger(subsystem: "com.xpycode.MousePlus", category: "RuntimeSafety")

    private final class ProbeRun {
        let reason: String
        let startedAt: TimeInterval
        var result: Bool?
        var waiters: [CheckedContinuation<Bool, Never>] = []
        var deadlineTimer: (any RuntimeTrustTimer)?
        init(reason: String, startedAt: TimeInterval) {
            self.reason = reason
            self.startedAt = startedAt
        }
    }

    private let trustReader: () -> Bool
    private let probe: RuntimeTrustProbe
    private let notificationSource: any RuntimeTrustNotificationSource
    private let scheduler: any RuntimeTrustScheduling

    private var onLoss: (() -> Void)?
    private var isRunning = false
    private var hasLost = false
    private var lastTrust: Bool?
    private var inFlight: ProbeRun?
    private var trustTimer: (any RuntimeTrustTimer)?
    private var backstopTimer: (any RuntimeTrustTimer)?
    private var coalesceTimer: (any RuntimeTrustTimer)?

    private(set) var lossReason: LossReason?

    init(
        trustReader: (() -> Bool)? = nil,
        probe: RuntimeTrustProbe? = nil,
        notificationSource: (any RuntimeTrustNotificationSource)? = nil,
        scheduler: (any RuntimeTrustScheduling)? = nil
    ) {
        self.trustReader = trustReader ?? { SystemRuntimeTrust.isTrusted() }
        self.probe = probe ?? { await SystemRuntimeTrust.probe() }
        self.notificationSource = notificationSource ?? DarwinTCCNotificationSource()
        self.scheduler = scheduler ?? SystemRuntimeTrustScheduler()
    }

    /// Synchronous trust read for callers that must decide without awaiting.
    var trustReadIsFalse: Bool { !trustReader() }

    /// Begins monitoring. A monitor that already declared loss never restarts.
    func start(onLoss: @escaping () -> Void) {
        stop()
        guard !hasLost else { return }
        self.onLoss = onLoss
        isRunning = true
        lastTrust = trustReader()
        Self.log.info("monitor started trusted=\(self.lastTrust ?? false, privacy: .public)")
        notificationSource.start { [weak self] in self?.handleNotification() }
        trustTimer = scheduler.schedule(after: Self.trustReadInterval, repeating: true) { [weak self] in
            self?.trustTick()
        }
        backstopTimer = scheduler.schedule(after: Self.backstopProbeInterval, repeating: true) { [weak self] in
            self?.backstopTick()
        }
    }

    /// Stops sensing and drops the loss callback. An in-flight probe still completes for its
    /// waiters but can no longer declare loss.
    func stop() {
        isRunning = false
        onLoss = nil
        notificationSource.stop()
        trustTimer?.cancel(); trustTimer = nil
        backstopTimer?.cancel(); backstopTimer = nil
        coalesceTimer?.cancel(); coalesceTimer = nil
    }

    /// Runs (or joins) a probe. True means access is still held. A false result or a missed
    /// deadline also declares loss while the monitor is running.
    func requestProbe(reason: String) async -> Bool {
        if hasLost { return false }
        let run: ProbeRun
        if let existing = inFlight {
            run = existing
        } else {
            run = ProbeRun(reason: reason, startedAt: scheduler.now)
            inFlight = run
            run.deadlineTimer = scheduler.schedule(after: Self.probeDeadline, repeating: false) {
                [weak self] in
                self?.finish(run, ok: false, deadlineExceeded: true)
            }
            Self.log.info("probe started reason=\(reason, privacy: .public)")
            let probe = self.probe
            Task {
                let ok = await probe()
                self.finish(run, ok: ok, deadlineExceeded: false)
            }
        }
        return await withCheckedContinuation { continuation in
            if let result = run.result {
                continuation.resume(returning: result)
            } else {
                run.waiters.append(continuation)
            }
        }
    }

    // MARK: Private

    private func finish(_ run: ProbeRun, ok: Bool, deadlineExceeded: Bool) {
        // First completion wins; a late probe result after the deadline is ignored.
        guard run.result == nil else { return }
        run.result = ok
        run.deadlineTimer?.cancel()
        run.deadlineTimer = nil
        if inFlight === run { inFlight = nil }
        let latencyMs = Int((scheduler.now - run.startedAt) * 1000)
        Self.log.info("""
            probe finished reason=\(run.reason, privacy: .public) ok=\(ok, privacy: .public) \
            deadline=\(deadlineExceeded, privacy: .public) latencyMs=\(latencyMs, privacy: .public)
            """)
        let waiters = run.waiters
        run.waiters = []
        for waiter in waiters { waiter.resume(returning: ok) }
        if !ok { declareLoss(deadlineExceeded ? .probeDeadlineExceeded : .probeFailed) }
    }

    private func handleNotification() {
        guard isRunning else { return }
        Self.log.info("tcc notification received")
        guard coalesceTimer == nil else { return }
        coalesceTimer = scheduler.schedule(after: Self.notificationCoalescingWindow, repeating: false) {
            [weak self] in
            guard let self else { return }
            self.coalesceTimer = nil
            Task { _ = await self.requestProbe(reason: "tcc-notification") }
        }
    }

    private func trustTick() {
        guard isRunning else { return }
        let trusted = trustReader()
        if trusted != lastTrust {
            Self.log.info("trust read changed to \(trusted, privacy: .public)")
            lastTrust = trusted
        }
        if !trusted { declareLoss(.trustReadFalse) }
    }

    private func backstopTick() {
        guard isRunning else { return }
        Task { _ = await self.requestProbe(reason: "backstop") }
    }

    private func declareLoss(_ reason: LossReason) {
        guard isRunning, !hasLost else { return }
        hasLost = true
        lossReason = reason
        Self.log.error("trust loss declared reason=\(reason.rawValue, privacy: .public)")
        let callback = onLoss
        stop()
        callback?()
    }
}
