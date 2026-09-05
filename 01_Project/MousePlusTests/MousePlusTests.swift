import XCTest
import CoreGraphics
import AppKit
import SwiftUI
@testable import MousePlus

final class MousePlusTests: XCTestCase {
    func testTestTargetLoadsMousePlusModule() {
        XCTAssertTrue(true)
    }

    func testKeystrokePermissionFailurePostsNothing() async {
        let poster = RecordingEventPoster(hasAccess: false)
        let clock = RecordingKeystrokeClock()
        let service = KeystrokeService(poster: poster, clock: clock)

        do {
            try await service.send(keyCode: 12, flags: [.maskCommand])
            XCTFail("Expected permission failure")
        } catch {
            XCTAssertEqual(error as? KeystrokeError, .postEventAccessDenied)
        }

        XCTAssertEqual(poster.preflightCount, 1)
        XCTAssertTrue(poster.events.isEmpty)
        XCTAssertTrue(clock.durations.isEmpty)
    }

    func testKeystrokePostsDownThenUpWithExplicitFlagsAtHIDTap() async throws {
        let poster = RecordingEventPoster(hasAccess: true)
        let clock = RecordingKeystrokeClock()
        let service = KeystrokeService(poster: poster, clock: clock)
        let flags: CGEventFlags = [.maskControl, .maskAlternate, .maskCommand]

        try await service.send(keyCode: 12, flags: flags)

        XCTAssertEqual(clock.durations, [.milliseconds(50), .milliseconds(10)])
        XCTAssertEqual(poster.events, [
            .init(keyCode: 12, keyDown: true, flags: flags,
                  sourceStateID: .privateState, tap: .cghidEventTap),
            .init(keyCode: 12, keyDown: false, flags: flags,
                  sourceStateID: .privateState, tap: .cghidEventTap),
        ])
    }

    func testEmptyFlagsAreExplicitOnBothEvents() async throws {
        let poster = RecordingEventPoster(hasAccess: true)
        let service = KeystrokeService(poster: poster, clock: RecordingKeystrokeClock())

        try await service.send(keyCode: 0, flags: [])

        XCTAssertEqual(poster.events.map(\.flags), [[], []])
    }

