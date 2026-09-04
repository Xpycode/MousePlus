import XCTest
import CoreGraphics
@testable import MousePlus

@MainActor
final class RingViewModelHUDTests: XCTestCase {
    func testOuterRingPolicyStateTransitionMatrix() {
        struct Case {
            let policy: OuterRingVisibility
            let hasParent: Bool
            let itemCount: Int
            let traversal: [Bool]
            let eligible: Bool
            let visible: Bool
        }
        let cases = [
            Case(policy: .alwaysVisible, hasParent: false, itemCount: 2,
                 traversal: [], eligible: false, visible: false),
            Case(policy: .alwaysVisible, hasParent: true, itemCount: 0,
                 traversal: [], eligible: false, visible: false),
            Case(policy: .alwaysVisible, hasParent: true, itemCount: 2,
                 traversal: [], eligible: true, visible: true),
            Case(policy: .revealBeyondInnerRing, hasParent: true, itemCount: 2,
                 traversal: [], eligible: true, visible: false),
            Case(policy: .revealBeyondInnerRing, hasParent: true, itemCount: 2,
                 traversal: [false], eligible: true, visible: true),
            Case(policy: .revealBeyondInnerRing, hasParent: true, itemCount: 2,
                 traversal: [true], eligible: true, visible: false),
            Case(policy: .revealBeyondInnerRing, hasParent: true, itemCount: 2,
                 traversal: [true, false], eligible: true, visible: true),
            Case(policy: .alwaysHidden, hasParent: true, itemCount: 2,
                 traversal: [true, false], eligible: false, visible: false)
        ]

        for testCase in cases {
            var state = OuterRingPolicyState()
            var result = state.transition(
                policy: testCase.policy,
                hasExpandedParent: testCase.hasParent,
                itemCount: testCase.itemCount
            )
            for position in testCase.traversal {
                state = result.state
                result = state.transition(
                    policy: testCase.policy,
                    hasExpandedParent: testCase.hasParent,
                    itemCount: testCase.itemCount,
                    pointerIsAtOrInsideInnerBoundary: position
                )
            }
            XCTAssertEqual(result.isEligible, testCase.eligible, "\(testCase)")
            XCTAssertEqual(result.isVisible, testCase.visible, "\(testCase)")
        }
    }

    /// `HUDCustomization()`'s compatibility defaults must reproduce the
    /// pre-customization HUD: inner captions hidden, middle/outer shown, all
    /// upright, independent of icon orientation.
    func testDefaultHUDCustomizationReproducesCompatibilityLabelPresentation() {
        let viewModel = RingViewModel()

        XCTAssertFalse(viewModel.isLabelVisible(for: .inner))
        XCTAssertTrue(viewModel.isLabelVisible(for: .middle))
        XCTAssertTrue(viewModel.isLabelVisible(for: .outer))
        for band in [Band.inner, .middle, .outer] {
            XCTAssertEqual(viewModel.labelOrientation(for: band), .upright)
        }
    }

    func testEffectiveGeometryResolvesAutoAndFixedBandsIndependently() {
        var customization = HUDCustomization.default
        customization.inner.layout = HUDRingLayout(
            slotCountMode: .auto, fixedSlotCount: 8, angularOffset: -90
        )
        customization.middle.layout = HUDRingLayout(
            slotCountMode: .fixed, fixedSlotCount: 7, angularOffset: 450
        )
        let model = makeModel(innerCount: 2, middleCount: 3,
                              customization: customization)

        XCTAssertEqual(model.geometry.inner.slotCount, 2)
        XCTAssertEqual(model.geometry.middle.slotCount, 7)
        XCTAssertEqual(model.geometry.inner.angularOffset, 3 * .pi / 2, accuracy: 1e-12)
        XCTAssertEqual(model.geometry.middle.angularOffset, .pi / 2, accuracy: 1e-12)
    }

