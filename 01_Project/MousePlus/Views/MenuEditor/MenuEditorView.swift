//
//  MenuEditorView.swift
//  MousePlus
//
//  Reusable, persistence-neutral Menu Items editor workspace.
//

import SwiftUI

/// Reusable, persistence-neutral editor composition embedded in Settings.
struct MenuEditorWorkspace<TrailingToolbar: View>: View {
    @Bindable var model: MenuEditorModel
    var onReset: () -> Void
    @ViewBuilder var trailingToolbar: () -> TrailingToolbar

    @State private var showResetConfirm = false

    var body: some View {
        VStack(spacing: 12) {
            topBar

            // Ring preview (left) and the selected-slot detail form (right) sit
            // side by side in a draggable split, so the fixed ~448pt ring no
            // longer pushes the form below the fold. Matches the project's
            // HSplitView shell convention.
            HSplitView {
                // Left pane: live, click-to-select ring preview. The ring is a
                // fixed-size square, so centering it inside an expanding frame
                // (default .center alignment) keeps it put; the pane min width
                // stops the divider from clipping it when dragged left.
                RingPreviewSelector(model: model)
                    .frame(minWidth: 470, maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.trailing, 8)

                // Right pane: detail form for the selected slot, scrollable so a
                // tall form (long sub-item list) survives a short window height.
                ScrollView {
                    SlotEditorForm(model: model)
                        .padding(.vertical, 4)
                }
                .frame(minWidth: 320, maxWidth: .infinity, maxHeight: .infinity)
            }

            Divider()

            bottomToolbar
        }
        .padding(16)
        .confirmationDialog(
            "Reset Menu Items only? Inner and middle ring items will be replaced with defaults. Triggers, appearance, and behavior will not change. A recoverable backup will be created first.",
            isPresented: $showResetConfirm,
            titleVisibility: .visible
        ) {
            Button("Reset Menu Items", role: .destructive) {
                onReset()
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack {
            // Band selector — also retargets where "Add" inserts.
            AppKitSegmentedControl(
                labels: ["Inner", "Middle"],
                selection: activeBandSelection,
                accessibilityLabel: "Ring band",
                accessibilityIdentifier: "menuItems.band"
            )
            .frame(maxWidth: 220)

            Spacer()

            // Spoke-usage readout for the active band.
            Text("\(model.spokesUsed) of 8 spokes used")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Bottom toolbar

    private var bottomToolbar: some View {
        HStack(spacing: 12) {
            // Add to the active band; disabled (with an inline note) when THAT
            // band is full — the cap is per-band, so a full middle ring must
            // not block adding inner items (and vice versa).
            AppKitButton(
                title: addButtonTitle,
                isEnabled: !model.atCap(for: model.activeBand),
                accessibilityIdentifier: "menuItems.add.\(model.activeBand == .inner ? "inner" : "middle")"
            ) {
                model.addItem(to: model.activeBand)
            }

            if model.atCap(for: model.activeBand) {
                Text("Max 8 spokes")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            AppKitButton(
                title: "Reset Menu Items…",
                accessibilityIdentifier: "menuItems.reset"
            ) {
                showResetConfirm = true
            }

            trailingToolbar()
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
