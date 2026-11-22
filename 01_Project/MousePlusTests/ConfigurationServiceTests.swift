import Foundation
import XCTest
@testable import MousePlus

final class ConfigurationServiceTests: XCTestCase {
    private var temporaryDirectories: [URL] = []

    override func tearDownWithError() throws {
        for directory in temporaryDirectories {
            try? FileManager.default.removeItem(at: directory)
        }
    }

    func testAbsentFileReturnsExplicitDefaults() async throws {
        let service = makeService()

        let result = try await service.loadResult()

        guard case .defaults = result else {
            return XCTFail("An absent file must be distinguished from a loaded file")
        }
    }

    func testValidFileLoadsAsPersistedConfiguration() async throws {
        let service = makeService()
        let expected = Configuration()
        try await service.save(expected)

        let result = try await service.loadResult()

        guard case .loaded = result else {
            return XCTFail("Expected a persisted configuration")
        }
    }

    func testServicePersistsAppProfilesAndGlobalHUDShortcut() async throws {
        let service = makeService()
        let profile = AppHUDProfile(layout: HUDActionLayout(
            inner: [RingMenuItem(label: "Finder inner", icon: "circle", actionType: .custom)],
            middle: [RingMenuItem(label: "Finder middle", icon: "square", actionType: .custom)]
        ))
        let shortcut = TriggerBinding.keyboard(
            keyCode: 122,
            modifiers: 1 << 20,
            mode: .tapToggle
        )
        let configuration = Configuration(
            triggers: TriggersConfig(globalHUDShortcut: shortcut),
            appHUDProfiles: ["com.apple.finder": profile]
        )

        try await service.save(configuration)
        let reloaded = try await service.loadResult().configuration

        XCTAssertEqual(reloaded.triggers.globalHUDShortcut, shortcut)
        // The saved copy migrates at load into inheritance metadata that shows
        // exactly the same items.
        let migrated = profile.migrated(global: reloaded.globalHUDActionLayout)
        XCTAssertTrue(migrated.isInheriting)
        XCTAssertEqual(reloaded.appHUDProfile(forBundleIdentifier: "com.apple.finder"), migrated)
        XCTAssertEqual(reloaded.validAppHUDProfiles, ["com.apple.finder": migrated])
        XCTAssertEqual(
            reloaded.resolvedAppLayout(forBundleIdentifier: "com.apple.finder")?.layout,
            profile.v1Layout
        )
    }

    // MARK: - App HUD inheritance migration (AC16–AC18)

    func testVersion1FileLoadsWithIdenticalResolvedLayout() async throws {
        let fixture = Version1Fixture()
        let service = makeService()
        let before = fixture.configuration
        try await writeRaw(fixture.data(), to: service)

        let loaded = try await service.loadResult().configuration

        XCTAssertTrue(loaded.migratedAppHUDProfilesOnLoad)
        let stored = try XCTUnwrap(loaded.appHUDProfile(forBundleIdentifier: Version1Fixture.finder))
        XCTAssertTrue(stored.isInheriting)
        let resolved = try XCTUnwrap(loaded.resolvedAppLayout(forBundleIdentifier: Version1Fixture.finder))
        XCTAssertEqual(resolved.layout, fixture.v1Layout)
        XCTAssertEqual(resolved.origins[fixture.copy.id], .inherited)
        XCTAssertEqual(resolved.origins[fixture.snap.id], .customized)
        XCTAssertEqual(resolved.origins[fixture.note.id], .appOnly)
        XCTAssertEqual(stored.rings?.inner.hidden, [fixture.paste.id])
        XCTAssertNotNil(stored.rings?.middle.customOrder)

        let snapshot = FrontmostAppSnapshot(
            processIdentifier: 3,
            bundleIdentifier: Version1Fixture.finder,
            localizedName: "Finder"
        )
        XCTAssertEqual(
            loaded.resolveHUD(
                route: .contextual,
                frontmostApp: snapshot,
                mousePlusBundleIdentifier: "com.xpycode.MousePlus"
            ),
            before.resolveHUD(
                route: .contextual,
                frontmostApp: snapshot,
                mousePlusBundleIdentifier: "com.xpycode.MousePlus"
            )
        )
    }

