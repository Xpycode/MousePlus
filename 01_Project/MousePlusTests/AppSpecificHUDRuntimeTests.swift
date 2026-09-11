import XCTest
import SwiftUI
@testable import MousePlus

@MainActor
final class AppSpecificHUDRuntimeTests: XCTestCase {
    private let contextual = TriggerSource(
        route: .contextual,
        physicalSource: .keyboard(keyCode: 96, modifiers: 1)
    )
    private let global = TriggerSource(
        route: .global,
        physicalSource: .keyboard(keyCode: 97, modifiers: 2)
    )

    func testResolvedInvocationLoadsAppActionsWithGlobalPresentationAndFrozenTarget() {
        var customization = HUDCustomization.default
        customization.outerRingVisibility = .alwaysHidden
        let globalInner = [item("Global Inner")]
        let globalMiddle = [item("Global Middle")]
        let appLayout = HUDActionLayout(
            inner: [item("Finder Inner")],
            middle: [item("Finder Middle")]
        )
        let configuration = Configuration(
            inner: globalInner,
            middle: globalMiddle,
            appearance: AppearanceConfig(deadZone: 31, innerEdge: 52,
                                         middleEdge: 83, outerEdge: 117),
            hudCustomization: customization,
            appHUDProfiles: ["com.apple.finder": AppHUDProfile(layout: appLayout)]
        )
        let snapshot = FrontmostAppSnapshot(
            processIdentifier: 4321,
            bundleIdentifier: "com.apple.finder",
            localizedName: "Finder"
        )
        let resolved = configuration.resolveHUD(
            route: .contextual,
            frontmostApp: snapshot,
            mousePlusBundleIdentifier: "com.xpycode.MousePlus"
        )
        let model = RingViewModel()

        model.load(resolved: resolved, presentation: configuration)

        XCTAssertEqual(model.innerItems.map(\.label), ["Finder Inner"])
        XCTAssertEqual(model.middleItems.map(\.label), ["Finder Middle"])
        XCTAssertEqual(model.radii.r0, 31)
        XCTAssertEqual(model.radii.r1, 52)
        XCTAssertEqual(model.radii.r2, 83)
        XCTAssertEqual(model.radii.r3, 117)
        XCTAssertEqual(model.hudCustomization, customization)
        XCTAssertEqual(model.frontmostPID, 4321)
        XCTAssertEqual(model.resolvedHUDProfile, resolved)
    }

    func testProfileReplacementClearsSelectionExpansionAndDynamicIconState() {
        var parent = item("Apps")
        parent.subItems = [item("Child")]
        let first = resolved(layout: HUDActionLayout(inner: [], middle: [parent]), pid: 11)
        let replacement = resolved(
            route: .global,
            layout: HUDActionLayout(inner: [item("Global")], middle: []),
            pid: 22
        )
        var configuration = Configuration()
        configuration.hudCustomization.outerRingVisibility = .alwaysVisible
        let model = RingViewModel()
        model.load(resolved: first, presentation: configuration)
        model.expand(0)
        model.activeSelection = ActiveSelection(band: .outer, index: 0)
        XCTAssertNotNil(model.expandedParentIndex)

        model.load(resolved: replacement, presentation: configuration)

        XCTAssertEqual(model.innerItems.map(\.label), ["Global"])
        XCTAssertNil(model.activeSelection)
        XCTAssertNil(model.expandedParentIndex)
        XCTAssertTrue(model.outerItems.isEmpty)
        XCTAssertTrue(model.dynamicIcons.isEmpty)
        XCTAssertEqual(model.frontmostPID, 22)
    }

    func testConfigurationChangesDoNotMutateLoadedInvocationButNextLoadUsesThem() {
        var configuration = Configuration(
            inner: [item("Old Global")],
            middle: [],
            appHUDProfiles: [
                "com.apple.finder": AppHUDProfile(layout: HUDActionLayout(
                    inner: [item("Old Finder")], middle: []
                ))
            ]
        )
        let snapshot = FrontmostAppSnapshot(
            processIdentifier: 7,
            bundleIdentifier: "com.apple.finder",
            localizedName: "Finder"
        )
        let model = RingViewModel()
        model.load(
            resolved: configuration.resolveHUD(
                route: .contextual,
                frontmostApp: snapshot,
                mousePlusBundleIdentifier: "com.xpycode.MousePlus"
            ),
            presentation: configuration
        )

        _ = configuration.setAppHUDProfile(
            AppHUDProfile(layout: HUDActionLayout(inner: [item("New Finder")], middle: [])),
            forBundleIdentifier: "com.apple.finder"
        )
        XCTAssertEqual(model.innerItems.map(\.label), ["Old Finder"])

        model.load(
            resolved: configuration.resolveHUD(
                route: .contextual,
                frontmostApp: snapshot,
                mousePlusBundleIdentifier: "com.xpycode.MousePlus"
            ),
            presentation: configuration
        )
        XCTAssertEqual(model.innerItems.map(\.label), ["New Finder"])
    }

