import XCTest
import SwiftUI
@testable import MousePlus

@MainActor
final class HUDCenterSettingsTests: XCTestCase {
    func testActivationResetsBeforeRequestingCloseAndSettings() {
        let viewModel = RingViewModel()
        viewModel.activeSelection = ActiveSelection(band: .inner, index: 0)
        viewModel.expandedParentIndex = 0
        viewModel.outerItems = [RingMenuItem.sampleItems[0]]
        var events: [String] = []
        viewModel.requestClose = {
            XCTAssertNil(viewModel.activeSelection)
            XCTAssertNil(viewModel.expandedParentIndex)
            XCTAssertTrue(viewModel.outerItems.isEmpty)
            events.append("close")
        }
        viewModel.requestOpenMenuItemsSettings = {
            XCTAssertNil(viewModel.activeSelection)
            events.append("settings")
        }

        viewModel.activateCenterSettings()

        XCTAssertEqual(events, ["close", "settings"])
    }

    func testReleaseAfterCenterActivationCannotCommitPreviouslyActiveItem() {
        let viewModel = RingViewModel()
        viewModel.activeSelection = ActiveSelection(band: .inner, index: 0)
        var closeCount = 0
        var settingsCount = 0
        viewModel.requestClose = { closeCount += 1 }
        viewModel.requestOpenMenuItemsSettings = { settingsCount += 1 }

        viewModel.activateCenterSettings()
        viewModel.commitActive() // subsequent hold-release delivery

        XCTAssertEqual(closeCount, 1)
        XCTAssertEqual(settingsCount, 1)
        XCTAssertNil(viewModel.activeSelection)
    }

    func testTapToggleActivationUsesOnlyCenterCallbacks() {
        let viewModel = RingViewModel()
        viewModel.activeSelection = ActiveSelection(band: .middle, index: 0)
        var events: [String] = []
        viewModel.requestClose = { events.append("close") }
        viewModel.requestOpenMenuItemsSettings = { events.append("settings") }

        viewModel.activateCenterSettings()

        XCTAssertEqual(events, ["close", "settings"])
        XCTAssertNil(viewModel.activeSelection)
    }

    func testControlHasStableAccessibilityMetadata() {
        XCTAssertEqual(HUDCenterSettingsControl.accessibilityIdentifier, "hud.center.settings")
        XCTAssertEqual(HUDCenterSettingsControl.accessibilityLabel, "Open MousePlus Settings")
    }

    func testResolvedPresentationNamesAppAndGlobalContextsAccurately() {
        let finder = HUDCenterContextPresentation(resolved: resolvedProfile(
            route: .contextual,
            reference: .app(bundleIdentifier: "com.apple.finder"),
            name: "Finder"
        ))
        let fallback = HUDCenterContextPresentation(resolved: resolvedProfile(
            route: .contextual,
            reference: .global,
            name: "TextEdit"
        ))

        XCTAssertEqual(finder.name, "Finder")
        XCTAssertEqual(finder.bundleIdentifier, "com.apple.finder")
        XCTAssertEqual(finder.accessibilityLabel,
                       "Open MousePlus Settings — Finder HUD active")
        XCTAssertEqual(fallback, .global)
        XCTAssertEqual(fallback.accessibilityLabel,
                       "Open MousePlus Settings — Global HUD active")
    }

    func testHostedContextReplacementUpdatesOneNativeActionWithoutMovingIt() throws {
        let model = RingViewModel()
        model.load(
            resolved: resolvedProfile(
                route: .contextual,
                reference: .app(bundleIdentifier: "com.apple.finder"),
                name: "Finder"
            ),
            presentation: Configuration()
        )
        var iconRequests: [String] = []
        let mounted = centerHost(model: model) { bundleIdentifier in
            iconRequests.append(bundleIdentifier)
            return NSImage(size: NSSize(width: 16, height: 16))
        }
        let host = mounted.host
        let original = try XCTUnwrap(centerButton(in: host))
        let originalFrame = original.accessibilityFrame()
        XCTAssertFalse(originalFrame.isEmpty)

        XCTAssertEqual(original.title, "Finder")
        XCTAssertEqual(original.accessibilityLabel(),
                       "Open MousePlus Settings — Finder HUD active")
        XCTAssertEqual(iconRequests, ["com.apple.finder"])
        XCTAssertTrue(original.hitTest(NSPoint(x: 30, y: 30)) === original)

        model.load(
            resolved: resolvedProfile(route: .global, reference: .global, name: "Finder"),
            presentation: Configuration()
        )
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        host.layoutSubtreeIfNeeded()

        let replacement = try XCTUnwrap(centerButton(in: host))
        XCTAssertTrue(original === replacement)
        XCTAssertEqual(replacement.title, "Global")
        XCTAssertEqual(replacement.accessibilityLabel(),
                       "Open MousePlus Settings — Global HUD active")
        XCTAssertEqual(replacement.accessibilityFrame(), originalFrame)
        XCTAssertEqual(iconRequests, ["com.apple.finder"])
    }

