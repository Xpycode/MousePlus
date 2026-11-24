import Foundation

/// Where an item in a resolved App HUD ring comes from.
enum ItemOrigin: Hashable, Sendable {
    /// The Global item, unchanged; later Global edits reach it.
    case inherited
    /// An app copy of a Global item; Global edits no longer reach it.
    case customized
    /// An item that exists only in this app.
    case appOnly
}

/// One App HUD resolved against Global.
struct ResolvedAppLayout: Equatable {
    /// What the HUD shows. Locked rings exactly mirror their Global band.
    /// Item-level unknown JSON comes from Global for inherited items and from the
    /// app's own copy for customized and app-only items.
    var layout: HUDActionLayout
    /// Origin of every resolved item, including items in `notShown`.
    var origins: [UUID: ItemOrigin]
    /// Items beyond the ring capacity, per band, in resolved order. Bands that
    /// fit have no entry.
    var notShown: [Band: [RingMenuItem]]
    var lockedBands: Set<Band> = []
    /// Includes stored orders which happen to match Global's current order.
    var customOrderBands: Set<Band> = []
    /// An ID can appear in both bands with a different origin in each.
    var originsByBand: [Band: [UUID: ItemOrigin]] = [:]
}

/// Pure functions that turn Global plus per-app inheritance metadata into a
/// layout, and turn an edited layout back into metadata.
enum AppHUDResolver {
    /// Maximum items a top-level ring shows (the editor's 8-spoke cap).
    static let ringCapacity = 8

    // MARK: - Resolution

    /// Resolves a profile against Global. A version 1 copy is migrated in memory
    /// first, which shows exactly its copied items.
    static func resolve(global: HUDActionLayout, profile: AppHUDProfile) -> ResolvedAppLayout {
        switch profile.storage {
        case .copied(let v1Layout):
            return resolve(global: global, rings: migrate(v1Layout: v1Layout, global: global))
        case .inheriting(let rings):
            return resolve(global: global, rings: rings)
        }
    }

    static func resolve(global: HUDActionLayout, rings: AppHUDRings) -> ResolvedAppLayout {
        let inner = resolvedEntries(
            global: global.inner,
            globalJSON: global.preservedInnerItemsJSON,
            ring: rings.inner
        )
        let middle = resolvedEntries(
            global: global.middle,
            globalJSON: global.preservedMiddleItemsJSON,
            ring: rings.middle
        )

        func itemOrigins(_ entries: [Entry]) -> [UUID: ItemOrigin] {
            Dictionary(entries.map { ($0.item.id, $0.origin) }, uniquingKeysWith: { first, _ in first })
        }
        let innerOrigins = itemOrigins(inner)
        let middleOrigins = itemOrigins(middle)

        let shownInner = inner.prefix(rings.inner.followsGlobal ? inner.count : ringCapacity)
        let shownMiddle = middle.prefix(rings.middle.followsGlobal ? middle.count : ringCapacity)
        var notShown: [Band: [RingMenuItem]] = [:]
        if inner.count > shownInner.count {
            notShown[.inner] = inner.dropFirst(shownInner.count).map(\.item)
        }
        if middle.count > shownMiddle.count {
            notShown[.middle] = middle.dropFirst(shownMiddle.count).map(\.item)
        }

        return ResolvedAppLayout(
            layout: HUDActionLayout(
                inner: shownInner.map(\.item),
                middle: shownMiddle.map(\.item),
                preservingInner: shownInner.compactMap(\.json),
                preservingMiddle: shownMiddle.compactMap(\.json)
            ),
            origins: innerOrigins.merging(middleOrigins) { first, _ in first },
            notShown: notShown,
            lockedBands: Set([Band.inner, .middle].filter { rings.ring($0).followsGlobal }),
            customOrderBands: Set([Band.inner, .middle].filter {
                let ring = rings.ring($0)
                return !ring.followsGlobal && ring.customOrder != nil
            }),
            originsByBand: [.inner: innerOrigins, .middle: middleOrigins]
        )
    }

