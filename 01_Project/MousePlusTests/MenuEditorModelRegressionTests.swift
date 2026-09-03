import XCTest
import AppKit
@testable import MousePlus

@MainActor
final class MenuEditorModelRegressionTests: XCTestCase {
    func testItemColorResolutionFallsBackThroughRingAndMenuImmediately() throws {
        let item = RingMenuItem(label: "Item", icon: "circle", actionType: .custom)
        var customization = HUDCustomization()
        let menuWedge = HUDColor(red: 0.1, green: 0.2, blue: 0.3)
        let ringWedge = HUDColor(red: 0.3, green: 0.4, blue: 0.5)
        let itemWedge = HUDColor(red: 0.7, green: 0.8, blue: 0.9)
        customization.wedgeColor = menuWedge
        customization.middle.appearance.wedgeColor = ringWedge
        let model = MenuEditorModel(inner: [], middle: [item], hudCustomization: customization)
        let selection = SlotSelection(band: .middle, itemID: item.id, subItemID: nil)

        XCTAssertEqual(model.colorResolution(for: model.middle[0], selection: selection).requestedWedge, ringWedge)

        let binding = try XCTUnwrap(model.colorBinding(forItem: item.id, band: .middle, role: .wedge))
        binding.wrappedValue = itemWedge.nsColor
        XCTAssertEqual(model.colorResolution(for: model.middle[0], selection: selection).requestedWedge, itemWedge)

        binding.wrappedValue = nil
        XCTAssertEqual(model.colorResolution(for: model.middle[0], selection: selection).requestedWedge, ringWedge)

        model.hudCustomization.middle.appearance.wedgeColor = nil
        XCTAssertEqual(model.colorResolution(for: model.middle[0], selection: selection).requestedWedge, menuWedge)
    }

    func testStaleColorBindingCannotWriteAcrossRapidSelectionChanges() throws {
        let first = RingMenuItem(label: "First", icon: "1.circle", actionType: .custom)
        let second = RingMenuItem(label: "Second", icon: "2.circle", actionType: .custom)
        let model = MenuEditorModel(inner: [], middle: [first, second])
        model.selection = SlotSelection(band: .middle, itemID: first.id, subItemID: nil)
        let firstBinding = try XCTUnwrap(model.colorBinding(forItem: first.id, band: .middle, role: .icon))

        model.selection = SlotSelection(band: .middle, itemID: second.id, subItemID: nil)
        let chosen = HUDColor(red: 0.25, green: 0.5, blue: 0.75)
        firstBinding.wrappedValue = chosen.nsColor

        XCTAssertEqual(model.middle.first(where: { $0.id == first.id })?.iconColor, chosen)
        XCTAssertNil(model.middle.first(where: { $0.id == second.id })?.iconColor)
    }

    func testUnconvertibleItemColorEditPreservesPreviousValue() throws {
        let previous = HUDColor(red: 0.2, green: 0.4, blue: 0.6)
        let item = RingMenuItem(
            label: "Item", icon: "circle", actionType: .custom, wedgeColor: previous
        )
        let model = MenuEditorModel(inner: [], middle: [item])
        let binding = try XCTUnwrap(model.colorBinding(forItem: item.id, band: .middle, role: .wedge))

        binding.wrappedValue = NSColor(patternImage: NSImage(size: NSSize(width: 1, height: 1)))

        XCTAssertEqual(model.middle[0].wedgeColor, previous)
    }

    func testHUDCustomizationAndItemOverridesLoadAndMergeWithoutLosingSelection() throws {
        let item = RingMenuItem(label: "Item", icon: "circle", actionType: .custom)
        let model = MenuEditorModel(inner: [], middle: [item])
        model.selection = SlotSelection(band: .middle, itemID: item.id, subItemID: nil)

        var loaded = Configuration(inner: [], middle: [item])
        loaded.hudCustomization.inner.layout.angularOffset = 42
        model.load(from: loaded, preservingSelection: true)
        model.hudCustomization.outerRingVisibility = .alwaysHidden
        let binding = try XCTUnwrap(model.binding(forItem: item.id, band: .middle))
        binding.wrappedValue.wedgeColor = HUDColor(red: 0.2, green: 0.3, blue: 0.4)

        var unrelatedBase = Configuration()
        unrelatedBase.appearance.deadZone = 61
        let merged = model.merged(into: unrelatedBase)

        XCTAssertEqual(model.selection?.itemID, item.id)
        XCTAssertEqual(merged.hudCustomization.inner.layout.angularOffset, 42)
        XCTAssertEqual(merged.hudCustomization.outerRingVisibility, .alwaysHidden)
        XCTAssertEqual(merged.middle.first?.wedgeColor, HUDColor(red: 0.2, green: 0.3, blue: 0.4))
        XCTAssertEqual(merged.appearance.deadZone, 61)
    }

