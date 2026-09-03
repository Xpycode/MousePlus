import AppKit
import SwiftUI

/// Menu-wide and per-ring HUD controls. All interactive elements are backed by
/// AppKit controls so Settings retains native keyboard and accessibility behavior.
@MainActor
struct HUDCustomizationControls: View {
    @Bindable var model: MenuEditorModel

    private var customization: HUDCustomization { model.hudCustomization }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            hiddenSubmenuWarning

            GroupBox("Menu") {
                VStack(alignment: .leading, spacing: 10) {
                    row("Outer items") {
                        AppKitSegmentedControl(
                            labels: ["Always", "Reveal", "Hidden"],
                            selection: outerVisibilitySelection,
                            tooltips: ["Always visible", "Reveal beyond inner ring", "Always hidden"],
                            minimumSegmentWidth: 58,
                            accessibilityLabel: "Outer ring visibility",
                            accessibilityIdentifier: "hud.menu.outerVisibility"
                        )
                    }
                    orientationRow(
                        title: "Icon direction",
                        selection: menuOrientationSelection,
                        labels: ["Upright", "Radial", "Tangent"],
                        identifier: "hud.menu.orientation"
                    )
                    colorRow("Wedge color", color: menuWedgeColor, identifier: "hud.menu.wedgeColor")
                    colorRow("Icon color", color: menuIconColor, identifier: "hud.menu.iconColor")
                }
                .padding(.vertical, 4)
            }

            GroupBox("\(activeRingName) ring") {
                VStack(alignment: .leading, spacing: 10) {
                    row("Slots") {
                        AppKitSegmentedControl(
                            labels: ["Auto", "Fixed"],
                            selection: activeSlotModeSelection,
                            minimumSegmentWidth: 64,
                            accessibilityLabel: "\(activeRingName) ring slot count mode",
                            accessibilityIdentifier: "hud.\(activeRingID).slotMode"
                        )
                    }

                    if activeLayout.slotCountMode == .fixed {
                        row("Fixed count") {
                            AppKitCountControl(
                                value: activeFixedCount,
                                range: max(1, activeItemCount)...HUDRingLayout.supportedSlotRange.upperBound,
                                accessibilityLabel: "\(activeRingName) ring fixed slot count",
                                accessibilityIdentifier: "hud.\(activeRingID).fixedCount"
                            )
                        }
                        if activeLayout.fixedSlotCount < activeItemCount {
                            Text("Increase the fixed count to at least \(activeItemCount). Items are preserved while this layout is unavailable.")
                                .font(.caption)
                                .foregroundStyle(.orange)
                                .accessibilityIdentifier("hud.\(activeRingID).fixedCount.warning")
                        }
                    }

                    row("Rotation") {
                        HStack(spacing: 8) {
                            AppKitSlider(
                                value: activeAngularOffset,
                                range: 0...359,
                                accessibilityLabel: "\(activeRingName) ring angular offset",
                                accessibilityIdentifier: "hud.\(activeRingID).angularOffset"
                            )
                            .frame(minWidth: 120)
                            Text("\(Int(activeLayout.angularOffset.rounded()))°")
                                .monospacedDigit()
                                .frame(width: 36, alignment: .trailing)
                                .accessibilityLabel("Angular offset \(Int(activeLayout.angularOffset.rounded())) degrees")
                        }
                    }
                    orientationRow(
                        title: "Icon direction",
                        selection: activeOrientationSelection,
                        labels: ["Inherit", "Upright", "Radial", "Tangent"],
                        identifier: "hud.\(activeRingID).orientation"
                    )
                    colorRow("Wedge color", color: activeWedgeColor, identifier: "hud.\(activeRingID).wedgeColor")
                    colorRow("Icon color", color: activeIconColor, identifier: "hud.\(activeRingID).iconColor")
                }
                .padding(.vertical, 4)
            }

            GroupBox("Outer ring") {
                VStack(alignment: .leading, spacing: 10) {
                    orientationRow(
                        title: "Icon direction",
                        selection: outerOrientationSelection,
                        labels: ["Inherit", "Upright", "Radial", "Tangent"],
                        identifier: "hud.outer.orientation"
                    )
                    colorRow("Wedge color", color: outerWedgeColor, identifier: "hud.outer.wedgeColor")
                    colorRow("Icon color", color: outerIconColor, identifier: "hud.outer.iconColor")
                }
                .padding(.vertical, 4)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("hud.customization.controls")
    }

    @ViewBuilder
    private var hiddenSubmenuWarning: some View {
        if customization.outerRingVisibility == .alwaysHidden, model.middle.contains(where: { $0.hasSubItems }) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .accessibilityHidden(true)
                Text("Outer items are hidden, so submenu parents cannot expand.")
                    .font(.caption)
                Spacer()
                AppKitButton(
                    title: "Use Reveal",
                    accessibilityLabel: "Set outer ring visibility to reveal",
                    accessibilityIdentifier: "hud.hiddenSubmenu.useReveal"
                ) {
                    model.hudCustomization.outerRingVisibility = .revealBeyondInnerRing
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Warning: Outer items are hidden, so submenu parents cannot expand")
            .accessibilityIdentifier("hud.hiddenSubmenu.warning")
        }
    }