    private struct Entry {
        let item: RingMenuItem
        let origin: ItemOrigin
        let json: JSONValue?
    }

    private static func resolvedEntries(
        global: [RingMenuItem],
        globalJSON: [JSONValue],
        ring: RingInheritance
    ) -> [Entry] {
        let pairedGlobalJSON = pairedJSON(global, globalJSON)
        if ring.followsGlobal {
            return global.indices.map { Entry(item: global[$0], origin: .inherited, json: pairedGlobalJSON[$0]) }
        }
        let globalIndexByID = firstIndexByID(global)
        var entries: [Entry] = []
        var emittedGlobal = Set<UUID>()
        var emittedAppOnly = Set<Int>()

        func emitGlobal(at index: Int) {
            let item = global[index]
            guard !ring.hidden.contains(item.id), emittedGlobal.insert(item.id).inserted else { return }
            if let override = ring.overrides[item.id] {
                entries.append(Entry(
                    item: override,
                    origin: .customized,
                    json: ring.preservedJSON(forOverride: item.id) ?? pairedGlobalJSON[index]
                ))
            } else {
                entries.append(Entry(item: item, origin: .inherited, json: pairedGlobalJSON[index]))
            }
        }

        func emitAppOnly(at index: Int) {
            guard emittedAppOnly.insert(index).inserted else { return }
            let appOnly = ring.appOnly[index]
            entries.append(Entry(item: appOnly.item, origin: .appOnly, json: appOnly.preservedJSON))
        }

        if let customOrder = ring.customOrder {
            var appOnlyIndicesByID: [UUID: [Int]] = [:]
            for (index, appOnly) in ring.appOnly.enumerated() {
                appOnlyIndicesByID[appOnly.id, default: []].append(index)
            }
            for id in customOrder {
                if let index = globalIndexByID[id],
                   !ring.hidden.contains(id),
                   !emittedGlobal.contains(id) {
                    emitGlobal(at: index)
                } else if let index = appOnlyIndicesByID[id]?.first(where: {
                    !emittedAppOnly.contains($0)
                }) {
                    emitAppOnly(at: index)
                }
                // Anything else is an unknown or hidden ID: skipped.
            }
            for index in global.indices { emitGlobal(at: index) }
            for index in ring.appOnly.indices { emitAppOnly(at: index) }
            return entries
        }

        // Follows Global: app-only items sit after their anchor. Hidden Global
        // items still act as anchors, so hiding never moves app-only items.
        var ringStart: [Int] = []
        var anchoredTo: [UUID: [Int]] = [:]
        for (index, appOnly) in ring.appOnly.enumerated() {
            if let after = appOnly.after {
                anchoredTo[after, default: []].append(index)
            } else {
                ringStart.append(index)
            }
        }

        // `emittedAppOnly` is the cycle guard: each app-only item is emitted once.
        func emitChain(after anchor: UUID) {
            for index in anchoredTo[anchor] ?? [] where !emittedAppOnly.contains(index) {
                emitAppOnly(at: index)
                emitChain(after: ring.appOnly[index].id)
            }
        }

        func emitAppOnlyWithChain(at index: Int) {
            guard !emittedAppOnly.contains(index) else { return }
            emitAppOnly(at: index)
            emitChain(after: ring.appOnly[index].id)
        }

        for index in ringStart { emitAppOnlyWithChain(at: index) }
        for index in global.indices {
            emitGlobal(at: index)
            emitChain(after: global[index].id)
        }
        // Unknown anchors and cycles: append in stored order. Nothing is dropped.
        for index in ring.appOnly.indices { emitAppOnlyWithChain(at: index) }
        return entries
    }

    // MARK: - Edits back to storage

