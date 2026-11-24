import Foundation
import XCTest
@testable import MousePlus

final class AppHUDInheritanceTests: XCTestCase {
    private let copy = RingMenuItem(
        label: "Copy",
        icon: "doc.on.doc",
        actionType: .sendKeystroke,
        keystrokePayload: nil
    )
    private let paste = RingMenuItem(label: "Paste", icon: "doc.on.clipboard", actionType: .custom)
    private let spotlight = RingMenuItem(label: "Spotlight", icon: "magnifyingglass", actionType: .custom)
    private let apps = RingMenuItem(label: "Apps", icon: "square.grid.2x2", actionType: .custom)
    private let snap = RingMenuItem(label: "Snap", icon: "rectangle.split.2x1", actionType: .custom)
    private let menu = RingMenuItem(label: "Menu", icon: "menubar.rectangle", actionType: .custom)

    // MARK: - Resolution (AC1–AC8)

    func testAC1InheritedItemFollowsGlobalEdit() {
        var global = HUDActionLayout(inner: [copy, paste], middle: [apps])
        let profile = AppHUDProfile()
        global.inner[0].keystrokePayload = .key(keyCode: 8, modifiers: 1 << 20)

        let resolved = AppHUDResolver.resolve(global: global, profile: profile)

        XCTAssertEqual(resolved.layout.inner, global.inner)
        XCTAssertEqual(resolved.layout.inner[0].keystrokePayload, .key(keyCode: 8, modifiers: 1 << 20))
        XCTAssertEqual(resolved.origins[copy.id], .inherited)
        XCTAssertEqual(resolved.layout.middle, [apps])
    }

    func testAC2CustomizedItemIgnoresGlobalEdit() {
        var global = HUDActionLayout(inner: [copy, paste], middle: [])
        var safariCopy = copy
        safariCopy.label = "Safari Copy"
        let profile = AppHUDProfile(rings: AppHUDRings(
            inner: RingInheritance(overrides: [copy.id: safariCopy])
        ))
        global.inner[0].keystrokePayload = .key(keyCode: 8, modifiers: 1 << 20)

        let resolved = AppHUDResolver.resolve(global: global, profile: profile)

        XCTAssertEqual(resolved.layout.inner[0], safariCopy)
        XCTAssertNil(resolved.layout.inner[0].keystrokePayload)
        XCTAssertEqual(resolved.origins[copy.id], .customized)
        XCTAssertEqual(resolved.origins[paste.id], .inherited)
    }

    func testAC3RevertToGlobalDropsOverrideAndLaterEditsReachItem() {
        var global = HUDActionLayout(inner: [copy, paste], middle: [])
        var safariCopy = copy
        safariCopy.label = "Safari Copy"
        let previous = RingInheritance(overrides: [copy.id: safariCopy])

        let reverted = AppHUDResolver.diff(
            edited: global.inner,
            previous: previous,
            global: global.inner,
            origins: [copy.id: .inherited, paste.id: .inherited]
        )

        XCTAssertTrue(reverted.isEmpty)
        global.inner[0].label = "Copy v2"
        let resolved = AppHUDResolver.resolve(
            global: global,
            profile: AppHUDProfile(rings: AppHUDRings(inner: reverted))
        )
        XCTAssertEqual(resolved.layout.inner[0].label, "Copy v2")
        XCTAssertEqual(resolved.origins[copy.id], .inherited)
    }

    func testAC4NewGlobalItemAppearsAtGlobalPositionWhenFollowingOrder() {
        let note = RingMenuItem(label: "Note", icon: "note", actionType: .custom)
        let profile = AppHUDProfile(rings: AppHUDRings(
            middle: RingInheritance(appOnly: [AppOnlyItem(item: note, after: snap.id)])
        ))
        let added = RingMenuItem(label: "Added", icon: "plus", actionType: .custom)
        let global = HUDActionLayout(inner: [], middle: [apps, added, snap, menu])

        let resolved = AppHUDResolver.resolve(global: global, profile: profile)

        XCTAssertEqual(resolved.layout.middle.map(\.id), [apps.id, added.id, snap.id, note.id, menu.id])
        XCTAssertEqual(resolved.origins[added.id], .inherited)
    }

    func testAC5NewGlobalItemAppendedWhenRingHasCustomOrder() {
        let profile = AppHUDProfile(rings: AppHUDRings(
            middle: RingInheritance(customOrder: [menu.id, apps.id, snap.id])
        ))
        let added = RingMenuItem(label: "Added", icon: "plus", actionType: .custom)
        let global = HUDActionLayout(inner: [], middle: [added, apps, snap, menu])

        let resolved = AppHUDResolver.resolve(global: global, profile: profile)

        XCTAssertEqual(resolved.layout.middle.map(\.id), [menu.id, apps.id, snap.id, added.id])
    }

