//
//  MenuEditorView.swift
//  MousePlus
//
//  Assembles the dedicated Menu Items editor window content.
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

    /// Drives the "Reset to Defaults" confirmation dialog.
    @State private var showResetConfirm = false

    var body: some View {
        VStack(spacing: 12) {
            topBar

            // Live, click-to-select ring preview. Sized generously so the
            // ~448pt default ring has room; the window stays resizable around it.
            RingPreviewSelector(model: model)
                .frame(maxWidth: .infinity, minHeight: 380)

            Divider()

            // Detail form for the selected slot, scrollable so it survives
            // a short window height.
            ScrollView {
                SlotEditorForm(model: model)
                    .padding(.vertical, 4)
            }

            Divider()

            bottomToolbar
        }
        .padding(16)
        .frame(minWidth: 560, minHeight: 620)
        .confirmationDialog(
            "Reset both rings to the default items? This can't be undone.",
            isPresented: $showResetConfirm,
            titleVisibility: .visible
        ) {
            Button("Reset to Defaults", role: .destructive) {
                model.resetToDefaults()
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
            // Add to the active band; disabled (with an inline note) at cap.
            Button(addButtonTitle) {
                model.addItem(to: model.activeBand)
            }
            .disabled(model.atSpokeCap)

            if model.atSpokeCap {
                Text("Max 8 spokes")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("Reset to Defaults…") {
                showResetConfirm = true
            }

            Button("Done") {
                onDone()
            }
            .keyboardShortcut(.defaultAction)
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
