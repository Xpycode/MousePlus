import AppKit
import SwiftUI

enum HUDInvocationOwnershipEffect: Equatable {
    case show
    case replace
    case dismiss
    case updateSelection
    case commitRelease
    case ignore
}

/// Pure event-ownership boundary for two independently configured HUD routes.
/// Presentation can outlive a consumed Hold-release (for an expanded branch),
/// while only the exact current physical source may own the next release.
struct HUDInvocationOwnership: Equatable {
    private(set) var visibleRoute: HUDInvocationRoute?
    private(set) var presentationMode: TriggerMode?
    private(set) var releaseOwner: TriggerSource?

    mutating func handle(_ event: TriggerEvent) -> HUDInvocationOwnershipEffect {
        switch event {
        case .down(let source, let mode, _):
            guard let visibleRoute else {
                begin(source: source, mode: mode)
                return .show
            }
            if visibleRoute != source.route {
                begin(source: source, mode: mode)
                return .replace
            }
            if mode == .tapToggle {
                close()
                return .dismiss
            }
            // Preserve the visible same-route layout while arming this exact
            // physical source for its established Hold-release behavior.
            presentationMode = mode
            releaseOwner = source
            return .ignore

        case .moved(let source, let mode, _):
            return mode == .holdRelease && releaseOwner == source
                ? .updateSelection : .ignore

        case .up(let source, let mode, _):
            guard mode == .holdRelease, releaseOwner == source else { return .ignore }
            releaseOwner = nil
            return .commitRelease

        case .cancel(let source):
            guard releaseOwner == source else { return .ignore }
            close()
            return .dismiss
        }
    }

    mutating func close() {
        visibleRoute = nil
        presentationMode = nil
        releaseOwner = nil
    }

    private mutating func begin(source: TriggerSource, mode: TriggerMode) {
        visibleRoute = source.route
        presentationMode = mode
        releaseOwner = mode == .holdRelease ? source : nil
    }
}

/// Lifecycle adapter shared by production callbacks and tests. It owns no files or
/// event taps; effects run only after a real load outcome and permission grant.
@MainActor
@Observable
final class TriggerOnboardingLaunch {
    struct Effects {
        var applyRuntime: (Configuration) -> Void
        var showPermission: () -> Void
        var showTriggers: () -> Void
        var showSettings: () -> Void
    }

    private var policy = TriggerOnboardingPolicy()
    private var loadState: TriggerOnboardingPolicy.LoadState = .loading
    private var loadedConfiguration: Configuration?
    private var accessibilityGranted = false
    private var runtimeApplied = false
    private var receivedSavedConfiguration = false
    private let effects: Effects

    init(effects: Effects) { self.effects = effects }

    var continuationTitle: String {
        switch loadState {
        case .loading: "Continue"
        case .missingFile: "Choose a Trigger"
        case .failed: "Open Settings"
        case .loaded(let triggers):
            TriggerOnboardingPolicy.hasRingBinding(in: triggers) ? "Open Settings" : "Choose a Trigger"
        }
    }

    func begin(accessibilityGranted: Bool) {
        self.accessibilityGranted = accessibilityGranted
        evaluate()
    }

    func permissionGranted() {
        accessibilityGranted = true
        evaluate()
    }

    func continueFromPermission() {
        evaluate(continueFromPermission: true)
    }

    func configurationLoaded(_ result: Result<ConfigurationService.LoadResult, Error>) {
        guard !receivedSavedConfiguration else { return }
        switch result {
        case .success(let outcome):
            loadedConfiguration = outcome.configuration
            switch outcome {
            case .defaults: loadState = .missingFile
            case .loaded(let config): loadState = .loaded(config.triggers)
            }
        case .failure:
            loadState = .failed
            loadedConfiguration = nil
        }
        evaluate()
    }

    func configurationSaved(_ configuration: Configuration) {
        receivedSavedConfiguration = true
        loadedConfiguration = configuration
        loadState = .loaded(configuration.triggers)
        runtimeApplied = false
        evaluate()
    }

    func recoverLoadedSettingsConfiguration(_ configuration: Configuration) {
        guard !receivedSavedConfiguration else { return }
        switch loadState {
        case .loading, .failed:
            configurationSaved(configuration)
        case .loaded, .missingFile:
            break
        }
    }

