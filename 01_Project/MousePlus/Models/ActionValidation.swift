import Foundation

/// The canonical, side-effect-free action check used by both editing and execution.
enum ActionValidation: Equatable, Sendable {
    case valid
    case invalid(ActionValidationIssue)

    var isValid: Bool {
        if case .valid = self { return true }
        return false
    }

    /// Text suitable for an editor explanation or runtime failure surface.
    var userFacingText: String? {
        guard case .invalid(let issue) = self else { return nil }
        return issue.userFacingText
    }

    static func validate(_ item: RingMenuItem, context: ActionContext = .init()) -> Self {
        if item.hasSubItems {
            return .invalid(.container)
        }

        switch item.actionType {
        case .appSwitch:
            return nonempty(item.actionData)
                ? .valid
                : .invalid(.missingPayload(.appSwitch))

        case .windowSnap:
            guard SnapZone(rawValue: item.actionData) != nil else {
                return .invalid(item.actionData.isEmpty
                    ? .missingPayload(.windowSnap)
                    : .invalidPayload(.windowSnap))
            }
            guard context.frontmostPID != nil else {
                return .invalid(.missingContext(.targetApplication))
            }
            guard context.screenLayout != nil else {
                return .invalid(.missingContext(.screenLayout))
            }
            return .valid

        case .sendKeystroke:
            switch item.keystrokePayload {
            case .key:
                return .valid
            case .unresolvedLegacy:
                return .invalid(.unresolvedLegacyKeystroke)
            case nil:
                return .invalid(.missingPayload(.sendKeystroke))
            }

        case .custom:
            return nonempty(item.actionData)
                ? .valid
                : .invalid(.missingPayload(.custom))

        case .menuBar, .systemToggle, .screenshot:
            return .invalid(.knownUnavailable(item.actionType))

        case .unavailable(let rawValue):
            return .invalid(.unknownUnavailable(rawValue))
        }
    }

    private static func nonempty(_ value: String) -> Bool {
        !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

enum ActionContextRequirement: Equatable, Sendable {
    case targetApplication
    case screenLayout
}

enum ActionValidationIssue: Equatable, Sendable {
    case container
    case missingPayload(ActionType)
    case invalidPayload(ActionType)
    case unresolvedLegacyKeystroke
    case knownUnavailable(ActionType)
    case unknownUnavailable(String)
    case missingContext(ActionContextRequirement)

    /// Every invalid state owns its explanation so callers cannot accidentally
    /// surface a disabled action without telling the user why.
    var userFacingText: String {
        switch self {
        case .container:
            return "Choose one of this item's sub-items to test or run its action."
        case .missingPayload(let type):
            return "\(type.displayName) needs action details before it can run."
        case .invalidPayload(let type):
            return "\(type.displayName) has invalid action details. Choose a valid value."
        case .unresolvedLegacyKeystroke:
            return "This older keystroke could not be migrated safely. Record it again before running it."
        case .knownUnavailable(let type):
            return "\(type.displayName) is not available in this version of MousePlus."
        case .unknownUnavailable(let rawValue):
            let name = rawValue.isEmpty ? "Unknown action" : "Action “\(rawValue)”"
            return "\(name) is not supported by this version of MousePlus."
        case .missingContext(.targetApplication):
            return "No external target application is available for this action."
        case .missingContext(.screenLayout):
            return "Screen information is unavailable for this action."
        }
    }
}
