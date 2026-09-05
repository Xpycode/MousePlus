import SwiftUI
import Observation
import XCTest
@testable import MousePlus

final class HUDOpeningMotionTests: XCTestCase {
    @MainActor
    func testFullRuntimeSelectionDuringMountSuppressesReplayAndReportsReason() async throws {
        let model = RingViewModel()
        model.appearance.motion = HUDMotionConfiguration(baseDuration: 0.5, summon: .bloom)
        model.isVisible = true
        let mountedID = model.prepareOpeningPlayback()
        var frames: [HUDOpeningMotionFrame] = []
        var reasons: [String] = []
        let controller = RingWindowController()
        controller.show(at: NSEvent.mouseLocation, outerRadius: model.radii.r3,
                        content: RingMenuView(viewModel: model, interactionEnabled: false,
                                              onOpeningFrame: { frames.append($0) },
                                              onOpeningSettle: { reasons.append($0) }))
        defer { controller.hide() }
        try await Task.sleep(for: .milliseconds(80))
        XCTAssertEqual(frames.last?.progress, 0)

        // Exercise the real RingMenuView selection callback rather than
        // changing the animation owner's settle identity directly.
        model.activeSelection = ActiveSelection(band: .inner, index: 0)
        try await Task.sleep(for: .milliseconds(80))
        XCTAssertEqual(reasons, ["selection"])
        XCTAssertEqual(frames.last?.progress, 1)
        let settledCount = frames.count

        model.replayOpening(afterMounting: mountedID)
        try await Task.sleep(for: .milliseconds(80))
        XCTAssertTrue(frames.dropFirst(settledCount).allSatisfy {
            $0.progress == 1 && $0.artworkOpacity == 1 && $0.centerOpacity == 1
        })
    }

    @MainActor
    func testFullRuntimeRendererDisplaysIntermediateOpeningFramesAfterConcealedMount() async throws {
        try XCTSkipIf(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
                      "Spatial playback requires Reduce Motion to be off")
        for style in HUDSummonMotionStyle.allCases where style != .off {
            let model = RingViewModel()
            model.appearance.motion = HUDMotionConfiguration(baseDuration: 0.5, summon: style)
            model.isVisible = true
            let mountedID = model.prepareOpeningPlayback()
            var frames: [HUDOpeningMotionFrame] = []
            let controller = RingWindowController()
            let view = RingMenuView(viewModel: model, interactionEnabled: false,
                                    onOpeningFrame: { frames.append($0) })
            // Render the real materials and lifecycle, but isolate playback
            // assertions from physical pointer movement during a test run.
            controller.show(at: NSEvent.mouseLocation, outerRadius: model.radii.r3, content: view)
            defer { controller.hide() }
            try await Task.sleep(for: .milliseconds(16))
            XCTAssertFalse(frames.isEmpty)
            XCTAssertTrue(frames.allSatisfy {
                $0.progress == 0 && $0.artworkOpacity == 0 && $0.centerOpacity == 0
            }, "Mount: \(style)")
            model.replayOpening(afterMounting: mountedID)
            try await Task.sleep(for: .milliseconds(650))
            let intermediate = frames.filter { $0.progress > 0.05 && $0.progress < 0.95 }
            XCTAssertFalse(intermediate.isEmpty, "No intermediate frames for \(style): \(frames.map(\.progress))")
            let expectedEffect = HUDMotionPolicy.resolve(
                role: .summon, configuration: model.appearance.motion, reduceMotion: false
            ).effect
            XCTAssertTrue(frames.allSatisfy { $0.effect == expectedEffect },
                          "Selected \(style) must reach the renderer without falling back to Fade")
            switch style {
            case .circularSweep, .irisReveal:
                XCTAssertTrue(intermediate.allSatisfy { $0.mask != .none })
            case .bloom:
                XCTAssertTrue(intermediate.contains { $0.artworkScale != 1 })
            case .off, .fade, .staggeredSegments:
                break
            }
            XCTAssertEqual(frames.last?.progress, 1)
            XCTAssertNil(model.activeSelection)
        }
    }

    @MainActor
    func testHostedMountRemainsConcealedUntilReplayForEveryAnimatedStyle() async throws {
        for style in HUDSummonMotionStyle.allCases where style != .off {
            let probe = OpeningMountProbe(style: style)
            let controller = RingWindowController()
            controller.show(at: NSPoint(x: 100, y: 100), outerRadius: 32,
                            content: OpeningMountProbeView(probe: probe))
            defer { controller.hide() }
            try await probe.waitUntil { probe.didMount && !probe.frames.isEmpty }

            // Longer than both startup deferrals: insertion must never play
            // itself, even if the owner's mount callback arrives late.
            try await Task.sleep(for: .milliseconds(80))
            XCTAssertTrue(probe.frames.allSatisfy {
                $0.progress == 0 && $0.artworkOpacity == 0 && $0.centerOpacity == 0
            }, "Unexpected visible mount frame for \(style)")

            probe.replay()
            try await probe.waitUntil { probe.frames.last?.progress == 1 }
            XCTAssertEqual(probe.frames.last?.artworkOpacity, 1)
            XCTAssertEqual(probe.frames.last?.centerOpacity, 1)
        }
    }