    func testInvalidFixedCountCannotOverlapConfiguredItems() {
        var customization = HUDCustomization.default
        customization.inner.layout.slotCountMode = .fixed
        customization.inner.layout.fixedSlotCount = -20
        customization.middle.layout.slotCountMode = .fixed
        customization.middle.layout.fixedSlotCount = 99
        let model = makeModel(innerCount: 4, middleCount: 2,
                              customization: customization)

        XCTAssertEqual(model.geometry.inner.slotCount, 4)
        XCTAssertEqual(model.geometry.middle.slotCount, 8)
    }

    func testConditionalRevealRevealsOnDirectOutsideHoverAndLatches() {
        let model = conditionalModel()
        model.expand(0)

        model.updateActive(at: CGPoint(x: 25, y: 0), center: .zero)
        XCTAssertTrue(model.hasEnteredInnerBoundary)
        XCTAssertTrue(model.hasRevealedOuterRing)
        XCTAssertTrue(model.isOuterRingVisible)

        model.updateActive(at: CGPoint(x: 15, y: 0), center: .zero)
        XCTAssertTrue(model.hasRevealedOuterRing)
        XCTAssertTrue(model.isOuterRingVisible)
    }

    func testConditionalRevealStartsInsideForEveryInvocation() {
        let model = conditionalModel()
        model.expand(0)

        model.updateActive(at: CGPoint(x: 35, y: 0), center: .zero)
        XCTAssertTrue(model.hasRevealedOuterRing)
        XCTAssertTrue(model.isOuterRingVisible)
    }

    func testNaturalCenterToParentHoverAutoExpandsAndReveals() {
        let model = conditionalModel()
        model.updateActive(at: .zero, center: .zero)
        model.updateActive(at: CGPoint(x: 25, y: 0), center: .zero)

        XCTAssertEqual(model.expandedParentIndex, 0)
        XCTAssertTrue(model.hasEnteredInnerBoundary)
        XCTAssertTrue(model.hasRevealedOuterRing)
        XCTAssertTrue(model.isOuterRingVisible)
    }

    func testRevealOnlyUpdateDoesNotRepointExpandedParent() {
        var customization = HUDCustomization.default
        customization.outerRingVisibility = .revealBeyondInnerRing
        var apps = item("Apps")
        apps.subItems = [item("Safari"), item("Finder")]
        var snap = item("Snap")
        snap.subItems = [item("Left"), item("Right")]
        let config = Configuration(
            inner: [],
            middle: [snap, apps],
            triggers: .default,
            appearance: AppearanceConfig(deadZone: 10, innerEdge: 20,
                                         middleEdge: 30, outerEdge: 40),
            hudCustomization: customization
        )
        let model = RingViewModel()
        model.load(from: config)
        model.expand(1)

        model.updateOuterRingReveal(at: CGPoint(x: 20, y: 0), center: .zero)
        model.updateOuterRingReveal(at: CGPoint(x: 21, y: 0), center: .zero)

        XCTAssertTrue(model.isOuterRingVisible)
        XCTAssertEqual(model.expandedParentIndex, 1)
        XCTAssertEqual(model.outerItems.map(\.label), ["Safari", "Finder"])
        XCTAssertNil(model.activeSelection)
    }

    func testRevealStateIsTriggerNeutral() {
        for mode in [TriggerMode.holdRelease, .tapToggle] {
            let model = conditionalModel(triggerMode: mode)
            // Runtime opens centered on the pointer, tracks the parent while
            // moving outward, and expands before either release or click.
            model.updateActive(at: .zero, center: .zero)
            model.updateActive(at: CGPoint(x: 25, y: 0), center: .zero)
            XCTAssertEqual(model.expandedParentIndex, 0, "mode: \(mode)")
            XCTAssertTrue(model.isOuterRingVisible, "mode: \(mode)")
            XCTAssertEqual(model.commitActive(), .expanded, "mode: \(mode)")
            XCTAssertTrue(model.hasRevealedOuterRing, "mode: \(mode)")
            XCTAssertTrue(model.isOuterRingVisible, "mode: \(mode)")
        }
    }