    func testCancellationBeforeKeyDownPostsNothing() async {
        let poster = RecordingEventPoster(hasAccess: true)
        let service = KeystrokeService(
            poster: poster,
            clock: CancellingKeystrokeClock(cancelOnSleep: 1)
        )

        do {
            try await service.send(keyCode: 12, flags: [.maskCommand])
            XCTFail("Expected cancellation")
        } catch is CancellationError {
            // Expected.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertTrue(poster.events.isEmpty)
    }

    func testCancellationBetweenEventsPostsCleanupKeyUp() async {
        let poster = RecordingEventPoster(hasAccess: true)
        let service = KeystrokeService(
            poster: poster,
            clock: CancellingKeystrokeClock(cancelOnSleep: 2)
        )

        do {
            try await service.send(keyCode: 12, flags: [.maskCommand])
            XCTFail("Expected cancellation")
        } catch is CancellationError {
            // Expected.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertEqual(poster.events.map(\.keyDown), [true, false])
        XCTAssertEqual(poster.events.map(\.flags), [.maskCommand, .maskCommand])
    }
}

@MainActor
final class RingRuntimeInteractionTests: XCTestCase {
    func testRuntimeMountDoesNotArmPlaybackBeforeGuardedReplay() {
        let model = makeModel()
        model.isVisible = true
        model.appearance.motion = HUDMotionConfiguration(summon: .circularSweep)
        let mountedID = model.prepareOpeningPlayback()
        let view = RingMenuView(viewModel: model)
        let mountedRequest = view.openingMotionRequest(reduceMotion: false)

        XCTAssertTrue(mountedRequest.isAwaitingMount)
        XCTAssertEqual(HUDOpeningPlaybackSeed(request: mountedRequest).progress, 0)
        XCTAssertFalse(HUDOpeningPlaybackSeed(request: mountedRequest).isPlaybackPending)

        model.replayOpening(afterMounting: mountedID)
        let replay = view.openingMotionRequest(reduceMotion: false)
        XCTAssertFalse(replay.isAwaitingMount)
        XCTAssertEqual(HUDOpeningMotionTransition.resolve(previous: mountedRequest, current: replay), .replay)
        model.replayOpening(afterMounting: mountedID)
        XCTAssertEqual(view.openingMotionRequest(reduceMotion: false), replay)
    }

    func testOldMountCallbackCannotUnconcealAReopenedHUD() {
        let model = makeModel()
        model.isVisible = true
        let oldID = model.prepareOpeningPlayback()
        model.isVisible = false
        model.isVisible = true
        let newID = model.prepareOpeningPlayback()

        model.replayOpening(afterMounting: oldID)

        XCTAssertEqual(model.openingInvocationID, newID)
        XCTAssertTrue(model.openingIsAwaitingMount)
    }

    func testRuntimeOpeningReplayAdvancesOnlyForItsVisibleMountedInvocation() {
        let model = makeModel()
        model.isVisible = true

        let firstMountedID = model.prepareOpeningPlayback()
        XCTAssertEqual(model.openingInvocationID, firstMountedID)

        model.replayOpening(afterMounting: firstMountedID)
        XCTAssertEqual(model.openingInvocationID, firstMountedID + 1)

        // A duplicate/stale callback cannot replay the current HUD again.
        model.replayOpening(afterMounting: firstMountedID)
        XCTAssertEqual(model.openingInvocationID, firstMountedID + 1)

        let secondMountedID = model.prepareOpeningPlayback()
        model.isVisible = false
        model.replayOpening(afterMounting: secondMountedID)
        XCTAssertEqual(model.openingInvocationID, secondMountedID)
    }

    func testHoldReleaseFallsBackToTrackedSelectionWhenPanelCoordinatesAreUnavailable() {
        let model = makeModel()
        model.updateActive(at: point(model, .middle, 0), center: .zero)

        XCTAssertEqual(AppDelegate.commitHoldRelease(
            viewModel: model,
            pointerLocation: nil,
            resolveCoordinates: { _ in XCTFail("Unexpected coordinate conversion"); return nil }
        ), .expanded)
        XCTAssertEqual(model.expandedParentIndex, 0)
    }

    func testHoldReleaseTriggerCallbackReHitTestsReleaseAfterStaleRevealHover() {
        let model = makeModel(outerVisibility: .revealBeyondInnerRing)
        model.updateActive(at: .zero, center: .zero)
        model.updateActive(at: point(model, .middle, 0), center: .zero)
        XCTAssertEqual(model.activeSelection, ActiveSelection(band: .middle, index: 0))
        XCTAssertEqual(model.expandedParentIndex, 0)

        // Reproduce runtime ordering: Reveal's hover callback left the parent
        // active, then the independent trigger-up callback arrived with its own
        // final pointer snapshot over a direct wedge. No intervening SwiftUI
        // hover callback is assumed.
        let releasePoint = point(model, .middle, 1)
        let result = AppDelegate.commitHoldRelease(
            viewModel: model,
            pointerLocation: releasePoint,
            resolveCoordinates: { ($0, .zero) }
        )

        XCTAssertEqual(result, .executed)
        XCTAssertNil(model.expandedParentIndex)
        XCTAssertNil(model.activeSelection)
    }

    func testRuntimeHostForwardsOtherMouseDraggedToRevealBeforeTriggerRelease() throws {
        let model = makeModel(outerVisibility: .revealBeyondInnerRing)
        model.updateActive(at: .zero, center: .zero)

        let side = HUDPanelGeometry.squareSide(outerRadius: model.radii.r3)
        let host = RingHostingView(rootView: EmptyView())
        host.frame = CGRect(x: 0, y: 0, width: side, height: side)
        let window = NSWindow(contentRect: host.frame, styleMask: .borderless,
                              backing: .buffered, defer: false)
        window.contentView = host
        host.updateTrackingAreas()

        var forwardedPoint: CGPoint?
        var forwardedCenter: CGPoint?
        host.onOtherMouseDragged = { point, center in
            forwardedPoint = point
            forwardedCenter = center
            model.updateActive(at: point, center: center)
        }

        let center = CGPoint(x: side / 2, y: side / 2)
        let offset = point(model, .middle, 0)
        let localPoint = CGPoint(x: center.x + offset.x, y: center.y + offset.y)
        let windowPoint = CGPoint(x: localPoint.x, y: side - localPoint.y)
        let event = try XCTUnwrap(NSEvent.mouseEvent(
            with: .otherMouseDragged,
            location: windowPoint,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 1,
            clickCount: 0,
            pressure: 0
        ))

        host.otherMouseDragged(with: event)

        let actualPoint = try XCTUnwrap(forwardedPoint)
        XCTAssertEqual(actualPoint.x, localPoint.x, accuracy: 0.001)
        XCTAssertEqual(actualPoint.y, localPoint.y, accuracy: 0.001)
        XCTAssertEqual(forwardedCenter, center)
        XCTAssertEqual(model.activeSelection, ActiveSelection(band: .middle, index: 0))
        XCTAssertEqual(model.expandedParentIndex, 0)
        XCTAssertTrue(model.isOuterRingVisible)
        XCTAssertTrue(host.trackingAreas.contains {
            $0.options.contains([.activeAlways, .enabledDuringMouseDrag])
        })
    }

    func testRuntimeHostForwardsPrimaryMouseUpForTapToggleCommit() throws {
        let model = makeModel(motion: maximumMotion)
        let side = HUDPanelGeometry.squareSide(outerRadius: model.radii.r3)
        let host = RingHostingView(rootView: RingMenuView(
            viewModel: model, commitsOnPointerRelease: false
        ))
        host.frame = CGRect(x: 0, y: 0, width: side, height: side)
        let window = NSWindow(contentRect: host.frame, styleMask: .borderless,
                              backing: .buffered, defer: false)
        window.contentView = host

        var forwardedPoint: CGPoint?
        var forwardedCenter: CGPoint?
        host.onPrimaryMouseUp = { point, center in
            forwardedPoint = point
            forwardedCenter = center
        }

        let localPoint = CGPoint(x: 32, y: 47)
        let windowPoint = CGPoint(x: localPoint.x, y: side - localPoint.y)
        let event = try XCTUnwrap(NSEvent.mouseEvent(
            with: .leftMouseUp,
            location: windowPoint,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 1,
            clickCount: 1,
            pressure: 0
        ))

        host.mouseUp(with: event)

        let actualPoint = try XCTUnwrap(forwardedPoint)
        XCTAssertEqual(actualPoint.x, localPoint.x, accuracy: 0.001)
        XCTAssertEqual(actualPoint.y, localPoint.y, accuracy: 0.001)
        XCTAssertEqual(forwardedCenter, CGPoint(x: side / 2, y: side / 2))
    }

    func testTapToggleReHitTestsFinalLocationBeforeCommit() {
        let model = makeModel(motion: maximumMotion)
        model.isVisible = true
        var closes = 0
        model.requestClose = {
            XCTAssertNil(model.activeSelection)
            XCTAssertNil(model.expandedParentIndex)
            XCTAssertTrue(model.outerItems.isEmpty)
            model.isVisible = false
            closes += 1
        }
        defer { model.requestClose = nil }
        model.updateActive(at: point(model, .inner, 0), center: .zero)

        // Both final-position paths run in the same synchronous turn as opening,
        // without yielding. Rendering the summon fade is a separate live check.
        XCTAssertEqual(model.commit(at: .zero, center: .zero), .noSelection)
        XCTAssertNil(model.activeSelection)
        XCTAssertEqual(closes, 0)

        XCTAssertEqual(model.commit(at: point(model, .inner, 1), center: .zero), .executed)
        XCTAssertEqual(closes, 1)
        XCTAssertFalse(model.isVisible)
    }

    func testTapToggleRevealAutoExpandsOnNaturalParentHoverBeforeClick() {
        let model = makeModel(outerVisibility: .revealBeyondInnerRing)
        model.updateActive(at: .zero, center: .zero)
        model.updateActive(at: point(model, .middle, 0), center: .zero)

        XCTAssertEqual(model.expandedParentIndex, 0)
        XCTAssertTrue(model.isOuterRingVisible)
        XCTAssertEqual(model.commit(at: point(model, .middle, 0), center: .zero), .expanded)
        XCTAssertTrue(model.hasRevealedOuterRing)
        XCTAssertTrue(model.isOuterRingVisible)
    }

    func testHoldReleaseRevealAutoExpandsBeforeTriggerReleaseAndCommitKeepsHUDOpen() {
        let model = makeModel(outerVisibility: .revealBeyondInnerRing)
        model.updateActive(at: .zero, center: .zero)
        model.updateActive(at: point(model, .middle, 0), center: .zero)

        XCTAssertEqual(model.expandedParentIndex, 0)
        XCTAssertTrue(model.isOuterRingVisible)
        XCTAssertEqual(model.commitActive(), .expanded)
        XCTAssertTrue(model.hasRevealedOuterRing)
        XCTAssertTrue(model.isOuterRingVisible)
        XCTAssertTrue(AppDelegate.keepsRingOpen(after: .expanded))
        XCTAssertFalse(AppDelegate.keepsRingOpen(after: .executed))
        XCTAssertFalse(AppDelegate.keepsRingOpen(after: .noSelection))
        XCTAssertFalse(AppDelegate.keepsRingOpen(after: .unavailable))
    }

    func testRevealBranchReplacementIsImmediatelySelectableWithMaximumMotion() {
        let model = makeModel(outerVisibility: .revealBeyondInnerRing,
                              motion: maximumMotion)
        model.middleItems[1].subItems = [item("Other outer")]
        var closes = 0
        model.requestClose = { closes += 1 }
        model.updateActive(at: .zero, center: .zero)

        model.updateActive(at: point(model, .middle, 0), center: .zero)
        XCTAssertEqual(model.expandedParentIndex, 0)
        model.updateActive(at: point(model, .middle, 1), center: .zero)

        XCTAssertEqual(model.expandedParentIndex, 1)
        XCTAssertEqual(model.outerItems.map(\.label), ["Other outer"])
        XCTAssertEqual(closes, 0)

        // The replacement is selectable immediately, even while a view could
        // still be crossfading the previous branch's rendered content.
        model.updateActive(at: point(model, .outer, 0), center: .zero)
        XCTAssertEqual(model.activeSelection, ActiveSelection(band: .outer, index: 0))
        XCTAssertEqual(model.activeSelection.flatMap(model.item(for:))?.id,
                       model.middleItems[1].subItems?.first?.id)
        XCTAssertEqual(model.commitActive(), .executed)
        XCTAssertEqual(closes, 1)
        XCTAssertTrue(model.outerItems.isEmpty)
    }

    func testAlwaysStillRequiresCommitAndHiddenStillSuppressesHoverExpansion() {
        let always = makeModel(outerVisibility: .alwaysVisible)
        always.updateActive(at: .zero, center: .zero)
        always.updateActive(at: point(always, .middle, 0), center: .zero)
        XCTAssertNil(always.expandedParentIndex)
        XCTAssertEqual(always.commitActive(), .expanded)

        let hidden = makeModel(outerVisibility: .alwaysHidden)
        hidden.updateActive(at: .zero, center: .zero)
        hidden.updateActive(at: point(hidden, .middle, 0), center: .zero)
        XCTAssertNil(hidden.expandedParentIndex)
        XCTAssertFalse(hidden.isOuterRingVisible)
    }

    func testInvisibleFixedPositionIsInertInBothCommitPaths() {
        let model = makeModel(innerSlots: 4)
        let empty = point(model, .inner, 3)

        model.updateActive(at: empty, center: .zero)
        XCTAssertNil(model.activeSelection)
        XCTAssertEqual(model.commitActive(), .noSelection)
        XCTAssertEqual(model.commit(at: empty, center: .zero), .noSelection)
    }

    func testRotatedAsymmetricParentAndOuterItemHitAndCommit() {
        let model = makeModel(innerSlots: 4, middleSlots: 5,
                              middleOffsetDegrees: 63)
        var closes = 0
        model.requestClose = { closes += 1 }

        XCTAssertEqual(model.commit(at: point(model, .middle, 0), center: .zero), .expanded)
        XCTAssertTrue(model.isOuterRingVisible)
        XCTAssertEqual(model.commit(at: point(model, .outer, 1), center: .zero), .executed)
        XCTAssertEqual(closes, 1)
        XCTAssertNil(model.expandedParentIndex)
    }

    func testHiddenParentIsUnavailableClearsSelectionAndNeverCloses() {
        let model = makeModel(hiddenOuter: true)
        var closes = 0
        model.requestClose = { closes += 1 }

        XCTAssertEqual(model.commit(at: point(model, .middle, 0), center: .zero), .unavailable)
        XCTAssertEqual(model.hiddenSubmenuUnavailableReason, "Submenu hidden by HUD setting")
        XCTAssertNil(model.activeSelection)
        XCTAssertNil(model.expandedParentIndex)
        XCTAssertEqual(closes, 0)
    }

    func testCenterActivationClosesResetsAndRoutesSettings() {
        let model = makeModel()
        var closes = 0
        var settings = 0
        model.requestClose = { closes += 1 }
        model.requestOpenMenuItemsSettings = { settings += 1 }
        _ = model.commit(at: point(model, .middle, 0), center: .zero)

        model.activateCenterSettings()

        XCTAssertEqual(closes, 1)
        XCTAssertEqual(settings, 1)
        XCTAssertNil(model.activeSelection)
        XCTAssertNil(model.expandedParentIndex)
    }

    func testEscapeCollapsesThenRequestsCloseAndCloseResetsInvocation() {
        let model = makeModel(motion: maximumMotion)
        _ = model.commit(at: point(model, .middle, 0), center: .zero)

        XCTAssertFalse(model.handleEscape())
        XCTAssertNil(model.expandedParentIndex)
        XCTAssertTrue(model.handleEscape())

        model.isVisible = true
        model.activeSelection = ActiveSelection(band: .inner, index: 0)
        model.isVisible = false
        XCTAssertNil(model.activeSelection)
        XCTAssertNil(model.expandedParentIndex)
        XCTAssertFalse(model.hasRevealedOuterRing)
    }

    private var maximumMotion: HUDMotionConfiguration {
        HUDMotionConfiguration(isEnabled: true,
                               baseDuration: HUDMotionPolicy.maximumDuration,
                               summon: .fade, hover: .emphasis,
                               outerExpansion: .radialReveal,
                               branchChange: .crossfade)
    }

    private func makeModel(
        innerSlots: Int = 2,
        middleSlots: Int = 2,
        middleOffsetDegrees: Double = 0,
        hiddenOuter: Bool = false,
        outerVisibility: OuterRingVisibility? = nil,
        motion: HUDMotionConfiguration = .default
    ) -> RingViewModel {
        var customization = HUDCustomization.default
        customization.inner.layout = HUDRingLayout(
            slotCountMode: .fixed, fixedSlotCount: innerSlots, angularOffset: 17
        )
        customization.middle.layout = HUDRingLayout(
            slotCountMode: .fixed, fixedSlotCount: middleSlots,
            angularOffset: middleOffsetDegrees
        )
        customization.outerRingVisibility = outerVisibility
            ?? (hiddenOuter ? .alwaysHidden : .alwaysVisible)
        var parent = item("Parent")
        parent.subItems = [item("Outer 0"), item("Outer 1")]
        let configuration = Configuration(
            inner: [item("Inner 0"), item("Inner 1")],
            middle: [parent, item("Direct")],
            appearance: AppearanceConfig(deadZone: 10, innerEdge: 20,
                                         middleEdge: 30, outerEdge: 40,
                                         motion: motion),
            hudCustomization: customization
        )
        let model = RingViewModel()
        model.load(from: configuration)
        return model
    }

    private func item(_ label: String) -> RingMenuItem {
        RingMenuItem(label: label, icon: "circle", actionType: .custom,
                     actionData: "true")
    }

    private func point(_ model: RingViewModel, _ band: Band, _ index: Int) -> CGPoint {
        RadialGeometry.centroid(
            band: band, index: index, center: .zero, radii: model.radii,
            geometry: model.geometry,
            expandedParentIndex: model.expandedParentIndex,
            outerCount: model.outerItems.count
        )
    }
}

private final class RecordingEventPoster: CGEventPosting, @unchecked Sendable {
    struct Event: Equatable {
        let keyCode: UInt16
        let keyDown: Bool
        let flags: CGEventFlags
        let sourceStateID: CGEventSourceStateID
        let tap: CGEventTapLocation
    }

    let hasAccess: Bool
    private(set) var preflightCount = 0
    private(set) var events: [Event] = []

    init(hasAccess: Bool) {
        self.hasAccess = hasAccess
    }

    func preflightPostEventAccess() -> Bool {
        preflightCount += 1
        return hasAccess
    }

    func postKeyboardEvent(
        keyCode: UInt16,
        keyDown: Bool,
        flags: CGEventFlags,
        sourceStateID: CGEventSourceStateID,
        tap: CGEventTapLocation
    ) throws {
        events.append(.init(
            keyCode: keyCode,
            keyDown: keyDown,
            flags: flags,
            sourceStateID: sourceStateID,
            tap: tap
        ))
    }
}

private final class RecordingKeystrokeClock: KeystrokeClock, @unchecked Sendable {
    private(set) var durations: [Duration] = []

    func sleep(for duration: Duration) async throws {
        durations.append(duration)
    }
}

private final class CancellingKeystrokeClock: KeystrokeClock, @unchecked Sendable {
    private let cancelOnSleep: Int
    private var sleepCount = 0

    init(cancelOnSleep: Int) {
        self.cancelOnSleep = cancelOnSleep
    }

    func sleep(for duration: Duration) async throws {
        sleepCount += 1
        if sleepCount == cancelOnSleep {
            throw CancellationError()
        }
    }
}
