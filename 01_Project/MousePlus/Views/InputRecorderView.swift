import SwiftUI

/// Live diagnostic / recorder UI. Reused later for W4 Settings.
struct InputRecorderView: View {
    @Bindable var service: InputRecorderService
    var onDone: () -> Void
    /// Optional escape hatch to open the Settings window. Temporary: the menu-bar
    /// icon is invisible on the M1 Max, so this is currently the only reliable way
    /// into Settings. Remove when the menu-bar-icon bug is fixed.
    var onOpenSettings: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 16) {
            Text("Identify Input")
                .font(.title2.bold())

            Text("Press any key or mouse button to see what MousePlus detects.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)

            mostRecentPanel

            HStack {
                Text("Recent")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Clear") { service.clear() }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 4)

            historyList

            HStack {
                if let onOpenSettings {
                    Button("Settings…") { onOpenSettings() }
                }
                Button("Done") { onDone() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(28)
        .frame(width: 480)
        .onAppear { service.start() }
        .onDisappear { service.stop() }
    }

    private var mostRecentPanel: some View {
        VStack(spacing: 6) {
            if let last = service.lastInput {
                Text(last.primary)
                    .font(.title3.weight(.medium))
                if let mods = last.modifiers {
                    Text(mods).font(.title2.monospaced())
                } else {
                    Text("no modifiers").font(.caption).foregroundStyle(.tertiary)
                }
            } else {
                Text("waiting…")
                    .font(.title3.weight(.medium))
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 90)
        .padding()
        .background(.quinary, in: .rect(cornerRadius: 10))
    }

    private var historyList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(service.history) { item in
                    HStack {
                        Text(item.primary)
                            .font(.system(.body, design: .monospaced))
                        Spacer()
                        if let mods = item.modifiers {
                            Text(mods).font(.body)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(8)
        }
        .frame(height: 160)
        .background(.quinary, in: .rect(cornerRadius: 8))
    }
}
