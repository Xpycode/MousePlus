import AppKit

/// Where a wedge's rendered icon comes from. Runtime-only — `NSImage` must never
/// enter the `Codable` model.
enum IconSource {
    case sfSymbol(String)
    case appIcon(NSImage)
}