    private func evaluate(continueFromPermission: Bool = false) {
        if accessibilityGranted, !runtimeApplied, let loadedConfiguration {
            runtimeApplied = true
            effects.applyRuntime(loadedConfiguration)
        }
        let decision = policy.evaluate(configuration: loadState,
                                       accessibilityGranted: accessibilityGranted,
                                       continueFromPermission: continueFromPermission)
        switch decision.action {
        case .none: break
        case .showPermissionSetup: effects.showPermission()
        case .showTriggerSetup: effects.showTriggers()
        case .showSettings:
            if decision.status == .loadFailure { effects.showTriggers() }
            else { effects.showSettings() }
        }
    }
}

@main
struct MousePlusApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @Environment(\.openSettings) private var openSettings
    @State private var settingsSelection: SettingsSection? = .general
    @State private var requestedMenuItemID: UUID?

    var body: some Scene {
        // Settings window (opened from menu bar)
        Settings {
            SettingsView(selection: $settingsSelection,
                         requestedMenuItemID: $requestedMenuItemID) { configuration in
                AppDelegate.applyConfiguration?(configuration)
            }
                .environmentObject(appDelegate.settingsActionContextProvider)
        }
        .windowStyle(.hiddenTitleBar)
    }

    init() {
        // Store reference for AppDelegate to use
        AppDelegate.openSettingsAction = { [self] in
            openSettings()
        }
        AppDelegate.openTriggersSettingsAction = { [self] in
            settingsSelection = .triggers
            requestedMenuItemID = nil
            openSettings()
        }
        AppDelegate.openMenuItemsSettingsAction = { [self] in
            settingsSelection = .menuItems
            requestedMenuItemID = nil
            openSettings()
        }
        AppDelegate.openSettingsRouteAction = { [self] route in
            if case .menuItem(let itemID) = route {
                settingsSelection = .menuItems
                requestedMenuItemID = itemID
            }
            openSettings()
        }
    }
}

