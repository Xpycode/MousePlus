import XCTest
@testable import MousePlus

final class HUDOuterBranchMotionTests: XCTestCase {
    func testFirstExpansionAndItsAsyncContentUseOuterReveal() {
        let parent = UUID()
        let pending = HUDOuterBranchIdentity(parentID: parent, items: [])
        let ready = HUDOuterBranchIdentity(parentID: parent, items: [item("App")])
        let state = HUDOuterBranchMotionState().updating(pending)
        XCTAssertFalse(state.isReplacement)
        XCTAssertFalse(state.updating(ready).isReplacement)
    }

    func testStaticReplacementAndSameIDContentEditUseBranchFade() {
        let first = HUDOuterBranchIdentity(parentID: UUID(), items: [item("Left")])
        let second = HUDOuterBranchIdentity(parentID: UUID(), items: [item("Right")])
        let state = HUDOuterBranchMotionState().updating(first).updating(second)
        XCTAssertTrue(state.isReplacement)
        XCTAssertEqual(state.updating(second), state, "Unchanged content must not restart motion")

        var edited = first.items[0]
        edited.label = "Updated"
        let editedIdentity = HUDOuterBranchIdentity(parentID: first.parentID, items: [edited])
        XCTAssertNotEqual(editedIdentity, first)
        XCTAssertTrue(HUDOuterBranchMotionState().updating(first).updating(editedIdentity).isReplacement)
    }

    func testPendingAppsReplacementRetainsFadeAcrossFetchAndRepoint() {
        let snap = HUDOuterBranchIdentity(parentID: UUID(), items: [item("Left")])
        let appsParent = UUID()
        let pending = HUDOuterBranchIdentity(parentID: appsParent, items: [])
        let ready = HUDOuterBranchIdentity(parentID: appsParent, items: [item("Safari")])
        let state = HUDOuterBranchMotionState().updating(snap).updating(pending)
        XCTAssertTrue(state.isReplacement)
        XCTAssertTrue(state.updating(ready).isReplacement)
        XCTAssertTrue(state.updating(snap).isReplacement)
        XCTAssertEqual(state.updating(snap).identity, snap)
    }

    func testNewDynamicContentGenerationChangesIdentityAtSameParent() {
        let parent = UUID()
        let first = HUDOuterBranchIdentity(parentID: parent, items: [item("Safari")])
        let refreshed = HUDOuterBranchIdentity(parentID: parent, items: [item("Safari")])
        XCTAssertNotEqual(first, refreshed)
        XCTAssertTrue(HUDOuterBranchMotionState().updating(first).updating(refreshed).isReplacement)
    }

    func testCollapseResetsHistorySoReopeningUsesOuterReveal() {
        let first = HUDOuterBranchIdentity(parentID: UUID(), items: [item("Left")])
        let second = HUDOuterBranchIdentity(parentID: UUID(), items: [item("Right")])
        let state = HUDOuterBranchMotionState().updating(first).updating(second)
        let collapsed = state.updating(.init(parentID: nil, items: []))
        XCTAssertFalse(collapsed.isReplacement)
        XCTAssertFalse(collapsed.updating(first).isReplacement)
    }

    private func item(_ name: String) -> RingMenuItem {
        RingMenuItem(label: name, icon: "app", actionType: .custom, actionData: "")
    }
}
