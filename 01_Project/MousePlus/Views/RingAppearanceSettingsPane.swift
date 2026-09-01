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
                    isOn: appearanceBinding(\.animationEnabled),
                    isEnabled: coordinator.isLoaded,
                    accessibilityIdentifier: "appearance.animationEnabled"
                )
                sliderRow(
                    "Spring response",
                    keyPath: \.animationDuration,
                    range: 0.05...0.5,
                    isEnabled: coordinator.isLoaded && appearance.animationEnabled,
                    valueText: String(format: "%.2fs", appearance.animationDuration)
                )
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private var appearance: AppearanceConfig { coordinator.configuration.appearance }

    private func appearanceBinding<Value>(_ keyPath: WritableKeyPath<AppearanceConfig, Value>) -> Binding<Value> {
        Binding(
            get: { appearance[keyPath: keyPath] },
            set: { value in
                coordinator.edit([.appearance]) { $0.appearance[keyPath: keyPath] = value }
            }
        )
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
        valueText: String
    ) -> some View {
        HStack {
            Text(title)
            AppKitSlider(
                value: appearanceBinding(keyPath),
                range: range,
                isEnabled: isEnabled ?? coordinator.isLoaded,
                accessibilityLabel: title,
                accessibilityIdentifier: "appearance.\(title)"
            )
            Text(valueText)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 52, alignment: .trailing)
        }
    }
}
