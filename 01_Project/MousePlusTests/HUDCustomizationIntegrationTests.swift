import AppKit
import SwiftUI
import XCTest
@testable import MousePlus

@MainActor
final class HUDCustomizationIntegrationTests: XCTestCase {
    private let black = HUDColor.black
    private let white = HUDColor.white

    func testControlBindingsThroughSaveRoundTripProduceAsymmetricRotatedRuntimeGeometryAndFixedEmptyPositionsAreInert() async throws {
        let store = IntegrationPersistence(Configuration(
            inner: Self.items(2, prefix: "I"),
            middle: Self.items(3, prefix: "M")
        ))
        let runtime = RingViewModel()
        let coordinator = makeCoordinator(store: store, runtime: runtime)
        await coordinator.load()
        let model = coordinator.menuEditorModel

        // Drive the same Binding/AppKit coordinator boundary used by segmented controls.
        var modeSelection = 0
        let modeBinding = Binding<Int>(
            get: { modeSelection },
            set: {
                modeSelection = $0
                model.hudCustomization.inner.layout.slotCountMode = $0 == 1 ? .fixed : .auto
            }
        )
        let segmented = NSSegmentedControl(labels: ["Auto", "Fixed"], trackingMode: .selectOne,
                                           target: nil, action: nil)
        segmented.selectedSegment = 1
        AppKitSegmentedControl.Coordinator(selection: modeBinding).changed(segmented)

        model.hudCustomization.inner.layout.fixedSlotCount = 5
        model.hudCustomization.inner.layout.angularOffset = 350
        model.hudCustomization.middle.layout = HUDRingLayout(
            slotCountMode: .fixed, fixedSlotCount: 7, angularOffset: 95
        )
        coordinator.menuItemsDidChange()
        let flushed = await coordinator.flush()
        XCTAssertTrue(flushed)

        let decoded = try await store.decoded()
        XCTAssertEqual(decoded.hudCustomization.inner.layout.angularOffset, 350)
        XCTAssertEqual(decoded.hudCustomization.middle.layout.angularOffset, 95)
        XCTAssertEqual(runtime.geometry.inner.slotCount, 5)
        XCTAssertEqual(runtime.geometry.middle.slotCount, 7)
        XCTAssertEqual(runtime.geometry.inner.angularOffset, 350 * .pi / 180, accuracy: 0.000_001)
        XCTAssertEqual(runtime.geometry.middle.angularOffset, 95 * .pi / 180, accuracy: 0.000_001)

        let empty = RadialGeometry.centroid(
            band: .inner, index: 4, center: .zero, radii: runtime.radii,
            geometry: runtime.geometry, expandedParentIndex: nil, outerCount: 0
        )
        runtime.updateActive(at: empty, center: .zero)
        XCTAssertNil(runtime.activeSelection, "unused fixed positions have no hover/hit target")
        XCTAssertEqual(runtime.commit(at: empty, center: .zero), .noSelection)
    }

    func testMenuRingAndItemOrientationAndColorInheritanceResolveAfterEncodeDecodeAndLiveApply() async throws {
        var config = Configuration(inner: Self.items(1, prefix: "I"), middle: Self.items(1, prefix: "M"))
        config.middle[0].subItems = Self.items(1, prefix: "O")
        let store = IntegrationPersistence(config)
        let runtime = RingViewModel()
        let coordinator = makeCoordinator(store: store, runtime: runtime)
        await coordinator.load()
        let model = coordinator.menuEditorModel

        model.hudCustomization.iconOrientation = .radial
        model.hudCustomization.inner.appearance.iconOrientation = nil       // menu inheritance
        model.hudCustomization.middle.appearance.iconOrientation = .tangential // ring override
        model.hudCustomization.outerAppearance.iconOrientation = .upright  // outer override
        model.hudCustomization.wedgeColor = black
        model.hudCustomization.iconColor = white
        model.hudCustomization.middle.appearance.wedgeColor = white
        model.middle[0].wedgeColor = black                                 // item beats ring
        model.middle[0].iconColor = HUDColor(red: 0.1, green: 0.1, blue: 0.1) // contrast fallback
        coordinator.menuItemsDidChange()
        let flushed = await coordinator.flush()
        XCTAssertTrue(flushed)
        _ = try await store.decoded() // explicitly prove Codable storage is readable

        XCTAssertEqual(runtime.iconOrientation(for: .inner), .radial)
        XCTAssertEqual(runtime.iconOrientation(for: .middle), .tangential)
        XCTAssertEqual(runtime.iconOrientation(for: .outer), .upright)
        let resolution = runtime.colorResolution(
            for: runtime.middleItems[0], band: .middle,
            application: .init(wedge: white, icon: black), backdrop: black
        )
        XCTAssertEqual(resolution.requestedWedge, black)
        XCTAssertEqual(resolution.requestedIcon, HUDColor(red: 0.1, green: 0.1, blue: 0.1))
        XCTAssertEqual(resolution.renderedIcon, white, "low-contrast requested colors use the deterministic fallback")
    }

