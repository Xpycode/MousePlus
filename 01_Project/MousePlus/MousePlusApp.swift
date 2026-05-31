import SwiftUI

@main
struct MousePlusApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @Environment(\.openSettings) private var openSettings

    var body: some Scene {
        // Settings window (opened from menu bar)
        Settings {
            SettingsView()
        }
    }

    init() {
        // Store reference for AppDelegate to use
        AppDelegate.openSettingsAction = { [self] in
            openSettings()
        }
    }
}

/// App delegate for menu bar and trigger setup.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static var openSettingsAction: (() -> Void)?

    /// Settings → live ring bridge: pushes an edited `AppearanceConfig` into the
    /// shared ring view model so changes apply without restarting (also persisted
    /// to disk by Settings, so the next open reflects it regardless).
    @MainActor static var applyAppearance: ((AppearanceConfig) -> Void)?

    /// Settings → live trigger bridge: pushes an edited `TriggersConfig` into the
    /// running `TriggerService` so a rebind takes effect immediately (also persisted
    /// to disk by Settings, so the next launch reflects it regardless).
    @MainActor static var applyTriggers: ((TriggersConfig) -> Void)?

    private var menuBarController: MenuBarController?
    private var ringWindowController: RingWindowController?
    private var triggerService: TriggerService?
    private var triggerEventTask: Task<Void, Never>?
    private var configService: ConfigurationService?
    private var permissionsService = PermissionsService()
    private var onboardingWindowController: OnboardingWindowController?
    private var inputRecorderWindowController: InputRecorderWindowController?

    private var ringViewModel = RingViewModel()
    private var dismissMonitor: DismissMonitor?

    /// Loaded config; drives dismiss behavior. Sensible default until load completes.
    private var configuration = Configuration()

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenuBar()
        loadConfiguration()

        if permissionsService.isGranted {
            setupTriggers()
            showInputRecorder()  // menu-bar-icon bug workaround: auto-open diagnostic at launch
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
            self.showInputRecorder()  // menu-bar-icon bug workaround: auto-open diagnostic
        }

        controller.show(service: permissionsService) { [weak self] in
            self?.onboardingWindowController = nil
        }

        // Force polling so the grant is detected even if the SwiftUI view's
        // .onAppear is somehow late or skipped.
        permissionsService.startPolling()
        permissionsService.promptAccessibility()
    }

    private func setupMenuBar() {
        menuBarController = MenuBarController()
        menuBarController?.setup()

        menuBarController?.onPreferencesClicked = { [weak self] in
            self?.showSettings()
        }

        menuBarController?.onIdentifyInputClicked = { [weak self] in
            self?.showInputRecorder()
        }

        menuBarController?.onQuitClicked = {
            NSApp.terminate(nil)
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
                    self.showRing()
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

        // Live-apply appearance edits from the Settings window into the shared ring.
        AppDelegate.applyAppearance = { [weak self] appearance in
            guard let self else { return }
            self.configuration.appearance = appearance
            self.ringViewModel.appearance = appearance
            self.ringViewModel.radii = appearance.bandRadii
        }

        // Live-apply trigger rebinds from the Triggers settings tab into the running monitors.
        AppDelegate.applyTriggers = { [weak self] triggers in
            guard let self else { return }
            self.configuration.triggers = triggers
            self.triggerService?.updateConfig(triggers)
        }

        Task {
            if let config = try? await configService?.load() {
                configuration = config
                ringViewModel.load(from: config)
                // Now that the saved triggers are loaded, snap the live monitors to them
                // (setupTriggers may have started with the default before load finished).
                triggerService?.updateConfig(config.triggers)
            }
        }
    }

    private func showRing() {
        // keyDown repeats while held — without this guard each tick creates a new NSPanel.
        guard let controller = ringWindowController, !controller.isVisible else { return }

        // Capture the frontmost app BEFORE showing our (non-activating) panel, so
        // window/menu actions target the user's app rather than MousePlus.
        ringViewModel.frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier

        // Each open starts at the root: no stale expansion/selection.
        ringViewModel.reset()
        ringViewModel.isVisible = true

        let mouseLocation = NSEvent.mouseLocation
        let view = RingMenuView(viewModel: ringViewModel)
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
            showRing()
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
                if self.ringViewModel.expandedParentIndex != nil {
                    self.ringViewModel.collapse()
                } else {
                    self.closeRing()
                }
            },
            onClickOutside: { [weak self] in
                guard let self else { return }
                guard self.configuration.behavior.dismissOnClickOutside else { return }
                self.closeRing()
            }
        )
    }

    private func stopDismissMonitor() {
        dismissMonitor?.stop()
    }

    private func showSettings() {
        NSApp.activate(ignoringOtherApps: true)
        Self.openSettingsAction?()
    }

    func applicationWillTerminate(_ notification: Notification) {
        triggerEventTask?.cancel()
        triggerService?.stop()
        menuBarController?.remove()
    }
}
