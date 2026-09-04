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
            Set(["schemaVersion", "inner", "middle", "triggers", "appearance", "behavior", "hudCustomization"]),
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
