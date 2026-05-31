//
//  SymbolField.swift
//  MousePlus
//
//  A reusable SwiftUI control for entering and validating an SF Symbol name.
//
//  Features:
//   - Live preview of the entered symbol (or a red placeholder when invalid).
//   - A text field for free-form entry with inline validation feedback.
//   - A "browse" button that opens a curated, sectioned grid popover.
//
//  Validation is performed with `NSImage(systemSymbolName:accessibilityDescription:)`,
//  which is the only reliable runtime check: `Image(systemName:)` is non-failable and
//  silently renders blank for unknown names, so it is used ONLY for the preview.
//

import SwiftUI
import AppKit

/// A field for entering, validating, and visually browsing an SF Symbol name.
struct SymbolField: View {

    /// The currently entered/selected SF Symbol name.
    @Binding var symbolName: String

    /// Whether the curated-grid popover is presented.
    @State private var isPickerPresented = false

    /// `true` when the current name is empty (not yet set) or names a real symbol.
    ///
    /// Empty is treated as "not yet set" rather than invalid, so an untouched field
    /// stays neutral instead of flashing red.
    private var isValid: Bool {
        symbolName.isEmpty || Self.isValidSymbol(symbolName)
    }

    /// `true` only when the user has typed something that is not a real symbol.
    private var showsError: Bool {
        !symbolName.isEmpty && !isValid
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                preview

                TextField("SF Symbol name", text: $symbolName)
                    .textFieldStyle(.roundedBorder)
                    .foregroundStyle(showsError ? Color.red : Color.primary)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(showsError ? Color.red : Color.clear, lineWidth: 1)
                    )

                Button {
                    isPickerPresented.toggle()
                } label: {
                    Image(systemName: "square.grid.2x2")
                }
                .help("Browse symbols")
                .popover(isPresented: $isPickerPresented, arrowEdge: .bottom) {
                    pickerGrid
                }
            }

            if showsError {
                Label("Not a valid SF Symbol", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    // MARK: - Subviews

    /// Live preview of the entered symbol, or a red placeholder when invalid.
    @ViewBuilder
    private var preview: some View {
        Group {
            if symbolName.isEmpty {
                // Neutral placeholder for "not yet set".
                Image(systemName: "questionmark.app.dashed")
                    .foregroundStyle(.secondary)
            } else if isValid {
                Image(systemName: symbolName)
                    .foregroundStyle(.primary)
            } else {
                // Invalid name: explicit red error placeholder.
                Image(systemName: "questionmark.app.dashed")
                    .foregroundStyle(.red)
            }
        }
        .font(.title2)
        .frame(width: 24, height: 24)
    }

    /// The scrollable, sectioned curated-symbol grid shown in the popover.
    private var pickerGrid: some View {
        let columns = [GridItem(.adaptive(minimum: 44), spacing: 4)]

        return ScrollView {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                ForEach(CuratedSymbols.categories) { category in
                    Section {
                        ForEach(category.symbols, id: \.self) { sym in
                            Button {
                                symbolName = sym
                                isPickerPresented = false
                            } label: {
                                Image(systemName: sym)
                                    .font(.title3)
                                    .frame(width: 44, height: 44)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .help(sym)
                        }
                    } header: {
                        Text(category.name)
                            .font(.headline)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 4)
                    }
                }
            }
            .padding(12)
        }
        .frame(width: 320, height: 360)
    }

    // MARK: - Validation

    /// Returns `true` if `name` is a real SF Symbol available on this system.
    ///
    /// Reusable by forms / save-gating so the same validity rule is applied everywhere.
    /// Note: an empty name returns `false` here — empty-as-neutral is a UI concern
    /// handled by ``isValid``, not a statement about symbol validity.
    static func isValidSymbol(_ name: String) -> Bool {
        guard !name.isEmpty else { return false }
        return NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil
    }
}

#Preview {
    struct PreviewWrapper: View {
        @State private var valid = "star.fill"
        @State private var invalid = "not.a.real.symbol"
        @State private var empty = ""

        var body: some View {
            VStack(alignment: .leading, spacing: 16) {
                SymbolField(symbolName: $valid)
                SymbolField(symbolName: $invalid)
                SymbolField(symbolName: $empty)
            }
            .padding()
            .frame(width: 360)
        }
    }
    return PreviewWrapper()
}
