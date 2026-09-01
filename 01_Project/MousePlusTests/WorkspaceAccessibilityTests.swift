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
        XCTAssertEqual(presentation.identifier, "menuItems.wedge.outer.3")
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
