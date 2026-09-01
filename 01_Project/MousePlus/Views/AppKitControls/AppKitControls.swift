import AppKit
import SwiftUI

/// Shared behavior for app-owned AppKit controls embedded in SwiftUI.
@MainActor
private func configureAccessibility(
    _ view: NSView,
    label: String,
    identifier: String?
) {
    view.setAccessibilityLabel(label)
    if let identifier {
        view.setAccessibilityIdentifier(identifier)
    }
}

struct AppKitButton: NSViewRepresentable {
    let title: String
    var isEnabled = true
    var accessibilityLabel: String? = nil
    var accessibilityIdentifier: String? = nil
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
        button.isEnabled = isEnabled
        configureAccessibility(button, label: accessibilityLabel ?? title, identifier: accessibilityIdentifier)
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
    var accessibilityLabel: String
    var accessibilityIdentifier: String? = nil

    func makeCoordinator() -> Coordinator { Coordinator(selection: $selection) }

    func makeNSView(context: Context) -> NSSegmentedControl {
        let control = NSSegmentedControl(labels: labels, trackingMode: .selectOne, target: context.coordinator, action: #selector(Coordinator.changed(_:)))
        control.segmentStyle = .rounded
        return control
    }

    func updateNSView(_ control: NSSegmentedControl, context: Context) {
        context.coordinator.selection = $selection
        if control.segmentCount != labels.count {
            control.segmentCount = labels.count
        }
        for (index, label) in labels.enumerated() { control.setLabel(label, forSegment: index) }
        control.selectedSegment = labels.indices.contains(selection) ? selection : -1
        control.isEnabled = isEnabled
        configureAccessibility(control, label: accessibilityLabel, identifier: accessibilityIdentifier)
    }

    @MainActor final class Coordinator: NSObject {
        var selection: Binding<Int>
        init(selection: Binding<Int>) { self.selection = selection }
        @objc func changed(_ sender: NSSegmentedControl) { selection.wrappedValue = sender.selectedSegment }
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
        button.setAccessibilityValue(isSelected ? "Selected" : "Not selected")
        configureAccessibility(button, label: accessibilityLabel ?? title, identifier: accessibilityIdentifier)
    }

    @MainActor final class Coordinator: NSObject {
        var action: @MainActor () -> Void
        init(action: @escaping @MainActor () -> Void) { self.action = action }
        @objc func invoke() { action() }
    }
}
