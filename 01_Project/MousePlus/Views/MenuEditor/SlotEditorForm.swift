//
//  SlotEditorForm.swift
//  MousePlus
//
//  The detail form for the currently selected ring slot.
//
//  Renders an empty state when nothing is selected, otherwise a native-feeling
//  `Form` that edits the selected slot's icon, label, action, and (for middle
//  top-level slots only) its inline outer items, plus reorder / delete controls.
//
//  Everything is driven through the model's id-keyed bindings, so a stale
//  selection (slot removed out from under us) degrades gracefully to the empty
//  state rather than trapping.
//

import AppKit
import SwiftUI

/// Detail editor for whatever `model.selection` points at.
struct SlotEditorForm<ActionAccessory: View>: View {

    @Bindable var model: MenuEditorModel
    /// Display name of the App HUD's app, used in the inheritance text
    /// ("Customized for <App>", "Hide in <App>"). Ignored in Global; falls back
    /// to "this app" when an App HUD is edited without a name.
    var appName: String? = nil
    @ViewBuilder var actionAccessory: () -> ActionAccessory
    @State private var labelFocused = false
    /// Width available to the footer row, used to pick a delete title that fits.
    @State private var footerWidth: CGFloat?

    var body: some View {
        Group {
            if let item = itemBinding {
                editor(for: item)
            } else {
                emptyState
            }
        }
        // Slot-scoped controls (focus, popovers, and local AppKit field state)
        // must be recreated when identity changes, rather than bleeding into the
        // item that happens to occupy the same array position.
        .id(model.selection)
        // Each selection intentionally rebuilds slot-scoped AppKit controls.
        // Do not interpolate between forms with different intrinsic heights;
        // that makes the inspector and its scrollbar visibly hop.
        .transaction { transaction in
            transaction.animation = nil
        }
    }

    // MARK: - Current binding resolution

    /// Resolves the editable binding for the current selection.
    ///
    /// Routes through the model's id-keyed bindings (sub-item first, then
    /// top-level), each of which returns `nil` if the slot no longer exists.
    private var itemBinding: Binding<RingMenuItem>? {
        guard let sel = model.selection else { return nil }
        if let subID = sel.subItemID, let parentID = sel.itemID {
            return model.binding(forSubItem: subID, ofMiddle: parentID)
        } else if let id = sel.itemID {
            return model.binding(forItem: id, band: sel.band)
        }
        return nil
    }

    // MARK: - Selection context helpers

    /// `true` when editing a top-level inner slot (no labels rendered in the inner ring).
    private var isInnerTopLevel: Bool {
        model.selection?.band == .inner && model.selection?.subItemID == nil
    }

    /// `true` when editing a top-level middle slot (the only kind that owns sub-items).
    private var isMiddleTopLevel: Bool {
        model.selection?.band == .middle && model.selection?.subItemID == nil
    }

