import AppKit
import SwiftUI
import XCTest
@testable import MousePlus

@MainActor
final class AppKitControlsTests: XCTestCase {
    func testSetupButtonsExposeNativeReturnAndEscapeKeys() throws {
        var continued = false
        let host = NSHostingView(rootView: HStack {
            AppKitButton(title: "Continue", keyEquivalent: "\r") { continued = true }
            AppKitButton(title: "Quit", keyEquivalent: "\u{1b}") {}
        })
        host.frame = NSRect(x: 0, y: 0, width: 300, height: 80)
        host.layoutSubtreeIfNeeded()
        func buttons(in view: NSView) -> [NSButton] {
            (view as? NSButton).map { [$0] } ?? view.subviews.flatMap { buttons(in: $0) }
        }
        let controls = buttons(in: host)
        let next = try XCTUnwrap(controls.first { $0.title == "Continue" })
        let quit = try XCTUnwrap(controls.first { $0.title == "Quit" })
        XCTAssertEqual(next.keyEquivalent, "\r")
        XCTAssertEqual(quit.keyEquivalent, "\u{1b}")
        XCTAssertTrue(next.keyEquivalentModifierMask.isEmpty)
        next.performClick(nil)
        XCTAssertTrue(continued)
    }

    func testSegmentedCoordinatorWritesSelection() {
        var selection = 0
        let binding = Binding(get: { selection }, set: { selection = $0 })
        let coordinator = AppKitSegmentedControl.Coordinator(selection: binding)
        let control = NSSegmentedControl(labels: ["Auto", "Fixed"], trackingMode: .selectOne, target: nil, action: nil)

        control.selectedSegment = 1
        coordinator.changed(control)

        XCTAssertEqual(selection, 1)
    }

    func testRequestingCustomColorDoesNotPersistChooserSeed() {
        var color: NSColor?
        var writes = 0
        let binding = Binding(get: { color }, set: { color = $0; writes += 1 })
        let coordinator = AppKitColorWell.Coordinator(color: binding, defaultCustomColor: .systemBlue)
        let inherit = NSButton(checkboxWithTitle: "Default", target: nil, action: nil)
        let well = RecordingColorWell()
        coordinator.inheritButton = inherit
        coordinator.colorWell = well
        coordinator.synchronize()

        inherit.state = .off
        coordinator.inheritChanged(inherit)

        XCTAssertNil(color)
        XCTAssertEqual(writes, 0)
        XCTAssertEqual(inherit.state, .on)
        XCTAssertEqual(well.color, .systemBlue)
        XCTAssertEqual(well.activations, [true])

        // Deliberately enter through the target/action handler. The recording well
        // avoids opening the system panel; actual panel interaction remains manual.
        well.color = .systemGreen
        coordinator.colorChanged(well)
        XCTAssertEqual(color, .systemGreen)
        XCTAssertEqual(writes, 1)
        XCTAssertEqual(inherit.state, .off)

        inherit.state = .on
        coordinator.inheritChanged(inherit)
        XCTAssertNil(color)
        XCTAssertEqual(well.deactivations, 1)
        XCTAssertEqual(well.color, .systemBlue)
        XCTAssertTrue(well.isEnabled)

        inherit.state = .off
        coordinator.inheritChanged(inherit)
        XCTAssertNil(color, "Reopening must not restore a discarded override")
        XCTAssertEqual(writes, 2)
    }

    func testInheritedColorTracksCurrentContextInsteadOfPreviousChoice() {
        var firstColor: NSColor? = .systemRed
        var secondColor: NSColor?
        let firstBinding = Binding(get: { firstColor }, set: { firstColor = $0 })
        let coordinator = AppKitColorWell.Coordinator(color: firstBinding, defaultCustomColor: .systemBlue)
        let inherit = NSButton(checkboxWithTitle: "Inherit", target: nil, action: nil)
        let well = RecordingColorWell()
        coordinator.inheritButton = inherit
        coordinator.colorWell = well
        coordinator.synchronize()
        XCTAssertEqual(well.color, .systemRed)
        well.activate(true)

        // SwiftUI reuses the representable's coordinator when selecting another item.
        coordinator.color = Binding(get: { secondColor }, set: { secondColor = $0 })
        coordinator.defaultCustomColor = .systemYellow
        coordinator.synchronize()
        XCTAssertEqual(well.color, .systemYellow)
        XCTAssertEqual(well.deactivations, 1)
        XCTAssertFalse(well.isActive)
        XCTAssertEqual(inherit.state, .on)

        coordinator.defaultCustomColor = .systemPurple
        coordinator.synchronize()
        XCTAssertEqual(well.color, .systemPurple)
        XCTAssertNil(secondColor)
        XCTAssertEqual(firstColor, .systemRed)
    }

    func testDismantledColorWellDetachesSharedPanelAndAction() {
        let coordinator = AppKitColorWell.Coordinator(color: .constant(nil), defaultCustomColor: .clear)
        let well = RecordingColorWell()
        well.target = coordinator
        well.action = #selector(AppKitColorWell.Coordinator.colorChanged(_:))
        coordinator.colorWell = well
        well.activate(true)

        AppKitColorWell.dismantleNSView(NSStackView(views: [well]), coordinator: coordinator)

        XCTAssertFalse(well.isActive)
        XCTAssertEqual(well.deactivations, 1)
        XCTAssertNil(well.target)
        XCTAssertNil(well.action)
    }

    func testColorWellWithoutResolvedInheritanceUsesEmptySwatch() {
        let control = AppKitColorWell(color: .constant(nil), accessibilityLabel: "Wedge color")
        XCTAssertEqual(control.defaultCustomColor, .clear)
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

/// Captures native chooser requests without presenting or modifying desktop UI.
@MainActor
private final class RecordingColorWell: NSColorWell {
    var activations: [Bool] = []
    var deactivations = 0
    private var recordedActive = false
    override var isActive: Bool { recordedActive }

    override func activate(_ exclusive: Bool) {
        activations.append(exclusive)
        recordedActive = true
    }

    override func deactivate() {
        deactivations += 1
        recordedActive = false
    }
}
