import SwiftUI

/// Settings/Preferences view
struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem {
                    Label("General", systemImage: "gear")
                }

            HotkeySettingsView()
                .tabItem {
                    Label("Hotkey", systemImage: "keyboard")
                }

            MenuSettingsView()
                .tabItem {
                    Label("Menu Items", systemImage: "circle.hexagongrid")
                }
        }
        .frame(width: 450, height: 300)
    }
}

struct GeneralSettingsView: View {
    @AppStorage("animationEnabled") private var animationEnabled = true
    @AppStorage("holdToActivate") private var holdToActivate = true
    @AppStorage("tapToActivate") private var tapToActivate = true

    var body: some View {
        Form {
            Section("Activation") {
                Toggle("Hold hotkey + release to select", isOn: $holdToActivate)
                Toggle("Tap hotkey, click to select", isOn: $tapToActivate)
            }

            Section("Appearance") {
                Toggle("Enable animations", isOn: $animationEnabled)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

struct HotkeySettingsView: View {
    var body: some View {
        Form {
            Section("Current Hotkey") {
                Text("Control + Space")
                    .font(.title2)
                    .foregroundStyle(.secondary)

                Text("Hotkey customization coming soon")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

struct MenuSettingsView: View {
    var body: some View {
        Form {
            Section("Menu Items") {
                Text("Menu item customization coming soon")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

#Preview {
    SettingsView()
}