    func testPreMigrationBackupIsWrittenOnceBeforeFirstSave() async throws {
        let fixture = Version1Fixture()
        let service = makeService()
        let original = try fixture.data()
        try await writeRaw(original, to: service)
        let backupURL = service.preInheritanceBackupURL
        let store = await service.store

        let firstLoad = try await service.loadResult().configuration
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: backupURL.path),
            "Loading alone must not write anything"
        )

        try await service.save(firstLoad)
        XCTAssertEqual(try Data(contentsOf: backupURL), original)
        XCTAssertEqual(
            backupURL.deletingLastPathComponent(),
            store.configurationURL.deletingLastPathComponent()
        )
        let savedProfiles = try XCTUnwrap(try savedObject(store)["appHUDProfiles"] as? [String: Any])
        let savedProfile = try XCTUnwrap(savedProfiles[Version1Fixture.finder] as? [String: Any])
        XCTAssertNil(savedProfile["layout"])
        XCTAssertNotNil(savedProfile["rings"])

        // The migrated file is now on disk: a second load migrates nothing and
        // writes nothing, and a later save leaves the backup untouched.
        let directoryBefore = try directoryListing(store)
        let secondLoad = try await service.loadResult().configuration
        XCTAssertFalse(secondLoad.migratedAppHUDProfilesOnLoad)
        XCTAssertEqual(try directoryListing(store), directoryBefore)
        XCTAssertEqual(
            secondLoad.resolvedAppLayout(forBundleIdentifier: Version1Fixture.finder)?.layout,
            fixture.v1Layout
        )
        XCTAssertEqual(
            secondLoad.appHUDProfile(forBundleIdentifier: Version1Fixture.finder),
            firstLoad.appHUDProfile(forBundleIdentifier: Version1Fixture.finder)
        )

        try Data("sentinel".utf8).write(to: backupURL)
        try await service.save(secondLoad)
        XCTAssertEqual(try Data(contentsOf: backupURL), Data("sentinel".utf8))
    }

    func testPreMigrationBackupNeverOverwritesAnExistingBackup() async throws {
        let fixture = Version1Fixture()
        let service = makeService()
        try await writeRaw(fixture.data(), to: service)
        let backupURL = service.preInheritanceBackupURL
        try Data("earlier backup".utf8).write(to: backupURL)

        let loaded = try await service.loadResult().configuration
        try await service.save(loaded)

        XCTAssertEqual(try Data(contentsOf: backupURL), Data("earlier backup".utf8))
    }

    func testSavingWithoutCopiedProfilesWritesNoMigrationBackup() async throws {
        let service = makeService()
        var configuration = Configuration()
        XCTAssertTrue(configuration.setAppHUDProfile(
            configuration.makeAppHUDProfileFromGlobal(),
            forBundleIdentifier: Version1Fixture.finder
        ))
        try await service.save(configuration)
        let loaded = try await service.loadResult().configuration
        try await service.save(loaded)

        XCTAssertFalse(loaded.migratedAppHUDProfilesOnLoad)
        XCTAssertFalse(FileManager.default.fileExists(atPath: service.preInheritanceBackupURL.path))
    }

    func testQuarantinedProfileRoundTripsUnchangedAlongsideMigration() async throws {
        let fixture = Version1Fixture()
        let service = makeService()
        let unreadable: [String: Any] = [
            "layout": ["inner": "invalid", "middle": []],
            "futurePayload": ["revision": 9],
        ]
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: fixture.data()) as? [String: Any]
        )
        var profiles = try XCTUnwrap(object["appHUDProfiles"] as? [String: Any])
        profiles["com.example.broken"] = unreadable
        object["appHUDProfiles"] = profiles
        try await writeRaw(JSONSerialization.data(withJSONObject: object), to: service)

        let loaded = try await service.loadResult().configuration
        XCTAssertTrue(loaded.migratedAppHUDProfilesOnLoad)
        XCTAssertTrue(loaded.hasUnavailableAppHUDProfile(forBundleIdentifier: "com.example.broken"))
        XCTAssertNil(loaded.resolvedAppLayout(forBundleIdentifier: "com.example.broken"))
        try await service.save(loaded)

        let store = await service.store
        let saved = try XCTUnwrap(try savedObject(store)["appHUDProfiles"] as? [String: Any])
        XCTAssertEqual(saved["com.example.broken"] as? NSDictionary, unreadable as NSDictionary)
        XCTAssertNotNil((saved[Version1Fixture.finder] as? [String: Any])?["rings"])
    }

    func testSetAppHUDInheritanceUpdatesOnlyExistingReadableProfiles() throws {
        let fixture = Version1Fixture()
        var configuration = try JSONDecoder().decode(Configuration.self, from: fixture.data())
        var rings = try XCTUnwrap(
            configuration.appHUDProfile(forBundleIdentifier: Version1Fixture.finder)?.rings
        )
        rings.inner.hidden = []

        XCTAssertTrue(configuration.setAppHUDInheritance(rings, forBundleIdentifier: Version1Fixture.finder))
        XCTAssertEqual(configuration.appHUDProfile(forBundleIdentifier: Version1Fixture.finder)?.rings, rings)
        XCTAssertEqual(
            configuration.resolvedAppLayout(forBundleIdentifier: Version1Fixture.finder)?
                .layout.inner.map(\.label),
            ["Note", "Copy", "Paste"]
        )
        XCTAssertFalse(configuration.setAppHUDInheritance(AppHUDRings(), forBundleIdentifier: "com.apple.Notes"))
        XCTAssertNil(configuration.appHUDProfile(forBundleIdentifier: "com.apple.Notes"))
    }

    func testLoadRepairTurnsOrphanedOverrideIntoAppOnlyItem() throws {
        let fixture = Version1Fixture()
        let orphan = RingMenuItem(label: "Gone", icon: "xmark", actionType: .custom, actionData: "kept")
        let profile = AppHUDProfile(rings: AppHUDRings(
            inner: RingInheritance(overrides: [orphan.id: orphan])
        ))
        var configuration = fixture.configuration
        XCTAssertTrue(configuration.setAppHUDProfile(profile, forBundleIdentifier: "com.apple.Safari"))

        let reloaded = try JSONDecoder().decode(
            Configuration.self,
            from: JSONEncoder().encode(configuration)
        )

        let rings = try XCTUnwrap(reloaded.appHUDProfile(forBundleIdentifier: "com.apple.Safari")?.rings)
        XCTAssertTrue(rings.inner.overrides.isEmpty)
        XCTAssertEqual(rings.inner.appOnly.map(\.item), [orphan])
        XCTAssertEqual(
            reloaded.resolvedAppLayout(forBundleIdentifier: "com.apple.Safari")?.layout.inner.last,
            orphan
        )
    }

    func testServicePreservesUnreadableProfileDuringUnrelatedSave() async throws {
        let service = makeService()
        let store = await service.store
        try FileManager.default.createDirectory(
            at: store.configurationURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        var source = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(Configuration())) as? [String: Any]
        )
        let unreadable: [String: Any] = [
            "layout": ["inner": "invalid", "middle": []],
            "futurePayload": ["revision": 9, "enabled": true],
        ]
        source["appHUDProfiles"] = ["com.apple.finder": unreadable]
        try JSONSerialization.data(withJSONObject: source).write(to: store.configurationURL)

        var loaded = try await service.loadResult().configuration
        loaded.behavior.dismissOnClickOutside.toggle()
        try await service.save(loaded)

        let saved = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: store.configurationURL)) as? [String: Any]
        )
        let profiles = try XCTUnwrap(saved["appHUDProfiles"] as? [String: Any])
        XCTAssertEqual(profiles["com.apple.finder"] as? NSDictionary, unreadable as NSDictionary)
    }

    func testLegacySampleAppsGroupMigratesToRunningAppsWithoutDroppingPinnedChildren() throws {
        let child = RingMenuItem(
            label: "Pinned App", icon: "app.fill", actionType: .appSwitch,
            actionData: "com.example.Pinned"
        )
        let parentID = UUID()
        let legacyParent = RingMenuItem(
            id: parentID,
            label: "Apps",
            icon: "square.grid.2x2",
            actionType: .appSwitch,
            subItems: [child]
        )
        let encoded = try JSONEncoder().encode(Configuration(inner: [], middle: [legacyParent]))
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "schemaVersion")

        let decoded = try JSONDecoder().decode(
            Configuration.self,
            from: JSONSerialization.data(withJSONObject: object)
        )

        XCTAssertEqual(decoded.middle[0].id, parentID)
        XCTAssertEqual(decoded.middle[0].dynamicSource, .runningApps)
        XCTAssertEqual(decoded.middle[0].subItems, [child])
    }

    func testCurrentStaticAppsGroupIsNotMistakenForLegacySample() throws {
        let staticParent = RingMenuItem(
            label: "Apps",
            icon: "square.grid.2x2",
            actionType: .appSwitch,
            subItems: [RingMenuItem(
                label: "Pinned App", icon: "app.fill", actionType: .appSwitch,
                actionData: "com.example.Pinned"
            )]
        )

        let decoded = try JSONDecoder().decode(
            Configuration.self,
            from: JSONEncoder().encode(Configuration(inner: [], middle: [staticParent]))
        )

        XCTAssertEqual(decoded.middle[0].dynamicSource, .none)
        XCTAssertEqual(decoded.middle[0].subItems, staticParent.subItems)
    }

    func testLegacyConfigurationReceivesCompatibleHUDDefaults() throws {
        let current = Configuration()
        let encoded = try JSONEncoder().encode(current)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "hudCustomization")

        let decoded = try JSONDecoder().decode(
            Configuration.self,
            from: JSONSerialization.data(withJSONObject: object)
        )

        XCTAssertEqual(decoded.hudCustomization, .default)
        XCTAssertEqual(decoded.inner.map(\.id), current.inner.map(\.id))
        XCTAssertEqual(decoded.middle.map(\.id), current.middle.map(\.id))
        XCTAssertEqual(decoded.triggers, current.triggers)
        XCTAssertEqual(decoded.behavior, current.behavior)
    }

    func testLegacyMotionSettingsSeedRoleBasedConfiguration() throws {
        let decoded = try JSONDecoder().decode(
            Configuration.self,
            from: fixtureData(named: "legacy-motion-settings")
        )

        XCTAssertEqual(decoded.appearance.motion.isEnabled, false)
        XCTAssertEqual(decoded.appearance.motion.baseDuration, 0.42)
        XCTAssertEqual(decoded.appearance.motion.summon, .fade)
        XCTAssertEqual(decoded.appearance.motion.hover, .emphasis)
        XCTAssertEqual(decoded.appearance.motion.outerExpansion, .radialReveal)
        XCTAssertEqual(decoded.appearance.motion.branchChange, .crossfade)
        XCTAssertEqual(decoded.appearance.animationEnabled, false)
        XCTAssertEqual(decoded.appearance.animationDuration, 0.42)
    }

    func testRoleBasedMotionConfigurationRoundTripsEveryChoice() throws {
        let expected = HUDMotionConfiguration(
            isEnabled: true,
            baseDuration: 0.31,
            summon: .off,
            hover: .off,
            outerExpansion: .off,
            branchChange: .off
        )
        let configuration = Configuration(appearance: AppearanceConfig(motion: expected))

        let data = try JSONEncoder().encode(configuration)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let appearance = try XCTUnwrap(object["appearance"] as? [String: Any])
        XCTAssertNotNil(appearance["motion"])
        XCTAssertNil(appearance["animationEnabled"])
        XCTAssertNil(appearance["animationDuration"])

        let decoded = try JSONDecoder().decode(Configuration.self, from: data)
        XCTAssertEqual(decoded.appearance.motion, expected)
    }

    func testEverySummonMotionStyleRoundTripsWithStableRawValue() throws {
        let expectedRawValues = [
            "off",
            "fade",
            "circularSweep",
            "irisReveal",
            "bloom",
            "staggeredSegments",
        ]

        XCTAssertEqual(HUDSummonMotionStyle.allCases.map(\.rawValue), expectedRawValues)

        for style in HUDSummonMotionStyle.allCases {
            let configuration = Configuration(
                appearance: AppearanceConfig(
                    motion: HUDMotionConfiguration(summon: style)
                )
            )

            let encoded = try JSONEncoder().encode(configuration)
            let decoded = try JSONDecoder().decode(Configuration.self, from: encoded)

            XCTAssertEqual(decoded.appearance.motion.summon, style)
        }
    }

    func testMissingSummonMotionStyleKeepsFadeDefaultAndOtherFields() throws {
        let json = """
        {
          "inner": [],
          "middle": [],
          "appearance": {
            "motion": {
              "isEnabled": false,
              "baseDuration": 0.27,
              "hover": "off",
              "outerExpansion": "off",
              "branchChange": "off"
            }
          }
        }
        """

        let decoded = try JSONDecoder().decode(Configuration.self, from: Data(json.utf8))

        XCTAssertEqual(decoded.appearance.motion.summon, .fade)
        XCTAssertEqual(decoded.appearance.motion.isEnabled, false)
        XCTAssertEqual(decoded.appearance.motion.baseDuration, 0.27)
        XCTAssertEqual(decoded.appearance.motion.hover, .off)
        XCTAssertEqual(decoded.appearance.motion.outerExpansion, .off)
        XCTAssertEqual(decoded.appearance.motion.branchChange, .off)
    }

    func testMalformedMotionFieldsFallBackIndependently() throws {
        let json = """
        {
          "inner": [],
          "middle": [],
          "appearance": {
            "motion": {
              "isEnabled": false,
              "baseDuration": 0.27,
              "summon": "futureSummon",
              "hover": "off",
              "outerExpansion": 17,
              "branchChange": "crossfade"
            }
          }
        }
        """

        let decoded = try JSONDecoder().decode(Configuration.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.appearance.motion.isEnabled, false)
        XCTAssertEqual(decoded.appearance.motion.baseDuration, 0.27)
        XCTAssertEqual(decoded.appearance.motion.summon, .fade)
        XCTAssertEqual(decoded.appearance.motion.hover, .off)
        XCTAssertEqual(decoded.appearance.motion.outerExpansion, .radialReveal)
        XCTAssertEqual(decoded.appearance.motion.branchChange, .crossfade)
    }

    func testMalformedHUDFieldsPreserveKnownConfigurationAndUnknownAction() throws {
        let id = UUID()
        let json = """
        {
          "inner": [],
          "middle": [{
            "id": "\(id.uuidString)",
            "label": "Future action",
            "icon": "sparkles",
            "actionType": "newerVersionAction",
            "actionData": "opaque-payload"
          }],
          "hudCustomization": {
            "inner": {
              "layout": {
                "slotCountMode": "invalid",
                "fixedSlotCount": 999,
                "angularOffset": 725
              },
              "appearance": { "iconOrientation": "tangential" }
            },
            "outerRingVisibility": 123
          }
        }
        """

        let decoded = try JSONDecoder().decode(Configuration.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.middle.first?.actionType, .unavailable("newerVersionAction"))
        XCTAssertEqual(decoded.middle.first?.actionData, "opaque-payload")
        XCTAssertEqual(decoded.hudCustomization.inner.layout.slotCountMode, .auto)
        XCTAssertEqual(decoded.hudCustomization.inner.layout.fixedSlotCount, 8)
        XCTAssertEqual(decoded.hudCustomization.inner.layout.angularOffset, 5)
        XCTAssertEqual(decoded.hudCustomization.inner.appearance.iconOrientation, .tangential)
        XCTAssertEqual(decoded.hudCustomization.outerRingVisibility, .alwaysVisible)

        let roundTripped = try JSONDecoder().decode(
            Configuration.self,
            from: JSONEncoder().encode(decoded)
        )
        XCTAssertEqual(roundTripped.middle.first?.actionType, .unavailable("newerVersionAction"))
        XCTAssertEqual(roundTripped.middle.first?.actionData, "opaque-payload")
    }

    @MainActor
    func testCurrentProductionFixtureMigratesToCompatibleResolvedRenderInputs() async throws {
        let configuration = try await loadFixtureThroughService(named: "current-production")
        let inputs = resolvedRenderInputs(configuration)

        XCTAssertEqual(inputs.geometry.inner.slotCount, 1)
        XCTAssertEqual(inputs.geometry.middle.slotCount, 2)
        XCTAssertEqual(inputs.geometry.inner.angularOffset, 0, accuracy: 0.000_001)
        XCTAssertEqual(inputs.geometry.middle.angularOffset, 0, accuracy: 0.000_001)
        XCTAssertEqual(inputs.outerVisibility, .alwaysVisible)
        XCTAssertEqual(inputs.innerOrientation, .upright)
        XCTAssertEqual(inputs.middleOrientation, .upright)
        XCTAssertEqual(inputs.outerOrientation, .upright)
        XCTAssertEqual(inputs.firstMiddleColors.requestedWedge, .black)
        XCTAssertEqual(inputs.firstMiddleColors.requestedIcon, .white)
        assertUnknownAction(
            configuration.middle[0],
            rawValue: "futureProductionAction",
            payload: "opaque:{\"version\":7,\"flags\":[\"a\",\"b\"]}"
        )
        try assertCanonicalRoundTrip(configuration, fixtureName: "current-production")
    }

    @MainActor
    func testPreInnerMiddleFixtureMigratesFlatItemsWithoutChangingCompatibilityAppearance() async throws {
        let configuration = try await loadFixtureThroughService(named: "pre-inner-middle-legacy")
        let inputs = resolvedRenderInputs(configuration)

        XCTAssertTrue(configuration.inner.isEmpty)
        XCTAssertEqual(configuration.middle.count, 2)
        XCTAssertEqual(inputs.geometry.inner.slotCount, 1)
        XCTAssertEqual(inputs.geometry.middle.slotCount, 2)
        XCTAssertEqual(inputs.outerVisibility, .alwaysVisible)
        XCTAssertEqual(inputs.innerOrientation, .upright)
        XCTAssertEqual(inputs.middleOrientation, .upright)
        XCTAssertEqual(inputs.firstMiddleColors.requestedWedge, .black)
        XCTAssertEqual(inputs.firstMiddleColors.renderedIcon, .white)
        XCTAssertEqual(
            configuration.triggers.keyboard,
            .keyboard(keyCode: 96, modifiers: 1_048_576, mode: .holdRelease)
        )
        assertUnknownAction(
            configuration.middle[0],
            rawValue: "legacyPluginAction",
            payload: "plugin://payload?keep=true"
        )
        try assertCanonicalRoundTrip(configuration, fixtureName: "pre-inner-middle-legacy")
    }

    @MainActor
    func testPartialNewFixtureDefaultsOnlyMissingResolvedRenderInputs() async throws {
        let configuration = try await loadFixtureThroughService(named: "partial-new-shape")
        let inputs = resolvedRenderInputs(configuration)

        XCTAssertEqual(inputs.geometry.inner.slotCount, 6)
        XCTAssertEqual(inputs.geometry.middle.slotCount, 1)
        XCTAssertEqual(inputs.geometry.inner.angularOffset, 0, accuracy: 0.000_001)
        XCTAssertEqual(inputs.outerVisibility, .alwaysHidden)
        XCTAssertEqual(inputs.innerOrientation, .upright)
        XCTAssertEqual(inputs.middleOrientation, .upright)
        XCTAssertEqual(
            inputs.firstMiddleColors.requestedWedge,
            HUDColor(red: 0.2, green: 0.3, blue: 0.4, alpha: 0.8)
        )
        XCTAssertEqual(inputs.firstMiddleColors.requestedIcon, .white)
        assertUnknownAction(
            configuration.middle[0],
            rawValue: "partialFutureAction",
            payload: "partial-opaque-payload"
        )
        try assertCanonicalRoundTrip(configuration, fixtureName: "partial-new-shape")
    }

    @MainActor
    func testCorruptNewValuesAreIndividuallySanitizedInResolvedRenderInputs() async throws {
        let configuration = try await loadFixtureThroughService(named: "corrupt-new-values")
        let inputs = resolvedRenderInputs(configuration)

        XCTAssertEqual(inputs.geometry.inner.slotCount, 1)
        XCTAssertEqual(inputs.geometry.middle.slotCount, 8)
        XCTAssertEqual(inputs.geometry.inner.angularOffset, .pi * 1.5, accuracy: 0.000_001)
        XCTAssertEqual(inputs.geometry.middle.angularOffset, 5 * .pi / 180, accuracy: 0.000_001)
        XCTAssertEqual(inputs.outerVisibility, .alwaysVisible)
        XCTAssertEqual(inputs.innerOrientation, .radial)
        XCTAssertEqual(inputs.middleOrientation, .upright)
        XCTAssertEqual(inputs.outerOrientation, .tangential)
        XCTAssertEqual(inputs.firstInnerColors.requestedWedge, .black)
        XCTAssertEqual(
            inputs.firstInnerColors.requestedIcon,
            HUDColor(red: 1, green: 0, blue: 0.5, alpha: 1)
        )
        assertUnknownAction(
            configuration.inner[0],
            rawValue: "corruptFixtureFutureAction",
            payload: "do-not-normalize-this-payload"
        )
        try assertCanonicalRoundTrip(configuration, fixtureName: "corrupt-new-values")
    }

    @MainActor
    func testFullyCustomizedFixtureResolvesAllInheritanceLevelsAndRoundTrips() async throws {
        let configuration = try await loadFixtureThroughService(named: "fully-customized")
        let inputs = resolvedRenderInputs(configuration)

        XCTAssertEqual(inputs.geometry.inner.slotCount, 7)
        XCTAssertEqual(inputs.geometry.middle.slotCount, 5)
        XCTAssertEqual(inputs.geometry.inner.angularOffset, 22.5 * .pi / 180, accuracy: 0.000_001)
        XCTAssertEqual(inputs.geometry.middle.angularOffset, 315 * .pi / 180, accuracy: 0.000_001)
        XCTAssertEqual(inputs.outerVisibility, .revealBeyondInnerRing)
        XCTAssertEqual(inputs.innerOrientation, .radial)
        XCTAssertEqual(inputs.middleOrientation, .tangential)
        XCTAssertEqual(inputs.outerOrientation, .upright)
        XCTAssertEqual(
            inputs.firstInnerColors.requestedWedge,
            HUDColor(red: 0.9, green: 0.8, blue: 0.1, alpha: 0.75)
        )
        XCTAssertEqual(
            inputs.firstMiddleColors.requestedWedge,
            HUDColor(red: 0.2, green: 0.4, blue: 0.6)
        )
        XCTAssertEqual(
            inputs.firstMiddleColors.requestedIcon,
            HUDColor(red: 0.8, green: 0.8, blue: 0.8)
        )
        assertUnknownAction(
            configuration.middle[0],
            rawValue: "fullyCustomizedFutureAction",
            payload: "{\"opaque\":true,\"revision\":42}"
        )
        assertUnknownAction(
            try XCTUnwrap(configuration.middle[0].subItems?.first),
            rawValue: "childFutureAction",
            payload: "child-opaque"
        )
        try assertCanonicalRoundTrip(configuration, fixtureName: "fully-customized")
    }

    func testCorruptFileThrowsInsteadOfReturningDefaults() async throws {
        let service = makeService()
        let store = await service.store
        try FileManager.default.createDirectory(
            at: store.configurationURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("not json".utf8).write(to: store.configurationURL)

        do {
            _ = try await service.loadResult()
            XCTFail("Expected corrupt configuration to fail")
        } catch is DecodingError {
            // Expected.
        }
    }

    func testSaveFailsWhenStoreDirectoryCannotBeCreated() async throws {
        let baseDirectory = makeTemporaryDirectory()
        try FileManager.default.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
        let directory = baseDirectory.appendingPathComponent("not-a-directory")
        try Data().write(to: directory)
        let service = ConfigurationService(store: ConfigurationStore(directoryURL: directory))

        do {
            try await service.save(Configuration())
            XCTFail("Expected save to fail")
        } catch {
            // The store must surface the filesystem failure to its caller.
        }
    }

    func testFailedBackupReplacementPreservesPreviousBackup() async throws {
        let store = ConfigurationStore(directoryURL: makeTemporaryDirectory())
        let service = ConfigurationService(
            store: store,
            replaceItem: { _, _ in throw CocoaError(.fileWriteUnknown) }
        )
        try await service.save(Configuration())
        try Data("previous-backup".utf8).write(to: store.backupURL)

        do {
            try await service.createBackup()
            XCTFail("Expected injected backup replacement failure")
        } catch {
            XCTAssertEqual(try Data(contentsOf: store.backupURL), Data("previous-backup".utf8))
        }
    }

    func testBackupDiscoveryAndRestore() async throws {
        let service = makeService()
        let initiallyHasBackup = await service.hasBackup()
        XCTAssertFalse(initiallyHasBackup)
        try await service.save(Configuration())
        try await service.createBackup()
        let hasCreatedBackup = await service.hasBackup()
        XCTAssertTrue(hasCreatedBackup)

        let store = await service.store
        try Data("corrupt current file".utf8).write(to: store.configurationURL)
        _ = try await service.restoreBackup()

        guard case .loaded = try await service.loadResult() else {
            return XCTFail("Restore should atomically replace the current configuration")
        }
        let stillHasBackup = await service.hasBackup()
        XCTAssertTrue(stillHasBackup)
    }

    private func writeRaw(_ data: Data, to service: ConfigurationService) async throws {
        let store = await service.store
        try FileManager.default.createDirectory(
            at: store.configurationURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: store.configurationURL)
    }

    private func savedObject(_ store: ConfigurationStore) throws -> [String: Any] {
        try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: store.configurationURL))
                as? [String: Any]
        )
    }

    private func directoryListing(_ store: ConfigurationStore) throws -> [String] {
        try FileManager.default.contentsOfDirectory(
            atPath: store.configurationURL.deletingLastPathComponent().path
        ).sorted()
    }

    private func makeService() -> ConfigurationService {
        ConfigurationService(store: ConfigurationStore(directoryURL: makeTemporaryDirectory()))
    }

    private func makeTemporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("MousePlusTests-\(UUID().uuidString)", isDirectory: true)
        temporaryDirectories.append(url)
        return url
    }

    private func fixtureData(named name: String) throws -> Data {
        let testsDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        return try Data(contentsOf: testsDirectory
            .appendingPathComponent("Fixtures", isDirectory: true)
            .appendingPathComponent(name)
            .appendingPathExtension("json"))
    }

    private func loadFixtureThroughService(named name: String) async throws -> Configuration {
        let service = makeService()
        let store = await service.store
        try FileManager.default.createDirectory(
            at: store.configurationURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try fixtureData(named: name).write(to: store.configurationURL)
        guard case .loaded(let configuration) = try await service.loadResult() else {
            throw FixtureFailure.expectedLoadedConfiguration(name)
        }
        return configuration
    }

    @MainActor
    private func resolvedRenderInputs(_ configuration: Configuration) -> ResolvedRenderInputs {
        let viewModel = RingViewModel()
        viewModel.load(from: configuration)
        let application = HUDColorResolver.Overrides(wedge: .black, icon: .white)
        let hud = configuration.hudCustomization

        func orientation(_ appearance: HUDRingAppearance) -> IconOrientation {
            appearance.iconOrientation ?? hud.iconOrientation
        }

        func colors(_ item: RingMenuItem?, ring: HUDRingAppearance) -> HUDColorResolver.Resolution {
            HUDColorResolver.resolve(
                application: application,
                menu: .init(wedge: hud.wedgeColor, icon: hud.iconColor),
                ring: .init(wedge: ring.wedgeColor, icon: ring.iconColor),
                item: .init(wedge: item?.wedgeColor, icon: item?.iconColor),
                backdrop: .white
            )
        }

        return ResolvedRenderInputs(
            geometry: viewModel.geometry,
            outerVisibility: hud.outerRingVisibility,
            innerOrientation: orientation(hud.inner.appearance),
            middleOrientation: orientation(hud.middle.appearance),
            outerOrientation: orientation(hud.outerAppearance),
            firstInnerColors: colors(configuration.inner.first, ring: hud.inner.appearance),
            firstMiddleColors: colors(configuration.middle.first, ring: hud.middle.appearance)
        )
    }

    private func assertUnknownAction(
        _ item: RingMenuItem,
        rawValue: String,
        payload: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(item.actionType, .unavailable(rawValue), file: file, line: line)
        XCTAssertEqual(item.actionData, payload, file: file, line: line)
    }

    private func assertCanonicalRoundTrip(
        _ configuration: Configuration,
        fixtureName: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let canonicalData = try encoder.encode(configuration)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: canonicalData) as? [String: Any],
            file: file,
            line: line
        )
        XCTAssertEqual(
            Set(object.keys),
            Set([
                "schemaVersion", "inner", "middle", "triggers", "appearance", "behavior",
                "hudCustomization", "appHUDProfiles",
            ]),
            "\(fixtureName) must encode only the canonical top-level shape",
            file: file,
            line: line
        )
        XCTAssertNil(object["items"], file: file, line: line)
        XCTAssertNil(object["hotkey"], file: file, line: line)

        let decoded = try JSONDecoder().decode(Configuration.self, from: canonicalData)
        XCTAssertEqual(decoded.inner.map(\.id), configuration.inner.map(\.id), file: file, line: line)
        XCTAssertEqual(decoded.middle.map(\.id), configuration.middle.map(\.id), file: file, line: line)
        XCTAssertEqual(decoded.triggers, configuration.triggers, file: file, line: line)
        XCTAssertEqual(decoded.appearance, configuration.appearance, file: file, line: line)
        XCTAssertEqual(decoded.behavior, configuration.behavior, file: file, line: line)
        XCTAssertEqual(decoded.hudCustomization, configuration.hudCustomization, file: file, line: line)
        XCTAssertEqual(actionSnapshots(decoded), actionSnapshots(configuration), file: file, line: line)
    }

    private func actionSnapshots(_ configuration: Configuration) -> [ActionSnapshot] {
        func flatten(_ items: [RingMenuItem]) -> [ActionSnapshot] {
            items.flatMap { item in
                [ActionSnapshot(id: item.id, rawAction: item.actionType.rawValue, payload: item.actionData)]
                    + flatten(item.subItems ?? [])
            }
        }
        return flatten(configuration.inner) + flatten(configuration.middle)
    }
}