    func testAC6DeletedInheritedItemDisappears() {
        let profile = AppHUDProfile()
        let oldGlobal = HUDActionLayout(inner: [copy, paste, spotlight], middle: [])
        let newGlobal = HUDActionLayout(inner: [copy, spotlight], middle: [])

        let repaired = AppHUDResolver.repairAfterGlobalChange(
            profile: profile,
            oldGlobal: oldGlobal,
            newGlobal: newGlobal
        )
        let resolved = AppHUDResolver.resolve(global: newGlobal, profile: repaired)

        XCTAssertEqual(repaired, profile)
        XCTAssertEqual(resolved.layout.inner.map(\.id), [copy.id, spotlight.id])
    }

    func testAC7DeletedCustomizedItemBecomesAppOnlyAtFormerPosition() throws {
        var safariPaste = paste
        safariPaste.label = "Safari Paste"
        let profile = AppHUDProfile(rings: AppHUDRings(
            inner: RingInheritance(overrides: [paste.id: safariPaste])
        ))
        let oldGlobal = HUDActionLayout(inner: [copy, paste, spotlight], middle: [])
        let newGlobal = HUDActionLayout(inner: [copy, spotlight], middle: [])

        let repaired = AppHUDResolver.repairAfterGlobalChange(
            profile: profile,
            oldGlobal: oldGlobal,
            newGlobal: newGlobal
        )
        let ring = try XCTUnwrap(repaired.rings?.inner)
        let resolved = AppHUDResolver.resolve(global: newGlobal, profile: repaired)

        XCTAssertTrue(ring.overrides.isEmpty)
        XCTAssertEqual(ring.appOnly, [AppOnlyItem(item: safariPaste, after: copy.id)])
        XCTAssertEqual(resolved.layout.inner, [copy, safariPaste, spotlight])
        XCTAssertEqual(resolved.origins[paste.id], .appOnly)
    }

    func testAC8GlobalReorderKeepsAppOnlyItemNextToPreviousNeighbor() {
        let note = RingMenuItem(label: "Note", icon: "note", actionType: .custom)
        let profile = AppHUDProfile(rings: AppHUDRings(
            middle: RingInheritance(appOnly: [AppOnlyItem(item: note, after: apps.id)])
        ))
        let reordered = HUDActionLayout(inner: [], middle: [menu, snap, apps])

        let resolved = AppHUDResolver.resolve(global: reordered, profile: profile)

        XCTAssertEqual(resolved.layout.middle.map(\.id), [menu.id, snap.id, apps.id, note.id])
    }

    // MARK: - Anchors and guards

    func testAppOnlyItemsWithNilAnchorComeFirstAndChainInStoredOrder() {
        let first = RingMenuItem(label: "First", icon: "1.circle", actionType: .custom)
        let second = RingMenuItem(label: "Second", icon: "2.circle", actionType: .custom)
        let ring = RingInheritance(appOnly: [
            AppOnlyItem(item: second, after: first.id),
            AppOnlyItem(item: first, after: nil),
        ])
        let global = HUDActionLayout(inner: [copy, paste], middle: [])

        let resolved = AppHUDResolver.resolve(global: global, rings: AppHUDRings(inner: ring))

        XCTAssertEqual(resolved.layout.inner.map(\.id), [first.id, second.id, copy.id, paste.id])
    }

    func testAnchorDeletedFromGlobalMovesAppOnlyToFormerPredecessor() throws {
        let note = RingMenuItem(label: "Note", icon: "note", actionType: .custom)
        let profile = AppHUDProfile(rings: AppHUDRings(
            inner: RingInheritance(appOnly: [AppOnlyItem(item: note, after: paste.id)])
        ))
        let oldGlobal = HUDActionLayout(inner: [copy, paste, spotlight], middle: [])
        let newGlobal = HUDActionLayout(inner: [copy, spotlight], middle: [])

        // Before repair (e.g. external edit): an unknown anchor appends at the end, never drops.
        let unrepaired = AppHUDResolver.resolve(global: newGlobal, profile: profile)
        XCTAssertEqual(unrepaired.layout.inner.map(\.id), [copy.id, spotlight.id, note.id])

        let repaired = AppHUDResolver.repairAfterGlobalChange(
            profile: profile,
            oldGlobal: oldGlobal,
            newGlobal: newGlobal
        )
        XCTAssertEqual(try XCTUnwrap(repaired.rings?.inner.appOnly.first?.after), copy.id)
        XCTAssertEqual(
            AppHUDResolver.resolve(global: newGlobal, profile: repaired).layout.inner.map(\.id),
            [copy.id, note.id, spotlight.id]
        )
    }

    func testCycleGuardEmitsEveryAppOnlyItemExactlyOnce() {
        let first = RingMenuItem(label: "First", icon: "1.circle", actionType: .custom)
        let second = RingMenuItem(label: "Second", icon: "2.circle", actionType: .custom)
        let selfAnchored = RingMenuItem(label: "Self", icon: "3.circle", actionType: .custom)
        let ring = RingInheritance(appOnly: [
            AppOnlyItem(item: first, after: second.id),
            AppOnlyItem(item: second, after: first.id),
            AppOnlyItem(item: selfAnchored, after: selfAnchored.id),
        ])
        let global = HUDActionLayout(inner: [copy], middle: [])

        let resolved = AppHUDResolver.resolve(global: global, rings: AppHUDRings(inner: ring))

        XCTAssertEqual(
            resolved.layout.inner.map(\.id),
            [copy.id, first.id, second.id, selfAnchored.id]
        )
    }

