import XCTest
@testable import MousePlus

@MainActor
final class TriggerOnboardingGuidanceTests: XCTestCase {
    func testUnknownConfigurationDoesNotClaimAnEmptyFirstRun() {
        let guidance = TriggerOnboardingGuidance(savedTriggers: nil, accessibilityGranted: true)
        XCTAssertEqual(guidance.title, "Trigger setup")
        XCTAssertTrue(guidance.instructions.contains("Load your configuration"))
        XCTAssertFalse(guidance.settingsAccess.contains("press"))
    }

    func testSettingsOnlyShowsRecordingInstructions() {
        let guidance = TriggerOnboardingGuidance(savedTriggers: TriggersConfig(), accessibilityGranted: true)
        XCTAssertEqual(guidance.title, "Choose how to open MousePlus")
        XCTAssertTrue(guidance.instructions.contains("Record"))
        XCTAssertTrue(guidance.instructions.contains("Wait for Saved"))
    }

    func testHoldReleaseTrialUsesSavedMouseAndDismissesBeforeRelease() {
        let binding = TriggerBinding.mouseButton(buttonNumber: 4, mode: .holdRelease)
        let guidance = TriggerOnboardingGuidance(
            savedTriggers: TriggersConfig(mouseButton: binding), accessibilityGranted: true
        )
        XCTAssertTrue(guidance.instructions.contains("hold " + binding.displayString))
        XCTAssertTrue(guidance.instructions.contains("Escape before releasing"))
        XCTAssertTrue(guidance.instructions.contains("away from slices"))
    }

    func testGlobalOnlyTrialUsesTapToggleAndNamesGlobalHUD() {
        let binding = TriggerBinding.keyboard(keyCode: 40, modifiers: 0, mode: .tapToggle)
        let guidance = TriggerOnboardingGuidance(
            savedTriggers: TriggersConfig(globalHUDShortcut: binding), accessibilityGranted: true
        )
        XCTAssertEqual(guidance.title, "Try your saved trigger")
        XCTAssertTrue(guidance.instructions.contains("tap " + binding.displayString))
        XCTAssertTrue(guidance.instructions.contains("Global HUD"))
        XCTAssertTrue(guidance.instructions.contains("Escape to dismiss"))
    }

    func testRevokedPermissionIsExplicitWithoutLosingSavedTrial() {
        let binding = TriggerBinding.mouseButton(buttonNumber: 4, mode: .tapToggle)
        let guidance = TriggerOnboardingGuidance(
            savedTriggers: TriggersConfig(mouseButton: binding), accessibilityGranted: false
        )
        XCTAssertTrue(guidance.instructions.contains("Restore Accessibility permission"))
        XCTAssertTrue(guidance.instructions.contains(binding.displayString))
    }

    func testSettingsHelpReflectsCustomAndClearedBindings() {
        let custom = TriggerBinding.keyboard(keyCode: 40, modifiers: 0, mode: .tapToggle)
        let configured = TriggerOnboardingGuidance(
            savedTriggers: TriggersConfig(openSettings: custom), accessibilityGranted: true
        )
        XCTAssertTrue(configured.settingsAccess.contains(custom.displayString))
        let cleared = TriggerOnboardingGuidance(
            savedTriggers: TriggersConfig(openSettings: .none), accessibilityGranted: true
        )
        XCTAssertTrue(cleared.settingsAccess.contains("menu-bar icon"))
        XCTAssertFalse(cleared.settingsAccess.contains("press"))
    }
}