    @MainActor
    func testHostedEarlyInteractionSettlesAndLateMountReplayCannotHideAgain() async throws {
        let probe = OpeningMountProbe(style: .bloom)
        let controller = RingWindowController()
        controller.show(at: NSPoint(x: 100, y: 100), outerRadius: 32,
                        content: OpeningMountProbeView(probe: probe))
        defer { controller.hide() }
        try await probe.waitUntil { probe.didMount && !probe.frames.isEmpty }

        probe.settleID += 1
        try await probe.waitUntil { probe.frames.last?.progress == 1 }
        XCTAssertEqual(probe.frames.last?.artworkOpacity, 1)
        let settledCount = probe.frames.count

        probe.replay()
        try await Task.sleep(for: .milliseconds(80))
        XCTAssertTrue(probe.frames.dropFirst(settledCount).allSatisfy {
            $0.progress == 1 && $0.artworkOpacity == 1 && $0.centerOpacity == 1
        })
    }

    @MainActor
    func testHostedPreferenceChangeDuringMountSettlesAndSuppressesLateReplay() async throws {
        let probe = OpeningMountProbe(style: .circularSweep)
        let controller = RingWindowController()
        controller.show(at: NSPoint(x: 100, y: 100), outerRadius: 32,
                        content: OpeningMountProbeView(probe: probe))
        defer { controller.hide() }
        try await probe.waitUntil { probe.didMount && !probe.frames.isEmpty }

        probe.request = HUDOpeningMotionRequest(
            descriptor: .init(effect: .fade, duration: 0.5),
            playbackEnabled: true, invocationID: probe.request.invocationID, isAwaitingMount: true
        )
        try await probe.waitUntil { probe.frames.last?.progress == 1 }
        let settledCount = probe.frames.count

        probe.replay()
        try await Task.sleep(for: .milliseconds(80))
        XCTAssertTrue(probe.frames.dropFirst(settledCount).allSatisfy {
            $0.progress == 1 && $0.artworkOpacity == 1 && $0.centerOpacity == 1
        })
    }

    func testAnimatedMountConcealsArtworkAndCenterWithoutArmingClock() {
        for style in HUDSummonMotionStyle.allCases where style != .off {
            for reduceMotion in [false, true] {
                let request = HUDOpeningMotionRequest(
                    descriptor: HUDMotionPolicy.resolve(
                        role: .summon,
                        configuration: HUDMotionConfiguration(summon: style),
                        reduceMotion: reduceMotion
                    ),
                    playbackEnabled: true,
                    invocationID: 1,
                    isAwaitingMount: true
                )
                let seed = HUDOpeningPlaybackSeed(request: request)
                let content = HUDOpeningMotionContent(
                    descriptor: request.descriptor,
                    progress: seed.progress,
                    deadZoneRadius: 24,
                    revealRadius: 150,
                    isConcealed: seed.isConcealed
                ) { _ in EmptyView() }

                XCTAssertEqual(seed.progress, 0)
                XCTAssertFalse(seed.isPlaybackPending)
                XCTAssertTrue(seed.isConcealed)
                XCTAssertEqual(content.resolvedFrame.artworkOpacity, 0)
                XCTAssertEqual(content.resolvedFrame.centerOpacity, 0)
                XCTAssertEqual(HUDOpeningMotionTransition.resolve(previous: nil, current: request), .awaitMount)
                XCTAssertEqual(HUDOpeningMotionTransition.resolve(previous: request, current: request), .unchanged)
            }
        }
    }

    func testInstantAndDisabledMountsStayImmediatelyVisible() {
        let requests = [
            HUDOpeningMotionRequest(descriptor: .instant, playbackEnabled: true, invocationID: 1,
                                    isAwaitingMount: true),
            HUDOpeningMotionRequest(descriptor: .init(effect: .bloom, duration: 0.5),
                                    playbackEnabled: false, invocationID: 1, isAwaitingMount: true),
        ]
        for request in requests {
            let seed = HUDOpeningPlaybackSeed(request: request)
            XCTAssertEqual(seed.progress, 1)
            XCTAssertFalse(seed.isPlaybackPending)
            XCTAssertFalse(seed.isConcealed)
            XCTAssertEqual(HUDOpeningMotionTransition.resolve(previous: nil, current: request), .settle)
        }
    }