    func testRevealLatchSurvivesCollapseAndBranchExpansionUntilInvocationReset() {
        let model = conditionalModel()
        model.updateActive(at: .zero, center: .zero)
        model.updateActive(at: CGPoint(x: 25, y: 0), center: .zero)
        model.expand(0)
        XCTAssertTrue(model.isOuterRingVisible)

        model.collapse()
        XCTAssertFalse(model.isOuterRingVisible)
        XCTAssertTrue(model.hasRevealedOuterRing)

        model.expand(0)
        XCTAssertTrue(model.isOuterRingVisible)

        model.reset()
        XCTAssertFalse(model.hasRevealedOuterRing)
        XCTAssertTrue(model.hasEnteredInnerBoundary)
    }

    func testVisibilityPolicyRequiresAnAvailableExpandedBranch() {
        var always = HUDCustomization.default
        always.outerRingVisibility = .alwaysVisible
        let model = makeModel(customization: always)
        XCTAssertFalse(model.isOuterRingVisible)

        model.expand(0)
        XCTAssertTrue(model.isOuterRingVisible)
        model.collapse()
        XCTAssertFalse(model.isOuterRingVisible)

        model.middleItems[0].subItems = []
        model.expand(0)
        XCTAssertFalse(model.isOuterRingVisible)
    }

    func testHiddenSubmenuParentCannotExpandExecuteOrClose() {
        var hidden = HUDCustomization.default
        hidden.outerRingVisibility = .alwaysHidden
        let model = makeModel(customization: hidden)
        var closeRequests = 0
        model.requestClose = { closeRequests += 1 }
        model.activeSelection = ActiveSelection(band: .middle, index: 0)

        model.commitActive()

        XCTAssertNil(model.expandedParentIndex)
        XCTAssertTrue(model.outerItems.isEmpty)
        XCTAssertEqual(closeRequests, 0)
    }

    /// Regression guard (Wave 2): a `.none`-sourced middle wedge must expand
    /// synchronously from its static `subItems`, identically to before
    /// `expand()` grew a `dynamicSource` switch.
    func testStaticSubItemsStillExpandSynchronouslyAndUnchanged() {
        let model = makeModel()
        let children = model.middleItems[0].subItems ?? []
        XCTAssertFalse(children.isEmpty)

        model.expand(0)

        XCTAssertEqual(model.expandedParentIndex, 0)
        XCTAssertEqual(model.outerItems.map(\.label), children.map(\.label))
        XCTAssertTrue(model.dynamicIcons.isEmpty)
    }

    /// A `.runningApps`-sourced wedge points the expansion at itself and shows
    /// a transient empty arc (no "Loading…" placeholder) — population itself is
    /// wired in a later wave.
    func testDynamicSourceRunningAppsExpandsToTransientEmptyArc() {
        var customization = HUDCustomization.default
        customization.outerRingVisibility = .alwaysVisible
        var middle = [item("Apps")]
        middle[0].dynamicSource = .runningApps
        let config = Configuration(
            inner: [],
            middle: middle,
            triggers: .default,
            appearance: AppearanceConfig(deadZone: 10, innerEdge: 20,
                                         middleEdge: 30, outerEdge: 40),
            hudCustomization: customization
        )
        let model = RingViewModel()
        model.load(from: config)

        model.expand(0)

        XCTAssertEqual(model.expandedParentIndex, 0)
        XCTAssertTrue(model.outerItems.isEmpty)
        XCTAssertTrue(model.dynamicIcons.isEmpty)
        XCTAssertFalse(model.isOuterRingVisible)
    }

    func testDynamicSourceRunningAppsCanExpandThroughCommitPathBeforeFetch() {
        var customization = HUDCustomization.default
        customization.outerRingVisibility = .alwaysVisible
        var middle = [item("Apps")]
        middle[0].dynamicSource = .runningApps
        let config = Configuration(
            inner: [],
            middle: middle,
            triggers: .default,
            appearance: AppearanceConfig(deadZone: 10, innerEdge: 20,
                                         middleEdge: 30, outerEdge: 40),
            hudCustomization: customization
        )
        let model = RingViewModel()
        model.load(from: config)
        model.activeSelection = ActiveSelection(band: .middle, index: 0)

        XCTAssertEqual(model.commitActive(), .expanded)
        XCTAssertEqual(model.expandedParentIndex, 0)
    }

