import SwiftUI

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

    private var menuBarController: MenuBarController?
    private var ringWindowController: RingWindowController?
    private var triggerService: TriggerService?
    private var triggerEventTask: Task<Void, Never>?
    private var configService: ConfigurationService?
    private var permissionsService = PermissionsService()
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
    private lazy var ringViewModel = RingViewModel(actionResultRouter: actionResultRouter)
    private var dismissMonitor: DismissMonitor?
    let settingsActionContextProvider = SettingsActionContextProvider()

    /// Loaded config; drives dismiss behavior. Sensible default until load completes.
    private var configuration = Configuration()

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenuBar()
        loadConfiguration()

        if permissionsService.isGranted {
            setupTriggers()
            applySettingsHotkey(configuration.triggers.openSettings)  // reliable way into Settings
        } else {
            showPermissionOnboarding()
        }
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

        permissionsService.onGranted = { [weak self] in
            guard let self else { return }
            self.setupTriggers()
            self.applySettingsHotkey(self.configuration.triggers.openSettings)  // re-arm after grant
        }

        controller.show(service: permissionsService) { [weak self] in
            guard let self else { return }
            self.onboardingWindowController = nil
            self.showSettings()
        }

        // Force polling so the grant is detected even if the SwiftUI view's
        // .onAppear is somehow late or skipped.
        permissionsService.startPolling()
        permissionsService.promptAccessibility()
    }

    private func setupMenuBar() {
        Self.quitApplication = {
            NSApp.terminate(nil)
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
    }

    private func showInputRecorder() {
        if inputRecorderWindowController == nil {
            inputRecorderWindowController = InputRecorderWindowController()
        }
        inputRecorderWindowController?.onOpenSettings = { [weak self] in self?.showSettings() }
        inputRecorderWindowController?.show()
    }

    private func setupTriggers() {
        let service = TriggerService()
        triggerService = service
        ringWindowController = RingWindowController()

        // Start from whatever config has loaded so far; `loadConfiguration`'s async
        // completion calls `updateConfig` once the saved triggers are in hand.
        service.start(config: configuration.triggers)

        triggerEventTask = Task { [weak self] in
            for await event in service.events {
                guard let self else { return }
                switch event {
                case .down(_, .holdRelease):
                    self.showRing(commitsOnPointerRelease: false)
                case .up(_, .holdRelease):
                    self.hideRing(commitHovered: true)
                case .down(_, .tapToggle):
                    self.toggleRing()
                case .up(_, .tapToggle):
                    break  // tap-toggle ignores releases; commit is via slice click
                }
            }
        }
    }

    private func loadConfiguration() {
        configService = ConfigurationService()

        // In-view commits (tap-toggle click, hold-release drag end) call
        // `commitActive()` directly; the view can't tear down the panel, so route
        // closing commits back here. Only fires on a *closing* commit, never on expand.
        ringViewModel.requestClose = { [weak self] in
            self?.closeRing()
        }
        ringViewModel.requestOpenMenuItemsSettings = { [weak self] in
            self?.showMenuItemsSettings()
        }

        AppDelegate.applyConfiguration = { [weak self] config in
            guard let self else { return }
            self.configuration = config
            self.ringViewModel.load(from: config)
            self.triggerService?.updateConfig(config.triggers)
            self.applySettingsHotkey(config.triggers.openSettings)
        }

        // Open the "Identify Input" diagnostic from Settings / menu bar (no longer auto-opened).
        AppDelegate.showIdentifyInput = { [weak self] in self?.showInputRecorder() }

        Task {
            if let config = try? await configService?.load() {
                configuration = config
                ringViewModel.load(from: config)
                // Now that the saved triggers are loaded, snap the live monitors to them
                // (setupTriggers may have started with the default before load finished).
                triggerService?.updateConfig(config.triggers)
                applySettingsHotkey(config.triggers.openSettings)
            }
        }
    }

    private func showRing(commitsOnPointerRelease: Bool) {
        // keyDown repeats while held — without this guard each tick creates a new NSPanel.
        guard let controller = ringWindowController, !controller.isVisible else { return }

        // Capture the frontmost app BEFORE showing our (non-activating) panel, so
        // window/menu actions target the user's app rather than MousePlus.
        ringViewModel.frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier

        // Each open starts at the root: no stale expansion/selection.
        ringViewModel.reset()
        ringViewModel.isVisible = true

        let mouseLocation = NSEvent.mouseLocation
        let view = RingMenuView(
            viewModel: ringViewModel,
            commitsOnPointerRelease: commitsOnPointerRelease,
            onCenterDrag: commitsOnPointerRelease ? { [weak controller] delta in
                controller?.movePanel(by: delta)
            } : nil
        )
        controller.show(at: mouseLocation, content: view)

        startDismissMonitor()
    }

    /// Trigger-release / explicit commit path.
    ///
    /// `commitActive()` either EXPANDS an expandable middle wedge (ring stays open)
    /// or fires a direct/outer action and resets (ring should close). We detect
    /// which happened by comparing expansion state across the call: a transition
    /// into an expanded state means "expanded — keep open"; anything else closes.
    private func hideRing(commitHovered: Bool) {
        guard commitHovered else {
            closeRing()
            return
        }

        let wasExpanded = ringViewModel.expandedParentIndex != nil
        ringViewModel.commitActive()
        let isExpanded = ringViewModel.expandedParentIndex != nil

        // Just expanded (or re-pointed an expansion) → keep the ring open.
        // Direct/outer commit (or dead-zone cancel that left no expansion) → close.
        // Note: a direct commit also invokes `requestClose` via the view model, which
        // routes to `closeRing()`; closing again here is harmless (hide()/reset are idempotent).
        if isExpanded && !wasExpanded {
            return
        }
        closeRing()
    }

    /// Tear down the ring panel and return the view model to root state.
    /// Single close path reused by trigger-release, in-view commits (via
    /// `requestClose`), Escape, and click-outside.
    private func closeRing() {
        stopDismissMonitor()
        ringWindowController?.hide()
        ringViewModel.isVisible = false
        ringViewModel.reset()
    }

    /// Tap-toggle entry point: open the ring if hidden, close it (no commit) if visible.
    private func toggleRing() {
        if ringWindowController?.isVisible == true {
            hideRing(commitHovered: false)
        } else {
            showRing(commitsOnPointerRelease: true)
        }
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
                      self.configuration.behavior.dismissOnClickOutside,
                      self.ringWindowController?.shouldDismiss(
                        forLocalMouseDown: event,
                        outerRadius: self.ringViewModel.radii.r3
                      ) == true else { return false }
                self.closeRing()
                return true
            }
        )
    }

    private func stopDismissMonitor() {
        dismissMonitor?.stop()
    }

    private func showSettings() {
        settingsActionContextProvider.recordFrontmostApplicationBeforeSettingsActivation()
        NSApp.activate(ignoringOtherApps: true)
        Self.openSettingsAction?()
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
        settingsHotkeyMonitor?.stop()
        guard case let .keyboard(keyCode, modifiers, _) = binding else {
            settingsHotkeyMonitor = nil
            return
        }
        let monitor = settingsHotkeyMonitor ?? KeyboardTriggerMonitor()
        settingsHotkeyMonitor = monitor
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
