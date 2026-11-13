import XCTest
import AppKit
import SwiftUI
@testable import MousePlus

/// App-hosted only: references AppDelegate and the SwiftUI/MacUIKitSettings
/// editor, so it is not part of the headless input-safety harness.
final class KeystrokeCaptureEditorTests: XCTestCase {
    @MainActor
    func testUnitTestHostDoesNotStartProductionServices() {
        XCTAssertNil(AppDelegate.applyConfiguration,
                     "The test host must not install production configuration/trigger services")
    }

    @MainActor
    func testNativeRecordButtonCommitsCapturedKeyThroughEditorBinding() async throws {
        let item = RingMenuItem(label: "Copy", icon: "doc.on.doc", actionType: .sendKeystroke)
        let model = MenuEditorModel(inner: [item], middle: [])
        let binding = try XCTUnwrap(model.binding(forItem: item.id, band: .inner))
        let tap = CaptureTapStub()
        let recorder = KeystrokeCaptureRecorder(tap: tap, timeout: .seconds(60))
        let host = NSHostingView(rootView: ActionDataEditor(item: binding, recorder: recorder))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 200),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = host
        defer { recorder.cancel(); window.contentView = nil }
        func button(_ view: NSView) -> NSButton? {
            if let button = view as? NSButton,
               button.accessibilityIdentifier() == "menuItems.editor.keystroke.record" { return button }
            return view.subviews.lazy.compactMap { button($0) }.first
        }
        host.layoutSubtreeIfNeeded()
        try XCTUnwrap(button(host)).performClick(nil)
        XCTAssertTrue(recorder.isRecording)
        XCTAssertEqual(tap.send(.keyDown(keyCode: 0, modifiers: 0, isRepeat: false)), .consume)
        XCTAssertEqual(tap.send(.keyUp(keyCode: 0)), .consume)
        for _ in 0..<20 {
            host.layoutSubtreeIfNeeded()
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(model.inner[0].keystrokePayload, .key(keyCode: 0, modifiers: 0))
    }
}