/// App delegate for menu bar and trigger setup.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static var openSettingsAction: (() -> Void)?
    static var openTriggersSettingsAction: (() -> Void)?
    static var accessibilityPermissionGranted: (() -> Void)?
    static var recoverLoadedSettingsConfiguration: ((Configuration) -> Void)?
    static var openSettingsRouteAction: ((ActionSettingsRoute) -> Void)?
    static var openMenuItemsSettingsAction: (() -> Void)?

    /// The sole Settings → runtime bridge. The workspace invokes it only after a
    /// successful save and always supplies the complete durable configuration.
    @MainActor static var applyConfiguration: ((Configuration) -> Void)?

    /// Settings → app bridge: opens the "Identify Input" diagnostic window. No longer
    /// auto-opened at launch — reachable from Settings → General → Diagnostics and the
    /// menu bar (see the M1 Max menu-bar-icon mystery in `PROJECT_STATE.md`).
    @MainActor static var showIdentifyInput: (() -> Void)?

    /// Shared lifecycle bridge for every visible quit affordance. Keeping the
    /// termination request here ensures General Settings remains useful when the
    /// status item cannot be seen.
    @MainActor static var quitApplication: (() -> Void)?

    /// Shared lifecycle bridge for the menu-bar restart affordance.
    @MainActor static var restartApplication: (() -> Void)?

    /// Installed by the Settings workspace while it exists so termination can
    /// cross the same durability barrier as closing the Settings window.
    @MainActor static var flushPendingSettingsChanges: (() async -> Bool)?

    private var menuBarController: MenuBarController?
    private var ringWindowController: RingWindowController?
    private var triggerService: TriggerService?
    private var triggerEventTask: Task<Void, Never>?
    private var configService: ConfigurationService?
    private var permissionsService = PermissionsService()
    private let appSwitcherService = AppSwitcherService()
    private var onboardingWindowController: OnboardingWindowController?
    private var inputRecorderWindowController: InputRecorderWindowController?

    /// Global "open Settings" hotkey (default ⌥⌘,). The reliable way into Preferences
    /// for a menu-bar-only app when the status-item icon is missing (M1 Max bug).
    private var settingsHotkeyMonitor: KeyboardTriggerMonitor?

    private lazy var actionErrorHUDController = ActionErrorHUDController { [weak self] route in
        guard let self else { return }
        self.settingsActionContextProvider.recordFrontmostApplicationBeforeSettingsActivation()
        NSApp.activate(ignoringOtherApps: true)
        Self.openSettingsRouteAction?(route)
    }
    private lazy var actionResultRouter = ActionResultRouter { [weak self] failure in
        await MainActor.run { [weak self] in
            self?.actionErrorHUDController.show(failure)
        }
    }
    private lazy var ringViewModel = RingViewModel(actionResultRouter: actionResultRouter,
                                                    appSwitcherService: appSwitcherService)
    private var dismissMonitor: DismissMonitor?
    private var invocationOwnership = HUDInvocationOwnership()
    let settingsActionContextProvider = SettingsActionContextProvider()

    /// Loaded config; drives dismiss behavior. Sensible default until load completes.
    private var configuration = Configuration()
    private var injectedOnboardingEffects: TriggerOnboardingLaunch.Effects?
    private lazy var onboardingLaunch = TriggerOnboardingLaunch(effects: injectedOnboardingEffects ?? .init(
        applyRuntime: { [weak self] config in self?.applyRuntimeConfiguration(config) },
        showPermission: { [weak self] in self?.showPermissionOnboarding() },
        showTriggers: { [weak self] in self?.showTriggersSettings() },
        showSettings: { [weak self] in self?.showSettings() }
    ))

    /// Owns the response to losing Accessibility trust at runtime. All decisions live
    /// in the coordinator; this only supplies the effects.
    private lazy var safetyCoordinator = RuntimeSafetyCoordinator(
        monitor: RuntimeTrustMonitor(),
        effects: .init(
            teardownTaps: { InputTapRegistry.shared.teardownAll() },
            stopTriggerServices: { [weak self] in
                self?.triggerService?.stop()
                self?.settingsHotkeyMonitor?.stop()
            },
            teardownRecorders: {
                KeystrokeCaptureRecorder.teardownAllLive()
                TriggerRecorderService.teardownAllLive()
            },
            closeHUD: { [weak self] in self?.closeRing() },
            flush: { await Self.flushPendingSettingsChanges?() ?? true },
            launch: { await Self.launchNewApplicationInstance() },
            terminate: { NSApp.terminate(nil) },
            resumeTaps: { [weak self] in
                self?.triggerService?.resume()
                self?.settingsHotkeyMonitor?.resume()
            }
        )
    )

    override init() { super.init() }

    /// Inject lifecycle effects without starting real monitors, windows, or TCC prompts.
    init(onboardingEffects: TriggerOnboardingLaunch.Effects) {
        injectedOnboardingEffects = onboardingEffects
        super.init()
    }

    func beginTriggerOnboarding(accessibilityGranted: Bool) {
        onboardingLaunch.begin(accessibilityGranted: accessibilityGranted)
    }

    func triggerOnboardingPermissionGranted() { onboardingLaunch.permissionGranted() }
    func continueTriggerOnboarding() { onboardingLaunch.continueFromPermission() }
    func triggerOnboardingConfigurationLoaded(_ result: Result<ConfigurationService.LoadResult, Error>) {
        onboardingLaunch.configurationLoaded(result)
    }
    func applySavedConfiguration(_ configuration: Configuration) {
        onboardingLaunch.configurationSaved(configuration)
    }
    func recoverLoadedSettingsConfiguration(_ configuration: Configuration) {
        onboardingLaunch.recoverLoadedSettingsConfiguration(configuration)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // App-hosted unit tests must not start production event taps or request
        // TCC access under the Debug signing identity. Each test owns its own
        // services and fixtures; launching the real app here queues system
        // permission dialogs alongside the installed Developer ID build.
        guard NSClassFromString("XCTestCase") == nil else { return }
        setupMenuBar()
        loadConfiguration()

        Task { await appSwitcherService.startTrackingMRU() }

        permissionsService.onGranted = { [weak self] in
            self?.triggerOnboardingPermissionGranted()
        }
        Self.accessibilityPermissionGranted = { [weak self] in
            self?.triggerOnboardingPermissionGranted()
        }
        // Recorders live inside SwiftUI views; their tap faults reach the coordinator here.
        KeystrokeCaptureRecorder.faultReporter = { [weak self] fault in
            switch fault {
            case .disabled(let reason):
                self?.safetyCoordinator.reportDisabled(source: "keystroke-recorder", reason: reason)
            case .installFailed:
                self?.safetyCoordinator.reportInstallFailure(source: "keystroke-recorder")
            }
        }
        beginTriggerOnboarding(accessibilityGranted: permissionsService.isGranted)
    }

    /// MousePlus is a menu-bar/LSUIElement utility — its real job (the global
    /// trigger + ring) runs with no windows open. Without this, closing the last
    /// window (e.g. the "Identify Input" diagnostic) terminates the app and the
    /// trigger dies. Keep the process alive across all window closes.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    private func showPermissionOnboarding() {
        let controller = OnboardingWindowController()
        onboardingWindowController = controller

        controller.show(service: permissionsService, launch: onboardingLaunch) { [weak self] in
            guard let self else { return }
            self.onboardingWindowController = nil
            self.continueTriggerOnboarding()
        }

        // Force polling so the grant is detected even if the SwiftUI view's
        // .onAppear is somehow late or skipped.
        permissionsService.startPolling()
        permissionsService.promptAccessibility()
    }

    private func setupMenuBar() {
        Self.quitApplication = {
            Task { @MainActor in
                _ = await Self.performApplicationQuit(
                    flush: Self.flushPendingSettingsChanges,
                    terminate: { NSApp.terminate(nil) }
                )
            }
        }

        menuBarController = MenuBarController()
        menuBarController?.setup()

        menuBarController?.onPreferencesClicked = { [weak self] in
            self?.showSettings()
        }

        menuBarController?.onIdentifyInputClicked = { [weak self] in
            self?.showInputRecorder()
        }

        menuBarController?.onQuitClicked = {
            Self.quitApplication?()
        }

        menuBarController?.onRestartClicked = {
            Self.restartApplication?()
        }

        Self.restartApplication = {
            Task { @MainActor in
                _ = await Self.performApplicationRestart(
                    flush: Self.flushPendingSettingsChanges,
                    relaunch: { await Self.launchNewApplicationInstance() },
                    terminate: { NSApp.terminate(nil) }
                )
            }
        }
    }

    /// Returns false and leaves the process running when pending configuration
    /// cannot be made durable. This prevents Quit from racing autosave.
    @discardableResult
    static func performApplicationQuit(
        flush: (() async -> Bool)?,
        terminate: () -> Void
    ) async -> Bool {
        guard await (flush?() ?? true) else { return false }
        terminate()
        return true
    }

    /// Flushes pending settings, starts a new app instance, then terminates this one.
    /// If either the flush or launch fails, the current process remains running.
    @discardableResult
    static func performApplicationRestart(
        flush: (() async -> Bool)?,
        relaunch: () async -> Bool,
        terminate: () -> Void
    ) async -> Bool {
        guard await (flush?() ?? true), await relaunch() else { return false }
        terminate()
        return true
    }

    private static func launchNewApplicationInstance() async -> Bool {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        return await withCheckedContinuation { continuation in
            NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, error in
                continuation.resume(returning: error == nil)
            }
        }
    }

    /// Trigger-up keeps the HUD alive whenever the hovered selection resolves
    /// to a submenu expansion, including a Reveal branch that hover already
    /// expanded before the release event arrived.
    static func keepsRingOpen(after result: RingCommitResult) -> Bool {
        result == .expanded
    }

    private func showInputRecorder() {
        if inputRecorderWindowController == nil {
            inputRecorderWindowController = InputRecorderWindowController()
        }
        inputRecorderWindowController?.onOpenSettings = { [weak self] in self?.showSettings() }
        inputRecorderWindowController?.show()
    }

    private func setupTriggers() {
        guard triggerService == nil else { return }
        let service = TriggerService()
        service.onDisabled = { [weak self] reason in
            self?.safetyCoordinator.reportDisabled(source: "trigger-service", reason: reason)
        }
        service.onInstallFailed = { [weak self] in
            self?.safetyCoordinator.reportInstallFailure(source: "trigger-service")
        }
        triggerService = service
        ringWindowController = RingWindowController()

        // Only called after configuration loading succeeds and permission is granted.
        service.start(config: configuration.triggers)

        triggerEventTask = Task { [weak self] in
            for await event in service.events {
                guard let self else { return }
                self.handleTriggerEvent(event)
            }
        }
    }

    private func handleTriggerEvent(_ event: TriggerEvent) {
        // Includes the `.cancel` that `TriggerService.stop()` yields asynchronously
        // during loss teardown; the HUD is already closed.
        guard !safetyCoordinator.isLatched else { return }
        let effect = invocationOwnership.handle(event)
        switch (effect, event) {
        case (.show, .down(let source, let mode, let pointerLocation)):
            showRing(at: pointerLocation, commitsOnPointerRelease: mode == .tapToggle, source: source)
        case (.replace, .down(let source, _, _)):
            replaceRingInvocation(source: source)
        case (.dismiss, _):
            closeRing()
        case (.updateSelection, .moved(_, _, let pointerLocation)):
            updateRingSelection(at: pointerLocation)
        case (.commitRelease, .up(_, _, let pointerLocation)):
            hideRing(commitHovered: true, pointerLocation: pointerLocation)
        default:
            break
        }
    }

    private func loadConfiguration() {
        configService = ConfigurationService()

        // In-view tap-toggle commits call the model directly; the view can't tear
        // down the panel, so route closing commits back here. Hold-release commits
        // through the trigger-up path below. This only fires on a *closing* commit,
        // never on expansion.
        ringViewModel.requestClose = { [weak self] in
            self?.closeRing()
        }
        ringViewModel.requestOpenMenuItemsSettings = { [weak self] in
            self?.showMenuItemsSettings()
        }

        AppDelegate.applyConfiguration = { [weak self] config in
            self?.applySavedConfiguration(config)
        }
        AppDelegate.recoverLoadedSettingsConfiguration = { [weak self] config in
            self?.recoverLoadedSettingsConfiguration(config)
        }

        // Open the "Identify Input" diagnostic from Settings / menu bar (no longer auto-opened).
        AppDelegate.showIdentifyInput = { [weak self] in self?.showInputRecorder() }

        Task {
            guard let configService else { return }
            do {
                triggerOnboardingConfigurationLoaded(.success(try await configService.loadResult()))
            } catch {
                // The Triggers workspace exposes its existing load error and Retry.
                // No defaults are applied or written after an unreadable file.
                triggerOnboardingConfigurationLoaded(.failure(error))
            }
        }
    }

    private func applyRuntimeConfiguration(_ config: Configuration) {
        configuration = config
        // After a trust loss nothing may start taps again: not a configuration
        // save, not a permission grant.
        guard !safetyCoordinator.isLatched else { return }
        if !ringViewModel.isVisible { ringViewModel.load(from: config) }
        if let triggerService { triggerService.updateConfig(config.triggers) }
        else { setupTriggers() }
        applySettingsHotkey(config.triggers.openSettings)
        safetyCoordinator.startMonitoring()
    }

    private func showRing(at pointerLocation: CGPoint, commitsOnPointerRelease: Bool,
                          source: TriggerSource) {
        guard !safetyCoordinator.isLatched else { return }
        // keyDown repeats while held — without this guard each tick creates a new NSPanel.
        guard let controller = ringWindowController, !controller.isVisible else { return }

        let resolvedProfile = resolveInvocation(route: source.route)
        ringViewModel.load(resolved: resolvedProfile, presentation: configuration)

        // Each open starts at the root: no stale expansion/selection.
        ringViewModel.isVisible = true
        // Every invocation is centered on the current pointer. Record that
        // initial inside-r1 position explicitly so event coalescing cannot lose
        // the first half of Reveal's natural center-to-parent traversal.
        ringViewModel.updateActive(at: .zero, center: .zero)
        let mountedOpeningID = ringViewModel.prepareOpeningPlayback()

        // Runtime primary-button commits come from RingHostingView's native
        // mouse-up callback below. SwiftUI's DragGesture release is unreliable
        // in the tested non-activating panel, so keep it selection-only here.
        var view = RingMenuView(
            viewModel: ringViewModel,
            commitsOnPointerRelease: false,
            onCenterDrag: commitsOnPointerRelease ? { [weak controller] delta in
                controller?.movePanel(by: delta)
            } : nil
        )
        #if DEBUG
        let openingDiagnostics = HUDOpeningDiagnostics(
            invocation: mountedOpeningID, configuration: ringViewModel.appearance.motion,
            triggerPoint: pointerLocation, source: source,
            commitsOnPointerRelease: commitsOnPointerRelease
        )
        view.onOpeningFrame = openingDiagnostics.record
        view.onOpeningSettle = openingDiagnostics.settle
        view.onOpeningHover = { [weak controller, weak ringViewModel] point, center, hasSelection in
            let screenPoint = NSEvent.mouseLocation
            openingDiagnostics.hover(
                point: point, center: center, hasSelection: hasSelection,
                screenPoint: screenPoint,
                nativeCoordinates: controller?.hitTestCoordinates(forScreenPoint: screenPoint),
                deadZoneRadius: ringViewModel?.radii.r0 ?? 0
            )
        }
        #endif
        controller.show(
            at: pointerLocation,
            outerRadius: ringViewModel.radii.r3,
            content: view,
            onPrimaryMouseUp: commitsOnPointerRelease ? {
                [weak self, weak controller] point, center in
                // A transparent-corner mouse-down may have dismissed the HUD
                // before AppKit delivers this release.
                guard let self, controller?.isVisible == true,
                      Self.ownsTapTogglePrimaryCommit(self.invocationOwnership) else { return }
                self.ringViewModel.commit(at: point, center: center)
            } : nil,
            onOtherMouseDragged: commitsOnPointerRelease ? nil : {
                [weak ringViewModel] point, center in
                ringViewModel?.updateActive(at: point, center: center)
            }
        )

        #if DEBUG
        if let coordinates = controller.hitTestCoordinates(forScreenPoint: NSEvent.mouseLocation) {
            openingDiagnostics.mounted(point: coordinates.point, center: coordinates.center)
        }
        #endif

        // Mount animated content concealed and with no playback armed: initial
        // insertion can otherwise flash a settled frame in an AppKit panel.
        // Replay after one mounted frame, matching the
        // Settings preview's reliable identity-change path. The captured ID
        // prevents delayed work from touching a newer invocation.
        Task { @MainActor [weak self, weak controller] in
            do {
                try await Task.sleep(for: .milliseconds(16))
            } catch {
                return
            }
            guard let self, controller?.isVisible == true else { return }
            #if DEBUG
            openingDiagnostics.replay()
            #endif
            self.ringViewModel.replayOpening(afterMounting: mountedOpeningID)
        }

        startDismissMonitor()
    }

    private func replaceRingInvocation(source: TriggerSource) {
        guard ringWindowController?.isVisible == true else { return }
        let resolvedProfile = resolveInvocation(route: source.route)
        ringViewModel.cancelOpeningPlayback()
        ringViewModel.load(resolved: resolvedProfile, presentation: configuration)
        let commitsOnPointerRelease = invocationOwnership.presentationMode == .tapToggle
        let triggeringAuxiliaryButton: Int?
        if case .mouseButton(let buttonNumber) = source.physicalSource {
            triggeringAuxiliaryButton = buttonNumber
        } else {
            triggeringAuxiliaryButton = nil
        }
        let view = RingMenuView(
            viewModel: ringViewModel,
            openingPlaybackEnabled: false,
            commitsOnPointerRelease: false,
            onCenterDrag: commitsOnPointerRelease ? { [weak ringWindowController] delta in
                ringWindowController?.movePanel(by: delta)
            } : nil
        )
        ringWindowController?.replaceContent(
            outerRadius: ringViewModel.radii.r3,
            content: view,
            onPrimaryMouseUp: commitsOnPointerRelease ? {
                [weak self, weak ringWindowController] point, center in
                guard let self, ringWindowController?.isVisible == true,
                      Self.ownsTapTogglePrimaryCommit(self.invocationOwnership) else { return }
                self.ringViewModel.commit(at: point, center: center)
            } : nil,
            onOtherMouseDragged: commitsOnPointerRelease ? nil : {
                [weak ringViewModel] point, center in
                ringViewModel?.updateActive(at: point, center: center)
            },
            adoptingAuxiliaryButton: triggeringAuxiliaryButton
        )
    }

    private func resolveInvocation(route: HUDInvocationRoute) -> ResolvedHUDProfile {
        let app = NSWorkspace.shared.frontmostApplication
        let snapshot = FrontmostAppSnapshot(
            processIdentifier: app?.processIdentifier ?? 0,
            bundleIdentifier: app?.bundleIdentifier,
            localizedName: app?.localizedName
        )
        return configuration.resolveHUD(
            route: route,
            frontmostApp: snapshot,
            mousePlusBundleIdentifier: Bundle.main.bundleIdentifier ?? "com.xpycode.MousePlus"
        )
    }

    static func ownsTapTogglePrimaryCommit(_ ownership: HUDInvocationOwnership) -> Bool {
        ownership.presentationMode == .tapToggle
    }

    /// Global auxiliary-button drags can remain owned by the app that received
    /// trigger-down, even after the HUD appears. Convert them through the live
    /// hosting view so RingViewModel sees the same flipped coordinates as SwiftUI.
    private func updateRingSelection(at screenPoint: CGPoint) {
        guard let coordinates = ringWindowController?.hitTestCoordinates(
            forScreenPoint: screenPoint
        ) else { return }
        ringViewModel.updateActive(at: coordinates.point, center: coordinates.center)
    }

    /// Trigger-release / explicit commit path.
    ///
    /// `commitActive()` either EXPANDS an expandable middle wedge (ring stays open)
    /// or fires a direct/outer action and resets (ring should close). Reveal can
    /// auto-expand the hovered parent before trigger-up, so the commit result —
    /// not an expansion-state delta — decides whether the HUD stays open.
    private func hideRing(commitHovered: Bool, pointerLocation: CGPoint? = nil) {
        guard commitHovered else {
            closeRing()
            return
        }

        let result = Self.commitHoldRelease(
            viewModel: ringViewModel,
            pointerLocation: pointerLocation,
            resolveCoordinates: { [weak ringWindowController] screenPoint in
                ringWindowController?.hitTestCoordinates(forScreenPoint: screenPoint)
            }
        )

        // Expanded (or re-pointed an expansion) → keep the ring open.
        // Direct/outer commit (or dead-zone cancel that left no expansion) → close.
        // Note: a direct commit also invokes `requestClose` via the view model, which
        // routes to `closeRing()`; closing again here is harmless (hide()/reset are idempotent).
        if Self.keepsRingOpen(after: result) { return }
        closeRing()
    }

    /// Commits from the trigger callback's pointer snapshot, not whatever hover
    /// update happened to run most recently. Mouse-up and SwiftUI hover/release
    /// delivery are separate callbacks, so their ordering is not a safe source
    /// of the final selection.
    @discardableResult
    static func commitHoldRelease(
        viewModel: RingViewModel,
        pointerLocation: CGPoint?,
        resolveCoordinates: (CGPoint) -> (point: CGPoint, center: CGPoint)?
    ) -> RingCommitResult {
        guard let pointerLocation,
              let coordinates = resolveCoordinates(pointerLocation) else {
            return viewModel.commitActive()
        }
        return viewModel.commit(at: coordinates.point, center: coordinates.center)
    }

    /// Tear down the ring panel and return the view model to root state.
    /// Single close path reused by trigger-release, in-view commits (via
    /// `requestClose`), Escape, and click-outside.
    private func closeRing() {
        invocationOwnership.close()
        stopDismissMonitor()
        ringWindowController?.hide()
        ringViewModel.isVisible = false
        ringViewModel.reset()
    }

    // MARK: - Dismiss monitors (T10)

    private func startDismissMonitor() {
        let monitor = dismissMonitor ?? DismissMonitor()
        dismissMonitor = monitor
        monitor.start(
            onEscape: { [weak self] in
                guard let self else { return }
                guard self.configuration.behavior.dismissOnEscape else { return }
                // Esc first collapses an expanded outer ring back to root; only a
                // second Esc (when nothing is expanded) closes the whole ring.
                if self.ringViewModel.handleEscape() {
                    self.closeRing()
                }
            },
            onClickOutside: { [weak self] in
                guard let self else { return }
                guard self.configuration.behavior.dismissOnClickOutside else { return }
                self.closeRing()
            },
            onLocalMouseDown: { [weak self] event in
                guard let self,
                      self.configuration.behavior.dismissOnClickOutside else { return false }
                // The trigger service owns tap-toggle semantics. If this same
                // press also lands in the panel's transparent square, closing
                // here races the queued trigger and can immediately reopen it.
                guard !Self.isTapToggleMouseTrigger(
                    eventType: event.type,
                    buttonNumber: event.buttonNumber,
                    binding: self.configuration.triggers.mouseButton
                ),
                      let disposition = self.ringWindowController?.localMouseDownDisposition(
                          for: event,
                          outerRadius: self.ringViewModel.radii.r3
                      ) else { return false }
                switch disposition {
                case .ignore:
                    return false
                case .dismissPreservingEvent:
                    self.closeRing()
                    return false
                case .dismissConsumingEvent:
                    self.closeRing()
                    return true
                }
            }
        )
    }

    static func isTapToggleMouseTrigger(
        eventType: NSEvent.EventType,
        buttonNumber: Int,
        binding: TriggerBinding
    ) -> Bool {
        guard eventType == .otherMouseDown,
              case .mouseButton(let configuredButton, let mode) = binding else { return false }
        return mode == .tapToggle && buttonNumber == configuredButton
    }

    private func stopDismissMonitor() {
        dismissMonitor?.stop()
    }

    private func showSettings() {
        settingsActionContextProvider.recordFrontmostApplicationBeforeSettingsActivation()
        NSApp.activate(ignoringOtherApps: true)
        Self.openSettingsAction?()
    }

    private func showTriggersSettings() {
        settingsActionContextProvider.recordFrontmostApplicationBeforeSettingsActivation()
        NSApp.activate(ignoringOtherApps: true)
        Self.openTriggersSettingsAction?()
    }

    private func showMenuItemsSettings() {
        settingsActionContextProvider.recordFrontmostApplicationBeforeSettingsActivation()
        NSApp.activate(ignoringOtherApps: true)
        Self.openMenuItemsSettingsAction?()
    }

    /// (Re)bind the global "open Settings" hotkey to `binding`. A `.keyboard` binding
    /// arms a `KeyboardTriggerMonitor` that opens Settings on key-down; any other
    /// binding (including `.none`) tears the monitor down. Re-armed after the
    /// Accessibility grant and after a rebind in the Triggers tab — the same pattern
    /// `setupTriggers`/`applyConfiguration` use for the ring triggers.
    private func applySettingsHotkey(_ binding: TriggerBinding) {
        guard !safetyCoordinator.isLatched else { return }
        settingsHotkeyMonitor?.stop()
        guard case let .keyboard(keyCode, modifiers, _) = binding else {
            settingsHotkeyMonitor = nil
            return
        }
        let monitor = settingsHotkeyMonitor ?? KeyboardTriggerMonitor()
        settingsHotkeyMonitor = monitor
        monitor.onDisabled = { [weak self] reason in
            self?.safetyCoordinator.reportDisabled(source: "settings-hotkey", reason: reason)
        }
        monitor.onInstallFailed = { [weak self] in
            self?.safetyCoordinator.reportInstallFailure(source: "settings-hotkey")
        }
        monitor.start(
            keyCode: keyCode,
            modifiers: modifiers,
            onDown: { [weak self] in self?.showSettings() },
            onUp: {}
        )
    }

    func applicationWillTerminate(_ notification: Notification) {
        closeRing()
        triggerEventTask?.cancel()
        triggerService?.stop()
        settingsHotkeyMonitor?.stop()
        menuBarController?.remove()
        actionErrorHUDController.dismiss()
    }
}
