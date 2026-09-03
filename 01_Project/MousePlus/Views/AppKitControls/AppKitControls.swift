import AppKit
import SwiftUI

/// Shared behavior for app-owned AppKit controls embedded in SwiftUI.
@MainActor
private func configureAccessibility(
    _ view: NSView,
    label: String,
    identifier: String?,
    value: String? = nil
) {
    view.setAccessibilityLabel(label)
    view.setAccessibilityValue(value)
    if let identifier {
        view.setAccessibilityIdentifier(identifier)
    }
}

struct AppKitButton: NSViewRepresentable {
    let title: String
    var systemImageName: String? = nil
    var isEnabled = true
    var accessibilityLabel: String? = nil
    var accessibilityIdentifier: String? = nil
    var accessibilityValue: String? = nil
    let action: @MainActor () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(action: action) }

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(title: title, target: context.coordinator, action: #selector(Coordinator.invoke))
        button.bezelStyle = .rounded
        return button
    }

    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.action = action
        button.title = title
        button.image = systemImageName.flatMap {
            NSImage(systemSymbolName: $0, accessibilityDescription: accessibilityLabel ?? title)
        }
        button.imagePosition = title.isEmpty ? .imageOnly : .imageLeading
        button.isEnabled = isEnabled
        configureAccessibility(
            button,
            label: accessibilityLabel ?? title,
            identifier: accessibilityIdentifier,
            value: accessibilityValue
        )
    }

    @MainActor final class Coordinator: NSObject {
        var action: @MainActor () -> Void
        init(action: @escaping @MainActor () -> Void) { self.action = action }
        @objc func invoke() { action() }
    }
}

struct AppKitCheckbox: NSViewRepresentable {
    let title: String
    @Binding var isOn: Bool
    var isEnabled = true
    var accessibilityLabel: String? = nil
    var accessibilityIdentifier: String? = nil

    func makeCoordinator() -> Coordinator { Coordinator(value: $isOn) }

    func makeNSView(context: Context) -> NSButton {
        NSButton(checkboxWithTitle: title, target: context.coordinator, action: #selector(Coordinator.changed(_:)))
    }

    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.value = $isOn
        button.title = title
        button.state = isOn ? .on : .off
        button.isEnabled = isEnabled
        configureAccessibility(button, label: accessibilityLabel ?? title, identifier: accessibilityIdentifier)
    }

    @MainActor final class Coordinator: NSObject {
        var value: Binding<Bool>
        init(value: Binding<Bool>) { self.value = value }
        @objc func changed(_ sender: NSButton) { value.wrappedValue = sender.state == .on }
    }
}

struct AppKitPopup: NSViewRepresentable {
    let options: [String]
    @Binding var selection: Int
    var isEnabled = true
    var disabledOptions: Set<Int> = []
    var accessibilityLabel: String
    var accessibilityIdentifier: String? = nil

    func makeCoordinator() -> Coordinator { Coordinator(selection: $selection) }

    func makeNSView(context: Context) -> NSPopUpButton {
        let popup = NSPopUpButton(frame: .zero, pullsDown: false)
        popup.target = context.coordinator
        popup.action = #selector(Coordinator.changed(_:))
        return popup
    }

    func updateNSView(_ popup: NSPopUpButton, context: Context) {
        context.coordinator.selection = $selection
        if popup.itemTitles != options {
            popup.removeAllItems()
            popup.addItems(withTitles: options)
        }
        popup.selectItem(at: options.indices.contains(selection) ? selection : -1)
        for index in options.indices {
            popup.item(at: index)?.isEnabled = !disabledOptions.contains(index)
        }
        popup.isEnabled = isEnabled
        configureAccessibility(popup, label: accessibilityLabel, identifier: accessibilityIdentifier)
    }

    @MainActor final class Coordinator: NSObject {
        var selection: Binding<Int>
        init(selection: Binding<Int>) { self.selection = selection }
        @objc func changed(_ sender: NSPopUpButton) { selection.wrappedValue = sender.indexOfSelectedItem }
    }
}

struct AppKitSegmentedControl: NSViewRepresentable {
    let labels: [String]
    @Binding var selection: Int
    var isEnabled = true
    var tooltips: [String]? = nil
    var minimumSegmentWidth: CGFloat = 64
    var accessibilityLabel: String
    var accessibilityIdentifier: String? = nil

    func makeCoordinator() -> Coordinator { Coordinator(selection: $selection) }

