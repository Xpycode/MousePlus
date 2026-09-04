import AppKit
import SwiftUI

/// Menu-wide and per-ring HUD controls, organized into scope-owned tabs. All
/// interactive elements are backed by AppKit controls so Settings retains
/// native keyboard and accessibility behavior.
///
/// The Menu/Inner/Middle/Outer tab is deliberately local UI state, separate
/// from item selection. Browsing a ring's customization never retargets the
/// selected item, while each ring owns its own add action.
@MainActor
struct HUDCustomizationControls: View {
    @Bindable var model: MenuEditorModel
    @State private var tab: Tab = .menu

    private enum Tab: Int, CaseIterable {
        case menu, inner, middle, outer

        var label: String {
            switch self {
            case .menu: return "Menu"
            case .inner: return "Inner"
            case .middle: return "Middle"
            case .outer: return "Outer"
            }
        }
    }

    private var customization: HUDCustomization { model.hudCustomization }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            hiddenSubmenuWarning

            AppKitSegmentedControl(
                labels: Tab.allCases.map(\.label),
                selection: tabSelection,
                minimumSegmentWidth: 64,
                accessibilityLabel: "Menu and rings customization scope",
                accessibilityIdentifier: "hud.customization.tabs"
            )
            .frame(maxWidth: 320)