/// A 0.1.0-shaped configuration: the Finder App HUD is a full copy (`layout`)
/// with an unchanged item, an edited item, an app-only item, a removed Global
/// item and its own middle order.
private struct Version1Fixture {
    static let finder = "com.apple.finder"

    let copy = RingMenuItem(label: "Copy", icon: "doc.on.doc", actionType: .custom)
    let paste = RingMenuItem(label: "Paste", icon: "doc.on.clipboard", actionType: .custom)
    let apps = RingMenuItem(label: "Apps", icon: "square.grid.2x2", actionType: .custom)
    let snap = RingMenuItem(label: "Snap", icon: "rectangle.split.2x1", actionType: .custom)
    let note = RingMenuItem(label: "Note", icon: "note.text", actionType: .custom)

    var v1Layout: HUDActionLayout {
        var finderSnap = snap
        finderSnap.label = "Finder Snap"
        return HUDActionLayout(inner: [note, copy], middle: [finderSnap, apps])
    }

    var configuration: Configuration {
        Configuration(
            inner: [copy, paste],
            middle: [apps, snap],
            appHUDProfiles: [Self.finder: AppHUDProfile(layout: v1Layout)]
        )
    }

    /// An in-memory copied profile encodes the version 1 `layout` shape, exactly
    /// as 0.1.0 wrote it.
    func data() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(configuration)
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let profile = (object?["appHUDProfiles"] as? [String: Any])?[Self.finder] as? [String: Any]
        guard profile?["layout"] != nil, profile?["rings"] == nil else {
            throw FixtureFailure.expectedLoadedConfiguration("version 1 fixture")
        }
        return data
    }
}

private struct ResolvedRenderInputs {
    let geometry: TopLevelRingGeometry
    let outerVisibility: OuterRingVisibility
    let innerOrientation: IconOrientation
    let middleOrientation: IconOrientation
    let outerOrientation: IconOrientation
    let firstInnerColors: HUDColorResolver.Resolution
    let firstMiddleColors: HUDColorResolver.Resolution
}

private struct ActionSnapshot: Equatable {
    let id: UUID
    let rawAction: String
    let payload: String
}

private enum FixtureFailure: Error {
    case expectedLoadedConfiguration(String)
}
