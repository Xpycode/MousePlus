import Foundation

/// The action-bearing part of a HUD configuration. Presentation, motion,
/// behavior, and triggers deliberately remain global.
struct HUDActionLayout: Codable, Equatable {
    var inner: [RingMenuItem]
    var middle: [RingMenuItem]
    private var unknownFields: [String: JSONValue]
    private var preservedInnerJSON: [JSONValue]
    private var preservedMiddleJSON: [JSONValue]

    init(inner: [RingMenuItem], middle: [RingMenuItem]) {
        self.init(inner: inner, middle: middle, preservingInner: [], preservingMiddle: [])
    }

    init(
        inner: [RingMenuItem],
        middle: [RingMenuItem],
        preservingInner: [JSONValue],
        preservingMiddle: [JSONValue]
    ) {
        self.inner = inner
        self.middle = middle
        unknownFields = [:]
        preservedInnerJSON = preservingInner
        preservedMiddleJSON = preservingMiddle
    }

    var preservedInnerItemsJSON: [JSONValue] { preservedInnerJSON }
    var preservedMiddleItemsJSON: [JSONValue] { preservedMiddleJSON }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicCodingKey.self)
        preservedInnerJSON = try container.decode(
            [JSONValue].self,
            forKey: DynamicCodingKey("inner")
        )
        preservedMiddleJSON = try container.decode(
            [JSONValue].self,
            forKey: DynamicCodingKey("middle")
        )
        inner = try preservedInnerJSON.map { try $0.decode(RingMenuItem.self) }
        middle = try preservedMiddleJSON.map { try $0.decode(RingMenuItem.self) }
        unknownFields = try container.unknownJSONValues(excluding: ["inner", "middle"])
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: DynamicCodingKey.self)
        try container.encode(unknownFields, excluding: ["inner", "middle"])
        try container.encode(
            Self.mergedItems(inner, preserving: preservedInnerJSON),
            forKey: DynamicCodingKey("inner")
        )
        try container.encode(
            Self.mergedItems(middle, preserving: preservedMiddleJSON),
            forKey: DynamicCodingKey("middle")
        )
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.inner == rhs.inner
            && lhs.middle == rhs.middle
            && lhs.unknownFields == rhs.unknownFields
    }

    private static let itemKeys: Set<String> = [
        "id", "label", "icon", "actionType", "actionData", "subItems", "keystrokePayload",
        "wedgeColor", "iconColor", "dynamicSource", "keyboardShortcut",
    ]

    static func mergedItems(
        _ items: [RingMenuItem],
        preserving originals: [JSONValue]
    ) throws -> [JSONValue] {
        let typed = try items.map(JSONValue.decodeEncoded)
        return mergeItems(typed, preserving: originals)
    }

    /// Matches each identifier occurrence at most once. UUIDs should be unique,
    /// but treating duplicate IDs as an ordered multiset prevents one item's
    /// opaque payload from being copied over another's during compatibility saves.
    private static func mergeItems(
        _ typedItems: [JSONValue],
        preserving originals: [JSONValue]
    ) -> [JSONValue] {
        var unmatchedOriginalIndices = Array(originals.indices)
        return typedItems.map { typed in
            let match = unmatchedOriginalIndices.firstIndex { remainingIndex in
                originals[remainingIndex].itemIdentifier == typed.itemIdentifier
            }
            let original: JSONValue?
            if let match {
                original = originals[unmatchedOriginalIndices.remove(at: match)]
            } else {
                original = nil
            }
            return mergeItem(typed: typed, original: original)
        }
    }

    private static func mergeItem(typed: JSONValue, original: JSONValue?) -> JSONValue {
        guard case .object(let typedObject) = typed else { return typed }
        var result: [String: JSONValue]
        if case .object(let originalObject) = original {
            result = originalObject
        } else {
            result = [:]
        }

        for key in itemKeys {
            if key == "keyboardShortcut" {
                // Decode-only legacy data is intentionally retired by RingMenuItem.
                result.removeValue(forKey: key)
            } else if key == "subItems",
                      case .array(let typedChildren) = typedObject[key] {
                let originalChildren: [JSONValue]
                if case .object(let originalObject) = original,
                   case .array(let children) = originalObject[key] {
                    originalChildren = children
                } else {
                    originalChildren = []
                }
                result[key] = .array(mergeItems(typedChildren, preserving: originalChildren))
            } else if let value = typedObject[key] {
                result[key] = value
            } else {
                result.removeValue(forKey: key)
            }
        }
        return .object(result)
    }
}