    func testSharedContentInterpolatesNormalizedProgressInsteadOfOnlyEndpoints() {
        var content = HUDOpeningMotionContent(
            descriptor: .init(effect: .circularSweep, duration: 0.5),
            progress: 0,
            deadZoneRadius: 24,
            revealRadius: 150
        ) { _ in
            EmptyView()
        }

        content.animatableData = 0.5

        XCTAssertEqual(content.progress, 0.5)
        guard case .circularSweep(let progress) = content.resolvedFrame.mask else {
            return XCTFail("Expected an intermediate sweep mask")
        }
        XCTAssertGreaterThan(progress, 0.5)
        XCTAssertLessThan(progress, 1)
    }

    func testFirstAnimatedRequestStartsPlayback() {
        let request = HUDOpeningMotionRequest(
            descriptor: .init(effect: .fade, duration: 0.15),
            playbackEnabled: true,
            invocationID: 1
        )

        XCTAssertEqual(
            HUDOpeningMotionTransition.resolve(previous: nil, current: request),
            .replay
        )
        let seed = HUDOpeningPlaybackSeed(request: request)
        XCTAssertEqual(seed.progress, 0)
        XCTAssertTrue(seed.isPlaybackPending)
    }

    func testReplayIdentityRestartsButDescriptorChangeOnlySettlesLiveEntrance() {
        let initial = HUDOpeningMotionRequest(
            descriptor: .init(effect: .circularSweep, duration: 0.15),
            playbackEnabled: true,
            invocationID: 1
        )
        let replay = HUDOpeningMotionRequest(
            descriptor: initial.descriptor,
            playbackEnabled: true,
            invocationID: 2
        )
        let changedPreference = HUDOpeningMotionRequest(
            descriptor: .init(effect: .irisReveal, duration: 0.5),
            playbackEnabled: true,
            invocationID: 1
        )

        XCTAssertEqual(
            HUDOpeningMotionTransition.resolve(previous: initial, current: replay),
            .replay
        )
        XCTAssertEqual(
            HUDOpeningMotionTransition.resolve(previous: initial, current: changedPreference),
            .settle
        )
    }

    func testDisabledOrInstantPlaybackAlwaysSettles() {
        let fade = HUDMotionPresentationDescriptor(effect: .fade, duration: 0.15)
        let disabled = HUDOpeningMotionRequest(
            descriptor: fade, playbackEnabled: false, invocationID: 1
        )
        let instant = HUDOpeningMotionRequest(
            descriptor: .instant, playbackEnabled: true, invocationID: 2
        )

        XCTAssertEqual(
            HUDOpeningMotionTransition.resolve(previous: nil, current: disabled),
            .settle
        )
        XCTAssertEqual(
            HUDOpeningMotionTransition.resolve(previous: disabled, current: instant),
            .settle
        )
    }

    func testStaticEditorIsIndependentFromInteractionPermission() {
        let configuration = HUDMotionConfiguration(summon: .bloom)

        XCTAssertEqual(
            HUDRingPresentationMode.staticEditor.motion(
                for: .summon, configuration: configuration, reduceMotion: false
            ),
            .instant
        )
        XCTAssertEqual(
            HUDRingPresentationMode.openingPreview.motion(
                for: .summon, configuration: configuration, reduceMotion: false
            ).effect,
            .bloom
        )
    }

    func testWaveTwoFrameKeepsFadeAndInstantEndpoints() {
        let fade = HUDMotionPresentationDescriptor(effect: .fade, duration: 0.15)

        XCTAssertEqual(HUDOpeningMotionFrame.resolve(descriptor: .instant, progress: 0).artworkOpacity, 1)
        XCTAssertEqual(HUDOpeningMotionFrame.resolve(descriptor: fade, progress: -1).artworkOpacity, 0)
        XCTAssertEqual(HUDOpeningMotionFrame.resolve(descriptor: fade, progress: 0.5).artworkOpacity, 0.5)
        XCTAssertEqual(HUDOpeningMotionFrame.resolve(descriptor: fade, progress: 2).artworkOpacity, 1)
    }

