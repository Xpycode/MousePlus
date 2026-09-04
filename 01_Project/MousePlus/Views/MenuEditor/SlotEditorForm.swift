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
    @ViewBuilder var actionAccessory: () -> ActionAccessory
    @State private var labelFocused = false

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

    @ViewBuilder
    private var footerControls: some View {
        HStack {
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
            }

            Spacer()

            AppKitButton(
                title: isSubItem ? "Delete Outer Item" : "Delete Item",
                systemImageName: "trash",
                accessibilityLabel: isSubItem ? "Delete this outer item" : "Delete this item",
                accessibilityIdentifier: "menuItems.delete"
            ) {
                model.removeSelectedItem()
            }
            .help(isSubItem ? "Delete this outer item" : "Delete this item")
        }
    }
}