    func makeNSView(context: Context) -> NSSegmentedControl {
        let control = NSSegmentedControl(labels: labels, trackingMode: .selectOne, target: context.coordinator, action: #selector(Coordinator.changed(_:)))
        control.segmentStyle = .rounded
        control.setAccessibilityRole(.radioGroup)
        return control
    }

    func updateNSView(_ control: NSSegmentedControl, context: Context) {
        context.coordinator.selection = $selection
        if control.segmentCount != labels.count {
            control.segmentCount = labels.count
        }
        for (index, label) in labels.enumerated() {
            control.setLabel(label, forSegment: index)
            control.setToolTip(tooltips?[safe: index] ?? label, forSegment: index)
            control.setWidth(max(minimumSegmentWidth, measuredSegmentWidth(label)), forSegment: index)
        }
        control.selectedSegment = labels.indices.contains(selection) ? selection : -1
        control.isEnabled = isEnabled
        configureAccessibility(
            control,
            label: accessibilityLabel,
            identifier: accessibilityIdentifier,
            value: labels.indices.contains(selection) ? labels[selection] : "No selection"
        )
    }

    @MainActor final class Coordinator: NSObject {
        var selection: Binding<Int>
        init(selection: Binding<Int>) { self.selection = selection }
        @objc func changed(_ sender: NSSegmentedControl) { selection.wrappedValue = sender.selectedSegment }
    }

    private func measuredSegmentWidth(_ label: String) -> CGFloat {
        ceil((label as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: NSFont.systemFontSize)]).width) + 24
    }
}

/// A native color well paired with an explicit Inherit state.
/// `nil` represents inheritance; switching back to Custom restores the last chosen color.
struct AppKitColorWell: NSViewRepresentable {
    @Binding var color: NSColor?
    var defaultCustomColor: NSColor = .controlAccentColor
    var isEnabled = true
    var accessibilityLabel: String
    var accessibilityIdentifier: String? = nil

    func makeCoordinator() -> Coordinator {
        Coordinator(color: $color, defaultCustomColor: defaultCustomColor)
    }

    func makeNSView(context: Context) -> NSStackView {
        let inherit = NSButton(
            checkboxWithTitle: "Inherit",
            target: context.coordinator,
            action: #selector(Coordinator.inheritChanged(_:))
        )
        let well = NSColorWell()
        well.target = context.coordinator
        well.action = #selector(Coordinator.colorChanged(_:))
        well.colorWellStyle = .minimal
        let stack = NSStackView(views: [inherit, well])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 8
        context.coordinator.inheritButton = inherit
        context.coordinator.colorWell = well
        return stack
    }

    func updateNSView(_ stack: NSStackView, context: Context) {
        context.coordinator.color = $color
        context.coordinator.defaultCustomColor = defaultCustomColor
        let inherits = color == nil
        if let color { context.coordinator.lastCustomColor = color }
        context.coordinator.inheritButton?.state = inherits ? .on : .off
        context.coordinator.inheritButton?.isEnabled = isEnabled
        context.coordinator.colorWell?.isEnabled = isEnabled && !inherits
        context.coordinator.colorWell?.color = color ?? context.coordinator.lastCustomColor
        configureAccessibility(
            stack,
            label: accessibilityLabel,
            identifier: accessibilityIdentifier,
            value: inherits ? "Inherit" : "Custom"
        )
        if let identifier = accessibilityIdentifier {
            context.coordinator.inheritButton?.setAccessibilityIdentifier("\(identifier).inherit")
            context.coordinator.colorWell?.setAccessibilityIdentifier("\(identifier).color")
        }
        context.coordinator.inheritButton?.setAccessibilityLabel("Inherit \(accessibilityLabel)")
        context.coordinator.colorWell?.setAccessibilityLabel(accessibilityLabel)
    }

    @MainActor final class Coordinator: NSObject {
        var color: Binding<NSColor?>
        var defaultCustomColor: NSColor
        var lastCustomColor: NSColor
        weak var inheritButton: NSButton?
        weak var colorWell: NSColorWell?

        init(color: Binding<NSColor?>, defaultCustomColor: NSColor) {
            self.color = color
            self.defaultCustomColor = defaultCustomColor
            self.lastCustomColor = color.wrappedValue ?? defaultCustomColor
        }