            Group {
                switch tab {
                case .menu: menuTab
                case .inner: ringTab(.inner)
                case .middle: ringTab(.middle)
                case .outer: outerTab
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("hud.customization.controls")
    }

    private var tabSelection: Binding<Int> {
        Binding(get: { tab.rawValue }, set: { tab = Tab(rawValue: $0) ?? .menu })
    }

    // MARK: - Menu tab

    private var menuTab: some View {
        GroupBox("Menu") {
            VStack(alignment: .leading, spacing: 10) {
                orientationRow(
                    title: "Icon direction",
                    selection: menuOrientationSelection,
                    labels: ["Upright", "Radial", "Tangent"],
                    identifier: "hud.menu.orientation"
                )
                orientationRow(
                    title: "Label direction",
                    selection: menuLabelOrientationSelection,
                    labels: ["Upright", "Radial", "Tangent"],
                    identifier: "hud.menu.labelOrientation"
                )
                colorRow("Wedge color", color: menuWedgeColor, identifier: "hud.menu.wedgeColor", inheritTitle: "Default")
                colorRow("Icon color", color: menuIconColor, identifier: "hud.menu.iconColor", inheritTitle: "Default")

                Text("Menu settings are the application default. Inner, Middle, and Outer can inherit them or override per ring; individual items can override their ring.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("hud.menu.hierarchyHelp")
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Inner / Middle tabs

    private func ringTab(_ band: EditorBand) -> some View {
        let ring = ringCustomization(band)

        return GroupBox("\(ringName(band)) ring") {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("\(ringItemCount(band))/8 items")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    AppKitButton(
                        title: "Add \(ringName(band)) Item",
                        systemImageName: "plus",
                        isEnabled: !model.atCap(for: band),
                        accessibilityIdentifier: "hud.\(ringID(band)).addItem"
                    ) {
                        model.addItem(to: band)
                    }
                    .help(model.atCap(for: band) ? "Maximum 8 items" : "Add \(ringName(band).lowercased()) item")
                }

                row("Slots") {
                    AppKitSegmentedControl(
                        labels: ["Auto", "Fixed"],
                        selection: slotModeSelection(band),
                        minimumSegmentWidth: 64,
                        accessibilityLabel: "\(ringName(band)) ring slot count mode",
                        accessibilityIdentifier: "hud.\(ringID(band)).slotMode"
                    )
                }

                if ring.layout.slotCountMode == .fixed {
                    row("Fixed count") {
                        AppKitCountControl(
                            value: fixedCountBinding(band),
                            range: max(1, ringItemCount(band))...HUDRingLayout.supportedSlotRange.upperBound,
                            accessibilityLabel: "\(ringName(band)) ring fixed slot count",
                            accessibilityIdentifier: "hud.\(ringID(band)).fixedCount"
                        )
                    }
                    if ring.layout.fixedSlotCount < ringItemCount(band) {
                        Text("Increase the fixed count to at least \(ringItemCount(band)). Items are preserved while this layout is unavailable.")
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .accessibilityIdentifier("hud.\(ringID(band)).fixedCount.warning")
                    }
                }

                row("Rotation") {
                    HStack(spacing: 8) {
                        AppKitSlider(
                            value: angularOffsetBinding(band),
                            range: 0...359,
                            accessibilityLabel: "\(ringName(band)) ring angular offset",
                            accessibilityIdentifier: "hud.\(ringID(band)).angularOffset"
                        )
                        .frame(minWidth: 120)
                        Text("\(Int(ring.layout.angularOffset.rounded()))°")
                            .monospacedDigit()
                            .frame(width: 36, alignment: .trailing)
                            .accessibilityLabel("Angular offset \(Int(ring.layout.angularOffset.rounded())) degrees")
                    }
                }
                orientationRow(
                    title: "Icon direction",
                    selection: iconOrientationSelection(band),
                    labels: ["Inherit", "Upright", "Radial", "Tangent"],
                    identifier: "hud.\(ringID(band)).orientation"
                )
                row("Label") {
                    AppKitCheckbox(
                        title: "Show label",
                        isOn: labelVisibleBinding(band),
                        accessibilityLabel: "\(ringName(band)) ring label visibility",
                        accessibilityIdentifier: "hud.\(ringID(band)).labelVisible"
                    )
                }
                orientationRow(
                    title: "Label direction",
                    selection: labelOrientationSelection(band),
                    labels: ["Inherit", "Upright", "Radial", "Tangent"],
                    identifier: "hud.\(ringID(band)).labelOrientation"
                )
                colorRow("Wedge color", color: wedgeColorBinding(band), identifier: "hud.\(ringID(band)).wedgeColor")
                colorRow("Icon color", color: iconColorBinding(band), identifier: "hud.\(ringID(band)).iconColor")
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Outer tab

    private var outerTab: some View {
        GroupBox("Outer ring") {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(outerAddHelp)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    AppKitButton(
                        title: "Add Outer Item",
                        systemImageName: "plus",
                        isEnabled: selectedOuterParentID.map { !model.subItemsAtCap(for: $0) } ?? false,
                        accessibilityIdentifier: "hud.outer.addItem"
                    ) {
                        if let parentID = selectedOuterParentID {
                            model.addSubItem(toMiddle: parentID)
                        }
                    }
                }
                row("Visibility") {
                    AppKitSegmentedControl(
                        labels: ["Always", "Reveal", "Hidden"],
                        selection: outerVisibilitySelection,
                        tooltips: ["Always visible", "Reveal beyond inner ring", "Always hidden"],
                        minimumSegmentWidth: 58,
                        accessibilityLabel: "Outer ring visibility",
                        accessibilityIdentifier: "hud.outer.visibility"
                    )
                }
                orientationRow(
                    title: "Icon direction",
                    selection: outerOrientationSelection,
                    labels: ["Inherit", "Upright", "Radial", "Tangent"],
                    identifier: "hud.outer.orientation"
                )
                row("Label") {
                    AppKitCheckbox(
                        title: "Show label",
                        isOn: outerLabelVisibleBinding,
                        accessibilityLabel: "Outer ring label visibility",
                        accessibilityIdentifier: "hud.outer.labelVisible"
                    )
                }
                orientationRow(
                    title: "Label direction",
                    selection: outerLabelOrientationSelection,
                    labels: ["Inherit", "Upright", "Radial", "Tangent"],
                    identifier: "hud.outer.labelOrientation"
                )
                colorRow("Wedge color", color: outerWedgeColor, identifier: "hud.outer.wedgeColor")
                colorRow("Icon color", color: outerIconColor, identifier: "hud.outer.iconColor")
            }
            .padding(.vertical, 4)
        }
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

    // MARK: - Row helpers

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
                accessibilityLabel: "\(scopeName(for: identifier)) \(title.lowercased())",
                accessibilityIdentifier: identifier
            )
        }
    }

    private func colorRow(_ title: String, color: Binding<NSColor?>, identifier: String, inheritTitle: String = "Inherit") -> some View {
        row(title) {
            AppKitColorWell(
                color: color,
                inheritTitle: inheritTitle,
                accessibilityLabel: "\(scopeName(for: identifier)) \(title.lowercased())",
                accessibilityIdentifier: identifier
            )
        }
    }

    /// Derives an unambiguous accessibility scope name from an identifier's
    /// `hud.<scope>.` prefix, so Menu, Inner, Middle, and Outer controls that
    /// share row titles (e.g. both rings have "Wedge color") remain
    /// distinguishable to VoiceOver even though only one tab renders at a time.
    private func scopeName(for identifier: String) -> String {
        switch true {
        case identifier.hasPrefix("hud.menu."): return "Menu"
        case identifier.hasPrefix("hud.inner."): return "Inner ring"
        case identifier.hasPrefix("hud.middle."): return "Middle ring"
        case identifier.hasPrefix("hud.outer."): return "Outer ring"
        default: return "Ring"
        }
    }

    // MARK: - Ring-scoped state

    private func ringCustomization(_ band: EditorBand) -> HUDRingCustomization {
        band == .inner ? customization.inner : customization.middle
    }

    private func ringName(_ band: EditorBand) -> String { band == .inner ? "Inner" : "Middle" }
    private func ringID(_ band: EditorBand) -> String { band == .inner ? "inner" : "middle" }
    private func ringItemCount(_ band: EditorBand) -> Int { band == .inner ? model.inner.count : model.middle.count }

    /// Outer items belong to a static middle parent rather than to a standalone
    /// ring. Keep the add action explicitly tied to that selected parent.
    private var selectedOuterParentID: UUID? {
        guard let selection = model.selection,
              selection.band == .middle,
              let parentID = selection.itemID,
              let parent = model.middle.first(where: { $0.id == parentID }),
              parent.dynamicSource == .none
        else { return nil }
        return parentID
    }

    private var outerAddHelp: String {
        if let selection = model.selection,
           selection.band == .middle,
           let parentID = selection.itemID,
           let parent = model.middle.first(where: { $0.id == parentID }),
           parent.dynamicSource == .runningApps {
            let label = parent.label.isEmpty ? "This item" : parent.label
            return "\(label) is populated automatically from running apps and cannot have manual outer items."
        }

        guard let parentID = selectedOuterParentID,
              let parent = model.middle.first(where: { $0.id == parentID }) else {
            return "Select a static Middle item to add its outer items."
        }
        if model.subItemsAtCap(for: parentID) { return "Maximum 12 outer items." }
        let label = parent.label.isEmpty ? "selected Middle item" : parent.label
        return "Adds to \(label)."
    }

    private func mutateRing(_ band: EditorBand, _ mutation: (inout HUDRingCustomization) -> Void) {
        if band == .inner { mutation(&model.hudCustomization.inner) }
        else { mutation(&model.hudCustomization.middle) }
    }

    private func slotModeSelection(_ band: EditorBand) -> Binding<Int> {
        enumBinding(values: SlotCountMode.allCases, get: { ringCustomization(band).layout.slotCountMode }) { value in
            mutateRing(band) { $0.layout.slotCountMode = value }
        }
    }

    private func fixedCountBinding(_ band: EditorBand) -> Binding<Int> {
        Binding(
            get: { max(ringCustomization(band).layout.fixedSlotCount, ringItemCount(band)) },
            set: { value in mutateRing(band) { $0.layout.fixedSlotCount = max(value, ringItemCount(band)) } }
        )
    }

    private func angularOffsetBinding(_ band: EditorBand) -> Binding<Double> {
        Binding(
            get: { ringCustomization(band).layout.angularOffset },
            set: { value in mutateRing(band) { $0.layout.angularOffset = HUDRingLayout.normalizedAngle(value) } }
        )
    }

    private func iconOrientationSelection(_ band: EditorBand) -> Binding<Int> {
        optionalOrientationBinding(get: { ringCustomization(band).appearance.iconOrientation }) { value in
            mutateRing(band) { $0.appearance.iconOrientation = value }
        }
    }

    private func labelVisibleBinding(_ band: EditorBand) -> Binding<Bool> {
        Binding(
            get: { ringCustomization(band).appearance.labelVisible },
            set: { value in mutateRing(band) { $0.appearance.labelVisible = value } }
        )
    }

    private func labelOrientationSelection(_ band: EditorBand) -> Binding<Int> {
        optionalLabelOrientationBinding(get: { ringCustomization(band).appearance.labelOrientation }) { value in
            mutateRing(band) { $0.appearance.labelOrientation = value }
        }
    }

    private func wedgeColorBinding(_ band: EditorBand) -> Binding<NSColor?> {
        colorBinding(get: { ringCustomization(band).appearance.wedgeColor }, set: { value in mutateRing(band) { $0.appearance.wedgeColor = value } })
    }

    private func iconColorBinding(_ band: EditorBand) -> Binding<NSColor?> {
        colorBinding(get: { ringCustomization(band).appearance.iconColor }, set: { value in mutateRing(band) { $0.appearance.iconColor = value } })
    }

    // MARK: - Menu-scoped state

    private var menuOrientationSelection: Binding<Int> {
        enumBinding(values: IconOrientation.allCases, get: { customization.iconOrientation }, set: { model.hudCustomization.iconOrientation = $0 })
    }

    private var menuLabelOrientationSelection: Binding<Int> {
        enumBinding(values: LabelOrientation.allCases, get: { customization.labelOrientation }, set: { model.hudCustomization.labelOrientation = $0 })
    }

    private var menuWedgeColor: Binding<NSColor?> { colorBinding(get: { customization.wedgeColor }, set: { model.hudCustomization.wedgeColor = $0 }) }
    private var menuIconColor: Binding<NSColor?> { colorBinding(get: { customization.iconColor }, set: { model.hudCustomization.iconColor = $0 }) }

    // MARK: - Outer-scoped state

    private var outerVisibilitySelection: Binding<Int> {
        enumBinding(
            values: OuterRingVisibility.allCases,
            get: { customization.outerRingVisibility },
            set: { model.hudCustomization.outerRingVisibility = $0 }
        )
    }

    private var outerOrientationSelection: Binding<Int> {
        optionalOrientationBinding(get: { customization.outerAppearance.iconOrientation }) {
            model.hudCustomization.outerAppearance.iconOrientation = $0
        }
    }

    private var outerLabelVisibleBinding: Binding<Bool> {
        Binding(
            get: { customization.outerAppearance.labelVisible },
            set: { model.hudCustomization.outerAppearance.labelVisible = $0 }
        )
    }

    private var outerLabelOrientationSelection: Binding<Int> {
        optionalLabelOrientationBinding(get: { customization.outerAppearance.labelOrientation }) {
            model.hudCustomization.outerAppearance.labelOrientation = $0
        }
    }

    private var outerWedgeColor: Binding<NSColor?> { colorBinding(get: { customization.outerAppearance.wedgeColor }, set: { model.hudCustomization.outerAppearance.wedgeColor = $0 }) }
    private var outerIconColor: Binding<NSColor?> { colorBinding(get: { customization.outerAppearance.iconColor }, set: { model.hudCustomization.outerAppearance.iconColor = $0 }) }

    // MARK: - Binding utilities

    private func enumBinding<Value: Equatable>(values: [Value], get: @escaping () -> Value, set: @escaping (Value) -> Void) -> Binding<Int> {
        Binding(get: { values.firstIndex(of: get()) ?? 0 }, set: { index in guard values.indices.contains(index) else { return }; set(values[index]) })
    }

    private func optionalOrientationBinding(get: @escaping () -> IconOrientation?, set: @escaping (IconOrientation?) -> Void) -> Binding<Int> {
        Binding(
            get: { get().flatMap { IconOrientation.allCases.firstIndex(of: $0) }.map { $0 + 1 } ?? 0 },
            set: { index in set(index == 0 ? nil : IconOrientation.allCases[index - 1]) }
        )
    }

    private func optionalLabelOrientationBinding(get: @escaping () -> LabelOrientation?, set: @escaping (LabelOrientation?) -> Void) -> Binding<Int> {
        Binding(
            get: { get().flatMap { LabelOrientation.allCases.firstIndex(of: $0) }.map { $0 + 1 } ?? 0 },
            set: { index in set(index == 0 ? nil : LabelOrientation.allCases[index - 1]) }
        )
    }

    private func colorBinding(get: @escaping () -> HUDColor?, set: @escaping (HUDColor?) -> Void) -> Binding<NSColor?> {
        Binding(get: { get()?.nsColor }, set: { set($0.flatMap(HUDColor.init(nsColor:))) })
    }
}
