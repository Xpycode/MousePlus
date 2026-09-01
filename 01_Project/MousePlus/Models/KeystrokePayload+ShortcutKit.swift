import AppKit
import ShortcutKit

extension KeystrokePayload {
    /// Bridges the app's canonical, display-independent payload to ShortcutKit's
    /// layout-aware recorder value. Unresolved legacy text deliberately remains
    /// unbound: it cannot safely identify a physical key.
    var shortcutKitValue: CustomKeyboardShortcut {
        switch self {
        case let .key(keyCode, modifiers):
            let flags = NSEvent.ModifierFlags(rawValue: modifiers & Self.modifierMask)
            return CustomKeyboardShortcut(
                keyCode: Int(keyCode),
                modifiers: flags,
                displayName: ""
            )
        case .unresolvedLegacy:
            return .none
        }
    }

    init?(shortcutKitValue shortcut: CustomKeyboardShortcut) {
        guard !shortcut.isUnbound,
              (0...Int(UInt16.max)).contains(shortcut.keyCode)
        else { return nil }

        self = .key(
            keyCode: UInt16(shortcut.keyCode),
            modifiers: shortcut.modifiers.rawValue & Self.modifierMask
        )
    }
}

/// Conflict verdict for a keystroke that will be posted into another app.
/// App-responder collisions are useful, common chords (for example Copy/Paste),
/// so they only warn. A system-wide owner can consume the event before the target
/// app and is therefore a reliably unusable selection.
struct KeystrokeConflictAssessment: Equatable {
    enum Severity: Equatable {
        case advisory
        case blocked
    }

    let severity: Severity
    let message: String
}

struct KeystrokeConflictChecker {
    private let systemState: SystemShortcutState

    init(systemState: SystemShortcutState = .live()) {
        self.systemState = systemState
    }

    func assessment(for shortcut: CustomKeyboardShortcut) -> KeystrokeConflictAssessment? {
        guard !shortcut.isUnbound else { return nil }

        if let owner = systemState.owner(of: shortcut, scope: .systemWideOnly) {
            return KeystrokeConflictAssessment(
                severity: .blocked,
                message: "\(shortcut.resolvedDisplayName) is reserved by macOS for “\(owner).”"
            )
        }

        if let owner = systemState.owner(of: shortcut, scope: .all) {
            return KeystrokeConflictAssessment(
                severity: .advisory,
                message: "\(shortcut.resolvedDisplayName) is also used for “\(owner).” It can still be saved."
            )
        }

        return nil
    }
}