    func testGlobalRouteBypassesExactAppProfileAndFallbackRemainsCompleteGlobalLayout() {
        let globalLayout = HUDActionLayout(
            inner: [item("Global Inner")], middle: [item("Global Middle")]
        )
        let configuration = Configuration(
            inner: globalLayout.inner,
            middle: globalLayout.middle,
            appHUDProfiles: [
                "com.apple.finder": AppHUDProfile(layout: HUDActionLayout(
                    inner: [item("Finder")], middle: []
                ))
            ]
        )
        let finder = FrontmostAppSnapshot(
            processIdentifier: 19,
            bundleIdentifier: "com.apple.finder",
            localizedName: "Finder"
        )
        let missingBundleID = FrontmostAppSnapshot(
            processIdentifier: 20,
            bundleIdentifier: nil,
            localizedName: "Unknown"
        )

        XCTAssertEqual(
            configuration.resolveHUD(
                route: .global, frontmostApp: finder,
                mousePlusBundleIdentifier: "com.xpycode.MousePlus"
            ).actionLayout,
            globalLayout
        )
        XCTAssertEqual(
            configuration.resolveHUD(
                route: .contextual, frontmostApp: missingBundleID,
                mousePlusBundleIdentifier: "com.xpycode.MousePlus"
            ).actionLayout,
            globalLayout
        )
    }

    func testOtherRouteReplacesAndTransfersReleaseOwnership() {
        var ownership = HUDInvocationOwnership()
        XCTAssertEqual(ownership.handle(down(contextual, .holdRelease)), .show)
        XCTAssertEqual(ownership.handle(down(global, .holdRelease)), .replace)
        XCTAssertEqual(ownership.visibleRoute, .global)
        XCTAssertEqual(ownership.releaseOwner, global)

        XCTAssertEqual(ownership.handle(up(contextual, .holdRelease)), .ignore)
        XCTAssertEqual(ownership.handle(moved(contextual, .holdRelease)), .ignore)
        XCTAssertEqual(ownership.handle(moved(global, .holdRelease)), .updateSelection)
        XCTAssertEqual(ownership.handle(up(global, .holdRelease)), .commitRelease)
        XCTAssertNil(ownership.releaseOwner)
    }

    func testRapidRouteSwitchingAlwaysLeavesNewestInvocationAsOwner() {
        var ownership = HUDInvocationOwnership()
        XCTAssertEqual(ownership.handle(down(contextual, .holdRelease)), .show)
        XCTAssertEqual(ownership.handle(down(global, .holdRelease)), .replace)
        XCTAssertEqual(ownership.handle(down(contextual, .holdRelease)), .replace)

        XCTAssertEqual(ownership.handle(up(global, .holdRelease)), .ignore)
        XCTAssertEqual(ownership.handle(up(contextual, .holdRelease)), .commitRelease)
        XCTAssertEqual(ownership.visibleRoute, .contextual)
    }

    func testSameRouteTapToggleDismissesWhileOtherRouteTapReplaces() {
        var ownership = HUDInvocationOwnership()
        XCTAssertEqual(ownership.handle(down(contextual, .tapToggle)), .show)
        XCTAssertEqual(ownership.handle(down(contextual, .tapToggle)), .dismiss)
        XCTAssertNil(ownership.visibleRoute)

        XCTAssertEqual(ownership.handle(down(contextual, .tapToggle)), .show)
        XCTAssertEqual(ownership.handle(down(global, .tapToggle)), .replace)
        XCTAssertEqual(ownership.visibleRoute, .global)
        XCTAssertEqual(ownership.presentationMode, .tapToggle)
        XCTAssertNil(ownership.releaseOwner)
    }

    func testSameRouteHoldReleaseRearmsExactPhysicalSourceWithoutReplacingLayout() {
        let contextualMouse = TriggerSource(
            route: .contextual,
            physicalSource: .mouseButton(buttonNumber: 4)
        )
        var ownership = HUDInvocationOwnership()
        XCTAssertEqual(ownership.handle(down(contextual, .holdRelease)), .show)
        XCTAssertEqual(ownership.handle(up(contextual, .holdRelease)), .commitRelease)

        XCTAssertEqual(ownership.handle(down(contextualMouse, .holdRelease)), .ignore)
        XCTAssertEqual(ownership.releaseOwner, contextualMouse)
        XCTAssertEqual(ownership.handle(up(contextual, .holdRelease)), .ignore)
        XCTAssertEqual(ownership.handle(up(contextualMouse, .holdRelease)), .commitRelease)
    }

