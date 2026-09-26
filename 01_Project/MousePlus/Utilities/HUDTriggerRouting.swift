import AppKit
import Foundation

/// A conflict that would make the two HUD keyboard routes indistinguishable.
enum HUDTriggerBindingCollision: Equatable, Sendable {
    case contextualKeyboard

    var explanation: String {
        switch self {
        case .contextualKeyboard:
            "Contextual keyboard trigger and Global HUD Shortcut must use different key combinations."
        }
    }
}

/// Result of validating either keyboard slot. Rejection explicitly returns the
/// old value so callers cannot accidentally persist the ambiguous candidate.
enum HUDShortcutBindingUpdate: Equatable, Sendable {
    case accepted(TriggerBinding)
    case rejected(collision: HUDTriggerBindingCollision, retained: TriggerBinding)
}

/// Pure policy shared by Settings and runtime monitor configuration.
enum HUDTriggerRouting {
    private static let chordModifierMask = NSEvent.ModifierFlags([
        .control, .option, .shift, .command,
    ]).rawValue

    static func normalizedChordModifiers(_ modifiers: UInt) -> UInt {
        modifiers & chordModifierMask
    }

    static func keyboardEventMatches(
        keyCode eventKeyCode: UInt16,
        modifiers eventModifiers: UInt,
        bindingKeyCode: UInt16,
        bindingModifiers: UInt
    ) -> Bool {
        eventKeyCode == bindingKeyCode
            && normalizedChordModifiers(eventModifiers)
                == normalizedChordModifiers(bindingModifiers)
    }

    static func collision(
        globalHUDShortcut: TriggerBinding,
        contextualKeyboard: TriggerBinding
    ) -> HUDTriggerBindingCollision? {
        guard case let .keyboard(globalKeyCode, globalModifiers, _) = globalHUDShortcut,
              case let .keyboard(contextualKeyCode, contextualModifiers, _) = contextualKeyboard,
              globalKeyCode == contextualKeyCode,
              normalizedChordModifiers(globalModifiers)
                == normalizedChordModifiers(contextualModifiers) else { return nil }
        return .contextualKeyboard
    }

    static func validateGlobalHUDShortcut(
        _ candidate: TriggerBinding,
        previous: TriggerBinding,
        contextualKeyboard: TriggerBinding
    ) -> HUDShortcutBindingUpdate {
        if let collision = collision(
            globalHUDShortcut: candidate,
            contextualKeyboard: contextualKeyboard
        ) {
            return .rejected(collision: collision, retained: previous)
        }
        return .accepted(candidate)
    }

    static func validateContextualKeyboard(
        _ candidate: TriggerBinding,
        previous: TriggerBinding,
        globalHUDShortcut: TriggerBinding
    ) -> HUDShortcutBindingUpdate {
        if let collision = collision(
            globalHUDShortcut: globalHUDShortcut,
            contextualKeyboard: candidate
        ) {
            return .rejected(collision: collision, retained: previous)
        }
        return .accepted(candidate)
    }
}
