import Foundation
import XCTest
@testable import MousePlus

final class HUDCustomizationCodingTests: XCTestCase {
    func testCompatibilityDefaultsMatchExistingHUDBehavior() {
        let value = HUDCustomization.default

        XCTAssertEqual(value.inner.layout.slotCountMode, .auto)
        XCTAssertEqual(value.middle.layout.slotCountMode, .auto)
        XCTAssertEqual(value.inner.layout.angularOffset, 0)
        XCTAssertEqual(value.middle.layout.angularOffset, 0)
        XCTAssertEqual(value.iconOrientation, .upright)
        XCTAssertEqual(value.outerRingVisibility, .alwaysVisible)
        XCTAssertNil(value.wedgeColor)
        XCTAssertNil(value.iconColor)
        XCTAssertNil(value.inner.appearance.iconOrientation)
        XCTAssertNil(value.middle.appearance.iconOrientation)
        XCTAssertNil(value.outerAppearance.iconOrientation)

        XCTAssertEqual(value.labelOrientation, .upright)
        XCTAssertNil(value.inner.appearance.labelOrientation)
        XCTAssertNil(value.middle.appearance.labelOrientation)
        XCTAssertNil(value.outerAppearance.labelOrientation)
        XCTAssertFalse(value.inner.appearance.labelVisible, "inner labels stay hidden to match the pre-customization HUD")
        XCTAssertTrue(value.middle.appearance.labelVisible)
        XCTAssertTrue(value.outerAppearance.labelVisible)
    }

    func testMissingConfigurationDecodesToCompatibilityLabelDefaults() throws {
        let value = try JSONDecoder().decode(HUDCustomization.self, from: Data("{}".utf8))

        XCTAssertEqual(value, .default)
        XCTAssertFalse(value.inner.appearance.labelVisible)
        XCTAssertTrue(value.middle.appearance.labelVisible)
        XCTAssertTrue(value.outerAppearance.labelVisible)
        XCTAssertEqual(value.labelOrientation, .upright)
        XCTAssertNil(value.inner.appearance.labelOrientation)
        XCTAssertNil(value.middle.appearance.labelOrientation)
        XCTAssertNil(value.outerAppearance.labelOrientation)
    }

    func testPartialNestedConfigurationDefaultsOnlyMissingFields() throws {
        let json = """
        {
          "inner": {
            "layout": { "slotCountMode": "fixed", "fixedSlotCount": 6 },
            "appearance": { "iconOrientation": "radial" }
          },
          "outerRingVisibility": "alwaysHidden",
          "iconOrientation": "tangential"
        }
        """

        let value = try JSONDecoder().decode(HUDCustomization.self, from: Data(json.utf8))

        XCTAssertEqual(value.inner.layout.slotCountMode, .fixed)
        XCTAssertEqual(value.inner.layout.fixedSlotCount, 6)
        XCTAssertEqual(value.inner.layout.angularOffset, 0)
        XCTAssertEqual(value.inner.appearance.iconOrientation, .radial)
        XCTAssertEqual(value.middle, HUDRingCustomization())
        XCTAssertEqual(value.outerRingVisibility, .alwaysHidden)
        XCTAssertEqual(value.iconOrientation, .tangential)
    }

    func testPartialLabelFieldsFillCompatibilityDefaultsAndPreserveSiblings() throws {
        let json = """
        {
          "inner": {
            "appearance": { "labelVisible": true }
          },
          "outerAppearance": {
            "iconOrientation": "upright",
            "labelOrientation": "tangential"
          }
        }
        """

        let value = try JSONDecoder().decode(HUDCustomization.self, from: Data(json.utf8))

        XCTAssertTrue(value.inner.appearance.labelVisible, "explicit override replaces the inner compatibility default")
        XCTAssertNil(value.inner.appearance.labelOrientation)
        XCTAssertTrue(value.middle.appearance.labelVisible, "an entirely absent ring keeps its compatibility default")
        XCTAssertEqual(value.outerAppearance.iconOrientation, .upright)
        XCTAssertEqual(value.outerAppearance.labelOrientation, .tangential)
        XCTAssertTrue(value.outerAppearance.labelVisible, "outer labelVisible falls back to its compatibility default when omitted")
    }

