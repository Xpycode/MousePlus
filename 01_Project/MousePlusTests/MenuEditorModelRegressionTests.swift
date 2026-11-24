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
        loaded.hudCustomization.inner.appearance.labelVisible = true
        loaded.hudCustomization.middle.appearance.labelOrientation = .radial
        model.load(from: loaded, preservingSelection: true)
        model.hudCustomization.outerRingVisibility = .alwaysHidden
        model.hudCustomization.outerAppearance.labelVisible = false
        model.hudCustomization.labelOrientation = .tangential
        let binding = try XCTUnwrap(model.binding(forItem: item.id, band: .middle))
        binding.wrappedValue.wedgeColor = HUDColor(red: 0.2, green: 0.3, blue: 0.4)

        var unrelatedBase = Configuration()
        unrelatedBase.appearance.deadZone = 61
        let merged = model.merged(into: unrelatedBase)

        XCTAssertEqual(model.selection?.itemID, item.id)
        XCTAssertEqual(merged.hudCustomization.inner.layout.angularOffset, 42)
        XCTAssertEqual(merged.hudCustomization.outerRingVisibility, .alwaysHidden)
        XCTAssertTrue(merged.hudCustomization.inner.appearance.labelVisible, "the loaded per-ring label override must survive load + merge")
        XCTAssertEqual(merged.hudCustomization.middle.appearance.labelOrientation, .radial, "the loaded ring label orientation override must survive load + merge")
        XCTAssertFalse(merged.hudCustomization.outerAppearance.labelVisible, "the in-editor label visibility edit must survive merge")
        XCTAssertEqual(merged.hudCustomization.labelOrientation, .tangential, "the in-editor menu-level label orientation edit must survive merge")
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

    func testTopLevelReorderWrapsEarlierInBothBandsAndPreservesSelection() {
        for band in [EditorBand.inner, .middle] {
            let first = RingMenuItem(label: "First", icon: "1.circle", actionType: .custom)
            let second = RingMenuItem(label: "Second", icon: "2.circle", actionType: .custom)
            let third = RingMenuItem(label: "Third", icon: "3.circle", actionType: .custom)
            let model = MenuEditorModel(
                inner: band == .inner ? [first, second, third] : [],
                middle: band == .middle ? [first, second, third] : []
            )
            model.selection = SlotSelection(band: band, itemID: first.id, subItemID: nil)

            model.moveItem(id: first.id, in: band, by: -1)

            let items = band == .inner ? model.inner : model.middle
            XCTAssertEqual(items.map(\.id), [second.id, third.id, first.id])
            XCTAssertEqual(model.selection?.itemID, first.id)
        }
    }

    func testTopLevelReorderWrapsLaterInBothBandsAndPreservesSelection() {
        for band in [EditorBand.inner, .middle] {
            let first = RingMenuItem(label: "First", icon: "1.circle", actionType: .custom)
            let second = RingMenuItem(label: "Second", icon: "2.circle", actionType: .custom)
            let third = RingMenuItem(label: "Third", icon: "3.circle", actionType: .custom)
            let model = MenuEditorModel(
                inner: band == .inner ? [first, second, third] : [],
                middle: band == .middle ? [first, second, third] : []
            )
            model.selection = SlotSelection(band: band, itemID: third.id, subItemID: nil)

            model.moveItem(id: third.id, in: band, by: 1)

            let items = band == .inner ? model.inner : model.middle
            XCTAssertEqual(items.map(\.id), [third.id, first.id, second.id])
            XCTAssertEqual(model.selection?.itemID, third.id)
        }
    }

    func testTopLevelReorderOneItemBandsRemainStableInBothDirections() {
        for band in [EditorBand.inner, .middle] {
            let only = RingMenuItem(label: "Only", icon: "circle", actionType: .custom)
            let model = MenuEditorModel(
                inner: band == .inner ? [only] : [],
                middle: band == .middle ? [only] : []
            )
            model.selection = SlotSelection(band: band, itemID: only.id, subItemID: nil)

            model.moveItem(id: only.id, in: band, by: -1)
            model.moveItem(id: only.id, in: band, by: 1)

            let items = band == .inner ? model.inner : model.middle
            XCTAssertEqual(items.map(\.id), [only.id])
            XCTAssertEqual(model.selection?.itemID, only.id)
        }
    }

    func testTopLevelReorderRepeatedWrapCompletesMultipleRevolutions() {
        let first = RingMenuItem(label: "First", icon: "1.circle", actionType: .custom)
        let selected = RingMenuItem(label: "Selected", icon: "2.circle", actionType: .custom)
        let third = RingMenuItem(label: "Third", icon: "3.circle", actionType: .custom)
        let model = MenuEditorModel(inner: [], middle: [first, selected, third])
        model.selection = SlotSelection(band: .middle, itemID: selected.id, subItemID: nil)

        for _ in 0..<7 { model.moveItem(id: selected.id, in: .middle, by: 1) }
        XCTAssertEqual(model.middle.map(\.id), [first.id, third.id, selected.id])

        for _ in 0..<8 { model.moveItem(id: selected.id, in: .middle, by: -1) }
        XCTAssertEqual(model.middle.map(\.id), [selected.id, first.id, third.id])
        XCTAssertEqual(model.selection?.itemID, selected.id)
    }

    func testTopLevelReorderRejectsUnknownIdentityAndHandlesExtremeOffsets() {
        let first = RingMenuItem(label: "First", icon: "1.circle", actionType: .custom)
        let selected = RingMenuItem(label: "Selected", icon: "2.circle", actionType: .custom)
        let third = RingMenuItem(label: "Third", icon: "3.circle", actionType: .custom)
        let model = MenuEditorModel(inner: [first, selected, third], middle: [])

        model.moveItem(id: UUID(), in: .inner, by: Int.max)
        XCTAssertEqual(model.inner.map(\.id), [first.id, selected.id, third.id])

        model.moveItem(id: selected.id, in: .inner, by: Int.min)
        XCTAssertEqual(model.inner.map(\.id), [first.id, third.id, selected.id])
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

    func testMissingDynamicSourceDecodesToNone() throws {
        let json = #"{"id":"\#(UUID().uuidString)","label":"Apps","icon":"square.grid.2x2","actionType":"appSwitch","actionData":""}"#

        let decoded = try JSONDecoder().decode(RingMenuItem.self, from: Data(json.utf8))

        XCTAssertEqual(decoded.dynamicSource, .none)
    }

    func testDynamicSourceRoundTrips() throws {
        let original = RingMenuItem(
            label: "Apps", icon: "square.grid.2x2", actionType: .appSwitch, dynamicSource: .runningApps
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(RingMenuItem.self, from: data)

        XCTAssertEqual(decoded, original)
        XCTAssertEqual(decoded.dynamicSource, .runningApps)
    }

    // MARK: - App HUD inheritance (AC9–AC13)

    private struct AppFixture {
        let a = RingMenuItem(label: "A", icon: "a.circle", actionType: .custom)
        let b = RingMenuItem(label: "B", icon: "b.circle", actionType: .custom)
        let c = RingMenuItem(label: "C", icon: "c.circle", actionType: .custom)
        var global: HUDActionLayout { HUDActionLayout(inner: [], middle: [a, b, c]) }
    }

    private func makeAppModel(
        global: HUDActionLayout,
        inner: RingInheritance = RingInheritance(),
        middle: RingInheritance = RingInheritance()
    ) -> MenuEditorModel {
        let model = MenuEditorModel(inner: [], middle: [])
        let resolved = AppHUDResolver.resolve(global: global, rings: AppHUDRings(inner: inner, middle: middle))
        model.load(resolved: resolved, global: global, hudCustomization: .default, normalizeStoredValues: false)
        return model
    }

    /// The middle ring a save would store, via the `diff` contract.
    private func storedMiddle(_ model: MenuEditorModel) throws -> RingInheritance {
        let state = try XCTUnwrap(model.inheritanceEditState)
        return AppHUDResolver.diff(
            edited: state.edited.middle,
            previous: RingInheritance(),
            global: state.global.middle,
            origins: state.origins
        )
    }

    func testAppHUDFieldAndSubItemEditsCustomizeInheritedItem() throws {
        let f = AppFixture()
        let model = makeAppModel(global: f.global)
        XCTAssertTrue(model.isEditingAppHUD)
        XCTAssertEqual(model.origin(of: f.a.id), .inherited)

        let binding = try XCTUnwrap(model.binding(forItem: f.a.id, band: .middle))
        binding.wrappedValue = binding.wrappedValue
        XCTAssertEqual(model.origin(of: f.a.id), .inherited, "an unchanged write must not customize")

        binding.wrappedValue.label = "App A"
        XCTAssertEqual(model.origin(of: f.a.id), .customized)
        XCTAssertEqual(model.customizedItemIDs, [f.a.id])
        XCTAssertEqual(try storedMiddle(model).overrides[f.a.id]?.label, "App A")

        model.addSubItem(toMiddle: f.b.id)
        XCTAssertEqual(model.origin(of: f.b.id), .customized, "a sub-item edit customizes its parent")
        XCTAssertEqual(model.origin(of: f.c.id), .inherited)
    }

    func testAppHUDCustomizeKeepsIdenticalCopyAndRevertFollowsGlobal() throws {
        let f = AppFixture()
        let model = makeAppModel(global: f.global)

        model.customize(id: f.b.id)
        XCTAssertEqual(model.origin(of: f.b.id), .customized)
        XCTAssertEqual(model.middle[1], f.b, "Customize keeps the content identical")
        XCTAssertEqual(try storedMiddle(model).overrides[f.b.id], f.b, "an identical explicit Customize sticks")

        model.binding(forItem: f.b.id, band: .middle)?.wrappedValue.label = "Edited"
        model.revertToGlobal(id: f.b.id)
        XCTAssertEqual(model.origin(of: f.b.id), .inherited)
        XCTAssertEqual(model.middle[1], f.b)
        XCTAssertTrue(try storedMiddle(model).isEmpty)
    }

    func testAppHUDRemoveHidesGlobalItemAndShowRestoresItsPosition() throws {
        let f = AppFixture()
        let model = makeAppModel(global: f.global)
        model.selection = SlotSelection(band: .middle, itemID: f.b.id, subItemID: nil)

        model.removeSelectedItem()
        XCTAssertEqual(model.middle.map(\.id), [f.a.id, f.c.id])
        XCTAssertEqual(model.hiddenItems, [f.b])
        XCTAssertNil(model.origin(of: f.b.id))
        XCTAssertEqual(try storedMiddle(model).hidden, [f.b.id])

        model.show(hidden: f.b)
        XCTAssertEqual(model.middle.map(\.id), [f.a.id, f.b.id, f.c.id])
        XCTAssertEqual(model.origin(of: f.b.id), .inherited)
        XCTAssertTrue(model.hiddenItems.isEmpty)
        XCTAssertTrue(try storedMiddle(model).isEmpty)
    }

    func testAppHUDRemoveDeletesAppOnlyItem() throws {
        let f = AppFixture()
        let model = makeAppModel(global: f.global)
        model.addItem(to: .middle)
        let added = try XCTUnwrap(model.selection?.itemID)
        XCTAssertEqual(model.origin(of: added), .appOnly)

        model.removeSelectedItem()
        XCTAssertEqual(model.middle.map(\.id), [f.a.id, f.b.id, f.c.id])
        XCTAssertTrue(model.hiddenItems.isEmpty)
        XCTAssertTrue(try storedMiddle(model).isEmpty)
    }

    func testAppHUDShowInCustomOrderRingAppendsAtEnd() throws {
        let f = AppFixture()
        let model = makeAppModel(
            global: f.global,
            middle: RingInheritance(hidden: [f.a.id], customOrder: [f.c.id, f.b.id])
        )
        XCTAssertEqual(model.middle.map(\.id), [f.c.id, f.b.id])
        XCTAssertTrue(model.hasCustomOrder(band: .middle))

        model.show(hidden: f.a)
        XCTAssertEqual(model.middle.map(\.id), [f.c.id, f.b.id, f.a.id])
        XCTAssertEqual(model.origin(of: f.a.id), .inherited)
    }

    func testAppHUDMoveSetsCustomOrderAndRevertOrderKeepsAppOnlyAnchor() throws {
        let f = AppFixture()
        let x = RingMenuItem(label: "X", icon: "x.circle", actionType: .custom)
        let model = makeAppModel(
            global: f.global,
            middle: RingInheritance(appOnly: [AppOnlyItem(item: x, after: f.a.id)])
        )
        XCTAssertEqual(model.middle.map(\.id), [f.a.id, x.id, f.b.id, f.c.id])
        XCTAssertFalse(model.hasCustomOrder(band: .middle))

        model.moveItem(id: f.c.id, in: .middle, by: -1)
        XCTAssertEqual(model.middle.map(\.id), [f.a.id, x.id, f.c.id, f.b.id])
        XCTAssertTrue(model.hasCustomOrder(band: .middle))
        XCTAssertNotNil(try storedMiddle(model).customOrder)

        model.revertOrder(band: .middle)
        XCTAssertEqual(model.middle.map(\.id), [f.a.id, x.id, f.b.id, f.c.id])
        XCTAssertFalse(model.hasCustomOrder(band: .middle))
        XCTAssertNil(try storedMiddle(model).customOrder)
        XCTAssertEqual(model.origin(of: x.id), .appOnly)
    }

    func testAppHUDNotShownItemsStayInFullRing() throws {
        let globalItems = (0..<AppHUDResolver.ringCapacity).map {
            RingMenuItem(label: "G\($0)", icon: "circle", actionType: .custom)
        }
        let extra = RingMenuItem(label: "Extra", icon: "plus", actionType: .custom)
        let global = HUDActionLayout(inner: [], middle: globalItems)
        let model = makeAppModel(
            global: global,
            middle: RingInheritance(appOnly: [AppOnlyItem(item: extra, after: globalItems.last?.id)])
        )
        XCTAssertEqual(model.middle.count, AppHUDResolver.ringCapacity)
        XCTAssertEqual(model.notShown(band: .middle), [extra])
        XCTAssertEqual(model.origin(of: extra.id), .appOnly)
        XCTAssertEqual(try XCTUnwrap(model.inheritanceEditState).edited.middle.count, AppHUDResolver.ringCapacity + 1)
        XCTAssertTrue(try storedMiddle(model).hidden.isEmpty, "not-shown items must not become hidden")

        model.selection = SlotSelection(band: .middle, itemID: globalItems[0].id, subItemID: nil)
        model.removeSelectedItem()
        XCTAssertEqual(model.middle.last, extra, "hiding frees a slot for the not-shown item")
        XCTAssertTrue(model.notShown(band: .middle).isEmpty)
        XCTAssertEqual(model.hiddenItems, [globalItems[0]])
    }

    func testGlobalModeHasNoInheritanceAndRemoveDeletes() {
        let f = AppFixture()
        let model = makeAppModel(global: f.global)
        model.load(resolved: nil, global: f.global, hudCustomization: .default)

        XCTAssertFalse(model.isEditingAppHUD)
        XCTAssertEqual(model.middle.map(\.id), [f.a.id, f.b.id, f.c.id])
        XCTAssertNil(model.origin(of: f.a.id))
        XCTAssertNil(model.inheritanceEditState)
        model.setFollowsGlobal(true, for: .middle)
        XCTAssertFalse(model.followsGlobal(.middle))
        XCTAssertNil(model.globalRingConfirmation(for: .middle))

        model.binding(forItem: f.a.id, band: .middle)?.wrappedValue.label = "Edited"
        model.customize(id: f.b.id)
        model.moveItem(id: f.c.id, in: .middle, by: -1)
        XCTAssertTrue(model.origins.isEmpty)
        XCTAssertFalse(model.hasCustomOrder(band: .middle))

        model.selection = SlotSelection(band: .middle, itemID: f.b.id, subItemID: nil)
        model.removeSelectedItem()
        XCTAssertEqual(model.middle.map(\.id), [f.a.id, f.c.id])
        XCTAssertTrue(model.hiddenItems.isEmpty)
        XCTAssertTrue(model.notShown(band: .middle).isEmpty)

        // The existing Global entry point also leaves App HUD mode.
        let app = makeAppModel(global: f.global)
        app.load(actionLayout: f.global, hudCustomization: .default)
        XCTAssertFalse(app.isEditingAppHUD)
    }

    func testLockConfirmationCountsWorkingEditsAndOnlyClearsTheChosenRing() throws {
        let f = AppFixture()
        let other = RingMenuItem(label: "Inner", icon: "circle", actionType: .custom)
        let global = HUDActionLayout(inner: [other], middle: [f.a, f.b, f.c])
        let model = makeAppModel(global: global)
        XCTAssertNil(model.globalRingConfirmation(for: .middle))
        model.customize(id: other.id)
        model.customize(id: f.c.id)
        model.selection = SlotSelection(band: .middle, itemID: f.a.id, subItemID: nil)
        model.removeSelectedItem()
        model.moveItem(id: f.c.id, in: .middle, by: -1)
        model.addItem(to: .middle)
        model.addItem(to: .middle)

        let before = model.inheritanceEditState
        let prompt = try XCTUnwrap(model.globalRingConfirmation(for: .middle))
        for category in ["1 customized item", "1 hidden item", "2 app-only items", "1 custom order"] {
            XCTAssertTrue(prompt.contains(category), prompt)
        }
        XCTAssertEqual(model.inheritanceEditState, before)
        XCTAssertFalse(model.followsGlobal(.middle))

        model.setFollowsGlobal(true, for: .middle)
        XCTAssertEqual(model.middle, global.middle)
        XCTAssertTrue(model.hiddenItems.isEmpty)
        XCTAssertFalse(model.hasCustomOrder(band: .middle))
        XCTAssertNil(model.selection, "The selected app-only item disappeared")
        XCTAssertEqual(model.customizedItemIDs, [other.id])
        XCTAssertEqual(model.inner, global.inner)
        XCTAssertEqual(model.inheritanceEditState?.lockedBands, [.middle])
        for item in global.middle { XCTAssertEqual(model.origin(of: item.id), .inherited) }

        model.setFollowsGlobal(false, for: .middle)
        XCTAssertNil(model.globalRingConfirmation(for: .middle))
        XCTAssertEqual(model.middle, global.middle)
        model.binding(forItem: f.c.id, band: .middle)?.wrappedValue.label = "Now editable"
        XCTAssertEqual(model.origin(of: f.c.id), .customized)
    }

    func testLockedMiddleBlocksStaleBindingsAndMutationsButPreservesReadableSelection() throws {
        let f = AppFixture()
        var parent = f.a
        parent.subItems = [f.c]
        let global = HUDActionLayout(inner: [], middle: [parent, f.b])
        let model = makeAppModel(global: global)
        let item = try XCTUnwrap(model.binding(forItem: parent.id, band: .middle))
        let subItem = try XCTUnwrap(model.binding(forSubItem: f.c.id, ofMiddle: parent.id))
        let color = try XCTUnwrap(model.colorBinding(forSubItem: f.c.id, ofMiddle: parent.id, role: .icon))
        let selected = SlotSelection(band: .middle, itemID: parent.id, subItemID: f.c.id)
        model.selection = selected
        model.setFollowsGlobal(true, for: .middle)

        model.customize(id: parent.id)
        model.revertToGlobal(id: parent.id)
        model.revertOrder(band: .middle)
        model.show(hidden: f.b)
        model.moveItem(id: parent.id, in: .middle, by: 1)
        model.addItem(to: .middle)
        model.addSubItem(toMiddle: parent.id)
        model.removeSubItem(f.c.id, fromMiddle: parent.id)
        model.removeSelectedItem()
        item.wrappedValue.label = "Stale field"
        subItem.wrappedValue.label = "Stale sub-item"
        color.wrappedValue = .red
        model.middle.removeAll()
        XCTAssertEqual(model.selection, selected)
        XCTAssertEqual(item.wrappedValue, parent)
        XCTAssertEqual(subItem.wrappedValue, f.c)
        XCTAssertEqual(model.middle, global.middle)
        XCTAssertTrue(model.customizedItemIDs.isEmpty)

        model.selection = SlotSelection(band: .middle, itemID: f.b.id, subItemID: nil)
        model.removeSelectedItem()
        XCTAssertEqual(model.selection?.itemID, f.b.id)
        XCTAssertEqual(model.middle, global.middle)
        model.setFollowsGlobal(false, for: .middle)
        subItem.wrappedValue.label = "Editable again"
        XCTAssertEqual(model.origin(of: parent.id), .customized)
    }

    func testStoredOrderThatMatchesGlobalStillNeedsConfirmationUntilReverted() {
        let f = AppFixture()
        let model = makeAppModel(global: f.global, middle: RingInheritance(customOrder: f.global.middle.map(\.id)))
        XCTAssertEqual(model.middle, f.global.middle)
        XCTAssertEqual(model.inheritanceEditState?.customOrderBands, [.middle])
        XCTAssertTrue(model.globalRingConfirmation(for: .middle)?.contains("1 custom order") == true)
        model.revertOrder(band: .middle)
        XCTAssertNil(model.globalRingConfirmation(for: .middle))
        XCTAssertEqual(model.inheritanceEditState?.customOrderBands, [])
    }

    func testLockIncludesAppOnlyItemsBeyondRingCapacityInConfirmationAndCleanup() {
        let globalItems = (0..<AppHUDResolver.ringCapacity).map {
            RingMenuItem(label: "Item \($0)", icon: "circle", actionType: .custom)
        }
        let extra = RingMenuItem(label: "Overflow", icon: "plus", actionType: .custom)
        let model = makeAppModel(
            global: HUDActionLayout(inner: globalItems, middle: []),
            inner: RingInheritance(appOnly: [AppOnlyItem(item: extra, after: globalItems.last?.id)])
        )
        XCTAssertEqual(model.notShown(band: .inner), [extra])
        XCTAssertTrue(model.globalRingConfirmation(for: .inner)?.contains("1 app-only item") == true)
        model.setFollowsGlobal(true, for: .inner)
        XCTAssertEqual(model.inner, globalItems)
        XCTAssertTrue(model.notShown(band: .inner).isEmpty)
        XCTAssertNil(model.origin(of: extra.id))
    }

    func testLockKeepsIdenticalSiblingOverrideWhenBothBandsUseTheSameID() throws {
        let inner = RingMenuItem(label: "Inner", icon: "circle", actionType: .custom)
        var middle = inner
        middle.label = "Middle"
        let global = HUDActionLayout(inner: [inner], middle: [middle])
        let overrides = RingInheritance(overrides: [middle.id: middle])
        let model = makeAppModel(global: global, middle: overrides)
        XCTAssertNil(model.globalRingConfirmation(for: .inner))
        XCTAssertEqual(model.customizedItemIDs(band: .middle), [middle.id])
        XCTAssertTrue(model.customizedItemIDs(band: .inner).isEmpty)

        model.customize(id: inner.id, band: .inner)
        model.setFollowsGlobal(true, for: .inner)
        XCTAssertEqual(model.origin(of: inner.id, band: .inner), .inherited)
        XCTAssertEqual(model.origin(of: middle.id, band: .middle), .customized)
        XCTAssertTrue(model.globalRingConfirmation(for: .middle)?.contains("1 customized item") == true)
        let edit = try XCTUnwrap(model.inheritanceEditState)
        let stored = AppHUDResolver.diff(
            edited: edit.edited,
            previous: AppHUDProfile(rings: AppHUDRings(middle: overrides)),
            global: global, origins: edit.origins, lockedBands: edit.lockedBands,
            customOrderBands: edit.customOrderBands, originsByBand: edit.originsByBand
        )
        XCTAssertEqual(stored.rings?.middle.overrides[middle.id], middle)
        XCTAssertTrue(stored.rings?.inner.followsGlobal == true)

        model.revertToGlobal(id: middle.id, band: .middle)
        XCTAssertNil(model.globalRingConfirmation(for: .middle))
        model.customize(id: middle.id, band: .middle)
        XCTAssertEqual(model.origin(of: middle.id, band: .middle), .customized)
        model.revertToGlobal(id: inner.id, band: .inner)
        XCTAssertEqual(model.origin(of: middle.id, band: .middle), .customized)
        XCTAssertEqual(model.inner, [inner])
    }

    func testLoadedInnerLockPreservesGlobalWhenEditingMiddleAndUnlockAllowsEdits() throws {
        let f = AppFixture()
        var snap = RingMenuItem(label: "Snap", icon: "circle", actionType: .windowSnap)
        snap.actionData = ""
        var parent = f.a
        parent.subItems = [f.c]
        let global = HUDActionLayout(inner: [snap], middle: [parent])
        let locked = AppHUDResolver.resolve(global: global, rings: AppHUDRings(inner: RingInheritance(followsGlobal: true)))
        let model = MenuEditorModel(inner: [], middle: [])
        model.load(resolved: locked, global: global, hudCustomization: .default)
        XCTAssertTrue(model.followsGlobal(.inner))
        let binding = try XCTUnwrap(model.binding(forItem: snap.id, band: .inner))
        binding.wrappedValue.label = "Blocked"
        model.removeSubItem(f.c.id, fromMiddle: parent.id)
        XCTAssertEqual(model.origin(of: parent.id), .customized)
        XCTAssertEqual(model.inner, global.inner, "A locked ring must never normalize Global's payload")
        model.setFollowsGlobal(false, for: .inner)
        binding.wrappedValue.label = "Editable"
        XCTAssertEqual(model.origin(of: snap.id), .customized)
    }
}
