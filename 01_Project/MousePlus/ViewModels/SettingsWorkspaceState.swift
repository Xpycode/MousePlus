import Foundation

struct SettingsWorkspaceState: Equatable {
    enum Reset: Equatable {
        case idle
        case resetting
        case undoAvailable
        case failed(String)
    }

    enum CloseBarrier: Equatable {
        case idle
        case flushing
        case blocked(String)
    }

    enum CloseChoice: Equatable, Sendable {
        case retry
        case discardChanges
        case cancelClose
    }

    var reset: Reset = .idle
    var closeBarrier: CloseBarrier = .idle
    var durableBackupAvailable = false
}