    func testInvalidNewFieldsAreSanitizedWithoutDiscardingValidSiblings() throws {
        let json = """
        {
          "inner": {
            "layout": {
              "slotCountMode": "futureMode",
              "fixedSlotCount": -42,
              "angularOffset": -90
            },
            "appearance": { "iconOrientation": "radial", "wedgeColor": "bad" }
          },
          "middle": {
            "layout": {
              "slotCountMode": "fixed",
              "fixedSlotCount": 200,
              "angularOffset": 450
            }
          },
          "outerRingVisibility": "futureVisibility",
          "iconOrientation": "futureOrientation"
        }
        """

        let value = try JSONDecoder().decode(HUDCustomization.self, from: Data(json.utf8))

        XCTAssertEqual(value.inner.layout.slotCountMode, .auto)
        XCTAssertEqual(value.inner.layout.fixedSlotCount, 1)
        XCTAssertEqual(value.inner.layout.angularOffset, 270)
        XCTAssertEqual(value.inner.appearance.iconOrientation, .radial)
        XCTAssertNil(value.inner.appearance.wedgeColor)
        XCTAssertEqual(value.middle.layout.slotCountMode, .fixed)
        XCTAssertEqual(value.middle.layout.fixedSlotCount, 8)
        XCTAssertEqual(value.middle.layout.angularOffset, 90)
        XCTAssertEqual(value.outerRingVisibility, .alwaysVisible)
        XCTAssertEqual(value.iconOrientation, .upright)
    }

    func testInvalidLabelFieldsAreSanitizedWithoutDiscardingValidSiblings() throws {
        let json = """
        {
          "inner": {
            "appearance": {
              "iconOrientation": "radial",
              "labelOrientation": "diagonal",
              "labelVisible": "yes"
            }
          },
          "middle": {
            "appearance": { "labelOrientation": "futureOrientation", "labelVisible": 1 }
          },
          "outerAppearance": { "labelVisible": "maybe" },
          "labelOrientation": "futureOrientation"
        }
        """

        let value = try JSONDecoder().decode(HUDCustomization.self, from: Data(json.utf8))

        XCTAssertEqual(value.inner.appearance.iconOrientation, .radial, "a valid sibling survives an invalid label field")
        XCTAssertNil(value.inner.appearance.labelOrientation)
        XCTAssertFalse(value.inner.appearance.labelVisible, "invalid labelVisible falls back to the inner compatibility default")
        XCTAssertNil(value.middle.appearance.labelOrientation)
        XCTAssertTrue(value.middle.appearance.labelVisible, "invalid labelVisible falls back to the middle compatibility default")
        XCTAssertTrue(value.outerAppearance.labelVisible, "invalid labelVisible falls back to the outer compatibility default")
        XCTAssertEqual(value.labelOrientation, .upright)
    }

    func testCanonicalCustomizationRoundTrips() throws {
        let original = HUDCustomization(
            inner: HUDRingCustomization(
                layout: HUDRingLayout(slotCountMode: .fixed, fixedSlotCount: 7, angularOffset: 22.5),
                appearance: HUDRingAppearance(
                    iconOrientation: .radial, labelOrientation: .tangential, labelVisible: true
                )
            ),
            middle: HUDRingCustomization(
                layout: HUDRingLayout(slotCountMode: .fixed, fixedSlotCount: 5, angularOffset: 315),
                appearance: HUDRingAppearance(
                    iconOrientation: .tangential, labelOrientation: .radial, labelVisible: false
                )
            ),
            outerAppearance: HUDRingAppearance(
                iconOrientation: .upright, labelOrientation: .upright, labelVisible: false
            ),
            outerRingVisibility: .revealBeyondInnerRing,
            iconOrientation: .tangential,
            labelOrientation: .radial
        )

        let decoded = try JSONDecoder().decode(
            HUDCustomization.self,
            from: JSONEncoder().encode(original)
        )

        XCTAssertEqual(decoded, original)
    }

    func testResetToDefaultsProducesCompatibilityLabelValues() {
        var value = HUDCustomization(
            inner: HUDRingCustomization(appearance: .init(labelOrientation: .radial, labelVisible: true)),
            middle: HUDRingCustomization(appearance: .init(labelOrientation: .tangential, labelVisible: false)),
            outerAppearance: .init(labelOrientation: .tangential, labelVisible: false),
            labelOrientation: .radial
        )

        value = .default

        XCTAssertFalse(value.inner.appearance.labelVisible)
        XCTAssertTrue(value.middle.appearance.labelVisible)
        XCTAssertTrue(value.outerAppearance.labelVisible)
        XCTAssertEqual(value.labelOrientation, .upright)
        XCTAssertNil(value.inner.appearance.labelOrientation)
        XCTAssertNil(value.middle.appearance.labelOrientation)
        XCTAssertNil(value.outerAppearance.labelOrientation)
    }
}
