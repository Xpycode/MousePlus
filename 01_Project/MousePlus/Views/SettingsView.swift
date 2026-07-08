import SwiftUI

/// Settings/Preferences view
struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem {
                    Label("General", systemImage: "gear")
                }

            TriggersSettingsView()
                .tabItem {
                    Label("Triggers", systemImage: "cursorarrow.click.2")
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
        .frame(width: 460, height: 460)
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
    var body: some View {
        Form {
            Section("Triggers") {
                Text("Bind the ring to a keyboard shortcut or mouse button — and choose hold-release vs tap-toggle per binding — in the Triggers tab.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Appearance") {
                Text("Ring geometry, dimming, and animation are configured in the Ring Appearance tab.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Diagnostics") {
                Text("Identify Input inspects raw mouse and keyboard events — handy for finding a button's number or checking why a trigger isn't detected.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button("Open Identify Input…") {
                    AppDelegate.showIdentifyInput?()
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

/// Launcher tab for the standalone Menu Items editor. The full WYSIWYG-lite
/// editor lives in its own resizable window (see `MenuEditorWindowController`),
/// since the Settings content frame is too small for the band picker + ring
/// preview + form. This tab just explains and opens it.
struct MenuSettingsView: View {
    var body: some View {
        Form {
            Section("Menu Items") {
                Text("Customize the inner and middle rings — icons, labels, actions, and each middle wedge's sub-items.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button("Open Menu Editor…") {
                    AppDelegate.showMenuEditor?()
                }
                .controlSize(.large)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

#Preview {
    SettingsView()
}
