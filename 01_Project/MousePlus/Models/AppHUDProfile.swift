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
    /// Layout-level fields written by a newer version (carried through migration).
    var preservedUnknownFields: [String: JSONValue] { unknownFields }

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

/// One per-application HUD. Version 2 profiles store only how the app differs
/// from Global (`rings`); version 1 profiles were a complete copy (`layout`).
/// Unknown fields are retained so a save from this version does not erase
/// additions made by a newer version.
struct AppHUDProfile: Codable, Equatable {
    enum Storage: Equatable {
        // COMPAT(1.1): remove in task 3.1 — v1 copied layout, kept until migration.
        case copied(HUDActionLayout)
        case inheriting(AppHUDRings)
    }

    static let currentSchemaVersion = 2

    private(set) var storage: Storage
    private var unknownFields: [String: JSONValue]

    /// A version 2 profile. The default inherits every Global item.
    init(rings: AppHUDRings = AppHUDRings()) {
        storage = .inheriting(rings)
        unknownFields = [:]
    }

    // COMPAT(1.1): remove in task 3.1
    init(layout: HUDActionLayout) {
        storage = .copied(layout)
        unknownFields = [:]
    }

    /// The inheritance metadata, or `nil` for a version 1 copy awaiting migration.
    var rings: AppHUDRings? {
        guard case .inheriting(let rings) = storage else { return nil }
        return rings
    }

    var isInheriting: Bool { rings != nil }

    /// The copied version 1 layout, or `nil` once the profile inherits.
    var v1Layout: HUDActionLayout? {
        guard case .copied(let layout) = storage else { return nil }
        return layout
    }

    mutating func setRings(_ rings: AppHUDRings) {
        storage = .inheriting(rings)
    }

    // COMPAT(1.1): remove in task 3.1. An inheriting profile cannot be resolved
    // without Global, so its getter returns an empty layout; assigning a layout
    // turns the profile back into a version 1 copy. Use `AppHUDResolver` instead.
    var layout: HUDActionLayout {
        get {
            switch storage {
            case .copied(let layout): layout
            case .inheriting: HUDActionLayout(inner: [], middle: [])
            }
        }
        set { storage = .copied(newValue) }
    }

    // COMPAT(1.1): remove in task 3.1
    var inner: [RingMenuItem] {
        get { layout.inner }
        set { layout.inner = newValue }
    }

    // COMPAT(1.1): remove in task 3.1
    var middle: [RingMenuItem] {
        get { layout.middle }
        set { layout.middle = newValue }
    }

    /// Converts a version 1 copy into inheritance metadata without changing what
    /// it shows. A version 2 profile is returned unchanged (idempotent).
    func migrated(global: HUDActionLayout) -> AppHUDProfile {
        guard case .copied(let layout) = storage else { return self }
        var result = self
        result.storage = .inheriting(AppHUDResolver.migrate(v1Layout: layout, global: global))
        return result
    }

    private static let v1Keys: Set<String> = ["layout"]
    private static let v2Keys: Set<String> = ["layout", "rings", "schemaVersion"]

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicCodingKey.self)
        let versionKey = DynamicCodingKey("schemaVersion")
        let version = try container.decodeIfPresent(Int.self, forKey: versionKey)
        if let version, version > Self.currentSchemaVersion || version < 1 {
            throw DecodingError.dataCorruptedError(
                forKey: versionKey,
                in: container,
                debugDescription: "Unsupported App HUD schema version \(version)"
            )
        }
        if container.contains(DynamicCodingKey("rings")) {
            storage = .inheriting(
                try container.decode(AppHUDRings.self, forKey: DynamicCodingKey("rings"))
            )
            unknownFields = try container.unknownJSONValues(excluding: Self.v2Keys)
        } else if version == nil || version == 1 {
            // COMPAT(1.1): remove in task 3.1 (v1 `layout` stays decodable for migration).
            storage = .copied(
                try container.decode(HUDActionLayout.self, forKey: DynamicCodingKey("layout"))
            )
            unknownFields = try container.unknownJSONValues(excluding: Self.v1Keys)
        } else {
            throw DecodingError.keyNotFound(
                DynamicCodingKey("rings"),
                .init(
                    codingPath: container.codingPath,
                    debugDescription: "Version 2 App HUD without rings"
                )
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: DynamicCodingKey.self)
        switch storage {
        case .copied(let layout):
            try container.encode(unknownFields, excluding: Self.v1Keys)
            try container.encode(layout, forKey: DynamicCodingKey("layout"))
        case .inheriting(let rings):
            try container.encode(unknownFields, excluding: Self.v2Keys)
            try container.encode(Self.currentSchemaVersion, forKey: DynamicCodingKey("schemaVersion"))
            try container.encode(rings, forKey: DynamicCodingKey("rings"))
        }
    }
}