    func testEveryOuterVisibilityModeAndPreviewSuppressionMatchRuntimeWithoutExecutionPath() {
        for mode in OuterRingVisibility.allCases {
            var config = Configuration(inner: Self.items(1, prefix: "I"), middle: Self.items(1, prefix: "M"))
            config.middle[0].subItems = Self.items(2, prefix: "O")
            config.hudCustomization.outerRingVisibility = mode
            let runtime = RingViewModel()
            runtime.load(from: config)
            runtime.expand(0)

            var preview = HUDPreviewInteractionState()
            let snapshot = HUDPreviewInteractionSnapshot(
                geometry: runtime.geometry, radii: runtime.radii,
                innerCount: 1, middleCount: 1, expandedParentIndex: 0,
                outerCount: 2, outerVisibility: mode
            )
            let outerPoint = RadialGeometry.centroid(
                band: .outer, index: 0, center: .zero, radii: runtime.radii,
                geometry: runtime.geometry, expandedParentIndex: 0, outerCount: 2
            )
            if mode == .revealBeyondInnerRing {
                _ = preview.pointerMoved(to: CGPoint(x: runtime.radii.r1, y: 0), center: .zero, snapshot: snapshot)
                _ = preview.pointerMoved(to: CGPoint(x: runtime.radii.r1 + 1, y: 0), center: .zero, snapshot: snapshot)
                runtime.updateActive(at: CGPoint(x: runtime.radii.r1, y: 0), center: .zero)
                runtime.updateActive(at: CGPoint(x: runtime.radii.r1 + 1, y: 0), center: .zero)
            }
            let expectedVisible = mode != .alwaysHidden
            XCTAssertEqual(runtime.isOuterRingVisible, expectedVisible, "mode: \(mode)")
            XCTAssertEqual(preview.intent(at: outerPoint, center: .zero, snapshot: snapshot) != nil,
                           expectedVisible, "preview emits only an editor intent for mode: \(mode)")
        }
    }

    func testSaveFailureDoesNotLiveApplyAndRetryPreservesEditorValuesThenUpdatesRuntime() async {
        let store = IntegrationPersistence(Configuration())
        let runtime = RingViewModel()
        let coordinator = makeCoordinator(store: store, runtime: runtime)
        await coordinator.load()
        await store.failNextSave()
        coordinator.menuEditorModel.hudCustomization.outerRingVisibility = .alwaysHidden
        coordinator.menuEditorModel.hudCustomization.middle.layout.angularOffset = 271
        coordinator.menuItemsDidChange()

        let failedFlush = await coordinator.flush()
        XCTAssertFalse(failedFlush)
        XCTAssertEqual(runtime.hudCustomization, .default, "failed saves never leak into live runtime")
        XCTAssertEqual(coordinator.menuEditorModel.hudCustomization.middle.layout.angularOffset, 271)
        let retried = await coordinator.retry()
        XCTAssertTrue(retried)
        XCTAssertEqual(runtime.hudCustomization.outerRingVisibility, .alwaysHidden)
        XCTAssertEqual(runtime.hudCustomization.middle.layout.angularOffset, 271)
    }

    private func makeCoordinator(store: IntegrationPersistence, runtime: RingViewModel) -> SettingsWorkspaceCoordinator {
        SettingsWorkspaceCoordinator(
            persistence: store,
            debounceClock: IntegrationLongClock(),
            liveApply: { runtime.load(from: $0) }
        )
    }

    private static func items(_ count: Int, prefix: String) -> [RingMenuItem] {
        (0..<count).map { RingMenuItem(label: "\(prefix)\($0)", icon: "circle", actionType: .custom) }
    }
}

private struct IntegrationLongClock: WorkspaceDebounceClock {
    func sleep() async throws { try await Task.sleep(for: .seconds(60)) }
}

private enum IntegrationFailure: Error { case save }

private actor IntegrationPersistence: ConfigurationPersisting {
    private var data: Data
    private var shouldFail = false

    init(_ configuration: Configuration) {
        data = try! JSONEncoder().encode(configuration)
    }

    func loadResult() throws -> ConfigurationService.LoadResult {
        .loaded(try JSONDecoder().decode(Configuration.self, from: data))
    }

    func save(_ configuration: Configuration) throws {
        if shouldFail {
            shouldFail = false
            throw IntegrationFailure.save
        }
        data = try JSONEncoder().encode(configuration)
    }

    func failNextSave() { shouldFail = true }
    func decoded() throws -> Configuration { try JSONDecoder().decode(Configuration.self, from: data) }
}
