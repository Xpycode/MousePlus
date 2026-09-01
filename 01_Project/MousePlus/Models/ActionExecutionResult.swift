import Foundation

/// Presentation-neutral completion from `ActionService`.
enum ActionExecutionResult: Equatable, Sendable {
    case succeeded(message: String)
    case failed(message: String)

    static let completed: Self = .succeeded(message: "Action completed.")

    init(validation: ActionValidation) {
        switch validation {
        case .valid:
            self = .completed
        case .invalid(let issue):
            self = .failed(message: issue.userFacingText)
        }
    }

    var isSuccess: Bool {
        if case .succeeded = self { return true }
        return false
    }

    /// Always non-empty so Settings and the runtime router can present the
    /// result without knowing about action-specific errors.
    var userFacingText: String {
        switch self {
        case .succeeded(let message), .failed(let message): message
        }
    }
}
