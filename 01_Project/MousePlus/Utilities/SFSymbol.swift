//
//  SFSymbol.swift
//  MousePlus
//
//  Runtime helpers for SF Symbol names — the single source of truth for
//  "is this a real symbol?" and the fallback glyph used when it isn't.
//
//  `Image(systemName:)` is non-failable: an unknown name renders as *nothing*,
//  which on the icon-only inner ring is an invisible, unusable wedge. The menu
//  editor lets users type free-form symbol names (and `config.json` can be
//  hand-edited or carried over from an older build), so ANY name reaching the
//  renderer must pass through `resolved(_:)` first — guaranteeing every wedge
//  draws a real glyph. The editor still flags the bad name in red so the user
//  knows to fix it; this type only guarantees the live ring never goes blank.
//

import AppKit

/// SF Symbol validity + fallback, shared by the renderer and the editor.
enum SFSymbol {

    /// Fallback glyph substituted for an empty or unknown symbol name.
    ///
    /// It is the render backstop, so it must ITSELF always be a valid symbol —
    /// otherwise `resolved` could hand the renderer a blank and defeat its own
    /// purpose. `questionmark.circle` is a long-standing, universally available
    /// name (well predating the macOS 14 floor), so it can never be the missing one.
    static let placeholder = "questionmark.circle"

    /// True iff `name` is a real SF Symbol available on this system.
    ///
    /// `NSImage(systemSymbolName:accessibilityDescription:)` is the only reliable
    /// runtime check — it returns `nil` for unknown names, whereas
    /// `Image(systemName:)` silently renders blank. An empty name is not a valid
    /// symbol (callers that treat empty as "not yet set" handle that themselves).
    static func isValid(_ name: String) -> Bool {
        guard !name.isEmpty else { return false }
        return NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil
    }

    /// The name to actually render: `name` when it's a real symbol, else
    /// ``placeholder``. Call this at every `Image(systemName:)` site that draws a
    /// user-supplied icon so a bad name can never blank the glyph.
    static func resolved(_ name: String) -> String {
        isValid(name) ? name : placeholder
    }
}
