import AppKit
import SwiftUI
import XCTest
@testable import MousePlus

@MainActor
final class AppKitControlsTests: XCTestCase {
    func testSegmentedCoordinatorWritesSelection() {
        var selection = 0
        let binding = Binding(get: { selection }, set: { selection = $0 })
        let coordinator = AppKitSegmentedControl.Coordinator(selection: binding)
        let control = NSSegmentedControl(labels: ["Auto", "Fixed"], trackingMode: .selectOne, target: nil, action: nil)

        control.selectedSegment = 1
        coordinator.changed(control)

        XCTAssertEqual(selection, 1)
    }

    func testColorWellCoordinatorRoundTripsCustomAndInheritedStates() {
        var color: NSColor? = .systemRed
        let binding = Binding(get: { color }, set: { color = $0 })
        let coordinator = AppKitColorWell.Coordinator(color: binding, defaultCustomColor: .systemBlue)
        let inherit = NSButton(checkboxWithTitle: "Inherit", target: nil, action: nil)
        let well = NSColorWell()
        coordinator.inheritButton = inherit
        coordinator.colorWell = well

        inherit.state = .on
        coordinator.inheritChanged(inherit)
        XCTAssertNil(color)
        XCTAssertFalse(well.isEnabled)

        inherit.state = .off
        coordinator.inheritChanged(inherit)
        XCTAssertEqual(color, .systemRed)
        XCTAssertTrue(well.isEnabled)

        well.color = .systemGreen
        coordinator.colorChanged(well)
        XCTAssertEqual(color, .systemGreen)
    }

    func testColorWellDefaultsToInheritTitle() {
        let binding = Binding<NSColor?>(get: { nil }, set: { _ in })
        let well = AppKitColorWell(color: binding, accessibilityLabel: "Wedge color")

        XCTAssertEqual(well.inheritTitle, "Inherit")
    }

    func testColorWellAcceptsMenuRootDefaultTitle() {
        let binding = Binding<NSColor?>(get: { nil }, set: { _ in })
        let well = AppKitColorWell(color: binding, inheritTitle: "Default", accessibilityLabel: "Wedge color")

        XCTAssertEqual(well.inheritTitle, "Default")
    }

    func testCountCoordinatorClampsStepperInput() {
        var value = 4
        let binding = Binding(get: { value }, set: { value = $0 })
        let coordinator = AppKitCountControl.Coordinator(value: binding, range: 1...8)
        let field = NSTextField()
        let stepper = NSStepper()
        coordinator.field = field
        coordinator.stepper = stepper

        stepper.integerValue = 12
        coordinator.stepperChanged(stepper)

        XCTAssertEqual(value, 8)
        XCTAssertEqual(field.integerValue, 8)
        XCTAssertEqual(stepper.integerValue, 8)
    }
}