    func testHiddenAnchorDoesNotMoveItemsAnchoredToIt() {
        let note = RingMenuItem(label: "Note", icon: "note", actionType: .custom)
        let ring = RingInheritance(
            hidden: [paste.id],
            appOnly: [AppOnlyItem(item: note, after: paste.id)]
        )
        let global = HUDActionLayout(inner: [copy, paste, spotlight], middle: [])

        let resolved = AppHUDResolver.resolve(global: global, rings: AppHUDRings(inner: ring))

        XCTAssertEqual(resolved.layout.inner.map(\.id), [copy.id, note.id, spotlight.id])
        XCTAssertNil(resolved.origins[paste.id])
    }

    func testOverrideOfDeletedGlobalItemIsSkippedUntilRepairedThenKept() throws {
        var safariPaste = paste
        safariPaste.label = "Safari Paste"
        let profile = AppHUDProfile(rings: AppHUDRings(
            inner: RingInheritance(overrides: [paste.id: safariPaste], hidden: [UUID()])
        ))
        let global = HUDActionLayout(inner: [copy, spotlight], middle: [])

        let unrepaired = AppHUDResolver.resolve(global: global, profile: profile)
        XCTAssertEqual(unrepaired.layout.inner.map(\.id), [copy.id, spotlight.id])

        // Load-time fallback: Global's previous state is unknown, so the item goes to the end.
        let repaired = AppHUDResolver.repairAfterGlobalChange(
            profile: profile,
            oldGlobal: global,
            newGlobal: global
        )
        let ring = try XCTUnwrap(repaired.rings?.inner)
        XCTAssertTrue(ring.overrides.isEmpty)
        XCTAssertTrue(ring.hidden.isEmpty)
        XCTAssertEqual(
            AppHUDResolver.resolve(global: global, profile: repaired).layout.inner,
            [copy, spotlight, safariPaste]
        )
    }

    func testDeletedFirstGlobalItemOverrideStaysAtRingStart() throws {
        var safariCopy = copy
        safariCopy.label = "Safari Copy"
        let profile = AppHUDProfile(rings: AppHUDRings(
            inner: RingInheritance(overrides: [copy.id: safariCopy])
        ))
        let repaired = AppHUDResolver.repairAfterGlobalChange(
            profile: profile,
            oldGlobal: HUDActionLayout(inner: [copy, paste], middle: []),
            newGlobal: HUDActionLayout(inner: [paste], middle: [])
        )

        XCTAssertEqual(try XCTUnwrap(repaired.rings?.inner.appOnly), [AppOnlyItem(item: safariCopy, after: nil)])
    }

    func testRepairWithoutGlobalDeletionLeavesStorageByteEqual() throws {
        var safariCopy = copy
        safariCopy.label = "Safari Copy"
        let note = RingMenuItem(label: "Note", icon: "note", actionType: .custom)
        let profile = AppHUDProfile(rings: AppHUDRings(
            inner: RingInheritance(
                overrides: [copy.id: safariCopy],
                hidden: [spotlight.id],
                appOnly: [AppOnlyItem(item: note, after: paste.id)],
                customOrder: [paste.id, note.id, copy.id]
            )
        ))
        let oldGlobal = HUDActionLayout(inner: [copy, paste, spotlight], middle: [apps])
        var newGlobal = oldGlobal
        newGlobal.inner[1].label = "Paste v2"
        newGlobal.middle.append(snap)

        let repaired = AppHUDResolver.repairAfterGlobalChange(
            profile: profile,
            oldGlobal: oldGlobal,
            newGlobal: newGlobal
        )

        XCTAssertEqual(repaired, profile)
        XCTAssertEqual(try sortedJSON(repaired), try sortedJSON(profile))
    }

    // MARK: - Diff

    func testExplicitIdenticalOverrideSurvivesDiff() throws {
        let global = [copy, paste]
        let customized = AppHUDResolver.diff(
            edited: global,
            previous: RingInheritance(),
            global: global,
            origins: [copy.id: .customized, paste.id: .inherited]
        )
        XCTAssertEqual(customized.overrides, [copy.id: copy])

        // A later save without origin information keeps the identical override.
        let resaved = AppHUDResolver.diff(edited: global, previous: customized, global: global)
        XCTAssertEqual(resaved.overrides, [copy.id: copy])

        let resolved = AppHUDResolver.resolve(
            global: HUDActionLayout(inner: global, middle: []),
            rings: AppHUDRings(inner: resaved)
        )
        XCTAssertEqual(resolved.origins[copy.id], .customized)
    }