    /// Turns one edited ring into inheritance metadata.
    ///
    /// - `edited` must be the complete ring, including items resolved as not shown;
    ///   a Global item missing from it becomes hidden.
    /// - `origins` is the editor's view of each item. `.customized` keeps an
    ///   override even when identical to Global (explicit Customize); `.inherited`
    ///   drops an identical override (Revert to Global). Without an entry, an
    ///   existing override is kept. Content that differs from Global always
    ///   becomes an override, so an edit is never lost.
    static func diff(
        edited: [RingMenuItem],
        previous: RingInheritance,
        global: [RingMenuItem],
        origins: [UUID: ItemOrigin]? = nil,
        editedItemsJSON: [JSONValue] = [],
        globalItemsJSON: [JSONValue] = []
    ) -> RingInheritance {
        if previous.followsGlobal {
            return previous.cleared(followsGlobal: true)
        }
        let editedJSON = pairedJSON(edited, editedItemsJSON)
        let pairedGlobalJSON = pairedJSON(global, globalItemsJSON)
        var previousAppOnly: [UUID: [AppOnlyItem]] = [:]
        for appOnly in previous.appOnly {
            previousAppOnly[appOnly.id, default: []].append(appOnly)
        }

        var ring = makeRing(
            items: edited,
            global: global,
            linked: { index, globalIndex in
                let item = edited[index]
                let differs = item != global[globalIndex]
                let isOverride: Bool
                switch origins?[item.id] {
                case .inherited: isOverride = differs
                case .customized, .appOnly: isOverride = true
                case nil: isOverride = differs || previous.overrides[item.id] != nil
                }
                let json = previous.preservedJSON(forOverride: item.id)
                    ?? editedJSON[index]
                    ?? pairedGlobalJSON[globalIndex]
                return (isOverride, json)
            },
            appOnly: { index, after in
                let item = edited[index]
                // Reuse the previous record so its own unknown fields survive.
                if var queue = previousAppOnly[item.id], !queue.isEmpty {
                    let record = queue.removeFirst()
                    previousAppOnly[item.id] = queue
                    return record.updated(item: item, after: after, fallbackJSON: editedJSON[index])
                }
                return AppOnlyItem(item: item, after: after, preservingJSON: editedJSON[index])
            }
        )
        ring.setUnknownFields(previous.preservedUnknownFields)
        return ring
    }

    /// Profile-level `diff`. A version 1 previous profile is migrated first;
    /// profile- and rings-level unknown fields are kept.
    static func diff(
        edited: HUDActionLayout,
        previous: AppHUDProfile,
        global: HUDActionLayout,
        origins: [UUID: ItemOrigin]? = nil,
        lockedBands: Set<Band>? = nil,
        customOrderBands: Set<Band>? = nil,
        originsByBand: [Band: [UUID: ItemOrigin]]? = nil
    ) -> AppHUDProfile {
        var result = previous.migrated(global: global)
        guard var rings = result.rings else { return result }
        func editedRing(
            _ band: Band, previous: RingInheritance, items: [RingMenuItem], json: [JSONValue],
            globalItems: [RingMenuItem], globalJSON: [JSONValue]
        ) -> RingInheritance {
            if lockedBands?.contains(band) ?? previous.followsGlobal {
                return previous.cleared(followsGlobal: true)
            }

            // Preserve the original anchors and partial order in an untouched
            // sibling ring. A round trip through visible items loses that detail.
            let before = resolvedEntries(global: globalItems, globalJSON: globalJSON, ring: previous)
            let wantsCustomOrder = customOrderBands?.contains(band)
            let bandOrigins = originsByBand?[band] ?? origins
            if !previous.followsGlobal,
               before.map(\.item) == items,
               before.allSatisfy({ bandOrigins?[$0.item.id] == nil || bandOrigins?[$0.item.id] == $0.origin }),
               wantsCustomOrder == nil || wantsCustomOrder == (previous.customOrder != nil) {
                return previous
            }

            let baseline = previous.followsGlobal ? previous.cleared(followsGlobal: false) : previous
            var ring = diff(
                edited: items, previous: baseline, global: globalItems, origins: bandOrigins,
                editedItemsJSON: json, globalItemsJSON: globalJSON
            )
            if let wantsCustomOrder {
                ring.customOrder = wantsCustomOrder ? ring.customOrder ?? items.map(\.id) : nil
            }
            return ring
        }
        rings.inner = editedRing(
            .inner, previous: rings.inner, items: edited.inner, json: edited.preservedInnerItemsJSON,
            globalItems: global.inner, globalJSON: global.preservedInnerItemsJSON
        )
        rings.middle = editedRing(
            .middle, previous: rings.middle, items: edited.middle, json: edited.preservedMiddleItemsJSON,
            globalItems: global.middle, globalJSON: global.preservedMiddleItemsJSON
        )
        result.setRings(rings)
        return result
    }

