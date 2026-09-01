import XCTest
@testable import MousePlus

@MainActor
final class MenuEditorModelRegressionTests: XCTestCase {
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
}
