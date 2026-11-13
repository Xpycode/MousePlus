import AppKit
import XCTest
@testable import MousePlus

@MainActor
final class TriggerOnboardingLaunchTests: XCTestCase {
    @MainActor
    private final class EffectsRecorder {
        var events: [String] = []
        var configurations: [Configuration] = []

        func delegate() -> AppDelegate {
            AppDelegate(onboardingEffects: .init(
                applyRuntime: { self.configurations.append($0); self.events.append("runtime") },
                showPermission: { self.events.append("permission") },
                showTriggers: { self.events.append("triggers") },
                showSettings: { self.events.append("settings") }
            ))
        }
    }

    func testGrantedLaunchWaitsForLoadAndOpensTriggersOnlyOnce() {
        let effects = EffectsRecorder()
        let delegate = effects.delegate()
        delegate.beginTriggerOnboarding(accessibilityGranted: true)
        XCTAssertTrue(effects.events.isEmpty)
        delegate.triggerOnboardingConfigurationLoaded(.success(.defaults(Configuration())))
        delegate.triggerOnboardingPermissionGranted()
        delegate.continueTriggerOnboarding()
        XCTAssertEqual(effects.events, ["runtime", "triggers"])
    }

    func testContinueDuringSlowLoadIsRetained() {
        let effects = EffectsRecorder()
        let delegate = effects.delegate()
        delegate.beginTriggerOnboarding(accessibilityGranted: false)
        delegate.triggerOnboardingPermissionGranted()
        delegate.continueTriggerOnboarding()
        XCTAssertEqual(effects.events, ["permission"])
        delegate.triggerOnboardingConfigurationLoaded(.success(.loaded(Configuration())))
        XCTAssertEqual(effects.events, ["permission", "runtime", "triggers"])
    }

    func testLoadBeforePermissionStartsRuntimeOnceAndWaitsForContinue() {
        let effects = EffectsRecorder()
        let delegate = effects.delegate()
        delegate.beginTriggerOnboarding(accessibilityGranted: false)
        delegate.triggerOnboardingConfigurationLoaded(.success(.defaults(Configuration())))
        XCTAssertEqual(effects.events, ["permission"])
        delegate.triggerOnboardingPermissionGranted()
        delegate.triggerOnboardingPermissionGranted()
        XCTAssertEqual(effects.events, ["permission", "runtime"])
        delegate.continueTriggerOnboarding()
        delegate.continueTriggerOnboarding()
        XCTAssertEqual(effects.events, ["permission", "runtime", "triggers"])
    }

    func testConfiguredPermissionRestorationPreservesBindingAndUsesOrdinarySettings() {
        let effects = EffectsRecorder()
        let delegate = effects.delegate()
        var config = Configuration()
        config.triggers.mouseButton = .mouseButton(buttonNumber: 4, mode: .tapToggle)
        delegate.beginTriggerOnboarding(accessibilityGranted: false)
        delegate.triggerOnboardingConfigurationLoaded(.success(.loaded(config)))
        delegate.triggerOnboardingPermissionGranted()
        delegate.continueTriggerOnboarding()
        XCTAssertEqual(effects.events, ["permission", "runtime", "settings"])
        XCTAssertEqual(effects.configurations.last?.triggers, config.triggers)
    }

    func testLoadFailureRoutesToTriggersWithoutApplyingDefaultsAndRecoveryApplies() {
        let effects = EffectsRecorder()
        let delegate = effects.delegate()
        delegate.beginTriggerOnboarding(accessibilityGranted: true)
        delegate.triggerOnboardingConfigurationLoaded(.failure(CocoaError(.fileReadCorruptFile)))
        XCTAssertEqual(effects.events, ["triggers"])
        XCTAssertTrue(effects.configurations.isEmpty)
        delegate.applySavedConfiguration(Configuration())
        XCTAssertEqual(effects.events, ["triggers", "runtime"])
    }

    func testSavedConfigurationWinsOverLateStartupLoad() {
        let effects = EffectsRecorder()
        let delegate = effects.delegate()
        var saved = Configuration()
        saved.triggers.mouseButton = .mouseButton(buttonNumber: 3, mode: .holdRelease)
        delegate.beginTriggerOnboarding(accessibilityGranted: true)
        delegate.applySavedConfiguration(saved)
        delegate.triggerOnboardingConfigurationLoaded(.success(.defaults(Configuration())))
        delegate.triggerOnboardingConfigurationLoaded(.failure(CocoaError(.fileReadCorruptFile)))
        XCTAssertEqual(effects.events, ["runtime"])
        XCTAssertEqual(effects.configurations.last?.triggers, saved.triggers)
    }

    func testSavedConfigurationWhileDeniedWaitsForGrant() {
        let effects = EffectsRecorder()
        let delegate = effects.delegate()
        delegate.beginTriggerOnboarding(accessibilityGranted: false)
        delegate.applySavedConfiguration(Configuration())
        XCTAssertEqual(effects.events, ["permission"])
        delegate.triggerOnboardingPermissionGranted()
        XCTAssertEqual(effects.events, ["permission", "runtime"])
    }

    func testAppHostedLaunchGuardDoesNotInvokeInjectedEffects() {
        let effects = EffectsRecorder()
        let delegate = effects.delegate()
        delegate.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
        XCTAssertTrue(effects.events.isEmpty)
    }
}