    func testSuppressedPreviewHasNoCenterNodeAndDoesNotResolveLiveIcon() {
        let model = RingViewModel()
        model.load(
            resolved: resolvedProfile(
                route: .contextual,
                reference: .app(bundleIdentifier: "com.apple.finder"),
                name: "Finder"
            ),
            presentation: Configuration()
        )
        var iconRequestCount = 0
        let mounted = centerHost(model: model, exposesCenterSettings: false) { _ in
            iconRequestCount += 1
            return NSImage()
        }
        let host = mounted.host

        XCTAssertNil(centerButton(in: host))
        XCTAssertEqual(iconRequestCount, 0)
    }

    func testMovementAtThresholdRemainsAClick() {
        var state = HUDCenterDragState()
        state.begin(at: .zero)

        XCTAssertNil(state.move(to: CGPoint(x: 4, y: 0)))
        XCTAssertTrue(state.end())
    }

    func testMovementBeyondThresholdBecomesDragAndCannotClick() {
        var state = HUDCenterDragState()
        state.begin(at: CGPoint(x: 10, y: 10))

        XCTAssertEqual(state.move(to: CGPoint(x: 13, y: 14)), CGSize(width: 3, height: 4))
        XCTAssertTrue(state.isDragging)
        XCTAssertEqual(state.move(to: CGPoint(x: 15, y: 17)), CGSize(width: 2, height: 3))
        XCTAssertFalse(state.end())
    }

    func testPanelOriginClampsToVisibleFrameIncludingOffsetScreens() {
        let visible = CGRect(x: -1200, y: 30, width: 1000, height: 800)
        let size = CGSize(width: 472, height: 472)

        XCTAssertEqual(
            HUDPanelGeometry.clampedOrigin(CGPoint(x: -1400, y: -100), size: size, in: visible),
            CGPoint(x: -1200, y: 30)
        )
        XCTAssertEqual(
            HUDPanelGeometry.clampedOrigin(CGPoint(x: 0, y: 900), size: size, in: visible),
            CGPoint(x: -672, y: 358)
        )
    }

    func testPanelSideTracksConfiguredOuterRadius() {
        XCTAssertEqual(HUDPanelGeometry.squareSide(outerRadius: 150), 324)
        XCTAssertEqual(HUDPanelGeometry.squareSide(outerRadius: 224), 472)
        XCTAssertEqual(HUDPanelGeometry.squareSide(outerRadius: 300), 624)
    }

    func testPanelLargerThanScreenPinsToMinimumEdges() {
        XCTAssertEqual(
            HUDPanelGeometry.clampedOrigin(
                CGPoint(x: 100, y: 100),
                size: CGSize(width: 600, height: 700),
                in: CGRect(x: 20, y: 40, width: 500, height: 500)
            ),
            CGPoint(x: 20, y: 40)
        )
    }

    private func resolvedProfile(
        route: HUDInvocationRoute,
        reference: HUDProfileReference,
        name: String
    ) -> ResolvedHUDProfile {
        ResolvedHUDProfile(
            route: route,
            profileReference: reference,
            actionLayout: HUDActionLayout(inner: [], middle: []),
            targetApplication: FrontmostAppSnapshot(
                processIdentifier: 42,
                bundleIdentifier: "com.apple.finder",
                localizedName: name
            ),
            resolution: reference == .global ? .globalRoute : .exactAppMatch
        )
    }

    private func centerHost(
        model: RingViewModel,
        exposesCenterSettings: Bool = true,
        icon: @escaping @MainActor (String) -> NSImage?
    ) -> (host: NSHostingView<AnyView>, window: NSWindow) {
        let host = NSHostingView(rootView: AnyView(RingMenuView(
            viewModel: model,
            interactionEnabled: false,
            openingPlaybackEnabled: false,
            exposesCenterSettings: exposesCenterSettings,
            centerApplicationIcon: icon
        )))
        let side = model.radii.r3 * 2
        host.frame = NSRect(x: 0, y: 0, width: side, height: side)
        let window = NSWindow(
            contentRect: host.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        return (host, window)
    }

    private func centerButton(in view: NSView) -> NSButton? {
        if let button = view as? NSButton,
           button.accessibilityIdentifier() == HUDCenterSettingsControl.accessibilityIdentifier {
            return button
        }
        return view.subviews.lazy.compactMap { self.centerButton(in: $0) }.first
    }
}
