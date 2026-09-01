import SwiftUI

/// First-launch sheet that explains the Accessibility requirement and links to System Settings.
/// Auto-advances to a "granted" state when `service.isGranted` flips.
struct PermissionOnboardingView: View {
    @Bindable var service: PermissionsService
    var onDone: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "circle.hexagongrid.fill")
                .font(.system(size: 56, weight: .regular))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)

            Text("Welcome to MousePlus")
                .font(.title2.bold())

            if service.isGranted {
                grantedState
            } else {
                pendingState
            }
        }
        .padding(36)
        .frame(width: 460)
        .onAppear { service.startPolling() }
        .onDisappear { service.stopPolling() }
    }

    private var pendingState: some View {
        VStack(spacing: 14) {
            Text("MousePlus needs Accessibility access to detect your global trigger — a keyboard shortcut or a mouse button — so the ring menu can appear over any app.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            HStack(spacing: 10) {
                Button("Open System Settings") {
                    service.openAccessibilitySettings()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)

                Button("Quit") { NSApp.terminate(nil) }
                    .keyboardShortcut(.cancelAction)
            }

            Text("Find MousePlus under Privacy & Security → Accessibility, then toggle it on. This window will update automatically.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
    }

    private var grantedState: some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 32))
                .foregroundStyle(.green)
                .accessibilityHidden(true)

            Text("Permission granted")
                .font(.headline)

            Text("Continue to Settings to choose your trigger — a keyboard shortcut, a mouse button, or both.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button("Open Settings") { onDone() }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
        }
    }
}