    func testDiffRecordsEditsHidesMissingItemsAndRecomputesAnchors() {
        let global = [copy, paste, spotlight]
        var edited = [copy, spotlight]
        edited[0].label = "Edited Copy"
        let note = RingMenuItem(label: "Note", icon: "note", actionType: .custom)
        edited.insert(note, at: 1)

        let ring = AppHUDResolver.diff(edited: edited, previous: RingInheritance(), global: global)

        XCTAssertEqual(ring.overrides, [copy.id: edited[0]])
        XCTAssertEqual(ring.hidden, [paste.id])
        XCTAssertEqual(ring.appOnly, [AppOnlyItem(item: note, after: copy.id)])
        XCTAssertNil(ring.customOrder)
        XCTAssertEqual(
            AppHUDResolver.resolve(
                global: HUDActionLayout(inner: global, middle: []),
                rings: AppHUDRings(inner: ring)
            ).layout.inner,
            edited
        )
    }

    func testDiffSetsCustomOrderOnlyWhenInheritedOrderDiffers() {
        let global = [copy, paste, spotlight]
        let reordered = AppHUDResolver.diff(
            edited: [spotlight, copy, paste],
            previous: RingInheritance(),
            global: global
        )
        XCTAssertEqual(reordered.customOrder, [spotlight.id, copy.id, paste.id])

        let restored = AppHUDResolver.diff(edited: global, previous: reordered, global: global)
        XCTAssertNil(restored.customOrder)
        XCTAssertTrue(restored.isEmpty)
    }

    func testUnknownHiddenAndOverrideIDsAreSkippedAndDroppedOnDiff() {
        let ghost = RingMenuItem(label: "Ghost", icon: "questionmark", actionType: .custom)
        let previous = RingInheritance(
            overrides: [ghost.id: ghost],
            hidden: [UUID()],
            customOrder: [UUID(), paste.id, copy.id]
        )
        let global = HUDActionLayout(inner: [copy, paste], middle: [])

        let resolved = AppHUDResolver.resolve(global: global, rings: AppHUDRings(inner: previous))
        XCTAssertEqual(resolved.layout.inner.map(\.id), [paste.id, copy.id])

        let saved = AppHUDResolver.diff(edited: resolved.layout.inner, previous: previous, global: global.inner)
        XCTAssertTrue(saved.overrides.isEmpty)
        XCTAssertTrue(saved.hidden.isEmpty)
        XCTAssertEqual(saved.customOrder, [paste.id, copy.id])
    }

    // MARK: - Overflow (AC14)

    func testAC14ItemsBeyondEightGoToNotShownInResolvedOrder() {
        let globalItems = (0..<8).map { RingMenuItem(label: "G\($0)", icon: "circle", actionType: .custom) }
        let extraA = RingMenuItem(label: "A", icon: "a.circle", actionType: .custom)
        let extraB = RingMenuItem(label: "B", icon: "b.circle", actionType: .custom)
        let ring = RingInheritance(appOnly: [
            AppOnlyItem(item: extraA, after: globalItems[3].id),
            AppOnlyItem(item: extraB, after: nil),
        ])
        let global = HUDActionLayout(inner: [], middle: globalItems)

        let resolved = AppHUDResolver.resolve(global: global, rings: AppHUDRings(middle: ring))

        XCTAssertEqual(resolved.layout.middle.count, AppHUDResolver.ringCapacity)
        XCTAssertEqual(
            resolved.layout.middle.map(\.id),
            [extraB.id] + globalItems[0...3].map(\.id) + [extraA.id] + globalItems[4...5].map(\.id)
        )
        XCTAssertEqual(resolved.notShown[.middle], Array(globalItems[6...7]))
        XCTAssertNil(resolved.notShown[.inner])
        XCTAssertEqual(resolved.origins[globalItems[7].id], .inherited)

        var hiding = ring
        hiding.hidden = [globalItems[0].id, globalItems[1].id]
        XCTAssertTrue(
            AppHUDResolver.resolve(global: global, rings: AppHUDRings(middle: hiding)).notShown.isEmpty
        )
    }

    // MARK: - Migration (AC16)

    func testAC16MigrationClassifiesItemsWithoutVisibleChange() throws {
        let note = RingMenuItem(label: "Note", icon: "note", actionType: .custom)
        var customizedPaste = paste
        customizedPaste.label = "Safari Paste"
        let global = HUDActionLayout(inner: [copy, paste, spotlight], middle: [apps, snap, menu])
        let v1 = HUDActionLayout(
            inner: [note, customizedPaste, copy],   // spotlight missing; order differs
            middle: [apps, snap, menu]
        )

        let rings = AppHUDResolver.migrate(v1Layout: v1, global: global)

        XCTAssertEqual(rings.inner.overrides, [paste.id: customizedPaste])
        XCTAssertEqual(rings.inner.hidden, [spotlight.id])
        XCTAssertEqual(rings.inner.appOnly, [AppOnlyItem(item: note, after: nil)])
        XCTAssertEqual(rings.inner.customOrder, [note.id, paste.id, copy.id])
        XCTAssertTrue(rings.middle.isEmpty)

        let resolved = AppHUDResolver.resolve(global: global, rings: rings)
        XCTAssertEqual(resolved.layout, v1)
        XCTAssertEqual(resolved.origins[copy.id], .inherited)
        XCTAssertEqual(resolved.origins[paste.id], .customized)
        XCTAssertEqual(resolved.origins[note.id], .appOnly)
        XCTAssertEqual(AppHUDResolver.resolve(global: global, profile: AppHUDProfile(layout: v1)), resolved)
    }

