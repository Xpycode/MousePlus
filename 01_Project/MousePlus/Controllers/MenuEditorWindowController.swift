import AppKit
import SwiftUI

/// Hosts `MenuEditorView` in a standalone titled window. LSUIElement apps have no
/// main window, so every secondary surface needs its own NSWindow. Mirrors
/// `InputRecorderWindowController`'s lifecycle (lazy window, retained by AppDelegate).
///
/// Edits autosave (debounced) into the on-disk config and live-apply into the
/// running ring via `AppDelegate.applyMenuItems`. The `baseConfig` snapshot
/// preserves triggers/appearance/behavior so merging only swaps the rings.
@MainActor
final class MenuEditorWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private let model = MenuEditorModel(inner: [], middle: [])
    private let configService = ConfigurationService()

    /// The on-disk config the edits merge into (preserves triggers/appearance/behavior).
    private var baseConfig = Configuration()

    private var saveTask: Task<Void, Never>?

    func show() {
        // Bring an existing window forward instead of rebuilding it.
        if let window {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            // Refresh from disk so the editor reflects any external changes.
            Task { @MainActor in
                let cfg = (try? await configService.load()) ?? Configuration()
                self.baseConfig = cfg
                self.model.load(from: cfg)
            }
            return
        }

        // Load the current config and populate the model before presenting. The
        // view is reactive, so a slightly-late populate still renders correctly.
        Task { @MainActor in
            let cfg = (try? await configService.load()) ?? Configuration()
            self.baseConfig = cfg
            self.model.load(from: cfg)
            self.observeForAutosave()
        }

        let view = MenuEditorView(
            model: model,
            onDone: { [weak self] in self?.window?.close() }
        )
        let host = NSHostingView(rootView: view)

        let w = NSWindow(
            contentRect: NSRect(origin: .zero, size: NSSize(width: 560, height: 620)),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        w.title = "Menu Items"
        w.contentView = host
        w.contentMinSize = NSSize(width: 560, height: 620)
        w.delegate = self
        w.isReleasedWhenClosed = false
        w.setFrameAutosaveName("MenuEditorWindow")
        if w.frame.origin == .zero {
            w.center()
        }
        w.level = .normal
        w.collectionBehavior = [.moveToActiveSpace]

        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
        self.window = w
    }

    // MARK: - Debounced autosave + live-apply

    /// Observe `@Observable` model edits and re-arm after each change (the
    /// `withObservationTracking` callback is one-shot per Apple's contract).
    private func observeForAutosave() {
        withObservationTracking {
            _ = model.inner
            _ = model.middle
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.scheduleSave()
                self.observeForAutosave()   // re-arm
            }
        }
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(400))
            if Task.isCancelled { return }
            let merged = self.model.merged(into: self.baseConfig)
            self.baseConfig = merged
            try? await self.configService.save(merged)
            AppDelegate.applyMenuItems?(merged)
        }
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        // Cancel any pending debounced save and flush one final save so an edit
        // that landed inside the debounce window is never lost.
        saveTask?.cancel()
        let merged = model.merged(into: baseConfig)
        baseConfig = merged
        Task { @MainActor in
            try? await configService.save(merged)
            AppDelegate.applyMenuItems?(merged)
        }
        window = nil
    }
}
