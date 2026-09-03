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

    func testCanonicalCustomizationRoundTrips() throws {
        let original = HUDCustomization(
            inner: HUDRingCustomization(
                layout: HUDRingLayout(slotCountMode: .fixed, fixedSlotCount: 7, angularOffset: 22.5),
                appearance: HUDRingAppearance(iconOrientation: .radial)
            ),
            middle: HUDRingCustomization(
                layout: HUDRingLayout(slotCountMode: .fixed, fixedSlotCount: 5, angularOffset: 315),
                appearance: HUDRingAppearance(iconOrientation: .tangential)
            ),
            outerAppearance: HUDRingAppearance(iconOrientation: .upright),
            outerRingVisibility: .revealBeyondInnerRing,
            iconOrientation: .tangential
        )

        let decoded = try JSONDecoder().decode(
            HUDCustomization.self,
            from: JSONEncoder().encode(original)
        )

        XCTAssertEqual(decoded, original)
    }
}