        @objc func inheritChanged(_ sender: NSButton) {
            if sender.state == .on {
                if let current = color.wrappedValue { lastCustomColor = current }
                color.wrappedValue = nil
                colorWell?.isEnabled = false
            } else {
                let restored = lastCustomColor
                color.wrappedValue = restored
                colorWell?.color = restored
                colorWell?.isEnabled = true
            }
        }

        @objc func colorChanged(_ sender: NSColorWell) {
            lastCustomColor = sender.color
            color.wrappedValue = sender.color
        }
    }
}

/// Compact native integer input. Text entry and the stepper share one clamped binding.
struct AppKitCountControl: NSViewRepresentable {
    @Binding var value: Int
    let range: ClosedRange<Int>
    var isEnabled = true
    var accessibilityLabel: String
    var accessibilityIdentifier: String? = nil

    func makeCoordinator() -> Coordinator { Coordinator(value: $value, range: range) }

    func makeNSView(context: Context) -> NSStackView {
        let field = NSTextField()
        field.alignment = .right
        field.formatter = NumberFormatter.integerFormatter(range: range)
        field.delegate = context.coordinator
        field.frame.size.width = 44
        field.setContentHuggingPriority(.required, for: .horizontal)
        let stepper = NSStepper()
        stepper.target = context.coordinator
        stepper.action = #selector(Coordinator.stepperChanged(_:))
        let stack = NSStackView(views: [field, stepper])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 4
        context.coordinator.field = field
        context.coordinator.stepper = stepper
        return stack
    }

    func updateNSView(_ stack: NSStackView, context: Context) {
        context.coordinator.value = $value
        context.coordinator.range = range
        let clamped = min(max(value, range.lowerBound), range.upperBound)
        context.coordinator.field?.integerValue = clamped
        context.coordinator.field?.isEnabled = isEnabled
        context.coordinator.stepper?.minValue = Double(range.lowerBound)
        context.coordinator.stepper?.maxValue = Double(range.upperBound)
        context.coordinator.stepper?.integerValue = clamped
        context.coordinator.stepper?.isEnabled = isEnabled
        configureAccessibility(stack, label: accessibilityLabel, identifier: accessibilityIdentifier, value: String(clamped))
        if let identifier = accessibilityIdentifier {
            context.coordinator.field?.setAccessibilityIdentifier("\(identifier).field")
            context.coordinator.stepper?.setAccessibilityIdentifier("\(identifier).stepper")
        }
        context.coordinator.field?.setAccessibilityLabel(accessibilityLabel)
        context.coordinator.stepper?.setAccessibilityLabel("Adjust \(accessibilityLabel)")
    }

    @MainActor final class Coordinator: NSObject, NSTextFieldDelegate {
        var value: Binding<Int>
        var range: ClosedRange<Int>
        weak var field: NSTextField?
        weak var stepper: NSStepper?

        init(value: Binding<Int>, range: ClosedRange<Int>) {
            self.value = value
            self.range = range
        }

        @objc func stepperChanged(_ sender: NSStepper) { commit(sender.integerValue) }

        func controlTextDidEndEditing(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            commit(field.integerValue)
        }

        func control(_ control: NSControl, textShouldEndEditing fieldEditor: NSText) -> Bool {
            guard Int(fieldEditor.string) != nil else {
                NSSound.beep()
                return false
            }
            return true
        }

        private func commit(_ proposed: Int) {
            let clamped = min(max(proposed, range.lowerBound), range.upperBound)
            value.wrappedValue = clamped
            field?.integerValue = clamped
            stepper?.integerValue = clamped
        }
    }
}

private extension Collection {
    subscript(safe index: Index) -> Element? { indices.contains(index) ? self[index] : nil }
}

private extension NumberFormatter {
    static func integerFormatter(range: ClosedRange<Int>) -> NumberFormatter {
        let formatter = NumberFormatter()
        formatter.allowsFloats = false
        formatter.minimum = NSNumber(value: range.lowerBound)
        formatter.maximum = NSNumber(value: range.upperBound)
        return formatter
    }
}

struct AppKitSlider: NSViewRepresentable {
    @Binding var value: Double
    let range: ClosedRange<Double>
    var isEnabled = true
    var accessibilityLabel: String
    var accessibilityIdentifier: String? = nil

    func makeCoordinator() -> Coordinator { Coordinator(value: $value) }

