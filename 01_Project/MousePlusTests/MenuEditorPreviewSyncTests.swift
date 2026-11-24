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

    /// Regression (2026-11-18): Settings opened on Menu Items, the saved menu loaded
    /// right after the preview mounted, and the preview kept drawing the samples.
    func testPreviewFollowsALoadThatLandsImmediatelyAfterMount() async throws {
        let model = MenuEditorModel(inner: RingMenuItem.sampleInnerItems,
                                    middle: RingMenuItem.sampleItems)
        let host = NSHostingView(rootView: RingPreviewSelector(model: model))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 500),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = host
        defer { window.contentView = nil }

        // No settling between mount and load: both land in the same update.
        var config = Configuration()
        config.inner.append(RingMenuItem(label: "Extra", icon: "app.fill", actionType: .appSwitch))
        config.middle.append(RingMenuItem(label: "Extra", icon: "app.fill", actionType: .appSwitch))
        config.hudCustomization.inner.layout.angularOffset = 61
        model.load(from: config)

        for _ in 0..<10 {
            host.layoutSubtreeIfNeeded()
            try? await Task.sleep(for: .milliseconds(10))
        }

        func surface(_ view: NSView) -> InteractionNSView? {
            if let view = view as? InteractionNSView { return view }
            return view.subviews.lazy.compactMap { surface($0) }.first
        }
        let snapshot = try XCTUnwrap(surface(host)?.coordinator?.snapshot)
        let runtime = RingViewModel()
        runtime.load(from: config)
        XCTAssertEqual(snapshot.geometry, runtime.geometry)
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