    // MARK: - Migration

    /// Converts a copied version 1 layout. Items identical to Global (all fields
    /// and unknown JSON) are inherited, different ones become overrides, unknown
    /// IDs become app-only and missing Global items become hidden. Resolving the
    /// result shows exactly the v1 items in the v1 order.
    static func migrate(v1Layout: HUDActionLayout, global: HUDActionLayout) -> AppHUDRings {
        AppHUDRings(
            inner: migrateRing(
                items: v1Layout.inner,
                itemsJSON: v1Layout.preservedInnerItemsJSON,
                global: global.inner,
                globalJSON: global.preservedInnerItemsJSON
            ),
            middle: migrateRing(
                items: v1Layout.middle,
                itemsJSON: v1Layout.preservedMiddleItemsJSON,
                global: global.middle,
                globalJSON: global.preservedMiddleItemsJSON
            ),
            unknownFields: v1Layout.preservedUnknownFields
        )
    }

    private static func migrateRing(
        items: [RingMenuItem],
        itemsJSON: [JSONValue],
        global: [RingMenuItem],
        globalJSON: [JSONValue]
    ) -> RingInheritance {
        let pairedItemJSON = pairedJSON(items, itemsJSON)
        let pairedGlobalJSON = pairedJSON(global, globalJSON)
        return makeRing(
            items: items,
            global: global,
            linked: { index, globalIndex in
                let item = items[index]
                let itemJSON = fullJSON(item, preserving: pairedItemJSON[index])
                let identical = item == global[globalIndex]
                    && itemJSON != nil
                    && itemJSON == fullJSON(global[globalIndex], preserving: pairedGlobalJSON[globalIndex])
                return (!identical, pairedItemJSON[index])
            },
            appOnly: { index, after in
                AppOnlyItem(item: items[index], after: after, preservingJSON: pairedItemJSON[index])
            }
        )
    }

    // MARK: - Global changes

    /// Repairs a profile after Global changed. An override whose Global item is
    /// gone becomes app-only, anchored to the deleted item's nearest surviving
    /// former predecessor (ring start if it had none; the end if `oldGlobal` does
    /// not contain it). App-only anchors to deleted items move the same way.
    /// Hidden and order IDs that no longer exist are removed. Without a deletion
    /// the result is equal to the input. On load, pass the current Global as both
    /// `oldGlobal` and `newGlobal`. A version 1 copy is returned unchanged.
    static func repairAfterGlobalChange(
        profile: AppHUDProfile,
        oldGlobal: HUDActionLayout,
        newGlobal: HUDActionLayout
    ) -> AppHUDProfile {
        guard var rings = profile.rings else { return profile }
        rings.inner = repairRing(rings.inner, oldGlobal: oldGlobal.inner, newGlobal: newGlobal.inner)
        rings.middle = repairRing(rings.middle, oldGlobal: oldGlobal.middle, newGlobal: newGlobal.middle)
        var result = profile
        result.setRings(rings)
        return result
    }

