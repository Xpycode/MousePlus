import AppKit
import XCTest
@testable import MousePlus

final class TriggerOnboardingPolicyTests: XCTestCase {
    private let keyboard = TriggerBinding.keyboard(
        keyCode: 96, modifiers: NSEvent.ModifierFlags.option.rawValue, mode: .holdRelease
    )
    private let mouse = TriggerBinding.mouseButton(buttonNumber: 4, mode: .tapToggle)

    func testGrantedPermissionWaitsForCompletedLoadBeforeOpeningSetupOnce() {
        var policy = TriggerOnboardingPolicy()
        XCTAssertEqual(policy.evaluate(configuration: .loading, accessibilityGranted: true),
                       .init(status: .waiting, action: .none))
        XCTAssertEqual(policy.evaluate(configuration: .loaded(.default), accessibilityGranted: true),
                       .init(status: .triggerSetup, action: .showTriggerSetup))
        XCTAssertEqual(policy.evaluate(configuration: .loaded(.default), accessibilityGranted: true).action, .none)
    }

    func testSlowConfiguredLoadDoesNotPresentProvisionalDefaults() {
        var policy = TriggerOnboardingPolicy()
        _ = policy.evaluate(configuration: .loading, accessibilityGranted: true)
        XCTAssertEqual(policy.evaluate(configuration: .loaded(TriggersConfig(keyboard: keyboard)), accessibilityGranted: true),
                       .init(status: .configured, action: .none))
        XCTAssertEqual(policy.evaluate(configuration: .loaded(.default), accessibilityGranted: true).action, .none,
                       "Clearing the last binding does not restart launch onboarding")
    }

    func testLoadBeforePermissionRequiresExplicitContinuation() {
        var policy = TriggerOnboardingPolicy()
        XCTAssertEqual(policy.evaluate(configuration: .missingFile, accessibilityGranted: false).action, .showPermissionSetup)
        XCTAssertEqual(policy.evaluate(configuration: .missingFile, accessibilityGranted: false).action, .none)
        XCTAssertEqual(policy.evaluate(configuration: .missingFile, accessibilityGranted: true),
                       .init(status: .triggerSetup, action: .none))
        XCTAssertEqual(policy.evaluate(configuration: .missingFile, accessibilityGranted: true, continueFromPermission: true).action,
                       .showTriggerSetup)
        XCTAssertEqual(policy.evaluate(configuration: .missingFile, accessibilityGranted: true, continueFromPermission: true).action,
                       .none)
    }

    func testPermissionContinuationBeforeLoadIsRetained() {
        var policy = TriggerOnboardingPolicy()
        XCTAssertEqual(policy.evaluate(configuration: .loading, accessibilityGranted: false).action, .showPermissionSetup)
        XCTAssertEqual(policy.evaluate(configuration: .loading, accessibilityGranted: true, continueFromPermission: true),
                       .init(status: .waiting, action: .none))
        XCTAssertEqual(policy.evaluate(configuration: .missingFile, accessibilityGranted: true).action, .showTriggerSetup)
    }

    func testConfiguredPermissionRestorationRoutesToOrdinarySettingsAndPreservesBindings() {
        var policy = TriggerOnboardingPolicy()
        let triggers = TriggersConfig(keyboard: keyboard, mouseButton: mouse)
        _ = policy.evaluate(configuration: .loaded(triggers), accessibilityGranted: false)
        XCTAssertEqual(policy.evaluate(configuration: .loaded(triggers), accessibilityGranted: true).action, .none)
        XCTAssertEqual(policy.evaluate(configuration: .loaded(triggers), accessibilityGranted: true, continueFromPermission: true),
                       .init(status: .configured, action: .showSettings))
        XCTAssertEqual(TriggerOnboardingPolicy.eligibleRingBindings(in: triggers).map(\.binding), [keyboard, mouse])
    }

