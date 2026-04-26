import SwiftUI
import Combine

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

/// App delegate for menu bar and hotkey setup
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static var openSettingsAction: (() -> Void)?

    private var menuBarController: MenuBarController?
    private var ringWindowController: RingWindowController?
    private var hotkeyService: HotkeyService?
    private var configService: ConfigurationService?

    private var ringViewModel = RingViewModel()
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenuBar()
        setupHotkey()
        loadConfiguration()
    }

    private func setupMenuBar() {
        menuBarController = MenuBarController()
        menuBarController?.setup()

        menuBarController?.onPreferencesClicked = { [weak self] in
            self?.showSettings()
        }

        menuBarController?.onQuitClicked = {
            NSApp.terminate(nil)
        }
    }

    private func setupHotkey() {
        hotkeyService = HotkeyService()
        ringWindowController = RingWindowController()

        Task {
            await hotkeyService?.start(with: .default)
        }

        // Subscribe to hotkey events
        Task {
            guard let service = hotkeyService else { return }

            for await _ in service.hotkeyPressed.values {
                showRing()
            }
        }

        Task {
            guard let service = hotkeyService else { return }

            for await _ in service.hotkeyReleased.values {
                hideRing()
            }
        }
    }

    private func loadConfiguration() {
        configService = ConfigurationService()

        Task {
            if let config = try? await configService?.load() {
                ringViewModel.items = config.items
            }
        }
    }

    private func showRing() {
        let mouseLocation = NSEvent.mouseLocation
        ringViewModel.show(at: mouseLocation)

        let view = RingMenuView(viewModel: ringViewModel)
        ringWindowController?.show(at: mouseLocation, content: view)
    }

    private func hideRing() {
        // Only hide if no item was clicked (hold+release mode)
        if ringViewModel.hoveredItem != nil {
            ringViewModel.selectItem(ringViewModel.hoveredItem!)
        }
        ringWindowController?.hide()
        ringViewModel.hide()
    }

    private func showSettings() {
        NSApp.activate(ignoringOtherApps: true)
        Self.openSettingsAction?()
    }

    func applicationWillTerminate(_ notification: Notification) {
        Task {
            await hotkeyService?.stop()
        }
        menuBarController?.remove()
    }
}
