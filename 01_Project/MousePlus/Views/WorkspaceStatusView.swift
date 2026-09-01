import SwiftUI

struct WorkspaceStatusPresentation: Equatable {
    let title: String
    let detail: String?
    let isFailure: Bool
    let canRetry: Bool

    init(status: SettingsWorkspaceCoordinator.Status) {
        switch status {
        case .idle: (title, detail, isFailure, canRetry) = ("Not Loaded", nil, false, false)
        case .loading: (title, detail, isFailure, canRetry) = ("Loading…", nil, false, false)
        case .saving: (title, detail, isFailure, canRetry) = ("Saving…", nil, false, false)
        case .saved: (title, detail, isFailure, canRetry) = ("Saved", nil, false, false)
        case .saveFailed(let message):
            (title, detail, isFailure, canRetry) = ("Save Failed", message, true, true)
        case .loadFailed(let message):
            (title, detail, isFailure, canRetry) = ("Load Failed", message, true, true)
        }
    }
}

struct WorkspaceStatusView: View {
    let status: SettingsWorkspaceCoordinator.Status
    let retry: @MainActor () -> Void

    private var presentation: WorkspaceStatusPresentation { .init(status: status) }

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .trailing, spacing: 2) {
                Text(presentation.title)
                    .foregroundStyle(presentation.isFailure ? .red : .secondary)
                if let detail = presentation.detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .help(detail)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(presentation.title)
            .accessibilityValue(presentation.detail ?? presentation.title)
            .accessibilityIdentifier("workspace.status")

            if presentation.canRetry {
                AppKitButton(
                    title: "Retry",
                    accessibilityIdentifier: "workspace.status.retry",
                    action: retry
                )
            }
        }
    }
}