    func testAC16MigrationTreatsUnknownItemJSONDifferenceAsCustomized() throws {
        let global = try layout(inner: [itemJSON(copy, extra: ["future": "global"]), itemJSON(paste)])
        let v1 = try layout(inner: [itemJSON(copy, extra: ["future": "app"]), itemJSON(paste)])

        let rings = AppHUDResolver.migrate(v1Layout: v1, global: global)
        XCTAssertEqual(rings.inner.overrides, [copy.id: copy])

        let identical = AppHUDResolver.migrate(
            v1Layout: try layout(inner: [itemJSON(copy, extra: ["future": "global"]), itemJSON(paste)]),
            global: global
        )
        XCTAssertTrue(identical.inner.isEmpty)

        let resolved = AppHUDResolver.resolve(global: global, rings: rings)
        let saved = try savedItems(resolved.layout)
        XCTAssertEqual(saved[0]["future"] as? String, "app")
    }

    func testAC16MigrationIsIdempotentAndEncodesAsVersion2() throws {
        let global = HUDActionLayout(inner: [copy, paste], middle: [apps])
        var edited = paste
        edited.label = "Edited"
        let v1Profile = AppHUDProfile(layout: HUDActionLayout(inner: [edited, copy], middle: [apps]))

        let once = v1Profile.migrated(global: global)
        let twice = once.migrated(global: global)
        let reloaded = try JSONDecoder().decode(AppHUDProfile.self, from: JSONEncoder().encode(once))

        XCTAssertTrue(once.isInheriting)
        XCTAssertEqual(once, twice)
        XCTAssertEqual(reloaded, once)
        XCTAssertEqual(reloaded.migrated(global: global), once)
        XCTAssertEqual(
            AppHUDResolver.resolve(global: global, profile: reloaded).layout,
            v1Profile.v1Layout
        )

        let object = try jsonObject(once)
        XCTAssertEqual(object["schemaVersion"] as? Int, 2)
        XCTAssertNotNil(object["rings"])
        XCTAssertNil(object["layout"])
    }

    func testAC16V1ConfigurationEntryMigratesWithUnknownFieldsIntact() throws {
        let profileJSON: [String: Any] = try [
            "layout": [
                "inner": [itemJSON(copy, extra: ["futureItem": 1]), itemJSON(paste)],
                "middle": [itemJSON(apps)],
                "futureLayoutSetting": ["spacing": 12],
            ],
            "futureProfileSetting": "keep",
        ]
        let global = try layout(
            inner: [itemJSON(copy), itemJSON(paste)],
            middle: [itemJSON(apps)]
        )
        let v1 = try JSONDecoder().decode(
            AppHUDProfile.self,
            from: JSONSerialization.data(withJSONObject: profileJSON)
        )
        XCTAssertFalse(v1.isInheriting)

        let migrated = v1.migrated(global: global)
        let object = try jsonObject(migrated)
        XCTAssertEqual(object["futureProfileSetting"] as? String, "keep")
        let rings = try XCTUnwrap(object["rings"] as? [String: Any])
        XCTAssertEqual(rings["futureLayoutSetting"] as? NSDictionary, ["spacing": 12] as NSDictionary)

        // Layout-level unknown fields live in storage (`rings`, asserted above); the resolved
        // runtime layout is never saved, so compare what is shown.
        let resolved = AppHUDResolver.resolve(global: global, profile: migrated)
        XCTAssertEqual(resolved.layout.inner, v1.v1Layout?.inner)
        XCTAssertEqual(resolved.layout.middle, v1.v1Layout?.middle)
        XCTAssertEqual(try savedItems(resolved.layout)[0]["futureItem"] as? Int, 1)
    }

    // MARK: - Round trip and quarantine (AC17, AC18)

