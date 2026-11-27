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

    /// Compare the actual pixels (including the glyph) at each wedge with the
    /// configured runtime renderer. Geometry alone also passes with stale artwork.
    func testSixWedgeArtworkAndClicksFollowTheEditedProfile() async throws {
        let colors = [NSColor.red, .green, .blue, .orange, .purple, .brown]
        let icons = ["sun.max.fill", "leaf.fill", "drop.fill", "bolt.fill", "heart.fill", "moon.fill"]
        var global = Configuration(
            inner: zip(icons, colors).map { icon, color in
                RingMenuItem(label: icon, icon: icon, actionType: .appSwitch,
                             wedgeColor: HUDColor(nsColor: color))
            },
            middle: [RingMenuItem(label: "Orbit", icon: "globe", actionType: .appSwitch,
                                  wedgeColor: HUDColor(nsColor: .darkGray))]
        )
        global.hudCustomization.inner.layout.angularOffset = 30
        let model = MenuEditorModel(inner: RingMenuItem.sampleInnerItems, middle: RingMenuItem.sampleItems)
        let selector = RingPreviewSelector(model: model)
        let side = global.appearance.bandRadii.r3 * 2
        let center = CGPoint(x: side / 2, y: side / 2)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: side, height: side),
                              styleMask: .borderless, backing: .buffered, defer: false)
        let host = NSHostingView(rootView: selector)
        window.contentView = host
        defer { window.contentView = nil }

        func surface(_ view: NSView) -> InteractionNSView? {
            if let view = view as? InteractionNSView { return view }
            return view.subviews.lazy.compactMap { surface($0) }.first
        }

        func bitmap<V: View>(_ view: V) throws -> NSBitmapImageRep {
            let renderer = ImageRenderer(content: view.frame(width: side, height: side))
            renderer.scale = 1
            return NSBitmapImageRep(cgImage: try XCTUnwrap(renderer.cgImage))
        }

        func verify(_ config: Configuration, firstFrame: Bool = false) async throws {
            let runtime = RingViewModel()
            runtime.load(from: config)
            let expected = try bitmap(RingMenuView(
                viewModel: runtime, interactionEnabled: false,
                presentationMode: .staticEditor, exposesCenterSettings: false
            ))
            // A first-frame render gives the preview no lifecycle callback in
            // which to repair an initially incorrect set of wedges.
            let first = firstFrame ? try bitmap(selector.artwork) : nil
            for _ in 0..<5 {
                host.layoutSubtreeIfNeeded()
                try await Task.sleep(for: .milliseconds(10))
            }
            let interaction = try XCTUnwrap(surface(host)?.coordinator)
            let mounted = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: mounted)
            for band in [Band.inner, .middle] {
                let items = band == .inner ? config.inner : config.middle
                for (index, item) in items.enumerated() {
                    let point = RadialGeometry.centroid(
                        band: band, index: index, center: center, radii: runtime.radii,
                        geometry: runtime.geometry, expandedParentIndex: nil, outerCount: 0
                    )
                    for actual in [first, mounted].compactMap({ $0 }) {
                        try assertArtwork(actual, matches: expected, at: point, label: item.label)
                    }
                    interaction.clicked(point, center: center)
                    XCTAssertEqual(model.selection, SlotSelection(band: band == .inner ? .inner : .middle,
                                                                  itemID: item.id, subItemID: nil))
                }
            }
        }

        model.load(from: global) // Immediately after mount, before the first run-loop turn.
        try await verify(global, firstFrame: true)

        global.inner.swapAt(1, 4)
        global.inner[0].icon = "camera.fill"
        global.hudCustomization.inner.layout.angularOffset = 75
        model.inner = global.inner
        model.hudCustomization = global.hudCustomization
        model.selection = nil
        try await verify(global)

        var override = global.inner[0]
        override.icon = "bell.fill"
        override.wedgeColor = HUDColor(nsColor: .cyan)
        let layout = global.globalHUDActionLayout
        let rings = AppHUDRings(inner: RingInheritance(overrides: [override.id: override],
                                                       hidden: [global.inner[2].id]))
        let resolved = AppHUDResolver.resolve(global: layout, rings: rings)
        model.load(resolved: resolved, global: layout, hudCustomization: global.hudCustomization)
        var app = global
        app.globalHUDActionLayout = resolved.layout
        try await verify(app)

        model.load(from: global)
        try await verify(global)
    }

    /// Compare a patch containing the symbol and its surrounding fill. Small
    /// color differences are expected between Core Graphics and a hosted view.
    private func assertArtwork(
        _ actual: NSBitmapImageRep, matches expected: NSBitmapImageRep,
        at point: CGPoint, label: String, file: StaticString = #filePath, line: UInt = #line
    ) throws {
        let scale = CGFloat(actual.pixelsWide) / CGFloat(expected.pixelsWide)
        var difference = 0.0
        var channels = 0
        for dy in stride(from: -12, through: 12, by: 2) {
            for dx in stride(from: -12, through: 12, by: 2) {
                let x = Int(point.x) + dx
                let y = Int(point.y) + dy
                let sampled = actual.colorAt(x: Int(CGFloat(x) * scale), y: Int(CGFloat(y) * scale))
                let a = try XCTUnwrap(sampled?.usingColorSpace(.sRGB))
                let b = try XCTUnwrap(expected.colorAt(x: x, y: y)?.usingColorSpace(.sRGB))
                difference += abs(a.redComponent - b.redComponent)
                    + abs(a.greenComponent - b.greenComponent) + abs(a.blueComponent - b.blueComponent)
                channels += 3
            }
        }
        XCTAssertLessThan(difference / Double(channels), 0.08, "Artwork for \(label)", file: file, line: line)
    }

    func testContextDeleteRevalidatesCapturedChildWithoutRemovingTheCurrentSelection() {
        let child = RingMenuItem(label: "Child", icon: "circle", actionType: .custom)
        var parent = RingMenuItem(label: "Parent", icon: "folder", actionType: .custom)
        parent.subItems = [child]
        let current = RingMenuItem(label: "Selected", icon: "star", actionType: .custom)
        let global = HUDActionLayout(inner: [], middle: [parent, current])
        let model = MenuEditorModel(inner: [], middle: [])
        model.load(resolved: AppHUDResolver.resolve(global: global, rings: AppHUDRings()),
                   global: global, hudCustomization: .default)
        let preview = RingPreviewSelector(model: model)
        let target = SlotSelection(band: .middle, itemID: parent.id, subItemID: child.id)
        let selected = SlotSelection(band: .middle, itemID: current.id, subItemID: nil)
        model.selection = selected
        XCTAssertTrue(preview.canDelete(target))

        model.setFollowsGlobal(true, for: .middle)
        XCTAssertFalse(preview.canDelete(target))
        preview.delete(target)
        XCTAssertEqual(model.middle, global.middle)
        XCTAssertEqual(model.selection, selected)

        model.setFollowsGlobal(false, for: .middle)
        model.middle.reverse()
        model.middle[1].dynamicSource = .runningApps
        XCTAssertFalse(preview.canDelete(target))
        preview.delete(target)
        XCTAssertEqual(model.selection, selected)
        XCTAssertEqual(model.middle[1].subItems, [child])

        model.middle[1].dynamicSource = .none
        preview.delete(target)
        XCTAssertNil(model.middle[1].subItems)
        model.selection = selected
        preview.delete(target)
        XCTAssertEqual(model.middle.map(\.id), [current.id, parent.id])
        XCTAssertEqual(model.selection, selected)
    }

    // MARK: - Customized-item marks (App HUD inheritance, task 1.3)

    private func wedgeLabel(
        for item: RingMenuItem, customizedItemIDs: Set<UUID>, appName: String?
    ) -> String {
        RingWedgeAccessibility(
            item: item, band: "Middle", position: 0, selected: false,
            identifierPrefix: "menuItems.preview.wedge",
            labelSuffix: RingPreviewCustomizationMarker.accessibilitySuffix(
                itemID: item.id, customizedItemIDs: customizedItemIDs, appName: appName
            )
        ).label
    }

    func testMarkedItemLabelGetsCustomizedForAppSuffix() {
        let item = RingMenuItem(label: "Copy", icon: "doc.on.doc", actionType: .appSwitch)
        let label = wedgeLabel(for: item, customizedItemIDs: [item.id], appName: "Safari")
        XCTAssertTrue(label.hasSuffix(", customized for Safari"), label)
        let plain = RingWedgeAccessibility(item: item, band: "Middle", position: 0,
                                           selected: false).label
        XCTAssertEqual(label, plain + ", customized for Safari")
    }

    func testUnmarkedItemLabelHasNoSuffix() {
        let marked = RingMenuItem(label: "Copy", icon: "doc.on.doc", actionType: .appSwitch)
        let unmarked = RingMenuItem(label: "Paste", icon: "doc.on.clipboard", actionType: .appSwitch)
        let label = wedgeLabel(for: unmarked, customizedItemIDs: [marked.id], appName: "Safari")
        XCTAssertFalse(label.contains("customized"), label)
        XCTAssertEqual(label, RingWedgeAccessibility(item: unmarked, band: "Middle",
                                                     position: 0, selected: false).label)
    }

    func testDefaultEmptySetAddsNoSuffix() {
        let model = MenuEditorModel(inner: RingMenuItem.sampleInnerItems,
                                    middle: RingMenuItem.sampleItems)
        let selector = RingPreviewSelector(model: model)
        XCTAssertTrue(model.customizedItemIDs.isEmpty)
        XCTAssertNil(selector.appName)
        for item in model.inner + model.middle {
            XCTAssertEqual(
                RingPreviewCustomizationMarker.accessibilitySuffix(
                    itemID: item.id, customizedItemIDs: model.customizedItemIDs,
                    appName: selector.appName
                ),
                ""
            )
        }
    }

    func testNilAppNameFallsBackToCustomized() {
        let item = RingMenuItem(label: "Copy", icon: "doc.on.doc", actionType: .appSwitch)
        let label = wedgeLabel(for: item, customizedItemIDs: [item.id], appName: nil)
        XCTAssertTrue(label.hasSuffix(", customized"), label)
        XCTAssertFalse(label.contains("customized for"), label)
    }
}
