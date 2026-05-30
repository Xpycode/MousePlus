import AppKit
import SwiftUI

/// Hosts `InputRecorderView` + `HIDInspectorPanel` in a standalone titled
/// window. LSUIElement apps have no main window, so every secondary surface
/// needs its own NSWindow.
@MainActor
final class InputRecorderWindowController {
    private var window: NSWindow?
    private let recorder = InputRecorderService()
    private let inspector = IOHIDDeviceInspector()

    func show() {
        guard window == nil else {
            window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        recorder.start()
        inspector.start()

        let view = IdentifyInputContainerView(
            recorder: recorder,
            inspector: inspector,
            onDone: { [weak self] in self?.close() }
        )
        let host = NSHostingView(rootView: view)

        let w = NSWindow(
            contentRect: NSRect(origin: .zero, size: host.fittingSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        w.title = "Identify Input"
        w.contentView = host
        w.center()
        w.isReleasedWhenClosed = false
        w.level = .floating
        w.collectionBehavior = [.moveToActiveSpace]

        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
        self.window = w
    }

    func close() {
        inspector.stop()
        recorder.stop()
        window?.close()
        window = nil
    }
}

/// Container so both the existing NSEvent-based recorder and the new
/// IOHIDManager inspector can sit in one window.
private struct IdentifyInputContainerView: View {
    @Bindable var recorder: InputRecorderService
    @Bindable var inspector: IOHIDDeviceInspector
    var onDone: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            InputRecorderView(service: recorder, onDone: onDone)
            Divider()
            HIDInspectorPanel(inspector: inspector)
        }
    }
}