    func testSameRouteHoldReleaseDisarmsPrimaryClickCommitAfterTapToggleReplacement() {
        let contextualMouse = TriggerSource(
            route: .contextual,
            physicalSource: .mouseButton(buttonNumber: 4)
        )
        var ownership = HUDInvocationOwnership()
        XCTAssertEqual(ownership.handle(down(global, .holdRelease)), .show)
        XCTAssertEqual(ownership.handle(down(contextual, .tapToggle)), .replace)
        XCTAssertTrue(AppDelegate.ownsTapTogglePrimaryCommit(ownership))

        XCTAssertEqual(ownership.handle(down(contextualMouse, .holdRelease)), .ignore)

        XCTAssertFalse(AppDelegate.ownsTapTogglePrimaryCommit(ownership))
        XCTAssertEqual(ownership.releaseOwner, contextualMouse)
    }

    func testVisibleContentReplacementPreservesPanelFrameAndSwapsNativeCallbacks() throws {
        let previousWindows = Set(NSApp.windows.map(\.windowNumber))
        let controller = RingWindowController()
        var originalPrimaryCalls = 0
        var replacementPrimaryCalls = 0
        var replacementDragCalls = 0
        let visible = try XCTUnwrap(NSScreen.main?.visibleFrame)
        let anchor = CGPoint(x: visible.midX, y: visible.midY)
        controller.show(
            at: anchor,
            outerRadius: 180,
            content: Color.clear,
            onPrimaryMouseUp: { _, _ in originalPrimaryCalls += 1 }
        )
        defer { controller.hide() }
        let panel = try XCTUnwrap(NSApp.windows.first {
            !previousWindows.contains($0.windowNumber) && $0 is NSPanel
        })
        let originalFrame = panel.frame
        let originalHost = try XCTUnwrap(panel.contentView as? RingHostingView<AnyView>)
        originalHost.onPrimaryMouseUp?(.zero, .zero)
        XCTAssertEqual(originalPrimaryCalls, 1)

        controller.replaceContent(
            outerRadius: 180,
            content: Color.clear,
            onPrimaryMouseUp: { _, _ in replacementPrimaryCalls += 1 },
            onOtherMouseDragged: { _, _ in replacementDragCalls += 1 }
        )

        XCTAssertEqual(panel.frame, originalFrame)
        let replacementHost = try XCTUnwrap(panel.contentView as? RingHostingView<AnyView>)
        XCTAssertTrue(originalHost === replacementHost)
        replacementHost.onPrimaryMouseUp?(.zero, .zero)
        replacementHost.onOtherMouseDragged?(.zero, .zero)
        XCTAssertEqual(originalPrimaryCalls, 1)
        XCTAssertEqual(replacementPrimaryCalls, 1)
        XCTAssertEqual(replacementDragCalls, 1)
    }

    func testNativeInputSequencesCannotCrossAnInPlaceReplacement() {
        var ownership = HUDNativeInputOwnership()
        ownership.primaryDown()
        XCTAssertTrue(ownership.ownsAuxiliaryDrag(buttonNumber: 4))

        ownership.beginReplacement()

        XCTAssertFalse(ownership.consumePrimaryUp())
        XCTAssertFalse(ownership.ownsAuxiliaryDrag(buttonNumber: 4))

        ownership.primaryDown()
        ownership.auxiliaryDown(buttonNumber: 4)
        XCTAssertTrue(ownership.consumePrimaryUp())
        XCTAssertTrue(ownership.ownsAuxiliaryDrag(buttonNumber: 4))
        ownership.auxiliaryUp(buttonNumber: 4)
        XCTAssertFalse(ownership.ownsAuxiliaryDrag(buttonNumber: 4))

        ownership.auxiliaryDown(buttonNumber: 5)
        ownership.beginReplacement(adoptingAuxiliaryButton: 5)
        XCTAssertTrue(ownership.ownsAuxiliaryDrag(buttonNumber: 5))
        XCTAssertFalse(ownership.ownsAuxiliaryDrag(buttonNumber: 4))
    }

    private func resolved(
        route: HUDInvocationRoute = .contextual,
        layout: HUDActionLayout,
        pid: Int32
    ) -> ResolvedHUDProfile {
        ResolvedHUDProfile(
            route: route,
            profileReference: route == .global ? .global : .app(bundleIdentifier: "com.test.app"),
            actionLayout: layout,
            targetApplication: FrontmostAppSnapshot(
                processIdentifier: pid,
                bundleIdentifier: "com.test.app",
                localizedName: "Test"
            ),
            resolution: route == .global ? .globalRoute : .exactAppMatch
        )
    }

    private func item(_ label: String) -> RingMenuItem {
        RingMenuItem(label: label, icon: "circle", actionType: .custom, actionData: "")
    }

    private func down(
        _ source: TriggerSource,
        _ mode: TriggerMode
    ) -> TriggerEvent {
        .down(source: source, mode: mode, pointerLocation: .zero)
    }

    private func moved(
        _ source: TriggerSource,
        _ mode: TriggerMode
    ) -> TriggerEvent {
        .moved(source: source, mode: mode, pointerLocation: .zero)
    }

    private func up(
        _ source: TriggerSource,
        _ mode: TriggerMode
    ) -> TriggerEvent {
        .up(source: source, mode: mode, pointerLocation: .zero)
    }
}