    func testFailureIsRecoveryNotFirstRunAndWaitsBehindPermissionWindow() {
        var policy = TriggerOnboardingPolicy()
        XCTAssertEqual(policy.evaluate(configuration: .failed, accessibilityGranted: true),
                       .init(status: .loadFailure, action: .showSettings))
        XCTAssertEqual(policy.evaluate(configuration: .failed, accessibilityGranted: true).action, .none)

        var permissionPolicy = TriggerOnboardingPolicy()
        _ = permissionPolicy.evaluate(configuration: .loading, accessibilityGranted: false)
        XCTAssertEqual(permissionPolicy.evaluate(configuration: .failed, accessibilityGranted: true),
                       .init(status: .loadFailure, action: .none))
        XCTAssertEqual(permissionPolicy.evaluate(configuration: .failed, accessibilityGranted: true, continueFromPermission: true).action,
                       .showSettings)
    }

    func testDeniedPermissionCannotQueueContinuation() {
        var policy = TriggerOnboardingPolicy()
        _ = policy.evaluate(configuration: .missingFile, accessibilityGranted: false)
        _ = policy.evaluate(configuration: .missingFile, accessibilityGranted: false, continueFromPermission: true)
        XCTAssertEqual(policy.evaluate(configuration: .missingFile, accessibilityGranted: true).action, .none)
    }

    func testNewLaunchRemindsAgainAfterUnconfiguredSetupWasClosed() {
        var firstLaunch = TriggerOnboardingPolicy()
        _ = firstLaunch.evaluate(configuration: .missingFile, accessibilityGranted: true)
        XCTAssertEqual(firstLaunch.evaluate(configuration: .missingFile, accessibilityGranted: true).action, .none)
        var nextLaunch = TriggerOnboardingPolicy()
        XCTAssertEqual(nextLaunch.evaluate(configuration: .missingFile, accessibilityGranted: true).action, .showTriggerSetup)
    }

    func testSettingsShortcutAndWrongSlotTypesDoNotQualify() {
        XCTAssertFalse(TriggerOnboardingPolicy.hasRingBinding(in: .default))
        XCTAssertFalse(TriggerOnboardingPolicy.hasRingBinding(in: TriggersConfig(openSettings: keyboard)))
        let wrongSlots = TriggersConfig(keyboard: mouse, mouseButton: keyboard, globalHUDShortcut: mouse)
        XCTAssertFalse(TriggerOnboardingPolicy.hasRingBinding(in: wrongSlots))
    }

    func testEachSupportedSlotQualifiesWithOriginalBindingAndMode() {
        for (triggers, expected) in [
            (TriggersConfig(keyboard: keyboard), TriggerOnboardingPolicy.RingBinding(slot: .contextualKeyboard, binding: keyboard)),
            (TriggersConfig(mouseButton: mouse), .init(slot: .mouseButton, binding: mouse)),
            (TriggersConfig(globalHUDShortcut: keyboard), .init(slot: .globalHUD, binding: keyboard))
        ] {
            XCTAssertEqual(TriggerOnboardingPolicy.eligibleRingBindings(in: triggers), [expected])
            var policy = TriggerOnboardingPolicy()
            XCTAssertEqual(policy.evaluate(configuration: .loaded(triggers), accessibilityGranted: true),
                           .init(status: .configured, action: .none))
        }
    }

    func testCollisionUsesNormalizedChordAndExcludesOnlyGlobalRoute() {
        let global = TriggerBinding.keyboard(
            keyCode: 96, modifiers: NSEvent.ModifierFlags([.option, .capsLock]).rawValue, mode: .tapToggle
        )
        let triggers = TriggersConfig(keyboard: keyboard, mouseButton: mouse, globalHUDShortcut: global)
        XCTAssertEqual(TriggerOnboardingPolicy.eligibleRingBindings(in: triggers), [
            .init(slot: .contextualKeyboard, binding: keyboard),
            .init(slot: .mouseButton, binding: mouse)
        ])
    }
}
