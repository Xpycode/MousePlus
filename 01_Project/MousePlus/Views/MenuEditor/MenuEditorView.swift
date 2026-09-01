//
//  MenuEditorView.swift
//  MousePlus
//
//  Assembles the legacy dedicated Menu Items editor window content.
//
//  This is a PURE composition view: it mutates the supplied `MenuEditorModel`
//  and invokes `onDone()`. It owns no persistence, no services, no timers,
//  and no AppDelegate calls — loading, debounced saving, and live-apply are
//  the responsibility of the window controller that hosts this view.
//

import SwiftUI

struct MenuEditorView: View {
    /// The editor state. Bound so band/selection/item edits flow back out.
    @Bindable var model: MenuEditorModel

    /// Invoked when the user dismisses the editor via the Done button.
    var onDone: () -> Void

    var body: some View {
        MenuEditorWorkspace(
            model: model,
            onReset: { model.resetToDefaults() },
            trailingToolbar: {
                Button("Done") { onDone() }
                    .keyboardShortcut(.defaultAction)
            }
        )
        .frame(minWidth: 900, minHeight: 600)
    }
}

/// Reusable, persistence-neutral editor composition shared by the embedded
/// Settings pane and the legacy editor window until task 4.4 retires it.
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
            "Reset both rings to the default items? This can't be undone.",
            isPresented: $showResetConfirm,
            titleVisibility: .visible
        ) {
            Button("Reset to Defaults", role: .destructive) {
                onReset()
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack {
            // Band selector — also retargets where "Add" inserts.
            Picker("Band", selection: $model.activeBand) {
                Text("Inner").tag(EditorBand.inner)
                Text("Middle").tag(EditorBand.middle)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
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
            Button(addButtonTitle) {
                model.addItem(to: model.activeBand)
            }
            .disabled(model.atCap(for: model.activeBand))

            if model.atCap(for: model.activeBand) {
                Text("Max 8 spokes")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("Reset to Defaults…") {
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
}
