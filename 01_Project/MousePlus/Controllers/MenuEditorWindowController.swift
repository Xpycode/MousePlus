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

    /// True once the one long-lived observation chain has been armed. The chain
    /// survives window close (it observes the model, not the window), so arming
    /// again on reopen would stack a second concurrent chain per open/close cycle.
    private var isObservingModel = false

    /// Save gate. Saves are allowed only in `.loaded` — flushing in `.pending`
    /// would merge the still-empty model into a default `Configuration` and
    /// overwrite the user's real file (empty rings, unbound trigger); saving in
    /// `.failed` would persist sample defaults over a config that exists on disk
    /// but didn't decode (e.g. a hand-edit gone wrong).
    private enum LoadState { case pending, loaded, failed }
    private var loadState: LoadState = .pending

    func show() {
        // Bring an existing window forward instead of rebuilding it.
        if let window {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            // Refresh from disk so the editor reflects any external changes.
            Task { @MainActor in
                await self.refreshFromDisk()
            }
            return
        }

        // Load the current config and populate the model before presenting. The
        // view is reactive, so a slightly-late populate still renders correctly.
        Task { @MainActor in
            await self.refreshFromDisk()
        }

        let view = MenuEditorView(
            model: model,
            onDone: { [weak self] in self?.window?.close() }
        )
        let host = NSHostingView(rootView: view)

        let w = NSWindow(
            // Wider than tall now that the ring and detail form sit side by side
            // (was 560×620 when they were stacked). contentMinSize clamps the
            // autosaved frame up too, so an older saved narrow frame can't
            // restore the panes into a squeezed state.
            contentRect: NSRect(origin: .zero, size: NSSize(width: 960, height: 660)),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        w.title = "Menu Items"
        w.contentView = host
        w.contentMinSize = NSSize(width: 900, height: 600)
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

    // MARK: - Load

    /// Reload the model + merge base from disk. Awaits any in-flight save first:
    /// on a close→reopen inside the debounce window, reading the file before the
    /// close-flush lands would load stale rings — and the autosave chain would
    /// then write those stale rings back over the flushed edit.
    ///
    /// `load()` returns a default `Configuration` when the file is simply absent
    /// (fresh install — defaults are correct); it THROWS only when the file
    /// exists but can't be read/decoded. In that case we must NOT populate the
    /// model with defaults: the autosave chain would persist those defaults over
    /// the user's real (recoverable) file 400ms later. Instead, lock saves out
    /// and tell the user.
    private func refreshFromDisk() async {
        if let pending = saveTask {
            await pending.value
        }
        do {
            let cfg = try await configService.load()
            baseConfig = cfg
            model.load(from: cfg)
            loadState = .loaded
            observeForAutosave()
        } catch {
            loadState = .failed
            presentLoadFailure(error)
        }
    }

    /// Explain a decode failure and why editing won't persist until it's fixed.
    private func presentLoadFailure(_ error: Error) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Couldn't Read the Saved Menu Configuration"
        alert.informativeText = """
        The config file exists but couldn't be decoded \
        (\(error.localizedDescription)) Saving is disabled so the file isn't \
        overwritten with defaults. Fix or remove \
        ~/Library/Application Support/MousePlus/config.json, then reopen this window.
        """
        if let window {
            alert.beginSheetModal(for: window)
        } else {
            alert.runModal()
        }
    }

    // MARK: - Debounced autosave + live-apply

    /// Arm the single long-lived observation chain (re-armed after each change —
    /// the `withObservationTracking` callback is one-shot per Apple's contract).
    private func observeForAutosave() {
        guard !isObservingModel else { return }
        isObservingModel = true
        armObservation()
    }

    private func armObservation() {
        withObservationTracking {
            _ = model.inner
            _ = model.middle
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.scheduleSave()
                self.armObservation()   // re-arm
            }
        }
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(400))
            if Task.isCancelled { return }
            await self.saveNow()
        }
    }

    /// Merge the edited rings into a FRESH read of the on-disk config and persist.
    ///
    /// Mirrors `RingAppearanceSettingsView.scheduleSave`'s read-modify-write: the
    /// merge base is re-read at save time (not the window-open `baseConfig`
    /// snapshot), so triggers/appearance/behavior edited in Settings while this
    /// window is open are never clobbered by a stale snapshot. (If that fresh
    /// read fails, fall back to `baseConfig` — the last config this controller
    /// knew to be good — rather than dropping to sample defaults.)
    private func saveNow() async {
        guard loadState == .loaded else { return }
        let base = (try? await configService.load()) ?? baseConfig
        let merged = model.merged(into: base)
        baseConfig = merged
        try? await configService.save(merged)
        AppDelegate.applyMenuItems?(merged)
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        // Cancel any pending debounced save and flush one final save so an edit
        // that landed inside the debounce window is never lost. The flush lives
        // in `saveTask` so a quick reopen's `refreshFromDisk` can await it.
        // (`saveNow` itself refuses to run unless a load succeeded, so closing
        // before the first load — or after a failed one — never writes.)
        saveTask?.cancel()
        saveTask = Task { @MainActor in
            await self.saveNow()
        }
        window = nil
    }
}