    func makeNSView(context: Context) -> NSSlider {
        NSSlider(value: value, minValue: range.lowerBound, maxValue: range.upperBound, target: context.coordinator, action: #selector(Coordinator.changed(_:)))
    }

    func updateNSView(_ slider: NSSlider, context: Context) {
        context.coordinator.value = $value
        slider.minValue = range.lowerBound
        slider.maxValue = range.upperBound
        slider.doubleValue = value
        slider.isEnabled = isEnabled
        configureAccessibility(slider, label: accessibilityLabel, identifier: accessibilityIdentifier)
    }

    @MainActor final class Coordinator: NSObject {
        var value: Binding<Double>
        init(value: Binding<Double>) { self.value = value }
        @objc func changed(_ sender: NSSlider) { value.wrappedValue = sender.doubleValue }
    }
}

struct AppKitTextField: NSViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool
    var placeholder: String? = nil
    var isEnabled = true
    var accessibilityLabel: String
    var accessibilityIdentifier: String? = nil

    func makeCoordinator() -> Coordinator { Coordinator(text: $text, isFocused: $isFocused) }

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.delegate = context.coordinator
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.text = $text
        context.coordinator.isFocused = $isFocused
        if field.stringValue != text { field.stringValue = text }
        field.placeholderString = placeholder
        field.isEnabled = isEnabled
        configureAccessibility(field, label: accessibilityLabel, identifier: accessibilityIdentifier)
        if isFocused, field.window?.firstResponder !== field.currentEditor() {
            field.window?.makeFirstResponder(field)
        } else if !isFocused, field.window?.firstResponder === field.currentEditor() {
            field.window?.makeFirstResponder(nil)
        }
    }

    @MainActor final class Coordinator: NSObject, NSTextFieldDelegate {
        var text: Binding<String>
        var isFocused: Binding<Bool>
        init(text: Binding<String>, isFocused: Binding<Bool>) { self.text = text; self.isFocused = isFocused }
        func controlTextDidBeginEditing(_ notification: Notification) { isFocused.wrappedValue = true }
        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            text.wrappedValue = field.stringValue
        }
        func controlTextDidEndEditing(_ notification: Notification) { isFocused.wrappedValue = false }
    }
}

struct AppKitMultilineTextField: NSViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool
    var isEnabled = true
    var accessibilityLabel: String
    var accessibilityIdentifier: String? = nil

    func makeCoordinator() -> Coordinator { Coordinator(text: $text, isFocused: $isFocused) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        let textView = NSTextView()
        textView.isRichText = false
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.delegate = context.coordinator
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        context.coordinator.text = $text
        context.coordinator.isFocused = $isFocused
        if textView.string != text { textView.string = text }
        textView.isEditable = isEnabled
        configureAccessibility(textView, label: accessibilityLabel, identifier: accessibilityIdentifier)
        if isFocused, textView.window?.firstResponder !== textView {
            textView.window?.makeFirstResponder(textView)
        } else if !isFocused, textView.window?.firstResponder === textView {
            textView.window?.makeFirstResponder(nil)
        }
    }

    @MainActor final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        var isFocused: Binding<Bool>
        init(text: Binding<String>, isFocused: Binding<Bool>) { self.text = text; self.isFocused = isFocused }
        func textDidBeginEditing(_ notification: Notification) { isFocused.wrappedValue = true }
        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text.wrappedValue = textView.string
        }
        func textDidEndEditing(_ notification: Notification) { isFocused.wrappedValue = false }
    }
}

struct AppKitSelectableRow: NSViewRepresentable {
    let title: String
    var subtitle: String? = nil
    let isSelected: Bool
    var isEnabled = true
    var accessibilityLabel: String? = nil
    var accessibilityIdentifier: String? = nil
    let action: @MainActor () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(action: action) }

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(title: title, target: context.coordinator, action: #selector(Coordinator.invoke))
        button.bezelStyle = .recessed
        button.setButtonType(.toggle)
        button.alignment = .left
        return button
    }

    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.action = action
        button.title = subtitle.map { "\(title)\n\($0)" } ?? title
        button.state = isSelected ? .on : .off
        button.isEnabled = isEnabled
        configureAccessibility(
            button,
            label: accessibilityLabel ?? title,
            identifier: accessibilityIdentifier,
            value: isSelected ? "Selected" : "Not selected"
        )
    }

    @MainActor final class Coordinator: NSObject {
        var action: @MainActor () -> Void
        init(action: @escaping @MainActor () -> Void) { self.action = action }
        @objc func invoke() { action() }
    }
}
