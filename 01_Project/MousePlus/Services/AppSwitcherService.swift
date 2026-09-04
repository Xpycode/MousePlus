import AppKit

/// A running application entry for the app-switcher wedge.
struct AppEntry: Identifiable, Sendable {
    let id: String              // bundleIdentifier
    let name: String
    let icon: NSImage
    let processIdentifier: pid_t
}

/// Enumerates running regular apps and self-tracks most-recently-activated order.
///
/// No public running-app z-order/MRU API exists on macOS 14 — MRU is self-tracked
/// from `NSWorkspace.didActivateApplicationNotification`, observed starting at
/// `startTrackingMRU()` (called once from app launch) into a bundleID→last-activated
/// map. `runningApps()` sorts MRU-first, falling back to alphabetical for apps never
/// observed activating (e.g. launched before MousePlus).
///
/// `NSWorkspace`/`NSRunningApplication`/`NSImage` reads are hopped to `@MainActor`
/// internally; only the plain `Sendable` `[AppEntry]` value crosses the actor
/// boundary, matching `ActionService`'s `SystemActionWorkspace` pattern
/// (`Services/ActionService.swift`).
actor AppSwitcherService {
    static let maxEntries = 12

    private var lastActivated: [String: Date] = [:]
    private var activationObserver: NSObjectProtocol?

    /// Begins observing app activations. Call once, at app launch. MRU starts
    /// empty until the first observed activation; `runningApps()` falls back to
    /// alphabetical ordering until then.
    func startTrackingMRU() async {
        guard activationObserver == nil else { return }
        activationObserver = await Self.observeActivations { [weak self] bundleIdentifier in
            Task { await self?.recordActivation(of: bundleIdentifier) }
        }
    }

    /// Running regular apps (MousePlus and the invocation's current app
    /// excluded), MRU-first, alphabetical tie-break. Capped at `maxEntries`,
    /// no pagination.
    func runningApps(excluding processIdentifier: pid_t? = nil) async -> [AppEntry] {
        let entries = await Self.currentRunningApps()
        return Array(
            entries
                .filter { $0.processIdentifier != processIdentifier }
                .sorted { isMRUOrdered($0, before: $1) }
                .prefix(Self.maxEntries)
        )
    }

    private func recordActivation(of bundleIdentifier: String) {
        lastActivated[bundleIdentifier] = Date()
    }

    private func isMRUOrdered(_ lhs: AppEntry, before rhs: AppEntry) -> Bool {
        switch (lastActivated[lhs.id], lastActivated[rhs.id]) {
        case let (l?, r?):
            return l > r
        case (.some, nil):
            return true
        case (nil, .some):
            return false
        case (nil, nil):
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    @MainActor
    private static func currentRunningApps() -> [AppEntry] {
        let selfBundleIdentifier = Bundle.main.bundleIdentifier
        return NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != selfBundleIdentifier }
            .compactMap { app -> AppEntry? in
                guard let bundleIdentifier = app.bundleIdentifier,
                      let name = app.localizedName else { return nil }
                return AppEntry(
                    id: bundleIdentifier,
                    name: name,
                    icon: app.icon ?? NSImage(),
                    processIdentifier: app.processIdentifier
                )
            }
    }

    @MainActor
    private static func observeActivations(
        _ handler: @escaping (String) -> Void
    ) -> NSObjectProtocol {
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: NSWorkspace.shared,
            queue: .main
        ) { notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                    as? NSRunningApplication,
                  let bundleIdentifier = app.bundleIdentifier else { return }
            handler(bundleIdentifier)
        }
    }
}
