import AppKit
import XCTest
@testable import MousePlus

final class HUDColorResolverTests: XCTestCase {
    func testComponentsClampAndRoundTrip() throws {
        let color = HUDColor(red: -1, green: 0.25, blue: 2, alpha: 1.5)
        XCTAssertEqual(color, HUDColor(red: 0, green: 0.25, blue: 1, alpha: 1))
        XCTAssertEqual(try JSONDecoder().decode(HUDColor.self, from: JSONEncoder().encode(color)), color)
    }

    func testNSColorBridgeUsesSRGBAndRejectsUnconvertibleColor() {
        let color = HUDColor(nsColor: NSColor(displayP3Red: 0.2, green: 0.4, blue: 0.6, alpha: 0.8))
        XCTAssertNotNil(color)
        XCTAssertEqual(color?.nsColor.colorSpace, .sRGB)
        XCTAssertNil(HUDColor(nsColor: NSColor(patternImage: NSImage(size: NSSize(width: 1, height: 1)))))
    }

    func testWCAGReferenceLuminanceAndContrast() {
        XCTAssertEqual(HUDColorResolver.relativeLuminance(of: .black), 0, accuracy: 1e-12)
        XCTAssertEqual(HUDColorResolver.relativeLuminance(of: .white), 1, accuracy: 1e-12)
        XCTAssertEqual(HUDColorResolver.contrastRatio(.black, .white), 21, accuracy: 1e-12)
        XCTAssertEqual(
            HUDColorResolver.relativeLuminance(of: HUDColor(red: 1, green: 0, blue: 0)),
            0.2126,
            accuracy: 1e-12
        )
    }

    func testInheritanceIsIndependentAndMostSpecificWins() {
        let application = HUDColorResolver.Overrides(wedge: .black, icon: .white)
        let menu = HUDColorResolver.Overrides(wedge: HUDColor(red: 0.1, green: 0.2, blue: 0.3))
        let ring = HUDColorResolver.Overrides(icon: HUDColor(red: 1, green: 0, blue: 0))
        let itemWedge = HUDColor(red: 0.8, green: 0.8, blue: 0.8)
        let result = HUDColorResolver.resolve(
            application: application,
            menu: menu,
            ring: ring,
            item: .init(wedge: itemWedge)
        )
        XCTAssertEqual(result.requestedWedge, itemWedge)
        XCTAssertEqual(result.requestedIcon, HUDColor(red: 1, green: 0, blue: 0))
    }

    func testAlphaCompositingPrecedesContrastFallback() {
        let result = HUDColorResolver.resolve(
            application: .init(
                wedge: HUDColor(red: 1, green: 1, blue: 1, alpha: 0.5),
                icon: HUDColor(red: 1, green: 1, blue: 1, alpha: 0.5)
            ),
            backdrop: .black
        )
        XCTAssertEqual(result.renderedWedge.red, 0.5, accuracy: 1e-12)
        XCTAssertEqual(result.renderedIcon, .black)
        XCTAssertEqual(result.requestedIcon.alpha, 0.5)
    }

    func testDeterministicFallbackChoosesHigherContrastBlackOrWhite() {
        let lightGray = HUDColor(red: 0.8, green: 0.8, blue: 0.8)
        let darkGray = HUDColor(red: 0.2, green: 0.2, blue: 0.2)
        let insufficient = HUDColor(red: 0.5, green: 0.5, blue: 0.5)
        XCTAssertEqual(
            HUDColorResolver.accessibleForeground(insufficient, against: lightGray, threshold: 4.5),
            .black
        )
        XCTAssertEqual(
            HUDColorResolver.accessibleForeground(insufficient, against: darkGray, threshold: 4.5),
            .white
        )
    }

    func testIconAndSmallLabelUseDifferentThresholds() {
        // 0.5 sRGB gray is about 3.98:1 against white: sufficient for an
        // icon's 3:1 threshold, but insufficient for a small label's 4.5:1.
        let foreground = HUDColor(red: 0.5, green: 0.5, blue: 0.5)
        let result = HUDColorResolver.resolve(
            application: .init(wedge: .white, icon: foreground)
        )
        XCTAssertEqual(result.renderedIcon, foreground)
        XCTAssertEqual(result.renderedLabel, .black)
    }
}
