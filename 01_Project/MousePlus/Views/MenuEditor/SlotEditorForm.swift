//
//  SlotEditorForm.swift
//  MousePlus
//
//  The detail form for the currently selected ring slot.
//
//  Renders an empty state when nothing is selected, otherwise a native-feeling
//  `Form` that edits the selected slot's icon, label, action, and (for middle
//  top-level slots only) its inline sub-items, plus reorder / delete controls.
//
//  Everything is driven through the model's id-keyed bindings, so a stale
//  selection (slot removed out from under us) degrades gracefully to the empty
//  state rather than trapping.
//

import SwiftUI

/// Detail editor for whatever `model.selection` points at.
struct SlotEditorForm: View {

    @Bindable var model: MenuEditorModel
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
            // 1. Context header.
            Section {
                Text(contextHeader)
                    .font(.headline)
                    .foregroundStyle(.secondary)
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
            }

            // 3. Action type + type-aware data control.
            Section("Action") {
                ActionDataEditor(item: item)
            }

            // 4. Sub-items — middle top-level only (depth cap 3).
            if isMiddleTopLevel, let parentID = model.selection?.itemID {
                subItemsSection(parentID: parentID, parent: item)
            }

            // 5. Footer controls: reorder + delete.
            Section {
                footerControls
            }
        }
        .formStyle(.grouped)
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

    // MARK: - Sub-items section

    @ViewBuilder
    private func subItemsSection(parentID: UUID, parent: Binding<RingMenuItem>) -> some View {
        let subItems = parent.wrappedValue.subItems ?? []

        Section("Sub-items (outer arc)") {
            if subItems.isEmpty {
                Text("No sub-items yet.")
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

            AppKitButton(
                title: "Add Sub-item",
                systemImageName: "plus",
                isEnabled: !model.subItemsAtCap(for: parentID),
                accessibilityIdentifier: "menuItems.addSubItem"
            ) {
                model.addSubItem(toMiddle: parentID)
            }

            if model.subItemsAtCap(for: parentID) {
                Text("Maximum sub-items reached.")
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
                title: "Delete",
                systemImageName: "trash",
                accessibilityLabel: "Delete this slot",
                accessibilityIdentifier: "menuItems.delete"
            ) {
                model.removeSelectedItem()
            }
            .help("Delete this slot")
        }
    }
}