    func testF7RemovingLastSnapSubItemNormalizesDirectPayload() throws {
        let child = RingMenuItem(label: "Left", icon: "rectangle.lefthalf.filled", actionType: .windowSnap, actionData: SnapZone.left.rawValue)
        let parent = RingMenuItem(label: "Snap", icon: "rectangle.split.2x1", actionType: .windowSnap, subItems: [child])
        let model = MenuEditorModel(inner: [], middle: [parent])

        model.removeSubItem(child.id, fromMiddle: parent.id)

        XCTAssertNil(model.middle[0].subItems)
        XCTAssertEqual(model.middle[0].actionData, SnapZone.left.rawValue)
    }

    func testF8SubItemCapRejectsThirteenthItem() {
        let children = (0..<MenuEditorModel.maxSubItems).map {
            RingMenuItem(label: "Item \($0)", icon: "circle", actionType: .custom)
        }
        let parent = RingMenuItem(label: "Parent", icon: "circle", actionType: .custom, subItems: children)
        let model = MenuEditorModel(inner: [], middle: [parent])

        model.addSubItem(toMiddle: parent.id)

        XCTAssertTrue(model.subItemsAtCap(for: parent.id))
        XCTAssertEqual(model.middle[0].subItems?.count, MenuEditorModel.maxSubItems)
    }

    func testF15InvalidSubItemSymbolResolvesToVisiblePlaceholder() {
        XCTAssertEqual(SFSymbol.resolved("not.a.real.symbol"), SFSymbol.placeholder)
    }

    func testTopLevelBindingFollowsUUIDAcrossReorder() throws {
        let first = RingMenuItem(label: "First", icon: "1.circle", actionType: .custom)
        let selected = RingMenuItem(label: "Selected", icon: "2.circle", actionType: .custom)
        let model = MenuEditorModel(inner: [], middle: [first, selected])
        let binding = try XCTUnwrap(model.binding(forItem: selected.id, band: .middle))

        model.moveItem(id: selected.id, in: .middle, by: -1)
        binding.wrappedValue.label = "Edited by identity"

        XCTAssertEqual(model.middle.first?.id, selected.id)
        XCTAssertEqual(model.middle.first?.label, "Edited by identity")
        XCTAssertEqual(model.middle.last?.label, "First")
    }

    func testSubItemBindingFollowsUUIDAfterSiblingRemoval() throws {
        let first = RingMenuItem(label: "First", icon: "1.circle", actionType: .custom)
        let selected = RingMenuItem(label: "Selected", icon: "2.circle", actionType: .custom)
        let parent = RingMenuItem(label: "Parent", icon: "circle", actionType: .custom, subItems: [first, selected])
        let model = MenuEditorModel(inner: [], middle: [parent])
        let binding = try XCTUnwrap(model.binding(forSubItem: selected.id, ofMiddle: parent.id))

        model.removeSubItem(first.id, fromMiddle: parent.id)
        binding.wrappedValue.label = "Edited by identity"

        XCTAssertEqual(model.middle[0].subItems?.first?.id, selected.id)
        XCTAssertEqual(model.middle[0].subItems?.first?.label, "Edited by identity")
    }

    func testActionTypeSwitchClearsIncompatiblePayloadsAndInitializesSnap() throws {
        let payload = KeystrokePayload.key(keyCode: 8, modifiers: 1 << 20)
        let original = RingMenuItem(
            label: "Copy", icon: "doc.on.doc", actionType: .sendKeystroke,
            actionData: "stale", keystrokePayload: payload
        )
        let model = MenuEditorModel(inner: [original], middle: [])
        let binding = try XCTUnwrap(model.binding(forItem: original.id, band: .inner))

        binding.wrappedValue.actionType = .windowSnap

        XCTAssertEqual(model.inner[0].actionData, SnapZone.left.rawValue)
        XCTAssertNil(model.inner[0].keystrokePayload)
    }

    func testActionTypeSwitchPreservesExplicitReplacementPayload() throws {
        let original = RingMenuItem(label: "Old", icon: "circle", actionType: .custom, actionData: "old")
        let model = MenuEditorModel(inner: [], middle: [original])
        let binding = try XCTUnwrap(model.binding(forItem: original.id, band: .middle))
        var replacement = binding.wrappedValue
        replacement.actionType = .appSwitch
        replacement.actionData = "com.example.NewApp"

        binding.wrappedValue = replacement

        XCTAssertEqual(model.middle[0].actionData, "com.example.NewApp")
    }

    func testUnavailableActionAndInvalidSymbolRoundTripWithoutMutation() throws {
        let original = RingMenuItem(
            label: "Future", icon: "future.invalid.symbol",
            actionType: .unavailable("future.action/v3"), actionData: "opaque-payload"
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(RingMenuItem.self, from: data)

        XCTAssertEqual(decoded, original)
        XCTAssertEqual(decoded.actionType.rawValue, "future.action/v3")
        XCTAssertEqual(decoded.actionData, "opaque-payload")
        XCTAssertEqual(decoded.icon, "future.invalid.symbol")
        XCTAssertEqual(SFSymbol.resolved(decoded.icon), SFSymbol.placeholder)
    }
}