    private func row<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Text(title).frame(width: 92, alignment: .leading)
            content().frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func orientationRow(title: String, selection: Binding<Int>, labels: [String], identifier: String) -> some View {
        row(title) {
            AppKitSegmentedControl(
                labels: labels,
                selection: selection,
                minimumSegmentWidth: 54,
                accessibilityLabel: "\(orientationScope(for: identifier)) icon direction",
                accessibilityIdentifier: identifier
            )
        }
    }

    private func orientationScope(for identifier: String) -> String {
        switch identifier {
        case "hud.menu.orientation": return "Menu"
        case "hud.outer.orientation": return "Outer ring"
        default: return "\(activeRingName) ring"
        }
    }

    private func colorRow(_ title: String, color: Binding<NSColor?>, identifier: String) -> some View {
        row(title) {
            AppKitColorWell(color: color, accessibilityLabel: title, accessibilityIdentifier: identifier)
        }
    }

    private var activeRingName: String { model.activeBand == .inner ? "Inner" : "Middle" }
    private var activeRingID: String { model.activeBand == .inner ? "inner" : "middle" }
    private var activeItemCount: Int { model.activeBand == .inner ? model.inner.count : model.middle.count }
    private var activeLayout: HUDRingLayout {
        model.activeBand == .inner ? customization.inner.layout : customization.middle.layout
    }

    private var outerVisibilitySelection: Binding<Int> {
        enumBinding(
            values: OuterRingVisibility.allCases,
            get: { customization.outerRingVisibility },
            set: { model.hudCustomization.outerRingVisibility = $0 }
        )
    }

    private var menuOrientationSelection: Binding<Int> {
        enumBinding(values: IconOrientation.allCases, get: { customization.iconOrientation }, set: { model.hudCustomization.iconOrientation = $0 })
    }

    private var activeSlotModeSelection: Binding<Int> {
        enumBinding(values: SlotCountMode.allCases, get: { activeLayout.slotCountMode }) { value in
            mutateActiveRing { $0.layout.slotCountMode = value }
        }
    }

    private var activeFixedCount: Binding<Int> {
        Binding(
            get: { max(activeLayout.fixedSlotCount, activeItemCount) },
            set: { value in mutateActiveRing { $0.layout.fixedSlotCount = max(value, activeItemCount) } }
        )
    }

    private var activeAngularOffset: Binding<Double> {
        Binding(get: { activeLayout.angularOffset }, set: { value in mutateActiveRing { $0.layout.angularOffset = HUDRingLayout.normalizedAngle(value) } })
    }

    private var activeOrientationSelection: Binding<Int> {
        optionalOrientationBinding(get: { activeAppearance.iconOrientation }) { value in
            mutateActiveRing { $0.appearance.iconOrientation = value }
        }
    }

    private var outerOrientationSelection: Binding<Int> {
        optionalOrientationBinding(get: { customization.outerAppearance.iconOrientation }) {
            model.hudCustomization.outerAppearance.iconOrientation = $0
        }
    }

    private var activeAppearance: HUDRingAppearance {
        model.activeBand == .inner ? customization.inner.appearance : customization.middle.appearance
    }

    private var menuWedgeColor: Binding<NSColor?> { colorBinding(get: { customization.wedgeColor }, set: { model.hudCustomization.wedgeColor = $0 }) }
    private var menuIconColor: Binding<NSColor?> { colorBinding(get: { customization.iconColor }, set: { model.hudCustomization.iconColor = $0 }) }
    private var activeWedgeColor: Binding<NSColor?> { colorBinding(get: { activeAppearance.wedgeColor }, set: { value in mutateActiveRing { $0.appearance.wedgeColor = value } }) }
    private var activeIconColor: Binding<NSColor?> { colorBinding(get: { activeAppearance.iconColor }, set: { value in mutateActiveRing { $0.appearance.iconColor = value } }) }
    private var outerWedgeColor: Binding<NSColor?> { colorBinding(get: { customization.outerAppearance.wedgeColor }, set: { model.hudCustomization.outerAppearance.wedgeColor = $0 }) }
    private var outerIconColor: Binding<NSColor?> { colorBinding(get: { customization.outerAppearance.iconColor }, set: { model.hudCustomization.outerAppearance.iconColor = $0 }) }

    private func mutateActiveRing(_ mutation: (inout HUDRingCustomization) -> Void) {
        if model.activeBand == .inner { mutation(&model.hudCustomization.inner) }
        else { mutation(&model.hudCustomization.middle) }
    }

    private func enumBinding<Value: Equatable>(values: [Value], get: @escaping () -> Value, set: @escaping (Value) -> Void) -> Binding<Int> {
        Binding(get: { values.firstIndex(of: get()) ?? 0 }, set: { index in guard values.indices.contains(index) else { return }; set(values[index]) })
    }

    private func optionalOrientationBinding(get: @escaping () -> IconOrientation?, set: @escaping (IconOrientation?) -> Void) -> Binding<Int> {
        Binding(
            get: { get().flatMap { IconOrientation.allCases.firstIndex(of: $0) }.map { $0 + 1 } ?? 0 },
            set: { index in set(index == 0 ? nil : IconOrientation.allCases[index - 1]) }
        )
    }

    private func colorBinding(get: @escaping () -> HUDColor?, set: @escaping (HUDColor?) -> Void) -> Binding<NSColor?> {
        Binding(get: { get()?.nsColor }, set: { set($0.flatMap(HUDColor.init(nsColor:))) })
    }
}
