import XCTest
import CoreGraphics
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
    func testHoldReleaseUsesTrackedSelectionWithoutSecondPointerCommit() {
        let model = makeModel()
        model.updateActive(at: point(model, .middle, 0), center: .zero)

        XCTAssertEqual(model.commitActive(), .expanded)
        XCTAssertEqual(model.expandedParentIndex, 0)
    }

    func testTapToggleReHitTestsFinalLocationBeforeCommit() {
        let model = makeModel()
        var closes = 0
        model.requestClose = { closes += 1 }
        model.activeSelection = ActiveSelection(band: .inner, index: 0)

        XCTAssertEqual(model.commit(at: .zero, center: .zero), .noSelection)
        XCTAssertEqual(closes, 0)

        XCTAssertEqual(model.commit(at: point(model, .inner, 1), center: .zero), .executed)
        XCTAssertEqual(closes, 1)
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
        let model = makeModel()
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

    private func makeModel(innerSlots: Int = 2,
                           middleSlots: Int = 2,
                           middleOffsetDegrees: Double = 0,
                           hiddenOuter: Bool = false) -> RingViewModel {
        var customization = HUDCustomization.default
        customization.inner.layout = HUDRingLayout(
            slotCountMode: .fixed, fixedSlotCount: innerSlots, angularOffset: 17
        )
        customization.middle.layout = HUDRingLayout(
            slotCountMode: .fixed, fixedSlotCount: middleSlots,
            angularOffset: middleOffsetDegrees
        )
        customization.outerRingVisibility = hiddenOuter ? .alwaysHidden : .alwaysVisible
        var parent = item("Parent")
        parent.subItems = [item("Outer 0"), item("Outer 1")]
        let configuration = Configuration(
            inner: [item("Inner 0"), item("Inner 1")],
            middle: [parent, item("Direct")],
            appearance: AppearanceConfig(deadZone: 10, innerEdge: 20,
                                         middleEdge: 30, outerEdge: 40),
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