    func testAC17Version2RoundTripPreservesUnknownJSONAtEveryLevel() throws {
        let note = RingMenuItem(label: "Note", icon: "note", actionType: .custom)
        let profileJSON: [String: Any] = try [
            "schemaVersion": 2,
            "futureProfile": ["mode": "v3"],
            "rings": [
                "futureRings": true,
                "inner": [
                    "overrides": [itemJSON(copy, extra: ["futureOverride": "o"])],
                    "hidden": [paste.id.uuidString],
                    "appOnly": [[
                        "item": itemJSON(note, extra: ["futureItem": "a"]),
                        "after": copy.id.uuidString,
                        "futureAppOnly": 7,
                    ]],
                    "futureRing": [1, 2],
                ],
                "middle": ["customOrder": [apps.id.uuidString]],
            ],
        ]
        let data = try JSONSerialization.data(withJSONObject: profileJSON, options: [.sortedKeys])
        var decoded = try JSONDecoder().decode(AppHUDProfile.self, from: data)
        let ring = try XCTUnwrap(decoded.rings?.inner)
        XCTAssertEqual(ring.overrides, [copy.id: copy])
        XCTAssertEqual(ring.hidden, [paste.id])
        XCTAssertEqual(ring.appOnly.count, 1)
        XCTAssertEqual(ring.appOnly.first?.item, note)
        XCTAssertEqual(ring.appOnly.first?.after, copy.id)
        XCTAssertEqual(decoded.rings?.middle.customOrder, [apps.id])

        let reloaded = try JSONDecoder().decode(AppHUDProfile.self, from: JSONEncoder().encode(decoded))
        XCTAssertEqual(reloaded, decoded)

        // An edit through diff keeps the override's own unknown JSON.
        let global = HUDActionLayout(inner: [copy, paste], middle: [apps])
        var editedCopy = copy
        editedCopy.label = "Edited"
        decoded = AppHUDResolver.diff(
            edited: HUDActionLayout(inner: [editedCopy, note], middle: [apps]),
            previous: decoded,
            global: global
        )

        let object = try jsonObject(decoded)
        XCTAssertNil(object["layout"])
        XCTAssertEqual(object["futureProfile"] as? NSDictionary, ["mode": "v3"] as NSDictionary)
        let rings = try XCTUnwrap(object["rings"] as? [String: Any])
        XCTAssertEqual(rings["futureRings"] as? Bool, true)
        let inner = try XCTUnwrap(rings["inner"] as? [String: Any])
        XCTAssertEqual(inner["futureRing"] as? [Int], [1, 2])
        let override = try XCTUnwrap((inner["overrides"] as? [[String: Any]])?.first)
        XCTAssertEqual(override["label"] as? String, "Edited")
        XCTAssertEqual(override["futureOverride"] as? String, "o")
        let appOnly = try XCTUnwrap((inner["appOnly"] as? [[String: Any]])?.first)
        XCTAssertEqual((appOnly["item"] as? [String: Any])?["futureItem"] as? String, "a")
        XCTAssertEqual(appOnly["futureAppOnly"] as? Int, 7)
    }

    func testAC17MigratedConfigurationSavesAndReloadsUnchanged() throws {
        let global = HUDActionLayout(inner: [copy, paste], middle: [apps, snap])
        var edited = snap
        edited.label = "Finder Snap"
        let migrated = AppHUDProfile(layout: HUDActionLayout(inner: [paste], middle: [edited, apps]))
            .migrated(global: global)
        var configuration = Configuration(inner: global.inner, middle: global.middle)
        XCTAssertTrue(configuration.setAppHUDProfile(migrated, forBundleIdentifier: "com.apple.finder"))

        let firstSave = try sortedData(configuration)
        let reloaded = try JSONDecoder().decode(Configuration.self, from: firstSave)
        let secondSave = try sortedData(reloaded)

        XCTAssertEqual(firstSave, secondSave)
        XCTAssertEqual(reloaded.appHUDProfile(forBundleIdentifier: "com.apple.finder"), migrated)
    }

