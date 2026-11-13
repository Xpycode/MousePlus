import Foundation
import OSLog

/// What the coordinator needs from a trust sensor. `RuntimeTrustMonitor` conforms;
/// tests substitute a scripted fake.
@MainActor
protocol RuntimeTrustSensing: AnyObject {
    var trustReadIsFalse: Bool { get }
    func start(onLoss: @escaping () -> Void)
    func stop()
    func requestProbe(reason: String) async -> Bool
}

extension RuntimeTrustMonitor: RuntimeTrustSensing {}

/// Owns the response to losing Accessibility trust while event taps are live.
///
/// A session `.defaultTap` owned by an untrusted process can hang keyboard and mouse
/// input system-wide, so the hazard is the *existence* of our taps after loss. On loss
/// this removes every tap synchronously, closes the HUD without committing, flushes
/// settings, then relaunches (the new instance starts untrusted and shows the existing
/// permission setup) and terminates. If relaunch is not allowed or fails, the process
/// stays alive suspended: no tap, and nothing re-arms one.
@MainActor
final class RuntimeSafetyCoordinator {
    /// Side effects, injected so the decision logic runs headless.
    struct Effects {
        /// `InputTapRegistry.shared.teardownAll()` (also seals the registry).
        var teardownTaps: () -> Void
        /// Stops the trigger service and the Settings hotkey monitor.
        var stopTriggerServices: () -> Void
        /// Tears down every live recorder and clears the recorder pass-through flags.
        var teardownRecorders: () -> Void
        /// Non-committing HUD close; also stops the dismissal NSEvent monitors.
        var closeHUD: () -> Void
        /// Makes pending settings durable. False leaves the process suspended.
        var flush: () async -> Bool
        /// Starts a new app instance. False leaves the process suspended.
        var launch: () async -> Bool
        var terminate: () -> Void
        /// Re-enables the trigger taps after a probe confirmed access is intact.
        var resumeTaps: () -> Void
    }

    enum State: Equatable {
        case running
        /// Loss handled; flush/launch/terminate in progress.
        case relaunching
        /// Loss handled; staying alive without taps.
        case suspended
    }

    static let relaunchWindow: TimeInterval = 60
    static let burstWindow: TimeInterval = 10
    static let burstLimit = 3
    static let lastRelaunchKey = "RuntimeSafety.lastSafetyRelaunchAt"

    private static let log = Logger(subsystem: "com.xpycode.MousePlus", category: "RuntimeSafety")

    private let monitor: any RuntimeTrustSensing
    private let effects: Effects
    private let clock: () -> Date
    private let defaults: UserDefaults

    private(set) var state: State = .running
    private var isMonitoring = false
    private var disableTimes: [Date] = []
    /// The post-teardown flush/relaunch work; exposed so tests can await it.
    private(set) var lossTask: Task<Void, Never>?

    init(
        monitor: any RuntimeTrustSensing,
        effects: Effects,
        clock: @escaping () -> Date = { Date() },
        defaults: UserDefaults = .standard
    ) {
        self.monitor = monitor
        self.effects = effects
        self.clock = clock
        self.defaults = defaults
    }

    /// True once loss was handled. Callers must not start or re-arm anything.
    var isLatched: Bool { state != .running }

    /// Starts trust monitoring. Idempotent; a latched coordinator never restarts.
    func startMonitoring() {
        guard !isLatched, !isMonitoring else { return }
        isMonitoring = true
        monitor.start(onLoss: { [weak self] in self?.handleLoss(cause: "trust-monitor") })
    }

    // MARK: - Loss

    /// The single loss entry point. Everything up to the `Task` is synchronous so no
    /// tap can outlive this call; a second call is ignored.
    func handleLoss(cause: String) {
        guard state == .running else {
            Self.log.info("loss ignored (already \(String(describing: self.state), privacy: .public)) cause=\(cause, privacy: .public)")
            return
        }
        state = .relaunching
        Self.log.error("loss handling started cause=\(cause, privacy: .public)")
        effects.teardownTaps()
        effects.stopTriggerServices()
        effects.teardownRecorders()
        effects.closeHUD()
        monitor.stop()
        isMonitoring = false
        Self.log.error("teardown complete")
        lossTask = Task { @MainActor [weak self] in await self?.relaunchAfterLoss() }
    }