    func testRunningAppsUseFullCircleHitTestingWhileStaticSubmenusKeepLocalizedArc() {
        var customization = HUDCustomization.default
        customization.outerRingVisibility = .alwaysVisible
        var snap = item("Snap")
        snap.subItems = [item("Left"), item("Right")]
        var apps = item("Apps")
        apps.dynamicSource = .runningApps
        let config = Configuration(
            inner: [],
            middle: [snap, apps],
            triggers: .default,
            appearance: AppearanceConfig(deadZone: 10, innerEdge: 20,
                                         middleEdge: 30, outerEdge: 40),
            hudCustomization: customization
        )
        let model = RingViewModel()
        model.load(from: config)

        model.expandedParentIndex = 0
        model.outerItems = [item("Left"), item("Right")]
        XCTAssertEqual(model.outerRingLayout, .localizedArc)

        model.expandedParentIndex = 1
        model.outerItems = [item("A"), item("B"), item("C"), item("D")]
        XCTAssertEqual(model.outerRingLayout, .fullCircle)
        model.updateActive(
            at: CGPoint(x: 35 * cos(CGFloat.pi / 2),
                        y: 35 * sin(CGFloat.pi / 2)),
            center: .zero
        )
        XCTAssertEqual(model.activeSelection, ActiveSelection(band: .outer, index: 2))
    }

    /// `AppSwitcherService` reads live `NSWorkspace.shared.runningApplications`,
    /// so its contents can't be controlled here — this asserts the invariant the
    /// population path guarantees instead: every outer item it produces commits
    /// through `.appSwitch` with a non-empty bundle identifier.
    func testDynamicSourceRunningAppsPopulatesAppSwitchItemsAfterFetchCompletes() async {
        var customization = HUDCustomization.default
        customization.outerRingVisibility = .alwaysVisible
        var middle = [item("Apps")]
        middle[0].dynamicSource = .runningApps
        let config = Configuration(
            inner: [],
            middle: middle,
            triggers: .default,
            appearance: AppearanceConfig(deadZone: 10, innerEdge: 20,
                                         middleEdge: 30, outerEdge: 40),
            hudCustomization: customization
        )
        let model = RingViewModel()
        model.load(from: config)

        model.expand(0)
        for _ in 0..<5 { await Task.yield() }
        try? await Task.sleep(nanoseconds: 30_000_000)

        XCTAssertEqual(model.expandedParentIndex, 0)
        for outerItem in model.outerItems {
            XCTAssertEqual(outerItem.actionType, .appSwitch)
            XCTAssertFalse(outerItem.actionData.isEmpty)
        }
    }

    /// Pending Apps results must not replace a newer static branch or restore a
    /// reset invocation, even with the longest branch crossfade configured.
    /// This uses the real workspace service, whose completion is not injectable;
    /// the bounded drain follows the population regression above.
    func testDynamicSourceRunningAppsLateResultIsDiscardedAfterRepointAndReset() async {
        var customization = HUDCustomization.default
        customization.outerRingVisibility = .alwaysVisible
        var middle = [item("Apps")]
        middle[0].dynamicSource = .runningApps
        var snap = item("Snap")
        snap.subItems = [item("Left"), item("Right")]
        middle.append(snap)
        let config = Configuration(
            inner: [],
            middle: middle,
            triggers: .default,
            appearance: AppearanceConfig(deadZone: 10, innerEdge: 20,
                                         middleEdge: 30, outerEdge: 40,
                                         motion: HUDMotionConfiguration(
                                            baseDuration: HUDMotionPolicy.maximumDuration
                                         )),
            hudCustomization: customization
        )
        for resetAfterRepoint in [false, true] {
            let model = RingViewModel()
            model.load(from: config)

            // All mutations occur before the main actor yields to the Apps task.
            model.expand(0)
            model.expand(1)
            XCTAssertEqual(model.outerItems.map(\.id), snap.subItems?.map(\.id))
            if resetAfterRepoint { model.reset() }
            for _ in 0..<5 { await Task.yield() }
            try? await Task.sleep(nanoseconds: 30_000_000)

            if resetAfterRepoint {
                XCTAssertTrue(model.outerItems.isEmpty)
                XCTAssertNil(model.expandedParentIndex)
            } else {
                XCTAssertEqual(model.outerItems.map(\.id), snap.subItems?.map(\.id))
                XCTAssertEqual(model.expandedParentIndex, 1)
            }
            XCTAssertTrue(model.dynamicIcons.isEmpty)
        }
    }

