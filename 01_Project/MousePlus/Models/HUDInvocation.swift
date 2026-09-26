import Foundation

enum HUDInvocationRoute: String, Codable, Equatable, Sendable {
    case contextual
    case global
}

enum HUDProfileReference: Codable, Equatable, Hashable, Sendable {
    case global
    case app(bundleIdentifier: String)
}

/// Stable process context captured before MousePlus presents its panel.
struct FrontmostAppSnapshot: Codable, Equatable, Sendable {
    let processIdentifier: Int32
    let bundleIdentifier: String?
    let localizedName: String?
}

enum HUDProfileResolution: String, Codable, Equatable, Sendable {
    case globalRoute
    case exactAppMatch
    case missingBundleIdentifier
    case mousePlusFrontmost
    case noMatchingProfile
    case unavailableProfile
}

/// Fully resolved, invocation-frozen inputs for the runtime HUD.
struct ResolvedHUDProfile: Equatable {
    let route: HUDInvocationRoute
    let profileReference: HUDProfileReference
    let actionLayout: HUDActionLayout
    let targetApplication: FrontmostAppSnapshot
    let resolution: HUDProfileResolution
}
