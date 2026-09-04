import AppKit
import SwiftUI

/// Manages the menu bar status item
@MainActor
final class MenuBarController {
    static let statusButtonAccessibilityIdentifier = "menuBar.statusItem"
    static let quitMenuItemAccessibilityIdentifier = "menuBar.quitMousePlus"
    static let restartMenuItemAccessibilityIdentifier = "menuBar.restartMousePlus"
    static let statusImageSize = NSSize(width: 18, height: 18)

    private var statusItem: NSStatusItem?

    var onPreferencesClicked: (() -> Void)?
    var onIdentifyInputClicked: (() -> Void)?
    var onQuitClicked: (() -> Void)?
    var onRestartClicked: (() -> Void)?

    func setup() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem?.button {
            button.image = Self.makeStatusImage()
            button.imagePosition = .imageOnly
            button.setAccessibilityLabel("MousePlus menu")
            button.setAccessibilityIdentifier(Self.statusButtonAccessibilityIdentifier)
        }

        setupMenu()
    }

    private func setupMenu() {
        let menu = NSMenu()

        menu.addItem(NSMenuItem(title: "About MousePlus", action: #selector(showAbout), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Preferences...", action: #selector(showPreferences), keyEquivalent: ","))
        menu.addItem(NSMenuItem(title: "Identify Input...", action: #selector(identifyInput), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        let restartItem = NSMenuItem(title: "Restart MousePlus", action: #selector(restart), keyEquivalent: "")
        restartItem.identifier = NSUserInterfaceItemIdentifier(Self.restartMenuItemAccessibilityIdentifier)
        menu.addItem(restartItem)
        let quitItem = NSMenuItem(title: "Quit MousePlus", action: #selector(quit), keyEquivalent: "q")
        quitItem.identifier = NSUserInterfaceItemIdentifier(Self.quitMenuItemAccessibilityIdentifier)
        menu.addItem(quitItem)

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

    @objc private func identifyInput() {
        onIdentifyInputClicked?()
    }

    @objc private func quit() {
        performQuit()
    }

    @objc private func restart() {
        onRestartClicked?()
    }

    static func makeStatusImage() -> NSImage? {
        guard let symbol = NSImage(
            systemSymbolName: "circle.hexagongrid",
            accessibilityDescription: "MousePlus"
        ) else { return nil }

        let configuration = NSImage.SymbolConfiguration(pointSize: statusImageSize.height, weight: .regular)
        let image = symbol.withSymbolConfiguration(configuration) ?? symbol
        image.size = statusImageSize
        image.isTemplate = true
        return image
    }

    /// Testable action entry point used by the menu item's Objective-C action.
    func performQuit() {
        onQuitClicked?()
    }

    /// Testable action entry point used by the menu item's Objective-C action.
    func performRestart() {
        onRestartClicked?()
    }

    func remove() {
        if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
        }
    }
}
