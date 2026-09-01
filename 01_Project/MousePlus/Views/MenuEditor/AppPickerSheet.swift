//
//  AppPickerSheet.swift
//  MousePlus
//
//  A searchable picker for installed + running applications. MousePlus is
//  non-sandboxed, so it can freely scan the standard app directories and read
//  `NSWorkspace.shared.runningApplications` without entitlements or bookmarks.
//
//  We persist the *bundle identifier* (not a path) because it survives moves
//  and updates. Resolution back to a URL/icon at display time elsewhere should
//  use `NSWorkspace.shared.urlForApplication(withBundleIdentifier:)`.
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct AppPickerSheet: View {
    /// Called when the user picks an app: (bundleID, displayName, suggestedSFSymbol). The presenter dismisses.
    var onPick: (_ bundleID: String, _ name: String, _ suggestedSymbol: String) -> Void
    /// Called when the user cancels.
    var onCancel: () -> Void

    // MARK: - Row model

    /// One installed/running application, deduped by bundle identifier.
    /// Carries no `NSImage` — icons are resolved lazily per visible row
    /// (see `AppIconView`), so building the full list stays cheap.
    private struct AppEntry: Identifiable {
        let id: String   // bundleID
        let name: String
        let url: URL
    }

    // MARK: - State

    @State private var entries: [AppEntry] = []
    @State private var searchText: String = ""
    @State private var searchFocused = false

    /// The SF Symbol suggested for app-launch ring items. The real app icon is
    /// rendered later via a future IconSource; for now the ring shows a symbol.
    private let suggestedSymbol = "app.fill"

    private var filteredEntries: [AppEntry] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return entries }
        return entries.filter { $0.name.range(of: query, options: .caseInsensitive) != nil }
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            Text("Choose an App")
                .font(.headline)
                .padding(.top, 16)
                .padding(.bottom, 8)

            AppKitTextField(
                text: $searchText,
                isFocused: $searchFocused,
                placeholder: "Search applications…",
                accessibilityLabel: "Search applications"
            )
                .padding(.horizontal, 16)
                .padding(.bottom, 8)

            List(filteredEntries) { entry in
                appRow(entry)
            }
            .listStyle(.inset)

            Divider()

            HStack {
                AppKitButton(title: "Other…") { chooseOther() }
                Spacer()
                AppKitButton(title: "Cancel", action: onCancel)
            }
            .padding(16)
        }
        .frame(width: 420, height: 520)
        .onAppear(perform: loadAppsIfNeeded)
    }

    // MARK: - Row view

    @ViewBuilder
    private func appRow(_ entry: AppEntry) -> some View {
        HStack(spacing: 10) {
            AppIconView(path: entry.url.path)
                .frame(width: 26, height: 26)
            AppKitSelectableRow(
                title: entry.name,
                subtitle: entry.id,
                isSelected: false,
                accessibilityLabel: "Choose \(entry.name)"
            ) {
                pick(entry)
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - Actions

    private func pick(_ entry: AppEntry) {
        onPick(entry.id, entry.name, suggestedSymbol)
    }

    /// Fallback: let the user point at any `.app` bundle directly.
    private func chooseOther() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [UTType.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")

        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let bundleID = Bundle(url: url)?.bundleIdentifier else { return }
        let name = Self.displayName(for: url)
        onPick(bundleID, name, suggestedSymbol)
    }

    // MARK: - Loading

    private func loadAppsIfNeeded() {
        guard entries.isEmpty else { return }
        entries = Self.scanApplications()
    }

    /// Build the merged, deduped, sorted application list.
    private static func scanApplications() -> [AppEntry] {
        let fm = FileManager.default

        var directories: [URL] = [
            URL(fileURLWithPath: "/Applications"),
            URL(fileURLWithPath: "/System/Applications"),
            URL(fileURLWithPath: "/System/Applications/Utilities"),
            fm.homeDirectoryForCurrentUser.appendingPathComponent("Applications"),
        ]
        // Drop directories that don't exist (e.g. ~/Applications may be absent).
        directories = directories.filter { fm.fileExists(atPath: $0.path) }

        var seen = Set<String>()        // bundleIDs already added
        var result: [AppEntry] = []

        // Helper that builds an entry for a candidate .app URL and records it.
        func add(appURL: URL) {
            guard let bundleID = Bundle(url: appURL)?.bundleIdentifier else { return }
            guard !seen.contains(bundleID) else { return }
            seen.insert(bundleID)

            let name = displayName(for: appURL)
            result.append(AppEntry(id: bundleID, name: name, url: appURL))
        }

        // 1. Scan the standard application directories (shallow is enough).
        for dir in directories {
            guard let contents = try? fm.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: [.isApplicationKey],
                options: [.skipsHiddenFiles]
            ) else { continue }

            for url in contents where isApplicationBundle(url) {
                add(appURL: url)
            }
        }

        // 2. Merge in currently running applications not found on disk above.
        for app in NSWorkspace.shared.runningApplications {
            guard let url = app.bundleURL, app.bundleIdentifier != nil else { continue }
            add(appURL: url)
        }

        // 3. Sort by display name, case-insensitive.
        result.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        return result
    }

    /// Returns true when the URL is an application bundle. Prefers the
    /// `isApplication` resource value, falling back to the `.app` extension.
    private static func isApplicationBundle(_ url: URL) -> Bool {
        if let values = try? url.resourceValues(forKeys: [.isApplicationKey]),
           let isApp = values.isApplication {
            return isApp
        }
        return url.pathExtension == "app"
    }

    /// Human-readable name for an app URL, with sensible fallbacks.
    private static func displayName(for url: URL) -> String {
        let fm = FileManager.default
        let displayed = fm.displayName(atPath: url.path)
        if !displayed.isEmpty {
            // `displayName` returns the localized name, often without ".app".
            return displayed.hasSuffix(".app")
                ? String(displayed.dropLast(4))
                : displayed
        }
        return url.deletingPathExtension().lastPathComponent
    }
}

/// Resolves an app's Finder icon lazily, once per row appearance.
///
/// `NSWorkspace.icon(forFile:)` costs a few ms per app; fetching it for every
/// installed app up-front made opening the picker block on hundreds of icon
/// loads. `List` rows are lazy, so resolving here spreads the cost over
/// scrolling and the sheet presents immediately.
private struct AppIconView: View {
    let path: String

    @State private var icon: NSImage?

    var body: some View {
        Group {
            if let icon {
                Image(nsImage: icon)
                    .resizable()
            } else {
                // Reserve the slot so rows don't jump when the icon lands.
                Color.clear
            }
        }
        .task(id: path) {
            icon = NSWorkspace.shared.icon(forFile: path)
        }
    }
}
