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
    @State private var fieldFocused = false

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

                AppKitTextField(
                    text: $symbolName,
                    isFocused: $fieldFocused,
                    placeholder: "SF Symbol name",
                    accessibilityLabel: showsError
                        ? "SF Symbol name, invalid value \(symbolName); placeholder shown"
                        : "SF Symbol name"
                )

                AppKitButton(
                    title: "",
                    systemImageName: "square.grid.2x2",
                    accessibilityLabel: "Browse symbols"
                ) {
                    isPickerPresented.toggle()
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
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(previewAccessibilityLabel)
    }

    /// The scrollable, sectioned curated-symbol grid shown in the popover.
    private var pickerGrid: some View {
        let columns = [GridItem(.adaptive(minimum: 44), spacing: 4)]

        return ScrollView {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                ForEach(CuratedSymbols.categories) { category in
                    Section {
                        ForEach(category.symbols, id: \.self) { sym in
                            AppKitButton(
                                title: "",
                                systemImageName: sym,
                                accessibilityLabel: sym
                            ) {
                                symbolName = sym
                                isPickerPresented = false
                            }
                            .frame(width: 44, height: 44)
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
    /// Thin forwarder to ``SFSymbol/isValid(_:)`` — the single source of truth the
    /// renderer also uses — so the field's red-flag rule and the ring's
    /// placeholder-substitution rule can never disagree about what counts as valid.
    /// Note: an empty name returns `false` here — empty-as-neutral is a UI concern
    /// handled by ``isValid``, not a statement about symbol validity.
    static func isValidSymbol(_ name: String) -> Bool {
        SFSymbol.isValid(name)
    }

    private var previewAccessibilityLabel: String {
        if symbolName.isEmpty { return "No SF Symbol selected; placeholder shown" }
        if showsError { return "Invalid SF Symbol \(symbolName); placeholder shown" }
        return "SF Symbol \(symbolName)"
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