/// The inner and middle inheritance records of one App HUD.
struct AppHUDRings: Codable, Equatable {
    var inner: RingInheritance
    var middle: RingInheritance
    private var unknownFields: [String: JSONValue]

    init(inner: RingInheritance = RingInheritance(), middle: RingInheritance = RingInheritance()) {
        self.init(inner: inner, middle: middle, unknownFields: [:])
    }

    init(inner: RingInheritance, middle: RingInheritance, unknownFields: [String: JSONValue]) {
        self.inner = inner
        self.middle = middle
        self.unknownFields = unknownFields
    }

    /// The record for a top-level band. `.outer` has no record of its own.
    func ring(_ band: Band) -> RingInheritance {
        switch band {
        case .inner: inner
        case .middle: middle
        case .outer: RingInheritance()
        }
    }

    var preservedUnknownFields: [String: JSONValue] { unknownFields }

    private static let knownKeys: Set<String> = ["inner", "middle"]

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicCodingKey.self)
        inner = try container.decodeIfPresent(RingInheritance.self, forKey: DynamicCodingKey("inner"))
            ?? RingInheritance()
        middle = try container.decodeIfPresent(RingInheritance.self, forKey: DynamicCodingKey("middle"))
            ?? RingInheritance()
        unknownFields = try container.unknownJSONValues(excluding: Self.knownKeys)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: DynamicCodingKey.self)
        try container.encode(unknownFields, excluding: Self.knownKeys)
        try container.encode(inner, forKey: DynamicCodingKey("inner"))
        try container.encode(middle, forKey: DynamicCodingKey("middle"))
    }
}

/// How one App HUD ring differs from the Global ring of the same band.
/// Items are matched to Global by ID; anything not recorded here is inherited.
struct RingInheritance: Codable, Equatable {
    /// Whole-item app copies of Global items, keyed by the Global item ID.
    var overrides: [UUID: RingMenuItem]
    /// Global item IDs hidden in this app.
    var hidden: Set<UUID>
    /// Items that exist only in this app, in stored order.
    var appOnly: [AppOnlyItem]
    /// `nil` follows Global's order; otherwise this ring's own item order.
    var customOrder: [UUID]?
    /// Original item JSON per override ID, so item-level unknown fields survive.
    private var preservedOverrideJSON: [UUID: JSONValue]
    private var unknownFields: [String: JSONValue]

    init(
        overrides: [UUID: RingMenuItem] = [:],
        hidden: Set<UUID> = [],
        appOnly: [AppOnlyItem] = [],
        customOrder: [UUID]? = nil
    ) {
        self.overrides = overrides
        self.hidden = hidden
        self.appOnly = appOnly
        self.customOrder = customOrder
        preservedOverrideJSON = [:]
        unknownFields = [:]
    }

    /// True when the ring inherits every Global item in Global's order.
    var isEmpty: Bool {
        overrides.isEmpty && hidden.isEmpty && appOnly.isEmpty && customOrder == nil
    }

    var preservedUnknownFields: [String: JSONValue] { unknownFields }

    mutating func setUnknownFields(_ fields: [String: JSONValue]) {
        unknownFields = fields
    }

    func preservedJSON(forOverride id: UUID) -> JSONValue? {
        preservedOverrideJSON[id]
    }

    /// Stores an override with the item JSON whose unknown fields it keeps.
    mutating func setOverride(_ item: RingMenuItem, preservingJSON json: JSONValue?) {
        overrides[item.id] = item
        preservedOverrideJSON[item.id] = json
    }

    @discardableResult
    mutating func removeOverride(id: UUID) -> RingMenuItem? {
        preservedOverrideJSON.removeValue(forKey: id)
        return overrides.removeValue(forKey: id)
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.overrides == rhs.overrides
            && lhs.hidden == rhs.hidden
            && lhs.appOnly == rhs.appOnly
            && lhs.customOrder == rhs.customOrder
            && lhs.unknownFields == rhs.unknownFields
    }

