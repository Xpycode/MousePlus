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
                 traversal: [false], eligible: true, visible: false),
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

    func testConditionalRevealRequiresInsideToOutsideTransitionAndLatches() {
        let model = conditionalModel()
        model.expand(0)

        model.updateActive(at: CGPoint(x: 25, y: 0), center: .zero)
        XCTAssertFalse(model.hasEnteredInnerBoundary)
        XCTAssertFalse(model.hasRevealedOuterRing)
        XCTAssertFalse(model.isOuterRingVisible)

        model.updateActive(at: CGPoint(x: 15, y: 0), center: .zero)
        XCTAssertTrue(model.hasEnteredInnerBoundary)
        XCTAssertFalse(model.hasRevealedOuterRing)

        model.updateActive(at: CGPoint(x: 21, y: 0), center: .zero)
        XCTAssertTrue(model.hasRevealedOuterRing)
        XCTAssertTrue(model.isOuterRingVisible)

        model.updateActive(at: CGPoint(x: 15, y: 0), center: .zero)
        XCTAssertTrue(model.hasRevealedOuterRing)
        XCTAssertTrue(model.isOuterRingVisible)
    }

    func testPointerStartingOutsideMustEnterBeforeLaterOutwardCrossing() {
        let model = conditionalModel()
        model.expand(0)

        model.updateActive(at: CGPoint(x: 35, y: 0), center: .zero)
        model.updateActive(at: CGPoint(x: 25, y: 0), center: .zero)
        XCTAssertFalse(model.hasRevealedOuterRing)

        model.updateActive(at: CGPoint(x: 20, y: 0), center: .zero)
        XCTAssertFalse(model.hasRevealedOuterRing)
        model.updateActive(at: CGPoint(x: 20.001, y: 0), center: .zero)
        XCTAssertTrue(model.hasRevealedOuterRing)
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
        XCTAssertFalse(model.hasEnteredInnerBoundary)
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

    func testConditionalOuterHitTargetsExistOnlyAfterReveal() {
        let model = conditionalModel()
        model.expand(0)
        let outerPoint = CGPoint(x: 35 * cos(CGFloat.pi / 4),
                                 y: 35 * sin(CGFloat.pi / 4))

        model.updateActive(at: outerPoint, center: .zero)
        XCTAssertNil(model.activeSelection)

        model.updateActive(at: CGPoint(x: 20, y: 0), center: .zero)
        model.updateActive(at: CGPoint(x: 21, y: 0), center: .zero)
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
        XCTAssertFalse(model.hasEnteredInnerBoundary, file: file, line: line)
        XCTAssertFalse(model.isOuterRingVisible, file: file, line: line)
        XCTAssertNil(model.expandedParentIndex, file: file, line: line)
        XCTAssertNil(model.activeSelection, file: file, line: line)
    }
}
