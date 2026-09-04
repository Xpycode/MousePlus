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
}
