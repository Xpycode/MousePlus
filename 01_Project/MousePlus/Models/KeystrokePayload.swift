import Foundation

/// Persisted data for a Send Keystroke action.
///
/// A legacy value is deliberately retained when it cannot prove which physical
/// key was meant. Callers must not execute `.unresolvedLegacy`; the user needs
/// to record that shortcut again.
enum KeystrokePayload: Hashable, Sendable {
    case key(keyCode: UInt16, modifiers: UInt)
    case unresolvedLegacy(String)

    /// Only the four chord modifiers are executable. Event-state flags such as
    /// Caps Lock, Numeric Pad, and Function are intentionally discarded.
    static let modifierMask: UInt =
        (1 << 17) | // Shift
        (1 << 18) | // Control
        (1 << 19) | // Option
        (1 << 20)   // Command

    /// Migrates only an explicit numeric representation of a physical key.
    /// Display strings (for example, `⌘C`) are ambiguous across keyboard
    /// layouts and therefore remain unresolved.
    static func migratingLegacy(_ value: String) -> Self {
        guard let data = value.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(LegacyKey.self, from: data)
        else {
            return .unresolvedLegacy(value)
        }
        return .key(keyCode: decoded.keyCode, modifiers: decoded.modifiers & modifierMask)
    }
}

extension KeystrokePayload: Codable {
    private enum CodingKeys: String, CodingKey {
        case kind
        case keyCode
        case modifiers
        case legacyValue
    }

    private enum Kind: String, Codable {
        case key
        case unresolvedLegacy
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .key:
            let keyCode = try container.decode(UInt16.self, forKey: .keyCode)
            let modifiers = try container.decodeIfPresent(UInt.self, forKey: .modifiers) ?? 0
            self = .key(keyCode: keyCode, modifiers: modifiers & Self.modifierMask)
        case .unresolvedLegacy:
            self = .unresolvedLegacy(try container.decode(String.self, forKey: .legacyValue))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .key(keyCode, modifiers):
            try container.encode(Kind.key, forKey: .kind)
            try container.encode(keyCode, forKey: .keyCode)
            try container.encode(modifiers & Self.modifierMask, forKey: .modifiers)
        case let .unresolvedLegacy(value):
            try container.encode(Kind.unresolvedLegacy, forKey: .kind)
            try container.encode(value, forKey: .legacyValue)
        }
    }
}

private struct LegacyKey: Decodable {
    let keyCode: UInt16
    let modifiers: UInt
}