/// One complete per-application action layout. Unknown fields are retained so
/// a save from this version does not erase additions made by a newer version.
struct AppHUDProfile: Codable, Equatable {
    var layout: HUDActionLayout
    private var unknownFields: [String: JSONValue]

    var inner: [RingMenuItem] {
        get { layout.inner }
        set { layout.inner = newValue }
    }

    var middle: [RingMenuItem] {
        get { layout.middle }
        set { layout.middle = newValue }
    }

    init(layout: HUDActionLayout) {
        self.layout = layout
        unknownFields = [:]
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicCodingKey.self)
        layout = try container.decode(HUDActionLayout.self, forKey: DynamicCodingKey("layout"))
        unknownFields = try container.unknownJSONValues(excluding: ["layout"])
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: DynamicCodingKey.self)
        try container.encode(unknownFields, excluding: ["layout"])
        try container.encode(layout, forKey: DynamicCodingKey("layout"))
    }
}

/// A profile entry is decoded through an untyped JSON boundary first. A bad
/// entry is quarantined independently and encoded back unchanged instead of
/// making the complete configuration unreadable or silently deleting data.
enum StoredAppHUDProfile: Codable, Equatable {
    case available(AppHUDProfile)
    case unavailable(JSONValue)

    init(from decoder: Decoder) throws {
        let raw = try JSONValue(from: decoder)
        if let profile = try? raw.decode(AppHUDProfile.self) {
            self = .available(profile)
        } else {
            self = .unavailable(raw)
        }
    }

    func encode(to encoder: Encoder) throws {
        switch self {
        case .available(let profile): try profile.encode(to: encoder)
        case .unavailable(let raw): try raw.encode(to: encoder)
        }
    }
}

/// JSON-compatible storage used only at compatibility boundaries.
indirect enum JSONValue: Codable, Equatable {
    case null
    case bool(Bool)
    case string(String)
    case integer(Int64)
    case unsignedInteger(UInt64)
    case decimal(Decimal)
    case floatingPoint(Double)
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int64.self) {
            self = .integer(value)
        } else if let value = try? container.decode(UInt64.self) {
            self = .unsignedInteger(value)
        } else if let value = try? container.decode(Decimal.self) {
            self = .decimal(value)
        } else if let value = try? container.decode(Double.self) {
            self = .floatingPoint(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Value is not representable as JSON"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .integer(let value): try container.encode(value)
        case .unsignedInteger(let value): try container.encode(value)
        case .decimal(let value): try container.encode(value)
        case .floatingPoint(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }

    func decode<Value: Decodable>(_ type: Value.Type) throws -> Value {
        try JSONDecoder().decode(type, from: JSONEncoder().encode(self))
    }

    static func decodeEncoded<Value: Encodable>(_ value: Value) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(value))
    }

    var itemIdentifier: UUID? {
        guard case .object(let object) = self,
              case .string(let rawIdentifier) = object["id"] else { return nil }
        return UUID(uuidString: rawIdentifier)
    }
}

struct DynamicCodingKey: CodingKey, Hashable {
    let stringValue: String
    let intValue: Int?

    init(_ stringValue: String) {
        self.stringValue = stringValue
        intValue = nil
    }

    init?(stringValue: String) { self.init(stringValue) }

    init?(intValue: Int) {
        stringValue = String(intValue)
        self.intValue = intValue
    }
}

extension KeyedDecodingContainer where Key == DynamicCodingKey {
    func unknownJSONValues(excluding knownKeys: Set<String>) throws -> [String: JSONValue] {
        var values: [String: JSONValue] = [:]
        for key in allKeys where !knownKeys.contains(key.stringValue) {
            values[key.stringValue] = try decode(JSONValue.self, forKey: key)
        }
        return values
    }
}

extension KeyedEncodingContainer where Key == DynamicCodingKey {
    mutating func encode(_ values: [String: JSONValue], excluding knownKeys: Set<String>) throws {
        for (name, value) in values where !knownKeys.contains(name) {
            try encode(value, forKey: DynamicCodingKey(name))
        }
    }
}
