import XCTest
@testable import MousePlus

final class HUDOpeningMotionTests: XCTestCase {
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
