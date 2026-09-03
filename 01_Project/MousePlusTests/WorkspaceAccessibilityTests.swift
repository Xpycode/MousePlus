import AppKit
import SwiftUI
import XCTest
@testable import MousePlus

@MainActor
final class WorkspaceAccessibilityTests: XCTestCase {
    func testWedgePresentationExposesRequiredVoiceOverContext() {
        let item = RingMenuItem(
            label: "Left Half",
            icon: "rectangle.lefthalf.filled",
            actionType: .windowSnap,
            actionData: SnapZone.left.rawValue
        )

        let presentation = RingWedgeAccessibility(
            item: item,
            band: "Outer",
            position: 2,
            selected: true
        )

        XCTAssertEqual(
            presentation.label,
            "Outer wedge, position 3, Left Half, action Window Snap"
        )
        XCTAssertEqual(presentation.value, "Selected")
        XCTAssertEqual(presentation.identifier, "hud.wedge.outer.3")
        XCTAssertTrue(presentation.isSelected)
        XCTAssertFalse(presentation.isUnavailable)
    }

    func testUnlabeledInvalidWedgeAnnouncesPlaceholderAndSelectionState() {
        let item = RingMenuItem(
            label: "",
            icon: "not.a.real.symbol.for.mouseplus",
            actionType: .custom
        )

        let presentation = RingWedgeAccessibility(
            item: item,
            band: "Inner",
            position: 0,
            selected: false
        )

        XCTAssertTrue(presentation.label.contains("Inner wedge, position 1"))
        XCTAssertTrue(presentation.label.contains("unlabeled"))
        XCTAssertTrue(presentation.label.contains("action Custom"))
        XCTAssertTrue(presentation.label.contains("invalid symbol; placeholder shown"))
        XCTAssertEqual(presentation.value, "Not selected")
    }

    func testHiddenSubmenuParentIsUnavailableAndHasNoActivationAmbiguity() {
        let parent = RingMenuItem(
            label: "Windows", icon: "macwindow", actionType: .custom,
            subItems: [RingMenuItem(label: "Left", icon: "arrow.left", actionType: .windowSnap)]
        )
        let snapshot = RingAccessibilitySnapshot(
            innerItems: [], middleItems: [parent], outerItems: parent.subItems ?? [],
            selected: ActiveSelection(band: .middle, index: 0), outerVisible: false,
            hiddenSubmenuReason: "Submenu hidden by HUD setting"
        )

        XCTAssertEqual(snapshot.middle.first?.identifier, "hud.wedge.middle.1")
        XCTAssertEqual(snapshot.middle.first?.value,
                       "Selected. Unavailable. Submenu hidden by HUD setting")
        XCTAssertTrue(snapshot.middle.first?.isSelected == true)
        XCTAssertTrue(snapshot.middle.first?.isUnavailable == true)
        XCTAssertTrue(snapshot.outer.isEmpty)
    }

    func testFixedEmptyPositionsAndHiddenOuterItemsAreAbsent() {
        let configured = RingMenuItem(label: "Copy", icon: "doc.on.doc", actionType: .custom)
        let hiddenOuter = RingMenuItem(label: "Paste", icon: "doc.on.clipboard", actionType: .custom)
        let snapshot = RingAccessibilitySnapshot(
            innerItems: [configured], middleItems: [], outerItems: [hiddenOuter],
            selected: nil, outerVisible: false
        )

        // A fixed geometry may reserve eight positions, but accessibility is
        // generated only from configured items, never from slot count.
        XCTAssertEqual(snapshot.inner.map(\.identifier), ["hud.wedge.inner.1"])
        XCTAssertFalse(snapshot.inner.contains { $0.identifier == "hud.wedge.inner.8" })
        XCTAssertTrue(snapshot.outer.isEmpty)
    }

    func testPreviewUsesDistinctIdentifiersAndAnnouncesSelection() {
        let item = RingMenuItem(label: "Mission Control", icon: "rectangle.3.group", actionType: .custom)
        let snapshot = RingAccessibilitySnapshot(
            innerItems: [], middleItems: [item], outerItems: [],
            selected: ActiveSelection(band: .middle, index: 0), outerVisible: false,
            identifierPrefix: "menuItems.preview.wedge"
        )

        XCTAssertEqual(snapshot.middle.first?.identifier, "menuItems.preview.wedge.middle.1")
        XCTAssertEqual(snapshot.middle.first?.value, "Selected")
        XCTAssertTrue(snapshot.middle.first?.isSelected == true)
    }

    func testCenterSettingsMetadataIsStableAndDescriptive() {
        XCTAssertEqual(HUDCenterSettingsControl.accessibilityIdentifier, "hud.center.settings")
        XCTAssertEqual(HUDCenterSettingsControl.accessibilityLabel, "Open MousePlus Settings")
    }

    func testSegmentedChoiceKeyboardChangeUpdatesSelectedValue() {
        var selection = 0
        let binding = Binding(get: { selection }, set: { selection = $0 })
        let coordinator = AppKitSegmentedControl.Coordinator(selection: binding)
        let control = NSSegmentedControl(
            labels: ["Always", "Reveal", "Hidden"], trackingMode: .selectOne,
            target: nil, action: nil
        )

        // NSSegmentedControl sends the same action for keyboard and pointer
        // changes; exercising the action path proves the binding retains the
        // newly selected, VoiceOver-announced value.
        control.selectedSegment = 1
        coordinator.changed(control)

        XCTAssertEqual(selection, 1)
        XCTAssertEqual(control.label(forSegment: selection), "Reveal")
    }

    func testPersistenceStatesNeverDependOnColorForMeaning() {
        let states: [SettingsWorkspaceCoordinator.Status] = [
            .idle,
            .loading,
            .saving,
            .saved,
            .saveFailed("Disk is read-only"),
            .loadFailed("Configuration is malformed")
        ]

        for state in states {
            let presentation = WorkspaceStatusPresentation(status: state)
            XCTAssertFalse(presentation.title.isEmpty)
            if presentation.isFailure {
                XCTAssertNotNil(presentation.detail)
                XCTAssertTrue(presentation.canRetry)
            }
        }
    }
}
