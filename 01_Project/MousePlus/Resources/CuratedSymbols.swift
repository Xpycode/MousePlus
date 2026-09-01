//
//  CuratedSymbols.swift
//  MousePlus
//
//  A zero-dependency, hand-picked catalog of SF Symbol names used to power the
//  discoverability grid in `SymbolField`. Every name here is a well-known symbol
//  that ships with macOS 14 (Sonoma), so the grid never renders blanks.
//
//  This is deliberately curated rather than exhaustive: a small, sensible set is
//  far more useful for picking a menu-item icon than the full ~6000-symbol library.
//

import Foundation

/// Curated SF Symbol catalog, grouped into human-friendly categories.
///
/// Use ``categories`` to drive a sectioned picker grid. All names are validated
/// to exist on macOS 14; if you add to this list, verify with SF Symbols.app or
/// `NSImage(systemSymbolName:accessibilityDescription:)`.
enum CuratedSymbols {

    /// A named group of related SF Symbols.
    struct Category: Identifiable {
        let id = UUID()
        /// Display name shown as the section header in the picker.
        let name: String
        /// SF Symbol names belonging to this category (all macOS 14-available).
        let symbols: [String]
    }

    /// All curated categories, in display order.
    static let categories: [Category] = [
        Category(name: "Apps & Windows", symbols: [
            "app.fill",
            "square.grid.2x2",
            "square.grid.3x3",
            "rectangle.split.2x1",
            "rectangle.3.group",
            "macwindow",
            "dock.rectangle",
            "menubar.rectangle",
        ]),
        Category(name: "Files & Folders", symbols: [
            "folder",
            "folder.fill",
            "doc",
            "doc.fill",
            "doc.on.doc",
            "doc.on.clipboard",
            "doc.text",
            "archivebox",
            "tray",
            "tray.full",
        ]),
        Category(name: "Editing", symbols: [
            "pencil",
            "pencil.circle",
            "scissors",
            "highlighter",
            "trash",
            "trash.fill",
            "square.and.pencil",
            "textformat",
            "paintbrush",
            "eraser",
        ]),
        Category(name: "Media & Playback", symbols: [
            "play.fill",
            "pause.fill",
            "stop.fill",
            "forward.fill",
            "backward.fill",
            "speaker.wave.2.fill",
            "speaker.slash.fill",
            "camera",
            "photo",
            "music.note",
            "film",
        ]),
        Category(name: "Communication", symbols: [
            "envelope",
            "envelope.fill",
            "message",
            "message.fill",
            "phone",
            "phone.fill",
            "bubble.left",
            "paperplane",
            "paperplane.fill",
        ]),
        Category(name: "System & Toggles", symbols: [
            "gearshape",
            "gearshape.fill",
            "wifi",
            "bell",
            "bell.fill",
            "moon.fill",
            "bolt.fill",
            "lock.fill",
            "lock.open.fill",
            "power",
            "battery.100",
            "sun.max.fill",
        ]),
        Category(name: "Computer Activity", symbols: [
            "cpu",
            "memorychip",
            "internaldrive",
            "externaldrive",
            "server.rack",
            "display",
            "desktopcomputer",
            "laptopcomputer",
            "network",
            "wifi.router",
            "antenna.radiowaves.left.and.right",
            "arrow.up.arrow.down",
            "waveform.path.ecg",
            "chart.bar",
            "chart.xyaxis.line",
            "gauge",
            "thermometer.medium",
            "fanblades",
            "bolt.horizontal",
            "cable.connector",
        ]),
        Category(name: "Navigation & Arrows", symbols: [
            "arrow.left",
            "arrow.right",
            "arrow.up",
            "arrow.down",
            "arrow.clockwise",
            "arrow.counterclockwise",
            "arrow.uturn.left",
            "chevron.left",
            "chevron.right",
            "chevron.up",
            "chevron.down",
            "arrow.up.left.and.arrow.down.right",
        ]),
        Category(name: "Shapes & Symbols", symbols: [
            "star.fill",
            "heart.fill",
            "circle.fill",
            "square.fill",
            "triangle.fill",
            "magnifyingglass",
            "terminal",
            "command",
            "globe",
            "safari",
            "tag.fill",
            "flag.fill",
            "bookmark.fill",
            "plus",
            "minus",
            "xmark",
            "checkmark",
        ]),
    ]
}
