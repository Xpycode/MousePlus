import SwiftUI

struct RingAppearanceSettingsPane: View {
    let coordinator: SettingsWorkspaceCoordinator

    var body: some View {
        Form {
            Section("Band Radii") {
                radiusSlider("Dead zone (r0)", keyPath: \.deadZone, range: 8...48)
                radiusSlider("Inner edge (r1)", keyPath: \.innerEdge, range: 40...120)
                radiusSlider("Middle edge (r2)", keyPath: \.middleEdge, range: 90...200)
                radiusSlider("Outer edge (r3)", keyPath: \.outerEdge, range: 150...300)
            }

            Section("Dimming") {
                sliderRow("Dim opacity", keyPath: \.dimOpacity, range: 0...1, valueText: String(format: "%.2f", appearance.dimOpacity))
                AppKitCheckbox(
                    title: "Keep selected spoke lit",
                    isOn: appearanceBinding(\.keepSpokeLit),
                    isEnabled: coordinator.isLoaded,
                    accessibilityIdentifier: "appearance.keepSpokeLit"
                )
            }

            Section("Animation") {
                AppKitCheckbox(
                    title: "Animate ring",
                    isOn: appearanceBinding(\.motion.isEnabled),
                    isEnabled: coordinator.isLoaded,
                    accessibilityIdentifier: "appearance.animationEnabled"
                )
                sliderRow(
                    "Motion speed",
                    keyPath: \.motion.baseDuration,
                    range: 0.05...0.5,
                    isEnabled: motionControlsEnabled,
                    valueText: String(format: "%.2fs", appearance.motion.baseDuration),
                    accessibilityIdentifier: "appearance.motion.baseDuration"
                )
                motionStyleRow(
                    "Opening", keyPath: \.motion.summon,
                    options: [(.off, "Off"), (.fade, "Fade")],
                    accessibilityIdentifier: "appearance.motion.summon"
                )
                motionStyleRow(
                    "Hover", keyPath: \.motion.hover,
                    options: [(.off, "Off"), (.emphasis, "Emphasis")],
                    accessibilityIdentifier: "appearance.motion.hover"
                )
                motionStyleRow(
                    "Outer ring", keyPath: \.motion.outerExpansion,
                    options: [(.off, "Off"), (.radialReveal, "Radial reveal")],
                    accessibilityIdentifier: "appearance.motion.outerExpansion"
                )
                motionStyleRow(
                    "Branch change", keyPath: \.motion.branchChange,
                    options: [(.off, "Off"), (.crossfade, "Crossfade")],
                    accessibilityIdentifier: "appearance.motion.branchChange"
                )
                Text("When macOS Reduce Motion is enabled, spatial motion is replaced with a short fade or an instant update.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("appearance.motion.reduceMotionNote")
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private var appearance: AppearanceConfig { coordinator.configuration.appearance }

    private var motionControlsEnabled: Bool { coordinator.isLoaded && appearance.motion.isEnabled }

    private func appearanceBinding<Value>(_ keyPath: WritableKeyPath<AppearanceConfig, Value>) -> Binding<Value> {
        Binding(
            get: { appearance[keyPath: keyPath] },
            set: { value in
                coordinator.edit([.appearance]) { $0.appearance[keyPath: keyPath] = value }
            }
        )
    }

    private func motionStyleRow<Style: Equatable>(
        _ title: String,
        keyPath: WritableKeyPath<AppearanceConfig, Style>,
        options: [(style: Style, title: String)],
        accessibilityIdentifier: String
    ) -> some View {
        HStack {
            Text(title)
            Spacer()
            AppKitPopup(
                options: options.map(\.title),
                selection: Binding(
                    get: { options.firstIndex { $0.style == appearance[keyPath: keyPath] } ?? 0 },
                    set: { index in
                        guard options.indices.contains(index) else { return }
                        appearanceBinding(keyPath).wrappedValue = options[index].style
                    }
                ),
                isEnabled: motionControlsEnabled,
                accessibilityLabel: title,
                accessibilityIdentifier: accessibilityIdentifier
            )
            .frame(width: 180)
        }
    }

    @ViewBuilder
    private func radiusSlider(
        _ title: String,
        keyPath: WritableKeyPath<AppearanceConfig, Double>,
        range: ClosedRange<Double>
    ) -> some View {
        sliderRow(title, keyPath: keyPath, range: range, valueText: "\(Int(appearance[keyPath: keyPath].rounded()))")
    }

    private func sliderRow(
        _ title: String,
        keyPath: WritableKeyPath<AppearanceConfig, Double>,
        range: ClosedRange<Double>,
        isEnabled: Bool? = nil,
        valueText: String,
        accessibilityIdentifier: String? = nil
    ) -> some View {
        HStack {
            Text(title)
            AppKitSlider(
                value: appearanceBinding(keyPath),
                range: range,
                isEnabled: isEnabled ?? coordinator.isLoaded,
                accessibilityLabel: title,
                accessibilityIdentifier: accessibilityIdentifier ?? "appearance.\(title)"
            )
            Text(valueText)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 52, alignment: .trailing)
        }
    }
}
