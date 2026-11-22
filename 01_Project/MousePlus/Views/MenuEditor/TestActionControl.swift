import SwiftUI

struct TestActionControl: View {
    let item: RingMenuItem
    let contextAvailability: SettingsActionContextAvailability
    @Bindable var controller: TestActionController
    /// Where the item comes from, e.g. "from Global" or "only in Safari".
    /// `nil` (the Global profile) shows no caption.
    var sourceLabel: String? = nil

    var body: some View {
        let presentation = controller.presentation(
            for: item,
            contextAvailability: contextAvailability
        )
        let displayedResult = controller.displayedResult.flatMap {
            $0.itemID == item.id ? $0 : nil
        }
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                AppKitButton(
                    title: buttonTitle(for: displayedResult),
                    isEnabled: displayedResult != nil || presentation.isEnabled,
                    accessibilityIdentifier: "menuItems.testAction",
                    accessibilityValue: controller.accessibilityValue(
                        for: displayedResult,
                        presentation: presentation,
                        sourceLabel: sourceLabel
                    )
                ) {
                    Task { @MainActor in
                        if displayedResult != nil {
                            await controller.dismissResult()
                        } else {
                            await controller.test(item, contextAvailability: contextAvailability)
                        }
                    }
                }
                .help(displayedResult == nil ? "Run this configured action" : "Dismiss the test result")

                if let targetName = presentation.targetName {
                    Text("Target: \(targetName)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let sourceLabel {
                    Text(sourceLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("menuItems.testAction.source")
                }
            }

            if let explanation = presentation.explanation {
                Text(explanation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let saveFailureMessage = controller.saveFailureMessage {
                Text(saveFailureMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("menuItems.testAction.status")
        .task(id: item.id) {
            await controller.restoreResult(for: item.id)
        }
    }

    private func buttonTitle(for result: SettingsActionResult?) -> String {
        if controller.isRunning { return "Testing…" }
        guard let result else { return "Test Action" }
        return result.result.isSuccess ? "✓ Action completed" : "Action failed — dismiss"
    }
}
