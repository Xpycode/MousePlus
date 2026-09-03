//
//  MenuEditorView.swift
//  MousePlus
//
//  Reusable, persistence-neutral Menu Items editor workspace.
//

import SwiftUI

/// Reusable, persistence-neutral editor composition embedded in Settings.
struct MenuEditorWorkspace<ActionAccessory: View, MenuAccessory: View>: View {
    @Bindable var model: MenuEditorModel
    var onReset: () -> Void
    @ViewBuilder var actionAccessory: () -> ActionAccessory
    @ViewBuilder var menuAccessory: () -> MenuAccessory

    @State private var showResetConfirm = false
    @State private var inspectorSelection = 0

    var body: some View {
        VStack(spacing: 12) {
            // Keep the preview in a fixed column. A resizable HSplitView lets
            // the selected form's changing intrinsic size renegotiate both pane
            // widths, which visibly shifts the ring as selections change.
            HStack(spacing: 12) {
                // The default ring is 448pt square. A stable 480pt column leaves
                // breathing room without coupling its position to the form.
                VStack(spacing: 8) {
                    topBar
                    RingPreviewSelector(model: model)
                        .frame(maxHeight: .infinity)
                }
                .frame(width: 480)
                .frame(maxHeight: .infinity)

                // One inspector uses the available height without competing
                // nested panes. Selecting a wedge routes directly to its editor;
                // menu-wide controls remain one explicit tab away.
                VStack(spacing: 8) {
                    AppKitSegmentedControl(
                        labels: ["Menu & Rings", "Selected Item"],
                        selection: $inspectorSelection,
                        accessibilityLabel: "Menu Items inspector",
                        accessibilityIdentifier: "menuItems.inspector"
                    )
                    .frame(maxWidth: 300)

                    if inspectorSelection == 0 {
                        VStack(spacing: 8) {
                            ScrollView {
                                HUDCustomizationControls(model: model)
                                    .padding(.vertical, 4)
                            }
                            Divider()
                            AppKitButton(
                                title: "Reset Menu Items…",
                                accessibilityIdentifier: "menuItems.reset"
                            ) {
                                showResetConfirm = true
                            }
                            menuAccessory()
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        SlotEditorForm(model: model, actionAccessory: actionAccessory)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .frame(minWidth: 380, maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(16)
        .confirmationDialog(
            "Reset Menu Items and HUD customization? Inner and middle ring items, fixed/automatic slot counts, angular offsets, outer-ring visibility, icon orientations, and menu/ring/item wedge and icon color overrides will return to defaults. Triggers, general appearance, and behavior will not change. A recoverable backup will be created first.",
            isPresented: $showResetConfirm,
            titleVisibility: .visible
        ) {
            Button("Reset Menu Items", role: .destructive) {
                onReset()
            }
            Button("Cancel", role: .cancel) {}
        }
        .onChange(of: model.selection) { oldSelection, newSelection in
            if let newSelection, newSelection != oldSelection {
                inspectorSelection = 1
            }
        }
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack(spacing: 10) {
            // Band selector — also retargets where "Add" inserts.
            AppKitSegmentedControl(
                labels: ["Inner", "Middle"],
                selection: activeBandSelection,
                accessibilityLabel: "Ring band",
                accessibilityIdentifier: "menuItems.band"
            )
            .frame(maxWidth: 220)

            // Keep capacity beside the control it describes instead of using
            // a full-width status row above both inspectors.
            Text("\(model.spokesUsed)/8 used")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer(minLength: 0)

            AppKitButton(
                title: addButtonTitle,
                isEnabled: !model.atCap(for: model.activeBand),
                accessibilityIdentifier: "menuItems.add.\(model.activeBand == .inner ? "inner" : "middle")"
            ) {
                model.addItem(to: model.activeBand)
            }
            .help(model.atCap(for: model.activeBand) ? "Maximum 8 spokes" : addButtonTitle)
        }
    }

    /// Label for the Add button, reflecting the active band.
    private var addButtonTitle: String {
        switch model.activeBand {
        case .inner: return "Add Inner Item"
        case .middle: return "Add Middle Item"
        }
    }

    private var activeBandSelection: Binding<Int> {
        Binding(
            get: { model.activeBand == .inner ? 0 : 1 },
            set: { model.activeBand = $0 == 0 ? .inner : .middle }
        )
    }
}
