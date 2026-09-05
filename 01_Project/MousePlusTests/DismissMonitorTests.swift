import AppKit
import XCTest
@testable import MousePlus

@MainActor
final class DismissMonitorTests: XCTestCase {
    func testCircularBoundaryIsInclusiveAndTransparentCornersAreOutside() {
        let center = CGPoint(x: 50, y: 50)

        XCTAssertFalse(HUDDismissalGeometry.isOutsideHUD(
            point: center, center: center, outerRadius: 40
        ))
        XCTAssertFalse(HUDDismissalGeometry.isOutsideHUD(
            point: CGPoint(x: 90, y: 50), center: center, outerRadius: 40
        ), "A point exactly on r3 remains inside")
        XCTAssertTrue(HUDDismissalGeometry.isOutsideHUD(
            point: CGPoint(x: 90.001, y: 50), center: center, outerRadius: 40
        ))
        XCTAssertTrue(HUDDismissalGeometry.isOutsideHUD(
            point: CGPoint(x: 10, y: 10), center: center, outerRadius: 40
        ), "A square panel corner lies beyond the circular HUD")
    }

    func testLocalMouseDispositionDismissesSiblingWindowWithoutEatingItsClick() {
        XCTAssertEqual(
            HUDLocalMouseDownDisposition.resolve(
                eventBelongsToPanel: false,
                isOutsideHUD: false
            ),
            .dismissPreservingEvent
        )
        XCTAssertEqual(
            HUDLocalMouseDownDisposition.resolve(
                eventBelongsToPanel: true,
                isOutsideHUD: true
            ),
            .dismissConsumingEvent
        )
        XCTAssertEqual(
            HUDLocalMouseDownDisposition.resolve(
                eventBelongsToPanel: true,
                isOutsideHUD: false
            ),
            .ignore
        )
    }

    func testTapToggleMouseTriggerIsOwnedOnlyByTriggerPath() {
        let tapToggle = TriggerBinding.mouseButton(buttonNumber: 4, mode: .tapToggle)
        let holdRelease = TriggerBinding.mouseButton(buttonNumber: 4, mode: .holdRelease)

        XCTAssertTrue(AppDelegate.isTapToggleMouseTrigger(
            eventType: .otherMouseDown,
            buttonNumber: 4,
            binding: tapToggle
        ))
        XCTAssertFalse(AppDelegate.isTapToggleMouseTrigger(
            eventType: .otherMouseDown,
            buttonNumber: 5,
            binding: tapToggle
        ))
        XCTAssertFalse(AppDelegate.isTapToggleMouseTrigger(
            eventType: .otherMouseDown,
            buttonNumber: 4,
            binding: holdRelease
        ))
        XCTAssertFalse(AppDelegate.isTapToggleMouseTrigger(
            eventType: .leftMouseDown,
            buttonNumber: 4,
            binding: tapToggle
        ))
    }

    func testStartIsIdempotentAndStopRemovesEveryMonitor() {
        let provider = RecordingEventMonitorProvider()
        let monitor = DismissMonitor(provider: provider)

        monitor.start(onEscape: {}, onClickOutside: {}, onLocalMouseDown: { _ in false })
        monitor.start(onEscape: {}, onClickOutside: {}, onLocalMouseDown: { _ in false })

        XCTAssertTrue(monitor.isRunning)
        XCTAssertEqual(provider.globalHandlers.count, 2)
        XCTAssertEqual(provider.localHandlers.count, 2)

        monitor.stop()

        XCTAssertFalse(monitor.isRunning)
        XCTAssertEqual(provider.removedTokens.count, 4)

        monitor.stop()
        XCTAssertEqual(provider.removedTokens.count, 4, "Repeated teardown is harmless")
    }

    func testDeinitAlsoRemovesEveryInstalledMonitor() {
        let provider = RecordingEventMonitorProvider()
        var monitor: DismissMonitor? = DismissMonitor(provider: provider)
        monitor?.start(onEscape: {}, onClickOutside: {}, onLocalMouseDown: { _ in false })

        monitor = nil

        XCTAssertEqual(provider.removedTokens.count, 4)
    }

    func testLocalMouseHandlerPreservesInsideInteractionsAndConsumesDismissal() throws {
        let provider = RecordingEventMonitorProvider()
        let monitor = DismissMonitor(provider: provider)
        let event = try XCTUnwrap(NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1
        ))
        var shouldDismiss = false

        monitor.start(
            onEscape: {},
            onClickOutside: {},
            onLocalMouseDown: { _ in shouldDismiss }
        )
        let mouseHandler = try XCTUnwrap(provider.localHandler(for: .leftMouseDown))

        XCTAssertIdentical(mouseHandler(event), event)
        shouldDismiss = true
        XCTAssertNil(mouseHandler(event))
    }

    func testGlobalMouseHandlerRemainsArmedForOtherApplications() throws {
        let provider = RecordingEventMonitorProvider()
        let monitor = DismissMonitor(provider: provider)
        var dismissCount = 0
        monitor.start(
            onEscape: {},
            onClickOutside: { dismissCount += 1 },
            onLocalMouseDown: { _ in false }
        )

        let handler = try XCTUnwrap(provider.globalHandler(for: .leftMouseDown))
        let event = try XCTUnwrap(NSEvent.mouseEvent(
            with: .leftMouseDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1
        ))
        handler(event)

        XCTAssertEqual(dismissCount, 1)
    }
}

private final class RecordingEventMonitorProvider: EventMonitorProviding {
    struct GlobalRegistration {
        let mask: NSEvent.EventTypeMask
        let handler: (NSEvent) -> Void
    }

    struct LocalRegistration {
        let mask: NSEvent.EventTypeMask
        let handler: (NSEvent) -> NSEvent?
    }

    private final class Token {}

    var globalHandlers: [GlobalRegistration] = []
    var localHandlers: [LocalRegistration] = []
    var removedTokens: [Any] = []

    func addGlobalMonitor(matching mask: NSEvent.EventTypeMask,
                          handler: @escaping (NSEvent) -> Void) -> Any? {
        globalHandlers.append(GlobalRegistration(mask: mask, handler: handler))
        return Token()
    }

    func addLocalMonitor(matching mask: NSEvent.EventTypeMask,
                         handler: @escaping (NSEvent) -> NSEvent?) -> Any? {
        localHandlers.append(LocalRegistration(mask: mask, handler: handler))
        return Token()
    }

    func removeMonitor(_ monitor: Any) {
        removedTokens.append(monitor)
    }

    func globalHandler(for eventType: NSEvent.EventType) -> ((NSEvent) -> Void)? {
        globalHandlers.first { $0.mask.contains(mask(for: eventType)) }?.handler
    }

    func localHandler(for eventType: NSEvent.EventType) -> ((NSEvent) -> NSEvent?)? {
        localHandlers.first { $0.mask.contains(mask(for: eventType)) }?.handler
    }

    private func mask(for eventType: NSEvent.EventType) -> NSEvent.EventTypeMask {
        NSEvent.EventTypeMask(rawValue: 1 << UInt64(eventType.rawValue))
    }
}