    func testConditionalOuterHitTargetsExistOnDirectArrival() {
        let model = conditionalModel()
        model.expand(0)
        let outerPoint = CGPoint(x: 35 * cos(CGFloat.pi / 4),
                                 y: 35 * sin(CGFloat.pi / 4))

        model.updateActive(at: outerPoint, center: .zero)
        XCTAssertEqual(model.activeSelection?.band, .outer)
    }

    func testResetAndVisibilityTransitionsClearInvocationState() {
        let model = conditionalModel()
        model.expand(0)
        model.updateActive(at: CGPoint(x: 20, y: 0), center: .zero)
        model.updateActive(at: CGPoint(x: 21, y: 0), center: .zero)
        XCTAssertTrue(model.hasRevealedOuterRing)

        model.reset()
        assertInvocationReset(model)

        model.expand(0)
        model.updateActive(at: CGPoint(x: 20, y: 0), center: .zero)
        model.updateActive(at: CGPoint(x: 21, y: 0), center: .zero)
        model.isVisible = true
        assertInvocationReset(model)

        model.expand(0)
        model.updateActive(at: CGPoint(x: 20, y: 0), center: .zero)
        model.updateActive(at: CGPoint(x: 21, y: 0), center: .zero)
        model.isVisible = false
        assertInvocationReset(model)
    }

    private func conditionalModel(triggerMode: TriggerMode = .holdRelease) -> RingViewModel {
        var customization = HUDCustomization.default
        customization.outerRingVisibility = .revealBeyondInnerRing
        let triggers = TriggersConfig(
            keyboard: .keyboard(keyCode: 1, modifiers: 0, mode: triggerMode)
        )
        return makeModel(customization: customization, triggers: triggers)
    }

    private func makeModel(innerCount: Int = 2,
                           middleCount: Int = 2,
                           customization: HUDCustomization = .default,
                           triggers: TriggersConfig = .default) -> RingViewModel {
        let children = [item("Child 1"), item("Child 2")]
        var middle = (0..<middleCount).map { item("Middle \($0)") }
        if !middle.isEmpty { middle[0].subItems = children }
        let config = Configuration(
            inner: (0..<innerCount).map { item("Inner \($0)") },
            middle: middle,
            triggers: triggers,
            appearance: AppearanceConfig(deadZone: 10, innerEdge: 20,
                                         middleEdge: 30, outerEdge: 40),
            hudCustomization: customization
        )
        let model = RingViewModel()
        model.load(from: config)
        return model
    }

    private func item(_ label: String) -> RingMenuItem {
        RingMenuItem(label: label, icon: "circle", actionType: .custom,
                     actionData: "true")
    }

    private func assertInvocationReset(_ model: RingViewModel,
                                       file: StaticString = #filePath,
                                       line: UInt = #line) {
        XCTAssertFalse(model.hasRevealedOuterRing, file: file, line: line)
        XCTAssertTrue(model.hasEnteredInnerBoundary, file: file, line: line)
        XCTAssertFalse(model.isOuterRingVisible, file: file, line: line)
        XCTAssertNil(model.expandedParentIndex, file: file, line: line)
        XCTAssertNil(model.activeSelection, file: file, line: line)
    }
}
