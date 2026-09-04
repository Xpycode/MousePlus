import XCTest
@testable import MousePlus

final class HUDMotionPolicyTests: XCTestCase {
    func testEveryRoleResolvesForMasterSwitchAndReduceMotionCombinations() {
        let expectedEffects: [HUDMotionRole: (standard: HUDMotionPresentationEffect, reduced: HUDMotionPresentationEffect)] = [
            .summon: (.fade, .fade),
            .hover: (.emphasis, .fade),
            .outerExpansion: (.radialReveal, .fade),
            .branchChange: (.fade, .fade),
        ]

        for role in HUDMotionRole.allCases {
            for isEnabled in [false, true] {
                for reduceMotion in [false, true] {
                    var configuration = HUDMotionConfiguration.default
                    configuration.isEnabled = isEnabled
                    configuration.baseDuration = 0.2

                    let descriptor = HUDMotionPolicy.resolve(
                        role: role,
                        configuration: configuration,
                        reduceMotion: reduceMotion
                    )

                    if isEnabled {
                        let expected = reduceMotion
                            ? expectedEffects[role]?.reduced
                            : expectedEffects[role]?.standard
                        XCTAssertEqual(descriptor.effect, expected, "role=\(role), reduceMotion=\(reduceMotion)")
                        XCTAssertEqual(descriptor.duration, 0.2, accuracy: 0.000_001)
                    } else {
                        XCTAssertEqual(descriptor, .instant, "role=\(role), reduceMotion=\(reduceMotion)")
                    }
                }
            }
        }
    }

    func testEachOffStyleResolvesInstantly() {
        var configuration = HUDMotionConfiguration.default

        configuration.summon = .off
        XCTAssertEqual(resolve(.summon, configuration), .instant)

        configuration = .default
        configuration.hover = .off
        XCTAssertEqual(resolve(.hover, configuration), .instant)

        configuration = .default
        configuration.outerExpansion = .off
        XCTAssertEqual(resolve(.outerExpansion, configuration), .instant)

        configuration = .default
        configuration.branchChange = .off
        XCTAssertEqual(resolve(.branchChange, configuration), .instant)
    }

    func testDurationIsClampedAndNonFiniteValuesUseDefault() {
        var configuration = HUDMotionConfiguration.default

        configuration.baseDuration = -1
        XCTAssertEqual(resolve(.summon, configuration).duration, HUDMotionPolicy.minimumDuration)

        configuration.baseDuration = 99
        XCTAssertEqual(resolve(.summon, configuration).duration, HUDMotionPolicy.maximumDuration)

        configuration.baseDuration = .nan
        XCTAssertEqual(
            resolve(.summon, configuration).duration,
            HUDMotionConfiguration.default.baseDuration
        )
    }

    private func resolve(
        _ role: HUDMotionRole,
        _ configuration: HUDMotionConfiguration
    ) -> HUDMotionPresentationDescriptor {
        HUDMotionPolicy.resolve(
            role: role,
            configuration: configuration,
            reduceMotion: false
        )
    }
}