    /// `true` when editing a sub-item (outer arc) of a middle slot.
    private var isSubItem: Bool {
        model.selection?.subItemID != nil
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack {
            Spacer()
            Text("Select a slot in the ring above to edit it.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Editor

    @ViewBuilder
    private func editor(for item: Binding<RingMenuItem>) -> some View {
        Form {
            // 1. Context header. Item actions live together in the footer.
            Section {
                HStack {
                    Text(contextHeader)
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                inheritanceStatusRow
            }

            // 2. Icon + (optional) label.
            Section("Appearance") {
                LabeledContent("Icon") {
                    SymbolField(symbolName: item.icon)
                }

                // Inner top-level slots render no labels, so don't offer the field.
                if !isInnerTopLevel {
                    AppKitTextField(
                        text: item.label,
                        isFocused: $labelFocused,
                        placeholder: "Label",
                        accessibilityLabel: "Label",
                        accessibilityIdentifier: "menuItems.editor.label"
                    )
                }
                itemColorControls(item: item)
            }

            // 3. Action type + type-aware data control. A dynamic parent is a
            // fixed runtime source, not a direct action with editable payload.
            if item.wrappedValue.dynamicSource == .none {
                Section("Action") {
                    ActionDataEditor(item: item)
                    actionAccessory()
                }
            } else {
                dynamicActionSection(parent: item.wrappedValue)
            }

            // 4. Sub-items — editable only for static middle parents. Dynamic
            // parents keep any migrated legacy children inactive and hidden.
            if isMiddleTopLevel, let parentID = model.selection?.itemID {
                if item.wrappedValue.dynamicSource == .none {
                    subItemsSection(parentID: parentID, parent: item)
                } else {
                    dynamicSubItemsSection(parent: item.wrappedValue)
                }
            }

            // 5. Footer controls: selected-item operations stay together.
            Section {
                footerControls
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private func itemColorControls(item: Binding<RingMenuItem>) -> some View {
        if let selection = model.selection,
           let wedgeBinding = colorBinding(for: .wedge),
           let iconBinding = colorBinding(for: .icon) {
            let resolution = model.colorResolution(for: item.wrappedValue, selection: selection)

            LabeledContent("Wedge color") {
                AppKitColorWell(
                    color: wedgeBinding,
                    defaultCustomColor: resolution.requestedWedge.nsColor,
                    accessibilityLabel: "Item wedge color",
                    accessibilityIdentifier: "menuItems.editor.wedgeColor"
                )
            }
            LabeledContent("Icon color") {
                AppKitColorWell(
                    color: iconBinding,
                    defaultCustomColor: resolution.requestedIcon.nsColor,
                    accessibilityLabel: "Item icon color",
                    accessibilityIdentifier: "menuItems.editor.iconColor"
                )
            }

            LabeledContent("Requested") {
                HStack(spacing: 10) {
                    colorSample(resolution.requestedWedge, label: "Requested wedge color")
                    colorSample(resolution.requestedIcon, label: "Requested icon color")
                }
            }

            if resolution.renderedIcon != resolution.requestedIcon
                || (!isInnerTopLevel && resolution.renderedLabel != resolution.requestedLabel) {
                Label {
                    Text(contrastNotice(for: resolution))
                } icon: {
                    Image(systemName: "info.circle")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("menuItems.editor.colorContrastNotice")
            }
        }
    }

    private func colorBinding(for role: RingMenuItem.ColorRole) -> Binding<NSColor?>? {
        guard let selection = model.selection, let itemID = selection.itemID else { return nil }
        if let subItemID = selection.subItemID {
            return model.colorBinding(forSubItem: subItemID, ofMiddle: itemID, role: role)
        }
        return model.colorBinding(forItem: itemID, band: selection.band, role: role)
    }

    private func colorSample(_ color: HUDColor, label: String) -> some View {
        Circle()
            .fill(Color(nsColor: color.nsColor))
            .overlay(Circle().stroke(.secondary, lineWidth: 1))
            .frame(width: 18, height: 18)
            .accessibilityLabel(label)
            .accessibilityValue(colorDescription(color))
    }

    private func colorDescription(_ color: HUDColor) -> String {
        String(
            format: "sRGB red %.0f percent, green %.0f percent, blue %.0f percent, opacity %.0f percent",
            color.red * 100, color.green * 100, color.blue * 100, color.alpha * 100
        )
    }

    private func contrastNotice(for resolution: HUDColorResolver.Resolution) -> String {
        let iconChanged = resolution.renderedIcon != resolution.requestedIcon
        let labelChanged = !isInnerTopLevel && resolution.renderedLabel != resolution.requestedLabel
        switch (iconChanged, labelChanged) {
        case (true, true):
            return "The preview uses contrast-safe icon and label colors. Your requested colors are preserved."
        case (true, false):
            return "The preview uses a contrast-safe icon color. Your requested color is preserved."
        case (false, true):
            return "The preview uses a contrast-safe label color. Your requested color is preserved."
        case (false, false):
            return ""
        }
    }

    // MARK: - Context header

    private var contextHeader: String {
        if isSubItem {
            let parentLabel = parentLabel ?? "slot"
            return "Sub-item of \(parentLabel)"
        }
        switch model.selection?.band {
        case .inner:  return "Selected: Inner slot"
        case .middle: return "Selected: Middle slot"
        case nil:     return "Selected slot"
        }
    }

    /// Label of the parent middle item when editing a sub-item.
    private var parentLabel: String? {
        guard let parentID = model.selection?.itemID else { return nil }
        let label = model.middle.first(where: { $0.id == parentID })?.label
        guard let label, !label.isEmpty else { return nil }
        return label
    }

    // MARK: - Dynamic action

    private func dynamicActionSection(parent: RingMenuItem) -> some View {
        let label = parent.label.isEmpty ? "This item" : parent.label
        return Section("Action") {
            LabeledContent("Type") {
                Text("Running Apps")
            }
            Text("Selecting \(label) opens an automatically generated outer ring of currently running apps.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Outer items section

    private func dynamicSubItemsSection(parent: RingMenuItem) -> some View {
        let label = parent.label.isEmpty ? "This item" : parent.label
        return Section("Outer items") {
            Text("\(label) is populated automatically from running apps and cannot have manual outer items.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func subItemsSection(parentID: UUID, parent: Binding<RingMenuItem>) -> some View {
        let subItems = parent.wrappedValue.subItems ?? []

        Section("Outer items") {
            if subItems.isEmpty {
                Text("No outer items yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(subItems) { sub in
                    HStack(spacing: 8) {
                        Image(systemName: SFSymbol.resolved(sub.icon))
                            .frame(width: 18)
                            .accessibilityHidden(true)
                        AppKitSelectableRow(
                            title: sub.label.isEmpty ? "(no label)" : sub.label,
                            subtitle: sub.actionType.displayName,
                            isSelected: model.selection?.subItemID == sub.id,
                            accessibilityLabel: "Outer wedge, \(sub.label.isEmpty ? "unlabeled" : sub.label), action \(sub.actionType.displayName), \(model.selection?.subItemID == sub.id ? "selected" : "not selected")",
                            accessibilityIdentifier: "menuItems.editor.subItem.\(sub.id.uuidString)"
                        ) {
                            model.selection = SlotSelection(
                                band: .middle,
                                itemID: parentID,
                                subItemID: sub.id
                            )
                        }

                        // Inline delete for this sub-item.
                        AppKitButton(
                            title: "",
                            systemImageName: "minus.circle",
                            accessibilityLabel: "Remove \(sub.label.isEmpty ? "sub-item" : sub.label)"
                        ) {
                            model.removeSubItem(sub.id, fromMiddle: parentID)
                        }
                        .help("Remove this sub-item")
                    }
                }
            }

            if model.subItemsAtCap(for: parentID) {
                Text("Maximum 12 outer items.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Add outer items from Menu & Rings → Outer.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Footer controls

    /// Item operations, in order: Move Earlier · Move Later · Revert Order ·
    /// Delete/Hide (trailing). The flow layout wraps buttons onto further rows
    /// instead of widening the form, and a "Hide in <App>" title that cannot fit
    /// on a row of its own falls back to a short title; the accessibility label
    /// and tooltip keep the full app name.
    @ViewBuilder
    private var footerControls: some View {
        SlotEditorFooterLayout(spacing: 8, rowSpacing: 6) {
            // Reorder is only meaningful for top-level slots (sub-item reorder is
            // out of scope for v1), so hide the move buttons when editing a sub-item.
            if !isSubItem, let sel = model.selection, let id = sel.itemID {
                AppKitButton(
                    title: "Move Earlier",
                    systemImageName: "chevron.left",
                    accessibilityIdentifier: "menuItems.moveEarlier"
                ) {
                    model.moveItem(id: id, in: sel.band, by: -1)
                }
                .help("Move slot earlier")

                AppKitButton(
                    title: "Move Later",
                    systemImageName: "chevron.right",
                    accessibilityIdentifier: "menuItems.moveLater"
                ) {
                    model.moveItem(id: id, in: sel.band, by: 1)
                }
                .help("Move slot later")

                // App HUD only: the ring has its own order (AC12). Always
                // false in Global, so nothing new appears there (AC13).
                if model.hasCustomOrder(band: sel.band) {
                    AppKitButton(
                        title: "Revert Order",
                        systemImageName: "arrow.uturn.backward",
                        accessibilityLabel: "Revert this ring to Global's order",
                        accessibilityIdentifier: "menuItems.revertOrder"
                    ) {
                        model.revertOrder(band: sel.band)
                    }
                    .help("Make this ring follow Global's order again")
                }
            }

            AppKitButton(
                title: fittingDeleteTitle,
                systemImageName: "trash",
                accessibilityLabel: deleteDescription,
                accessibilityIdentifier: "menuItems.delete"
            ) {
                // Hides a Global-linked item in an App HUD; deletes otherwise.
                model.removeSelectedItem()
            }
            .help(deleteDescription)
            .layoutValue(key: SlotEditorFooterTrailing.self, value: true)
        }
        .frame(maxWidth: .infinity)
        .background {
            GeometryReader { proxy in
                Color.clear
                    .onAppear { footerWidth = proxy.size.width }
                    .onChange(of: proxy.size.width) { _, width in footerWidth = width }
            }
        }
    }

    /// The delete/hide title that fits the footer. Until the footer has been
    /// measured, the full title is used.
    private var fittingDeleteTitle: String {
        let full = deleteTitle
        guard deleteHides, let footerWidth, footerWidth > 0 else { return full }
        let needed = SlotEditorFooterLayout.buttonWidth(title: full, systemImageName: "trash")
        return needed <= footerWidth ? full : "Hide in App HUD"
    }

    /// `true` when the selected top-level item is a Global item in an App HUD,
    /// so removing it hides it rather than deleting it (AC10).
    private var deleteHides: Bool {
        guard !isSubItem, let id = model.selection?.itemID else { return false }
        switch model.origin(of: id) {
        case .inherited, .customized: return true
        case .appOnly, nil: return false
        }
    }

    private var deleteTitle: String {
        if isSubItem { return "Delete Outer Item" }
        return deleteHides ? "Hide in \(displayAppName)" : "Delete Item"
    }

    private var deleteDescription: String {
        if isSubItem { return "Delete this outer item" }
        return deleteHides ? "Hide this item in \(displayAppName)" : "Delete this item"
    }

    // MARK: - Inheritance status (App HUD only)

    private var displayAppName: String {
        guard let appName, !appName.isEmpty else { return "this app" }
        return appName
    }

    /// Origin of the selected item. A sub-item reports its top-level parent's
    /// origin, because inheritance is tracked per top-level item. `nil` in Global.
    private var selectedOrigin: (id: UUID, origin: ItemOrigin)? {
        guard model.isEditingAppHUD,
              let id = model.selection?.itemID,
              let origin = model.origin(of: id) else { return nil }
        return (id, origin)
    }

    /// "Follows Global" / "Customized for <App>" / "Only in <App>", plus the
    /// matching action. Absent in Global (AC13). For a sub-item the parent's
    /// status is shown without buttons: the parent is the unit that is
    /// customized or reverted, and acting on it from here would be surprising.
    @ViewBuilder
    private var inheritanceStatusRow: some View {
        if let selected = selectedOrigin {
            let id = selected.id
            let origin = selected.origin
            HStack {
                SlotEditorStatusLabel(
                    text: statusText(for: origin),
                    accessibilityLabel: statusAccessibilityLabel(for: origin),
                    accessibilityIdentifier: "menuItems.editor.inheritance.status"
                )
                Spacer()
                if !isSubItem {
                    switch origin {
                    case .inherited:
                        AppKitButton(
                            title: "Customize",
                            accessibilityLabel: "Customize for \(displayAppName)",
                            accessibilityIdentifier: "menuItems.editor.inheritance.customize"
                        ) {
                            model.customize(id: id)
                        }
                        .help("Make an app copy of this item; later Global edits no longer reach it")
                    case .customized:
                        AppKitButton(
                            title: "Revert to Global",
                            accessibilityLabel: "Revert to Global",
                            accessibilityIdentifier: "menuItems.editor.inheritance.revertToGlobal"
                        ) {
                            model.revertToGlobal(id: id)
                        }
                        .help("Replace this item with the Global item and follow Global again")
                    case .appOnly:
                        EmptyView()
                    }
                }
            }
        }
    }

    private func statusText(for origin: ItemOrigin) -> String {
        switch origin {
        case .inherited: return "Follows Global"
        case .customized: return "Customized for \(displayAppName)"
        case .appOnly: return "Only in \(displayAppName)"
        }
    }

    private func statusAccessibilityLabel(for origin: ItemOrigin) -> String {
        let text = statusText(for: origin)
        return isSubItem ? "Parent item: \(text)" : text
    }
}

/// Native label for the inheritance status so it exposes a stable AppKit
/// accessibility identifier, like the rest of the editor's controls.
private struct SlotEditorStatusLabel: NSViewRepresentable {
    let text: String
    let accessibilityLabel: String
    let accessibilityIdentifier: String

    func makeNSView(context: Context) -> NSTextField {
        NSTextField(labelWithString: text)
    }

    func updateNSView(_ label: NSTextField, context: Context) {
        label.stringValue = text
        label.font = .systemFont(ofSize: NSFont.systemFontSize)
        label.textColor = .secondaryLabelColor
        label.lineBreakMode = .byWordWrapping
        label.maximumNumberOfLines = 0
        label.cell?.wraps = true
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        label.setAccessibilityLabel(accessibilityLabel)
        label.setAccessibilityIdentifier(accessibilityIdentifier)
    }

    /// Wraps a long status ("Customized for Microsoft PowerPoint") within the
    /// offered width instead of reporting a single-line width that widens the form.
    func sizeThatFits(_ proposal: ProposedViewSize, nsView label: NSTextField, context: Context) -> CGSize? {
        guard let width = proposal.width, width.isFinite, width > 0, let cell = label.cell else {
            return nil
        }
        let natural = cell.cellSize
        if natural.width <= width {
            return CGSize(width: ceil(natural.width), height: ceil(natural.height))
        }
        let fitted = cell.cellSize(forBounds: NSRect(x: 0, y: 0, width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: ceil(fitted.height))
    }
}

/// Marks the footer subview that sits at the trailing edge of its row.
private struct SlotEditorFooterTrailing: LayoutValueKey {
    static let defaultValue = false
}

/// Flow layout for the item footer: subviews keep their order and wrap onto a
/// new row when the current one is full, so the footer is never wider than the
/// form column. The trailing-marked subview (Delete/Hide) is right-aligned on
/// whichever row it lands on.
private struct SlotEditorFooterLayout: Layout {
    var spacing: CGFloat
    var rowSpacing: CGFloat

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let maxWidth = proposal.width ?? .infinity
        let rows = makeRows(sizes: sizes, maxWidth: maxWidth)
        let height = rows.map(\.height).reduce(0, +) + rowSpacing * CGFloat(max(rows.count - 1, 0))
        let contentWidth = rows.map(\.width).max() ?? 0
        let width = maxWidth.isFinite ? maxWidth : contentWidth
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let rows = makeRows(sizes: sizes, maxWidth: bounds.width)
        var y = bounds.minY
        for row in rows {
            var x = bounds.minX
            for index in row.indices {
                let size = sizes[index]
                let width = min(size.width, bounds.width)
                let originX = subviews[index][SlotEditorFooterTrailing.self]
                    ? max(x, bounds.maxX - width)
                    : x
                subviews[index].place(
                    at: CGPoint(x: originX, y: y + (row.height - size.height) / 2),
                    anchor: .topLeading,
                    proposal: ProposedViewSize(width: width, height: size.height)
                )
                x = originX + width + spacing
            }
            y += row.height + rowSpacing
        }
    }

    private func makeRows(sizes: [CGSize], maxWidth: CGFloat) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        for (index, size) in sizes.enumerated() {
            let added = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            if !current.indices.isEmpty, added > maxWidth {
                rows.append(current)
                current = Row()
            }
            current.width = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            current.height = max(current.height, size.height)
            current.indices.append(index)
        }
        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }

    /// Natural width of a rounded AppKit button with a leading SF Symbol,
    /// measured with the same configuration `AppKitButton` uses.
    @MainActor
    static func buttonWidth(title: String, systemImageName: String) -> CGFloat {
        let button = NSButton(title: title, target: nil, action: nil)
        button.bezelStyle = .rounded
        button.image = NSImage(systemSymbolName: systemImageName, accessibilityDescription: nil)
        button.imagePosition = .imageLeading
        return ceil(button.fittingSize.width)
    }
}