    func testAC18UnreadableVersion2EntriesStayQuarantinedAndRoundTripUnchanged() throws {
        let futureProfile: [String: Any] = [
            "schemaVersion": 3,
            "rings": ["inner": [String: Any](), "middle": [String: Any]()],
            "futureOnly": "x",
        ]
        let brokenProfile: [String: Any] = [
            "schemaVersion": 2,
            "rings": ["inner": ["overrides": "not-an-array"]],
        ]
        let missingRings: [String: Any] = ["schemaVersion": 2]
        let base = try JSONEncoder().encode(Configuration(inner: [], middle: []))
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: base) as? [String: Any])
        let profiles: [String: Any] = [
            "com.example.future": futureProfile,
            "com.example.broken": brokenProfile,
            "com.example.missing": missingRings,
        ]
        object["appHUDProfiles"] = profiles

        var decoded = try JSONDecoder().decode(
            Configuration.self,
            from: JSONSerialization.data(withJSONObject: object)
        )
        for bundleIdentifier in profiles.keys {
            XCTAssertTrue(decoded.hasUnavailableAppHUDProfile(forBundleIdentifier: bundleIdentifier))
            XCTAssertNil(decoded.appHUDProfile(forBundleIdentifier: bundleIdentifier))
        }

        decoded.behavior.dismissOnEscape.toggle()
        let saved = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(decoded)) as? [String: Any]
        )
        XCTAssertEqual(saved["appHUDProfiles"] as? NSDictionary, profiles as NSDictionary)
    }

    // MARK: - Whole-ring inheritance (AC20–AC27)

    func testLockUsesGlobalKeystrokeClearsOnlyInnerAndPreservesSiblingMetadata() throws {
        var global = HUDActionLayout(inner: [copy, paste], middle: [apps, snap, menu])
        global.inner[0].keystrokePayload = .key(keyCode: 8, modifiers: 1 << 20)
        let middle = RingInheritance(
            overrides: [menu.id: menu], hidden: [apps.id],
            appOnly: [AppOnlyItem(item: spotlight, after: apps.id)],
            customOrder: [menu.id, spotlight.id]
        )
        let profile = AppHUDProfile(rings: AppHUDRings(
            inner: RingInheritance(overrides: [copy.id: copy], hidden: [paste.id]),
            middle: middle
        ))
        let before = AppHUDResolver.resolve(global: global, profile: profile)
        let saved = AppHUDResolver.diff(
            edited: before.layout, previous: profile, global: global,
            origins: before.origins, lockedBands: [.inner], customOrderBands: [.middle]
        )
        let resolved = AppHUDResolver.resolve(global: global, profile: saved)

        XCTAssertEqual(saved.rings?.middle, middle)
        XCTAssertEqual(saved.rings?.inner, RingInheritance(followsGlobal: true))
        XCTAssertEqual(resolved.lockedBands, [.inner])
        XCTAssertEqual(resolved.customOrderBands, [.middle])
        XCTAssertEqual(resolved.layout.inner, global.inner)
        XCTAssertEqual(resolved.origins[copy.id], .inherited)
        XCTAssertEqual(resolved.layout.middle, before.layout.middle)
        XCTAssertEqual(resolved.origins[menu.id], .customized)
        XCTAssertEqual(resolved.origins[spotlight.id], .appOnly)
    }

    func testLockingInnerKeepsExplicitMiddleOverrideWithSameItemID() throws {
        var global = HUDActionLayout(inner: [copy], middle: [copy])
        let previous = AppHUDProfile(rings: AppHUDRings(
            inner: RingInheritance(hidden: [copy.id]),
            middle: RingInheritance(overrides: [copy.id: copy])
        ))
        var draft = try XCTUnwrap(previous.rings)
        draft.inner = RingInheritance(followsGlobal: true)
        let resolved = AppHUDResolver.resolve(global: global, rings: draft)
        XCTAssertEqual(resolved.origins[copy.id], .inherited)
        XCTAssertEqual(resolved.originsByBand[.inner]?[copy.id], .inherited)
        XCTAssertEqual(resolved.originsByBand[.middle]?[copy.id], .customized)
        let saved = AppHUDResolver.diff(
            edited: resolved.layout, previous: previous, global: global,
            origins: resolved.origins, lockedBands: resolved.lockedBands, originsByBand: resolved.originsByBand
        )
        XCTAssertEqual(saved.rings, draft)
        global.inner[0].label = "Updated Inner"
        global.middle[0].label = "Updated Middle"
        let next = AppHUDResolver.resolve(global: global, profile: saved)
        XCTAssertEqual(next.layout.inner, global.inner)
        XCTAssertEqual(next.layout.middle, [copy])
    }

    func testLockedMiddleTracksGlobalEditsAndSkipsRepairIncludingOuterItems() throws {
        var parent = apps
        parent.subItems = [copy]
        let oldGlobal = HUDActionLayout(inner: [], middle: [parent, snap, menu])
        // Even stale known fields on a locked ring must never enter resolution or repair.
        let stale = RingInheritance(
            followsGlobal: true, overrides: [snap.id: snap], hidden: [menu.id],
            appOnly: [AppOnlyItem(item: paste, after: snap.id)], customOrder: [snap.id]
        )
        let profile = AppHUDProfile(rings: AppHUDRings(middle: stale))
        parent.subItems = [paste, copy]
        let newGlobal = try layout(inner: [], middle: [
            itemJSON(menu), itemJSON(spotlight), itemJSON(parent, extra: ["future": 7]),
        ])
        let repaired = AppHUDResolver.repairAfterGlobalChange(
            profile: profile, oldGlobal: oldGlobal, newGlobal: newGlobal
        )
        let resolved = AppHUDResolver.resolve(global: newGlobal, profile: repaired)

        XCTAssertEqual(profile, repaired)
        XCTAssertEqual(try sortedJSON(profile), try sortedJSON(repaired))
        XCTAssertEqual(resolved.layout.middle, newGlobal.middle)
        XCTAssertEqual(resolved.layout.preservedMiddleItemsJSON, newGlobal.preservedMiddleItemsJSON)
        XCTAssertTrue(newGlobal.middle.allSatisfy { resolved.origins[$0.id] == .inherited })
        XCTAssertEqual(resolved.lockedBands, [.middle])
        XCTAssertTrue(resolved.customOrderBands.isEmpty)
    }

    func testLockRoundTripClearsKnownCustomizationPreservesUnknownKeysAndDefaultsOff() throws {
        let raw: [String: Any] = try [
            "schemaVersion": 2, "futureProfile": true, "rings": [
                "futureRings": 9, "inner": [
                    "futureRing": ["x": 4], "followsGlobal": true,
                    "overrides": [itemJSON(copy)], "hidden": [paste.id.uuidString],
                    "appOnly": [["item": itemJSON(menu)]], "customOrder": [copy.id.uuidString],
                ],
            ],
        ]
        let decoded = try JSONDecoder().decode(
            AppHUDProfile.self, from: JSONSerialization.data(withJSONObject: raw)
        )
        let global = HUDActionLayout(inner: [copy, paste], middle: [])
        let saved = AppHUDResolver.diff(edited: HUDActionLayout(inner: [menu], middle: []),
                                        previous: decoded, global: global)
        let object = try jsonObject(saved)
        let rings = try XCTUnwrap(object["rings"] as? [String: Any])
        let inner = try XCTUnwrap(rings["inner"] as? [String: Any])
        XCTAssertEqual(object["schemaVersion"] as? Int, 2)
        XCTAssertEqual(object["futureProfile"] as? Bool, true)
        XCTAssertEqual(rings["futureRings"] as? Int, 9)
        XCTAssertEqual(inner["futureRing"] as? [String: Int], ["x": 4])
        XCTAssertEqual(inner["followsGlobal"] as? Bool, true)
        for key in ["overrides", "hidden", "appOnly"] {
            XCTAssertEqual((inner[key] as? [Any])?.count, 0)
        }
        XCTAssertNil(inner["customOrder"])
        let reloaded = try JSONDecoder().decode(AppHUDProfile.self, from: JSONEncoder().encode(saved))
        XCTAssertEqual(AppHUDResolver.resolve(global: global, profile: reloaded).lockedBands, [.inner])
        XCTAssertEqual(reloaded.rings?.middle.followsGlobal, false)
        let legacy = AppHUDProfile(layout: global).migrated(global: global)
        XCTAssertEqual(legacy.rings, AppHUDRings())
        XCTAssertNil((rings["middle"] as? [String: Any])?["followsGlobal"])
    }

    func testExplicitUnlockLeavesGlobalContentInheritedAndAllowsNextEdit() {
        let global = HUDActionLayout(inner: [copy, paste], middle: [menu])
        let locked = RingInheritance(followsGlobal: true)
        let profile = AppHUDProfile(rings: AppHUDRings(inner: locked, middle: locked))
        let unlocked = AppHUDResolver.diff(edited: global, previous: profile, global: global, lockedBands: [])
        let resolved = AppHUDResolver.resolve(global: global, profile: unlocked)
        XCTAssertEqual(unlocked, AppHUDProfile())
        XCTAssertEqual(resolved.layout, global)
        XCTAssertTrue(resolved.origins.values.allSatisfy { $0 == .inherited })
        var edited = resolved.layout
        edited.inner[0].label = "Safari Copy"
        let saved = AppHUDResolver.diff(edited: edited, previous: unlocked, global: global)
        XCTAssertEqual(saved.rings?.inner.overrides[copy.id], edited.inner[0])
    }

    func testCoincidentStoredOrderSurvivesSiblingLockAndCanBeExplicitlyReverted() {
        let global = HUDActionLayout(inner: [copy, paste], middle: [apps, snap])
        let profile = AppHUDProfile(rings: AppHUDRings(middle: RingInheritance(customOrder: [apps.id])))
        let before = AppHUDResolver.resolve(global: global, profile: profile)
        XCTAssertEqual(before.layout, global)
        XCTAssertEqual(before.customOrderBands, [.middle])
        let saved = AppHUDResolver.diff(
            edited: global, previous: profile, global: global, lockedBands: [.inner],
            customOrderBands: before.customOrderBands
        )
        XCTAssertEqual(saved.rings?.middle, profile.rings?.middle)
        let reverted = AppHUDResolver.diff(
            edited: global, previous: saved, global: global, customOrderBands: []
        )
        XCTAssertNil(reverted.rings?.middle.customOrder)
        XCTAssertEqual(reverted.rings?.inner.followsGlobal, true)
    }

    func testLockedBandResolvesVerbatimWithoutOverflowWarnings() {
        let items = (0...AppHUDResolver.ringCapacity).map {
            RingMenuItem(label: "Global \($0)", icon: "circle", actionType: .custom)
        }
        let global = HUDActionLayout(inner: items, middle: [])
        let resolved = AppHUDResolver.resolve(
            global: global, rings: AppHUDRings(inner: RingInheritance(followsGlobal: true))
        )
        XCTAssertEqual(resolved.layout.inner, items)
        XCTAssertNil(resolved.notShown[.inner])
    }

    // MARK: - Helpers

    private func itemJSON(_ item: RingMenuItem, extra: [String: Any] = [:]) throws -> [String: Any] {
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(item)) as? [String: Any]
        )
        object.merge(extra) { _, new in new }
        return object
    }

    private func layout(inner: [[String: Any]], middle: [[String: Any]] = []) throws -> HUDActionLayout {
        try JSONDecoder().decode(
            HUDActionLayout.self,
            from: JSONSerialization.data(withJSONObject: ["inner": inner, "middle": middle])
        )
    }

    private func savedItems(_ layout: HUDActionLayout) throws -> [[String: Any]] {
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(layout)) as? [String: Any]
        )
        return try XCTUnwrap(object["inner"] as? [[String: Any]])
    }

    private func jsonObject(_ profile: AppHUDProfile) throws -> [String: Any] {
        try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(profile)) as? [String: Any]
        )
    }

    private func sortedJSON(_ profile: AppHUDProfile) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(profile)
    }

    private func sortedData(_ configuration: Configuration) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(configuration)
    }
}