    private static let knownKeys: Set<String> = ["overrides", "hidden", "appOnly", "customOrder"]

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicCodingKey.self)
        let overridesKey = DynamicCodingKey("overrides")
        let rawOverrides = try container.decodeIfPresent([JSONValue].self, forKey: overridesKey) ?? []
        var overrides: [UUID: RingMenuItem] = [:]
        var json: [UUID: JSONValue] = [:]
        for raw in rawOverrides {
            let item = try raw.decode(RingMenuItem.self)
            guard overrides[item.id] == nil else {
                throw DecodingError.dataCorruptedError(
                    forKey: overridesKey,
                    in: container,
                    debugDescription: "Duplicate override \(item.id)"
                )
            }
            overrides[item.id] = item
            json[item.id] = raw
        }
        self.overrides = overrides
        preservedOverrideJSON = json
        hidden = Set(try container.decodeIfPresent([UUID].self, forKey: DynamicCodingKey("hidden")) ?? [])
        appOnly = try container.decodeIfPresent([AppOnlyItem].self, forKey: DynamicCodingKey("appOnly")) ?? []
        customOrder = try container.decodeIfPresent([UUID].self, forKey: DynamicCodingKey("customOrder"))
        unknownFields = try container.unknownJSONValues(excluding: Self.knownKeys)
    }

    /// Deterministic: overrides and hidden IDs are sorted by UUID string, so an
    /// unchanged record always encodes to the same bytes.
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: DynamicCodingKey.self)
        try container.encode(unknownFields, excluding: Self.knownKeys)
        let sortedOverrides = overrides.values.sorted { $0.id.uuidString < $1.id.uuidString }
        let encodedOverrides = try sortedOverrides.map { item in
            try HUDActionLayout.mergedItems(
                [item],
                preserving: preservedOverrideJSON[item.id].map { [$0] } ?? []
            )[0]
        }
        try container.encode(encodedOverrides, forKey: DynamicCodingKey("overrides"))
        try container.encode(
            hidden.sorted { $0.uuidString < $1.uuidString },
            forKey: DynamicCodingKey("hidden")
        )
        try container.encode(appOnly, forKey: DynamicCodingKey("appOnly"))
        try container.encodeIfPresent(customOrder, forKey: DynamicCodingKey("customOrder"))
    }
}

/// An item that exists only in one App HUD. `after` names the item it follows
/// while the ring follows Global's order; `nil` places it at the ring start.
struct AppOnlyItem: Codable, Equatable {
    var item: RingMenuItem
    var after: UUID?
    private var preservedItemJSON: JSONValue?
    private var unknownFields: [String: JSONValue]

    init(item: RingMenuItem, after: UUID?, preservingJSON json: JSONValue? = nil) {
        self.item = item
        self.after = after
        preservedItemJSON = json
        unknownFields = [:]
    }

    var id: UUID { item.id }
    var preservedJSON: JSONValue? { preservedItemJSON }

    /// The same record with new content and anchor; its unknown fields are kept.
    func updated(item: RingMenuItem, after: UUID?, fallbackJSON: JSONValue?) -> AppOnlyItem {
        var result = self
        result.item = item
        result.after = after
        if result.preservedItemJSON == nil {
            result.preservedItemJSON = fallbackJSON
        }
        return result
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.item == rhs.item && lhs.after == rhs.after && lhs.unknownFields == rhs.unknownFields
    }

    private static let knownKeys: Set<String> = ["item", "after"]

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicCodingKey.self)
        let raw = try container.decode(JSONValue.self, forKey: DynamicCodingKey("item"))
        item = try raw.decode(RingMenuItem.self)
        preservedItemJSON = raw
        after = try container.decodeIfPresent(UUID.self, forKey: DynamicCodingKey("after"))
        unknownFields = try container.unknownJSONValues(excluding: Self.knownKeys)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: DynamicCodingKey.self)
        try container.encode(unknownFields, excluding: Self.knownKeys)
        try container.encode(
            HUDActionLayout.mergedItems([item], preserving: preservedItemJSON.map { [$0] } ?? [])[0],
            forKey: DynamicCodingKey("item")
        )
        try container.encodeIfPresent(after, forKey: DynamicCodingKey("after"))
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