    private static func repairRing(
        _ ring: RingInheritance,
        oldGlobal: [RingMenuItem],
        newGlobal: [RingMenuItem]
    ) -> RingInheritance {
        guard !ring.followsGlobal else { return ring }
        let newIDs = Set(newGlobal.map(\.id))
        let oldIndexByID = firstIndexByID(oldGlobal)
        let endAnchor = newGlobal.last?.id

        func formerPredecessor(of id: UUID) -> UUID? {
            guard let index = oldIndexByID[id] else { return endAnchor }
            for candidate in oldGlobal[..<index].reversed() where newIDs.contains(candidate.id) {
                return candidate.id
            }
            return nil
        }

        var result = ring
        let orphanIDs = ring.overrides.keys
            .filter { !newIDs.contains($0) }
            .sorted { lhs, rhs in
                let left = oldIndexByID[lhs] ?? Int.max
                let right = oldIndexByID[rhs] ?? Int.max
                return left == right ? lhs.uuidString < rhs.uuidString : left < right
            }
        for id in orphanIDs {
            let json = result.preservedJSON(forOverride: id)
            guard let item = result.removeOverride(id: id) else { continue }
            result.appOnly.append(AppOnlyItem(
                item: item,
                after: formerPredecessor(of: id),
                preservingJSON: json
            ))
        }

        let appOnlyIDs = Set(result.appOnly.map(\.id))
        for index in result.appOnly.indices {
            guard let after = result.appOnly[index].after,
                  !newIDs.contains(after),
                  !appOnlyIDs.contains(after) else { continue }
            result.appOnly[index].after = formerPredecessor(of: after)
        }

        result.hidden.formIntersection(newIDs)
        if let customOrder = result.customOrder {
            result.customOrder = customOrder.filter { newIDs.contains($0) || appOnlyIDs.contains($0) }
        }
        return result
    }

    // MARK: - Shared building blocks

    /// Builds metadata from a complete ordered ring. `linked` decides, for an item
    /// whose ID is in Global, whether it is an override and which JSON it keeps.
    private static func makeRing(
        items: [RingMenuItem],
        global: [RingMenuItem],
        linked: (_ index: Int, _ globalIndex: Int) -> (isOverride: Bool, json: JSONValue?),
        appOnly: (_ index: Int, _ after: UUID?) -> AppOnlyItem
    ) -> RingInheritance {
        let globalIndexByID = firstIndexByID(global)
        var ring = RingInheritance()
        var linkedOrder: [UUID] = []
        var linkedIDs = Set<UUID>()

        for (index, item) in items.enumerated() {
            if let globalIndex = globalIndexByID[item.id], linkedIDs.insert(item.id).inserted {
                linkedOrder.append(item.id)
                let decision = linked(index, globalIndex)
                if decision.isOverride {
                    ring.setOverride(item, preservingJSON: decision.json)
                }
            } else {
                // A repeated Global ID is kept as app-only so nothing is lost.
                ring.appOnly.append(appOnly(index, index == 0 ? nil : items[index - 1].id))
            }
        }

        var globalOrder: [UUID] = []
        var seenGlobal = Set<UUID>()
        for item in global where seenGlobal.insert(item.id).inserted {
            if linkedIDs.contains(item.id) {
                globalOrder.append(item.id)
            } else {
                ring.hidden.insert(item.id)
            }
        }
        if globalOrder != linkedOrder {
            ring.customOrder = items.map(\.id)
        }
        return ring
    }

    /// Pairs each item with its original JSON, matching each ID occurrence at
    /// most once (the same multiset rule as `HUDActionLayout.mergedItems`).
    private static func pairedJSON(_ items: [RingMenuItem], _ originals: [JSONValue]) -> [JSONValue?] {
        var unmatched = Array(originals.indices)
        return items.map { item in
            guard let match = unmatched.firstIndex(where: { originals[$0].itemIdentifier == item.id }) else {
                return nil
            }
            return originals[unmatched.remove(at: match)]
        }
    }

    private static func firstIndexByID(_ items: [RingMenuItem]) -> [UUID: Int] {
        var result: [UUID: Int] = [:]
        for (index, item) in items.enumerated() where result[item.id] == nil {
            result[item.id] = index
        }
        return result
    }

    /// The JSON an item encodes to, unknown fields included. `nil` only if
    /// encoding fails, which makes a comparison treat the item as different.
    private static func fullJSON(_ item: RingMenuItem, preserving original: JSONValue?) -> JSONValue? {
        try? HUDActionLayout.mergedItems([item], preserving: original.map { [$0] } ?? []).first
    }
}