    func testCircularSweepUsesTopOriginAndRemovesMaskAtCompletion() {
        let descriptor = HUDMotionPresentationDescriptor(effect: .circularSweep, duration: 0.15)
        let initial = HUDOpeningMotionFrame.resolve(descriptor: descriptor, progress: 0)
        let halfway = HUDOpeningMotionFrame.resolve(descriptor: descriptor, progress: 0.5)
        let final = HUDOpeningMotionFrame.resolve(descriptor: descriptor, progress: 1)

        XCTAssertEqual(initial.mask, .circularSweep(0))
        guard case .circularSweep(let progress) = halfway.mask else {
            return XCTFail("Expected a sweep mask")
        }
        XCTAssertGreaterThan(progress, 0.5)
        XCTAssertLessThan(progress, 1)
        XCTAssertEqual(final.mask, .none)
        XCTAssertEqual(final.artworkOpacity, 1)
        XCTAssertEqual(final.centerOpacity, 1)
    }

    func testIrisExpandsFromDeadZoneToMiddleOuterEdge() {
        let descriptor = HUDMotionPresentationDescriptor(effect: .irisReveal, duration: 0.15)
        let initial = HUDOpeningMotionFrame.resolve(
            descriptor: descriptor, progress: 0, deadZoneRadius: 24, revealRadius: 150
        )
        let final = HUDOpeningMotionFrame.resolve(
            descriptor: descriptor, progress: 1, deadZoneRadius: 24, revealRadius: 150
        )

        XCTAssertEqual(initial.mask, .iris(radius: 24))
        XCTAssertEqual(final.mask, .none)
    }

    func testBloomIsBoundedAndEndsExactlyAtFinalScale() {
        let descriptor = HUDMotionPresentationDescriptor(effect: .bloom, duration: 0.15)
        let samples = (0...1_000).map { index in
            HUDOpeningMotionFrame.resolve(
                descriptor: descriptor,
                progress: CGFloat(index) / 1_000
            )
        }

        XCTAssertEqual(samples[0].artworkScale, 0.92, accuracy: 0.000_001)
        XCTAssertEqual(samples[1_000].artworkScale, 1, accuracy: 0.000_001)
        XCTAssertLessThanOrEqual(samples.map(\.artworkScale).max() ?? 2, 1.015_001)
        XCTAssertGreaterThan(samples.map(\.artworkScale).max() ?? 0, 1)
        XCTAssertEqual(samples[0].centerOpacity, 1)
        XCTAssertEqual(samples[1_000].artworkOpacity, 1)
    }

    func testStaggerCadenceUsesClockwiseStartEdgeOrderAcrossWrap() {
        let slotCount = 4
        let offset = CGFloat.pi
        let ranks = (0..<slotCount).map {
            HUDOpeningMotionFrame.staggerRank(
                index: $0, slotCount: slotCount, angularOffset: offset
            )
        }

        XCTAssertEqual(ranks, [3, 0, 1, 2])
        XCTAssertEqual(
            HUDOpeningMotionFrame.staggerOpacity(globalProgress: 0, rank: 0, slotCount: 4),
            0
        )
        XCTAssertEqual(
            HUDOpeningMotionFrame.staggerOpacity(globalProgress: 1, rank: 3, slotCount: 4),
            1
        )
        XCTAssertEqual(
            HUDOpeningMotionFrame.staggerOpacity(globalProgress: 0.5, rank: 0, slotCount: 1),
            0.875,
            accuracy: 0.000_001
        )
    }
}

/// Exercises the real NSPanel and SwiftUI opening owner, recording the frames
/// supplied to artwork. It does not inspect material pixels or spoken VoiceOver.
@MainActor
@Observable
private final class OpeningMountProbe {
    var request: HUDOpeningMotionRequest
    var settleID = 0
    @ObservationIgnored var frames: [HUDOpeningMotionFrame] = []
    @ObservationIgnored var didMount = false

    init(style: HUDSummonMotionStyle) {
        request = HUDOpeningMotionRequest(
            descriptor: HUDMotionPolicy.resolve(
                role: .summon,
                configuration: HUDMotionConfiguration(baseDuration: 0.05, summon: style),
                reduceMotion: false
            ),
            playbackEnabled: true, invocationID: 1, isAwaitingMount: true
        )
    }

    func replay() {
        request = HUDOpeningMotionRequest(
            descriptor: request.descriptor, playbackEnabled: true,
            invocationID: request.invocationID + 1
        )
    }

    func waitUntil(_ predicate: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(2)
        while !predicate(), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(predicate(), "Hosted opening presentation did not update")
    }
}

private struct OpeningMountProbeView: View {
    let probe: OpeningMountProbe

    var body: some View {
        HUDOpeningMotion(request: probe.request, settleID: probe.settleID,
                         deadZoneRadius: 8, revealRadius: 24) { frame in
            let _ = probe.frames.append(frame)
            Color.clear.frame(width: 64, height: 64)
        }
        .task { probe.didMount = true }
    }
}