    private func relaunchAfterLoss() async {
        // A rate-limited loss still flushes: taps are already gone, and settings
        // edited just before the loss must not be stranded in a suspended process.
        guard await effects.flush() else {
            suspend(decision: "flush-failed")
            return
        }
        let now = clock()
        if isRateLimited(now: now) {
            suspend(decision: "rate-limited")
            return
        }
        // Written before launching so the new instance sees it.
        let previous = defaults.object(forKey: Self.lastRelaunchKey)
        defaults.set(now.timeIntervalSince1970, forKey: Self.lastRelaunchKey)
        guard await effects.launch() else {
            // No new instance exists, so this attempt must not consume the window.
            if let previous { defaults.set(previous, forKey: Self.lastRelaunchKey) }
            else { defaults.removeObject(forKey: Self.lastRelaunchKey) }
            suspend(decision: "launch-failed")
            return
        }
        Self.log.error("relaunch decision: relaunch")
        effects.terminate()
    }

    private func suspend(decision: String) {
        state = .suspended
        Self.log.error("relaunch decision: \(decision, privacy: .public); staying alive suspended")
    }

    /// Wall-clock on purpose: the limit must survive a process restart, and uptime
    /// does not. A stored time up to one window in the future still counts as recent
    /// (the clock may have stepped back a little); further ahead it is invalid, so a
    /// bad clock can never suppress relaunch for more than about two windows.
    private func isRateLimited(now: Date) -> Bool {
        guard let stored = defaults.object(forKey: Self.lastRelaunchKey) as? Double else { return false }
        let elapsed = now.timeIntervalSince1970 - stored
        if elapsed < -Self.relaunchWindow {
            Self.log.error("ignoring future-dated relaunch timestamp (\(Int(-elapsed), privacy: .public)s ahead)")
            return false
        }
        return elapsed < Self.relaunchWindow
    }

    // MARK: - Tap faults

    /// A tap was disabled by macOS. Never re-enables by itself: burst or trust-read
    /// false is loss immediately; otherwise a probe decides between resume and loss.
    /// Returns the pending probe work, or nil when handled synchronously.
    @discardableResult
    func reportDisabled(source: String, reason: InputTapDisableReason) -> Task<Void, Never>? {
        guard !isLatched else {
            Self.log.info("tap disabled ignored while latched source=\(source, privacy: .public)")
            return nil
        }
        Self.log.error("tap disabled source=\(source, privacy: .public) reason=\(String(describing: reason), privacy: .public)")
        let now = clock()
        disableTimes.append(now)
        disableTimes.removeAll { now.timeIntervalSince($0) > Self.burstWindow }
        if disableTimes.count > Self.burstLimit {
            handleLoss(cause: "disable-burst source=\(source)")
            return nil
        }
        if monitor.trustReadIsFalse {
            handleLoss(cause: "trust-read-false after disable source=\(source)")
            return nil
        }
        return Task { @MainActor [weak self] in
            guard let self else { return }
            let ok = await self.monitor.requestProbe(reason: "tap-disabled:\(source)")
            guard !self.isLatched else { return }
            guard ok else {
                self.handleLoss(cause: "probe-failed after disable source=\(source)")
                return
            }
            Self.log.info("probe ok after disable source=\(source, privacy: .public); resuming taps")
            self.effects.resumeTaps()
        }
    }

    /// A consuming tap could not be created. No fallback and no retry: a probe only
    /// decides whether this is a loss.
    @discardableResult
    func reportInstallFailure(source: String) -> Task<Void, Never>? {
        guard !isLatched else {
            Self.log.info("install failure ignored while latched source=\(source, privacy: .public)")
            return nil
        }
        Self.log.error("tap install failed source=\(source, privacy: .public)")
        return Task { @MainActor [weak self] in
            guard let self else { return }
            let ok = await self.monitor.requestProbe(reason: "install-failed:\(source)")
            guard !self.isLatched else { return }
            if ok {
                Self.log.info("probe ok after install failure source=\(source, privacy: .public); no fallback, no retry")
            } else {
                self.handleLoss(cause: "probe-failed after install failure source=\(source)")
            }
        }
    }
}
