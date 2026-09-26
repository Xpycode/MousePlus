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

    func testCommittedActionsUseFrozenInvocationPIDAndReplacementOwnerPID() async {
        let executor = RecordingActionExecutor()
        let model = RingViewModel(actionService: executor)
        let first = resolved(
            layout: HUDActionLayout(inner: [item("Finder Action")], middle: []),
            pid: 11
        )
        let replacement = resolved(
            route: .global,
            layout: HUDActionLayout(inner: [item("Global Action")], middle: []),
            pid: 22
        )
        let configuration = Configuration()

        model.load(resolved: first, presentation: configuration)
        model.activeSelection = ActiveSelection(band: .inner, index: 0)
        XCTAssertEqual(model.commitActive(), .executed)
        let firstCompleted = await waitForExecutionCount(1, recorder: executor)
        XCTAssertTrue(firstCompleted)

        model.load(resolved: replacement, presentation: configuration)
        model.activeSelection = ActiveSelection(band: .inner, index: 0)
        XCTAssertEqual(model.commitActive(), .executed)
        let replacementCompleted = await waitForExecutionCount(2, recorder: executor)
        XCTAssertTrue(replacementCompleted)

        let contexts = await executor.contexts
        XCTAssertEqual(contexts.map(\.frontmostPID), [11, 22])
    }

    func testSuspendedAppSwitcherResultCannotCrossProfileReplacement() async {
        let appSwitcher = SuspendedAppSwitcher()
        let model = RingViewModel(appSwitcherService: appSwitcher)
        var apps = item("Apps")
        apps.dynamicSource = .runningApps
        var configuration = Configuration()
        configuration.hudCustomization.outerRingVisibility = .alwaysVisible
        let contextualApps = resolved(
            layout: HUDActionLayout(inner: [], middle: [apps]), pid: 11
        )
        let globalStatic = resolved(
            route: .global,
            layout: HUDActionLayout(inner: [item("Global")], middle: []), pid: 22
        )
        let entry = AppEntry(
            id: "com.example.App",
            name: "Example",
            icon: NSImage(size: NSSize(width: 16, height: 16)),
            processIdentifier: 33
        )

        model.load(resolved: contextualApps, presentation: configuration)
        model.expand(0)
        let firstRequestStarted = await waitForSwitcherRequest(appSwitcher)
        XCTAssertTrue(firstRequestStarted)
        model.load(resolved: globalStatic, presentation: configuration)
        let firstResumed = await appSwitcher.resumeNext(with: [entry])
        XCTAssertTrue(firstResumed)
        let firstFinished = await waitForSwitcherCompletion(1, switcher: appSwitcher)
        XCTAssertTrue(firstFinished)

        XCTAssertNil(model.expandedParentIndex)
        XCTAssertTrue(model.outerItems.isEmpty)
        XCTAssertTrue(model.dynamicIcons.isEmpty)

        model.load(resolved: contextualApps, presentation: configuration)
        model.expand(0)
        let secondRequestStarted = await waitForSwitcherRequest(appSwitcher)
        XCTAssertTrue(secondRequestStarted)
        let secondResumed = await appSwitcher.resumeNext(with: [entry])
        XCTAssertTrue(secondResumed)
        let secondFinished = await waitForSwitcherCompletion(2, switcher: appSwitcher)
        XCTAssertTrue(secondFinished)
        let itemsApplied = await waitForOuterItems(1, model: model)
        XCTAssertTrue(itemsApplied)

        XCTAssertEqual(model.expandedParentIndex, 0)
        XCTAssertEqual(model.outerItems.map(\.label), ["Example"])
        XCTAssertEqual(model.dynamicIcons.count, 1)
        XCTAssertEqual(model.outerRingLayout, .fullCircle)
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

    func testProductionReplacementUpdatesCenterContextWithoutMovingItsHitTarget() async throws {
        let previousWindows = Set(NSApp.windows.map(\.windowNumber))
        let controller = RingWindowController()
        let model = RingViewModel()
        model.load(
            resolved: resolved(layout: HUDActionLayout(inner: [], middle: []), pid: 11),
            presentation: Configuration()
        )
        var iconRequests: [String] = []
        var openingFrames: [HUDOpeningMotionFrame] = []
        var replacementFrames: [HUDOpeningMotionFrame] = []
        var closeCount = 0
        var settingsCount = 0
        model.requestClose = { closeCount += 1 }
        model.requestOpenMenuItemsSettings = { settingsCount += 1 }
        let iconProvider: @MainActor (String) -> NSImage? = { bundleIdentifier in
            iconRequests.append(bundleIdentifier)
            return NSImage(size: NSSize(width: 16, height: 16))
        }
        let visible = try XCTUnwrap(NSScreen.main?.visibleFrame)
        controller.show(
            at: CGPoint(x: visible.midX, y: visible.midY),
            outerRadius: model.radii.r3,
            content: RingMenuView(
                viewModel: model,
                interactionEnabled: true,
                openingPlaybackEnabled: false,
                onOpeningFrame: { openingFrames.append($0) },
                onCenterDrag: { controller.movePanel(by: $0) },
                centerApplicationIcon: iconProvider
            ),
            onPrimaryMouseUp: nil,
            onOtherMouseDragged: nil
        )
        defer { controller.hide() }
        let panel = try XCTUnwrap(NSApp.windows.first {
            !previousWindows.contains($0.windowNumber) && $0 is NSPanel
        })
        try await Task.sleep(for: .milliseconds(50))
        panel.contentView?.layoutSubtreeIfNeeded()
        let originalPanelFrame = panel.frame
        let originalButton = try XCTUnwrap(centerButton(in: try XCTUnwrap(panel.contentView)))
        let originalCenterFrame = originalButton.accessibilityFrame()

        XCTAssertEqual(originalCenterFrame.size, NSSize(width: 40, height: 40))
        XCTAssertEqual(originalButton.accessibilityLabel(),
                       "Open MousePlus Settings — Test HUD active")
        XCTAssertEqual(iconRequests, ["com.test.app"])
        XCTAssertTrue(openingFrames.allSatisfy {
            $0.artworkScale == 1 && $0.mask == .none
        })

        let openingInvocationID = model.openingInvocationID
        model.load(
            resolved: resolved(
                route: .global,
                layout: HUDActionLayout(inner: [], middle: []),
                pid: 22
            ),
            presentation: Configuration()
        )
        controller.replaceContent(
            outerRadius: model.radii.r3,
            content: RingMenuView(
                viewModel: model,
                interactionEnabled: true,
                openingPlaybackEnabled: false,
                onOpeningFrame: { replacementFrames.append($0) },
                onCenterDrag: { controller.movePanel(by: $0) },
                centerApplicationIcon: iconProvider
            ),
            onPrimaryMouseUp: nil,
            onOtherMouseDragged: nil
        )
        try await Task.sleep(for: .milliseconds(50))
        panel.contentView?.layoutSubtreeIfNeeded()

        let replacementButton = try XCTUnwrap(centerButton(in: try XCTUnwrap(panel.contentView)))
        XCTAssertEqual(panel.frame, originalPanelFrame)
        XCTAssertEqual(replacementButton.accessibilityFrame(), originalCenterFrame)
        XCTAssertEqual(replacementButton.accessibilityLabel(),
                       "Open MousePlus Settings — Global HUD active")
        XCTAssertEqual(iconRequests, ["com.test.app"])
        XCTAssertEqual(model.openingInvocationID, openingInvocationID)
        XCTAssertFalse(replacementFrames.isEmpty)
        XCTAssertTrue(replacementFrames.allSatisfy {
            $0.artworkScale == 1 && $0.mask == .none
        })
        XCTAssertEqual(centerButtonCount(in: try XCTUnwrap(panel.contentView)), 1)
        let trackingButton = try XCTUnwrap(replacementButton as? HUDCenterTrackingButton)
        let frameBeforeDrag = panel.frame
        trackingButton.onDrag(CGSize(width: 6, height: 4))
        XCTAssertNotEqual(panel.frame.origin, frameBeforeDrag.origin)
        XCTAssertEqual(settingsCount, 0, "dragging the replacement center must not activate Settings")
        _ = replacementButton.accessibilityPerformPress()
        XCTAssertEqual(closeCount, 1)
        XCTAssertEqual(settingsCount, 1)
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

    func testCancellationDismissesOnlyTheHeldInvocationOwner() {
        let contextual = TriggerSource(
            route: .contextual,
            physicalSource: .keyboard(keyCode: 1, modifiers: 2)
        )
        let global = TriggerSource(
            route: .global,
            physicalSource: .keyboard(keyCode: 3, modifiers: 4)
        )
        var ownership = HUDInvocationOwnership()
        XCTAssertEqual(ownership.handle(down(contextual, .holdRelease)), .show)

        XCTAssertEqual(ownership.handle(.cancel(source: global)), .ignore)
        XCTAssertEqual(ownership.handle(.cancel(source: contextual)), .dismiss)
        XCTAssertNil(ownership.visibleRoute)
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

    private func centerButton(in view: NSView) -> NSButton? {
        if let button = view as? NSButton,
           button.accessibilityIdentifier() == HUDCenterSettingsControl.accessibilityIdentifier {
            return button
        }
        return view.subviews.lazy.compactMap { self.centerButton(in: $0) }.first
    }

    private func centerButtonCount(in view: NSView) -> Int {
        let ownCount = (view as? NSButton)?.accessibilityIdentifier()
            == HUDCenterSettingsControl.accessibilityIdentifier ? 1 : 0
        return ownCount + view.subviews.reduce(0) { $0 + centerButtonCount(in: $1) }
    }

    private func waitForExecutionCount(_ count: Int, recorder: RecordingActionExecutor) async -> Bool {
        for _ in 0..<100 {
            if await recorder.contexts.count >= count { return true }
            await Task.yield()
        }
        return false
    }

    private func waitForSwitcherRequest(_ switcher: SuspendedAppSwitcher) async -> Bool {
        for _ in 0..<100 {
            if await switcher.hasPendingRequest { return true }
            await Task.yield()
        }
        return false
    }

    private func waitForSwitcherCompletion(
        _ count: Int,
        switcher: SuspendedAppSwitcher
    ) async -> Bool {
        for _ in 0..<100 {
            if await switcher.completedResponseCount >= count { return true }
            await Task.yield()
        }
        return false
    }

    private func waitForOuterItems(_ count: Int, model: RingViewModel) async -> Bool {
        for _ in 0..<100 {
            if model.outerItems.count == count { return true }
            await Task.yield()
        }
        return false
    }
}

private actor RecordingActionExecutor: ActionExecuting {
    private(set) var contexts: [ActionContext] = []

    func execute(_ item: RingMenuItem, context: ActionContext) async -> ActionExecutionResult {
        contexts.append(context)
        return .completed
    }
}

private actor SuspendedAppSwitcher: AppSwitcherProviding {
    private var continuations: [CheckedContinuation<[AppEntry], Never>] = []
    private(set) var completedResponseCount = 0

    var hasPendingRequest: Bool { !continuations.isEmpty }

    func runningApps(excluding processIdentifier: pid_t?) async -> [AppEntry] {
        let entries = await withCheckedContinuation { continuation in
            continuations.append(continuation)
        }
        completedResponseCount += 1
        return entries
    }

    func resumeNext(with entries: [AppEntry]) -> Bool {
        guard !continuations.isEmpty else { return false }
        continuations.removeFirst().resume(returning: entries)
        return true
    }
}
