import AppKit
import SwiftUI

/// Manages the menu bar status item
@MainActor
final class MenuBarController {
    private var statusItem: NSStatusItem?

    var onPreferencesClicked: (() -> Void)?
    var onQuitClicked: (() -> Void)?

    func setup() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "circle.hexagongrid", accessibilityDescription: "MousePlus")
        }

        setupMenu()
    }

    private func setupMenu() {
        let menu = NSMenu()

        menu.addItem(NSMenuItem(title: "About MousePlus", action: #selector(showAbout), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Preferences...", action: #selector(showPreferences), keyEquivalent: ","))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q"))

        // Set target for menu items
        for item in menu.items {
            item.target = self
        }

        statusItem?.menu = menu
    }

    @objc private func showAbout() {
        NSApp.orderFrontStandardAboutPanel(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func showPreferences() {
        onPreferencesClicked?()
    }

    @objc private func quit() {
        onQuitClicked?()
    }

    func remove() {
        if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
        }
    }
}
