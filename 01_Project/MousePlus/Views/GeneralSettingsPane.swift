import SwiftUI

struct GeneralSettingsPane: View {
    static let quitAccessibilityIdentifier = "general.quitMousePlus"

    let coordinator: SettingsWorkspaceCoordinator

    var body: some View {
        Form {
            Section("Triggers") {
                Text("Bind the ring to a keyboard shortcut or mouse button — and choose hold-release vs tap-toggle per binding — in Triggers.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Appearance") {
                Text("Ring geometry, dimming, and animation are configured in Ring Appearance.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Diagnostics") {
                Text("Identify Input inspects raw mouse and keyboard events — handy for finding a button's number or checking why a trigger isn't detected.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                AppKitButton(
                    title: "Open Identify Input…",
                    accessibilityIdentifier: "general.openIdentifyInput"
                ) {
                    AppDelegate.showIdentifyInput?()
                }
            }

            Section("Application") {
                Text("Quit MousePlus completely. Your saved configuration will be used the next time you open the app.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                AppKitButton(
                    title: "Quit MousePlus",
                    accessibilityIdentifier: Self.quitAccessibilityIdentifier
                ) {
                    Self.performQuit()
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    static func performQuit() {
        AppDelegate.quitApplication?()
    }
}
