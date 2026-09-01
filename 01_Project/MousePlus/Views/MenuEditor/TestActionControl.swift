import SwiftUI

struct TestActionControl: View {
    let item: RingMenuItem
    let contextAvailability: SettingsActionContextAvailability
    @Bindable var controller: TestActionController

    var body: some View {
        let presentation = controller.presentation(
            for: item,
            contextAvailability: contextAvailability
        )
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                AppKitButton(
                    title: controller.isRunning ? "Testing…" : "Test Action",
                    isEnabled: presentation.isEnabled,
                    accessibilityIdentifier: "menuItems.testAction",
                    accessibilityValue: presentation.explanation ?? (controller.isRunning ? "Testing" : "Ready")
                ) {
                    Task { @MainActor in
                        await controller.test(item, contextAvailability: contextAvailability)
                    }
                }

                if let targetName = presentation.targetName {
                    Text("Target: \(targetName)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
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

            if let result = controller.displayedResult, result.itemID == item.id {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(result.result.userFacingText)
                        .font(.caption)
                        .foregroundStyle(result.result.isSuccess ? .green : .red)
                    AppKitButton(title: "Dismiss", accessibilityIdentifier: "menuItems.testAction.dismiss") {
                        Task { @MainActor in await controller.dismissResult() }
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("menuItems.testAction.status")
        .task(id: item.id) {
            await controller.restoreResult(for: item.id)
        }
    }
}
