import XCTest
import SwiftUI
@testable import MousePlus

@MainActor
final class MenuEditorPreviewSyncTests: XCTestCase {
    func testHostedPreviewLoadsAndTracksItemsRotationAndRadii() async throws {
        let model = MenuEditorModel(inner: RingMenuItem.sampleInnerItems,
                                    middle: RingMenuItem.sampleItems)
        var appearance = AppearanceConfig.default
        appearance.deadZone = 17
        appearance.innerEdge = 64
        appearance.middleEdge = 128
        appearance.outerEdge = 192
        let host = NSHostingView(rootView: RingPreviewSelector(model: model, appearance: appearance))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 500),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = host
        defer { window.contentView = nil }

        func surface(_ view: NSView) -> InteractionNSView? {
            if let view = view as? InteractionNSView { return view }
            return view.subviews.lazy.compactMap { surface($0) }.first
        }
        func settle() async {
            for _ in 0..<10 {
                host.layoutSubtreeIfNeeded()
                try? await Task.sleep(for: .milliseconds(10))
            }
        }
        await settle()
        let interaction = try XCTUnwrap(surface(host))
        XCTAssertEqual(interaction.coordinator?.snapshot.radii.r0, 17)
        XCTAssertEqual(interaction.coordinator?.snapshot.radii.r3, 192)

        var config = Configuration(appearance: appearance)
        config.inner.append(RingMenuItem(label: "Extra", icon: "app.fill", actionType: .appSwitch))
        config.middle.append(RingMenuItem(label: "Extra", icon: "app.fill", actionType: .appSwitch))
        config.hudCustomization.inner.layout.angularOffset = 61
        model.load(from: config)
        await settle()
        let loaded = try XCTUnwrap(interaction.coordinator?.snapshot)
        XCTAssertEqual(loaded.innerCount, config.inner.count)
        XCTAssertEqual(loaded.middleCount, config.middle.count)
        let runtime = RingViewModel()
        runtime.load(from: config)
        XCTAssertEqual(loaded.geometry, runtime.geometry)

        model.inner.removeLast()
        model.hudCustomization.inner.layout.angularOffset = 25
        await settle()
        XCTAssertEqual(interaction.coordinator?.snapshot.innerCount, model.inner.count)
        config.inner = model.inner
        config.hudCustomization = model.hudCustomization
        runtime.load(from: config)
        XCTAssertEqual(interaction.coordinator?.snapshot.geometry, runtime.geometry)
    }
}
