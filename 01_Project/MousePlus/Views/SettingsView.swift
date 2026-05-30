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

            RingAppearanceSettingsView()
                .tabItem {
                    Label("Ring Appearance", systemImage: "circle.dashed")
                }

            MenuSettingsView()
                .tabItem {
                    Label("Menu Items", systemImage: "circle.hexagongrid")
                }
        }
        .frame(width: 460, height: 420)
    }
}

/// Ring-geometry & rendering settings, persisted via `AppearanceConfig` on disk.
///
/// Loads the full `Configuration` on appear, binds each control to a field of its
/// `appearance`, and writes the whole config back through `ConfigurationService`
/// (debounced) whenever a value changes. Changes apply on the next ring open;
/// if `AppDelegate.applyAppearance` is wired, they also push into the live ring.
struct RingAppearanceSettingsView: View {
    private let configService = ConfigurationService()

    @State private var appearance: AppearanceConfig = .default
    @State private var loaded = false
    @State private var saveTask: Task<Void, Never>?

    var body: some View {
        Form {
            Section("Band Radii") {
                radiusSlider("Dead zone (r0)", value: $appearance.deadZone, range: 8...48)
                radiusSlider("Inner edge (r1)", value: $appearance.innerEdge, range: 40...120)
                radiusSlider("Middle edge (r2)", value: $appearance.middleEdge, range: 90...200)
                radiusSlider("Outer edge (r3)", value: $appearance.outerEdge, range: 150...300)
            }

            Section("Dimming") {
                HStack {
                    Text("Dim opacity")
                    Slider(value: $appearance.dimOpacity, in: 0.0...1.0)
                    Text(String(format: "%.2f", appearance.dimOpacity))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 44, alignment: .trailing)
                }
                Toggle("Keep selected spoke lit", isOn: $appearance.keepSpokeLit)
            }

            Section("Animation") {
                Toggle("Animate ring", isOn: $appearance.animationEnabled)
                HStack {
                    Text("Spring response")
                    Slider(value: $appearance.animationDuration, in: 0.05...0.5)
                    Text(String(format: "%.2fs", appearance.animationDuration))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 52, alignment: .trailing)
                }
                .disabled(!appearance.animationEnabled)
            }
        }
        .formStyle(.grouped)
        .padding()
        .task {
            // Load persisted config once; ignore in-flight edits to avoid clobbering.
            guard !loaded else { return }
            if let config = try? await configService.load() {
                appearance = config.appearance
            }
            loaded = true
        }
        .onChange(of: appearance) { _, newValue in
            guard loaded else { return }   // don't persist the initial load assignment
            scheduleSave(newValue)
        }
    }

    @ViewBuilder
    private func radiusSlider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        HStack {
            Text(title)
            Slider(value: value, in: range)
            Text("\(Int(value.wrappedValue.rounded()))")
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 44, alignment: .trailing)
        }
    }

    /// Debounced save: load the full config, swap in the edited appearance, persist.
    /// Also pushes the new appearance into the live ring if the app wired the hook.
    private func scheduleSave(_ newAppearance: AppearanceConfig) {
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            var config = (try? await configService.load()) ?? Configuration()
            config.appearance = newAppearance
            try? await configService.save(config)
            await MainActor.run {
                AppDelegate.applyAppearance?(newAppearance)
            }
        }
    }
}

struct GeneralSettingsView: View {
    @AppStorage("holdToActivate") private var holdToActivate = true
    @AppStorage("tapToActivate") private var tapToActivate = true

    var body: some View {
        Form {
            Section("Activation") {
                Toggle("Hold hotkey + release to select", isOn: $holdToActivate)
                Toggle("Tap hotkey, click to select", isOn: $tapToActivate)
            }

            Section("Appearance") {
                Text("Ring geometry, dimming, and animation are configured in the Ring Appearance tab.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
