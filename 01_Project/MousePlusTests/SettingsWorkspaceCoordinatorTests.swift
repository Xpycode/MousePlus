import AppKit
import Foundation
import XCTest
@testable import MousePlus

@MainActor
final class SettingsWorkspaceCoordinatorTests: XCTestCase {
    func testLoadExposesGlobalFirstAndKeepsProfileSelectionInMemoryOnly() async {
        var initial = Configuration()
        _ = initial.setAppHUDProfile(
            appHUD(labeledLayout("Finder")),
            forBundleIdentifier: "com.apple.finder"
        )
        _ = initial.setAppHUDProfile(
            appHUD(labeledLayout("Safari")),
            forBundleIdentifier: "com.apple.Safari"
        )
        let persistence = RecordingConfigurationPersistence(initial)
        let coordinator = makeCoordinator(persistence)
        await coordinator.load()

        XCTAssertEqual(coordinator.editableHUDProfiles, [
            .global,
            .app(bundleIdentifier: "com.apple.Safari"),
            .app(bundleIdentifier: "com.apple.finder"),
        ])
        XCTAssertTrue(coordinator.selectHUDProfile(.app(bundleIdentifier: "com.apple.finder")))
        XCTAssertEqual(coordinator.selectedAppHUDBundleIdentifier, "com.apple.finder")
        XCTAssertEqual(coordinator.menuEditorModel.middle[0].label, "Finder")
        XCTAssertTrue(coordinator.dirtyFields.isEmpty)
        var saveCount = await persistence.saveCount
        XCTAssertEqual(saveCount, 0)

        XCTAssertTrue(coordinator.selectHUDProfile(.global))
        XCTAssertEqual(coordinator.menuEditorModel.middle, initial.middle)
        XCTAssertNil(coordinator.selectedAppHUDBundleIdentifier)
        let flushed = await coordinator.flush()
        XCTAssertTrue(flushed)
        saveCount = await persistence.saveCount
        XCTAssertEqual(saveCount, 0)
    }

    func testCreateCopiesCurrentGlobalThenProfilesEditIndependentlyAcrossReload() async throws {
        let persistence = RecordingConfigurationPersistence(Configuration())
        let coordinator = makeCoordinator(persistence)
        await coordinator.load()
        coordinator.menuEditorModel.middle[0].label = "Current Global"

        XCTAssertEqual(
            coordinator.createAppHUD(forBundleIdentifier: "com.apple.finder"),
            .created
        )
        XCTAssertEqual(coordinator.selectedHUDProfile, .app(bundleIdentifier: "com.apple.finder"))
        XCTAssertEqual(coordinator.menuEditorModel.middle[0].label, "Current Global")
        coordinator.menuEditorModel.inner[0].icon = "folder"
        coordinator.menuEditorModel.middle[0].label = "Finder only"
        coordinator.menuItemsDidChange()
        let flushed = await coordinator.flush()
        XCTAssertTrue(flushed)

        let saved = await persistence.current
        XCTAssertEqual(saved.middle[0].label, "Current Global")
        let finder = try appLayout(saved, "com.apple.finder")
        XCTAssertEqual(finder.middle[0].label, "Finder only")
        XCTAssertEqual(finder.inner[0].icon, "folder")
        // Only the two edited items are stored, as overrides; the rest inherit.
        let rings = try XCTUnwrap(saved.appHUDProfile(forBundleIdentifier: "com.apple.finder")?.rings)
        XCTAssertEqual(Set(rings.inner.overrides.keys), [saved.inner[0].id])
        XCTAssertEqual(Set(rings.middle.overrides.keys), [saved.middle[0].id])
        XCTAssertTrue(rings.inner.hidden.isEmpty && rings.middle.hidden.isEmpty)
        XCTAssertTrue(rings.inner.appOnly.isEmpty && rings.middle.appOnly.isEmpty)
        XCTAssertNil(rings.inner.customOrder)
        XCTAssertNil(rings.middle.customOrder)

        let relaunched = makeCoordinator(persistence)
        await relaunched.load()
        XCTAssertEqual(relaunched.selectedHUDProfile, .global)
        XCTAssertTrue(relaunched.selectHUDProfile(.app(bundleIdentifier: "com.apple.finder")))
        XCTAssertEqual(relaunched.menuEditorModel.middle[0].label, "Finder only")
        XCTAssertTrue(relaunched.selectHUDProfile(.global))
        XCTAssertEqual(relaunched.menuEditorModel.middle[0].label, "Current Global")
    }

    func testDuplicateCreateSelectsExistingWithoutOverwritingOrSaving() async throws {
        var initial = Configuration()
        _ = initial.setAppHUDProfile(
            appHUD(labeledLayout("Existing Finder")),
            forBundleIdentifier: "com.apple.finder"
        )
        let persistence = RecordingConfigurationPersistence(initial)
        let coordinator = makeCoordinator(persistence)
        await coordinator.load()

        XCTAssertEqual(
            coordinator.createAppHUD(forBundleIdentifier: "com.apple.finder"),
            .selectedExisting
        )
        XCTAssertEqual(coordinator.selectedHUDProfile, .app(bundleIdentifier: "com.apple.finder"))
        XCTAssertEqual(coordinator.menuEditorModel.middle[0].label, "Existing Finder")
        XCTAssertTrue(coordinator.dirtyFields.isEmpty)
        let saveCount = await persistence.saveCount
        XCTAssertEqual(saveCount, 0)
        let current = await persistence.current
        XCTAssertEqual(try appLayout(current, "com.apple.finder").middle[0].label, "Existing Finder")
    }

    func testUnreadableDuplicateCanBeIntentionallyReplacedByCreatingThatAppHUD() async throws {
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(Configuration()))
                as? [String: Any]
        )
        object["appHUDProfiles"] = [
            "com.example.future": ["futurePayload": ["token": "keep-me"]],
        ]
        let decoded = try JSONDecoder().decode(
            Configuration.self,
            from: JSONSerialization.data(withJSONObject: object)
        )
        let persistence = RecordingConfigurationPersistence(decoded)
        let coordinator = makeCoordinator(persistence)
        await coordinator.load()

        XCTAssertEqual(
            coordinator.createAppHUD(forBundleIdentifier: "com.example.future"),
            .replacedUnavailable
        )
        let flushed = await coordinator.flush()
        XCTAssertTrue(flushed)

        let saved = await persistence.current
        let replacement = try XCTUnwrap(
            saved.appHUDProfile(forBundleIdentifier: "com.example.future")
        )
        XCTAssertEqual(replacement.rings, AppHUDRings())
        XCTAssertEqual(try appLayout(saved, "com.example.future"), saved.globalHUDActionLayout)
        XCTAssertFalse(saved.hasUnavailableAppHUDProfile(forBundleIdentifier: "com.example.future"))
    }

    func testUnreadableReplacementRefusesToOverwriteExternallyChangedOpaquePayload() async throws {
        let bundleIdentifier = "com.example.future"
        let initial = try configuration(Configuration()) { object in
            object["appHUDProfiles"] = [
                bundleIdentifier: ["futurePayload": ["token": "original"]],
            ]
        }
        let persistence = RecordingConfigurationPersistence(initial)
        let coordinator = makeCoordinator(persistence)
        await coordinator.load()
        XCTAssertEqual(
            coordinator.createAppHUD(forBundleIdentifier: bundleIdentifier),
            .replacedUnavailable
        )

        let externallyChanged = try configuration(initial) { object in
            object["appHUDProfiles"] = [
                bundleIdentifier: ["futurePayload": ["token": "external"]],
            ]
        }
        await persistence.mutateCurrent { $0 = externallyChanged }

        let flushed = await coordinator.flush()
        XCTAssertFalse(flushed)
        let saved = await persistence.current
        XCTAssertTrue(saved.hasUnavailableAppHUDProfile(forBundleIdentifier: bundleIdentifier))
        let savedObject = try encodedObject(saved)
        let profiles = try XCTUnwrap(savedObject["appHUDProfiles"] as? [String: Any])
        let opaque = try XCTUnwrap(profiles[bundleIdentifier] as? [String: Any])
        let payload = try XCTUnwrap(opaque["futurePayload"] as? [String: Any])
        XCTAssertEqual(payload["token"] as? String, "external")
    }

    func testAppEditUsesGlobalCustomizationWithoutWritingOtherActionProfiles() async throws {
        var initial = Configuration()
        initial.hudCustomization.middle.layout.angularOffset = 19
        _ = initial.setAppHUDProfile(
            appHUD(labeledLayout("Finder")),
            forBundleIdentifier: "com.apple.finder"
        )
        _ = initial.setAppHUDProfile(
            appHUD(labeledLayout("Safari")),
            forBundleIdentifier: "com.apple.Safari"
        )
        let persistence = RecordingConfigurationPersistence(initial)
        let coordinator = makeCoordinator(persistence)
        await coordinator.load()
        XCTAssertTrue(coordinator.selectHUDProfile(.app(bundleIdentifier: "com.apple.finder")))

        coordinator.menuEditorModel.middle[0].label = "Edited Finder"
        coordinator.menuEditorModel.hudCustomization.middle.layout.angularOffset = 77
        coordinator.menuItemsDidChange()
        let flushed = await coordinator.flush()
        XCTAssertTrue(flushed)

        let saved = await persistence.current
        XCTAssertEqual(saved.middle, initial.middle)
        XCTAssertEqual(saved.hudCustomization.middle.layout.angularOffset, 77)
        XCTAssertEqual(
            try appLayout(saved, "com.apple.finder").middle[0].label,
            "Edited Finder"
        )
        XCTAssertEqual(
            try appLayout(saved, "com.apple.Safari").middle[0].label,
            "Safari"
        )
    }

    func testDeleteSelectedAppFallsBackToGlobalAndSurvivesReload() async {
        var initial = Configuration()
        initial.middle[0].label = "Global survives"
        _ = initial.setAppHUDProfile(
            appHUD(labeledLayout("Finder")),
            forBundleIdentifier: "com.apple.finder"
        )
        let persistence = RecordingConfigurationPersistence(initial)
        let coordinator = makeCoordinator(persistence)
        await coordinator.load()
        XCTAssertTrue(coordinator.selectHUDProfile(.app(bundleIdentifier: "com.apple.finder")))

        XCTAssertTrue(coordinator.deleteAppHUD(forBundleIdentifier: "com.apple.finder"))
        XCTAssertEqual(coordinator.selectedHUDProfile, .global)
        XCTAssertEqual(coordinator.menuEditorModel.middle[0].label, "Global survives")
        let flushed = await coordinator.flush()
        XCTAssertTrue(flushed)
        let current = await persistence.current
        XCTAssertNil(current.appHUDProfile(forBundleIdentifier: "com.apple.finder"))

        let relaunched = makeCoordinator(persistence)
        await relaunched.load()
        XCTAssertEqual(relaunched.editableHUDProfiles, [.global])
        XCTAssertEqual(relaunched.configuration.middle[0].label, "Global survives")
    }

    func testMissingSelectedAppFallsBackToGlobalOnReloadAndRejectedSelectionIsSafe() async {
        var initial = Configuration()
        initial.middle[0].label = "Global"
        _ = initial.setAppHUDProfile(
            appHUD(labeledLayout("Finder")),
            forBundleIdentifier: "com.apple.finder"
        )
        let persistence = RecordingConfigurationPersistence(initial)
        let coordinator = makeCoordinator(persistence)
        await coordinator.load()
        XCTAssertTrue(coordinator.selectHUDProfile(.app(bundleIdentifier: "com.apple.finder")))
        await persistence.mutateCurrent {
            _ = $0.removeAppHUDProfile(forBundleIdentifier: "com.apple.finder")
        }

        await coordinator.load()
        XCTAssertEqual(coordinator.selectedHUDProfile, .global)
        XCTAssertEqual(coordinator.menuEditorModel.middle[0].label, "Global")
        XCTAssertFalse(coordinator.selectHUDProfile(.app(bundleIdentifier: "missing.app")))
        XCTAssertEqual(coordinator.selectedHUDProfile, .global)
        XCTAssertTrue(coordinator.dirtyFields.isEmpty)
    }

    func testAppProfileSaveFailureRetryAndCloseBarrierKeepRecoverableEdit() async {
        var initial = Configuration()
        _ = initial.setAppHUDProfile(
            appHUD(labeledLayout("Finder")),
            forBundleIdentifier: "com.apple.finder"
        )
        let persistence = RecordingConfigurationPersistence(initial)
        let recorder = LiveApplyRecorder()
        let coordinator = makeCoordinator(persistence, recorder: recorder)
        await coordinator.load()
        XCTAssertTrue(coordinator.selectHUDProfile(.app(bundleIdentifier: "com.apple.finder")))
        coordinator.menuEditorModel.middle[0].label = "Unsaved Finder"
        coordinator.menuItemsDidChange()
        await persistence.setSaveFailure(TestFailure.write)

        let mayClose = await coordinator.requestClose()
        XCTAssertFalse(mayClose)
        XCTAssertEqual(coordinator.dirtyFields, [.menuItems])
        XCTAssertEqual(coordinator.menuEditorModel.middle[0].label, "Unsaved Finder")
        XCTAssertTrue(recorder.events.isEmpty)
        guard case .blocked = coordinator.workspaceState.closeBarrier else {
            return XCTFail("A failed app-profile write must block close")
        }

        await persistence.setSaveFailure(nil)
        let resolved = await coordinator.resolveClose(.retry)
        XCTAssertTrue(resolved)
        let saved = await persistence.current
        XCTAssertEqual(
            saved.resolvedAppLayout(forBundleIdentifier: "com.apple.finder")?.layout.middle[0].label,
            "Unsaved Finder"
        )
        XCTAssertEqual(recorder.events.count, 1)
    }

    func testCorruptFreshBasePreventsAppProfileOverwrite() async {
        var initial = Configuration()
        _ = initial.setAppHUDProfile(
            appHUD(labeledLayout("Finder")),
            forBundleIdentifier: "com.apple.finder"
        )
        let persistence = RecordingConfigurationPersistence(initial)
        let coordinator = makeCoordinator(persistence)
        await coordinator.load()
        XCTAssertTrue(coordinator.selectHUDProfile(.app(bundleIdentifier: "com.apple.finder")))
        coordinator.menuEditorModel.middle[0].label = "Must remain recoverable"
        coordinator.menuItemsDidChange()
        await persistence.setLoadFailure(makeDecodingError())

        let flushed = await coordinator.flush()
        XCTAssertFalse(flushed)
        let saveCount = await persistence.saveCount
        XCTAssertEqual(saveCount, 0)
        XCTAssertEqual(coordinator.dirtyFields, [.menuItems])
        XCTAssertEqual(coordinator.menuEditorModel.middle[0].label, "Must remain recoverable")
        guard case .loadFailed = coordinator.status else {
            return XCTFail("A corrupt fresh base must report Load Failed")
        }
    }

    func testFreshBaseProfileDeltaPreservesExternalUntouchedProfileEditsAndAdditions() async throws {
        var initial = Configuration()
        _ = initial.setAppHUDProfile(
            appHUD(labeledLayout("Finder")),
            forBundleIdentifier: "com.apple.finder"
        )
        _ = initial.setAppHUDProfile(
            appHUD(labeledLayout("Safari")),
            forBundleIdentifier: "com.apple.Safari"
        )
        let persistence = RecordingConfigurationPersistence(initial)
        let coordinator = makeCoordinator(persistence)
        await coordinator.load()
        XCTAssertTrue(coordinator.selectHUDProfile(.app(bundleIdentifier: "com.apple.finder")))
        coordinator.menuEditorModel.middle[0].label = "Local Finder"
        coordinator.menuItemsDidChange()
        await persistence.mutateCurrent {
            relabelAppMiddle(&$0, "com.apple.Safari", "External Safari")
            _ = $0.setAppHUDProfile($0.makeAppHUDProfileFromGlobal(), forBundleIdentifier: "com.apple.Notes")
            relabelAppMiddle(&$0, "com.apple.Notes", "External Notes")
        }

        let flushed = await coordinator.flush()
        XCTAssertTrue(flushed)
        let saved = await persistence.current
        XCTAssertEqual(try appLayout(saved, "com.apple.finder").middle[0].label, "Local Finder")
        XCTAssertEqual(try appLayout(saved, "com.apple.Safari").middle[0].label, "External Safari")
        XCTAssertEqual(try appLayout(saved, "com.apple.Notes").middle[0].label, "External Notes")
    }

    func testFreshBaseRejectsConcurrentTypedEditToLocallyEditedProfile() async throws {
        var initial = Configuration()
        _ = initial.setAppHUDProfile(
            appHUD(labeledLayout("Finder")),
            forBundleIdentifier: "com.apple.finder"
        )
        let persistence = RecordingConfigurationPersistence(initial)
        let coordinator = makeCoordinator(persistence)
        await coordinator.load()
        XCTAssertTrue(coordinator.selectHUDProfile(.app(bundleIdentifier: "com.apple.finder")))
        coordinator.menuEditorModel.middle[0].label = "Local Finder"
        coordinator.menuItemsDidChange()
        await persistence.mutateCurrent {
            relabelAppMiddle(&$0, "com.apple.finder", "External Finder")
        }

        let flushed = await coordinator.flush()
        let saveCount = await persistence.saveCount
        let saved = await persistence.current
        XCTAssertFalse(flushed)
        XCTAssertEqual(saveCount, 0)
        XCTAssertEqual(
            saved.resolvedAppLayout(forBundleIdentifier: "com.apple.finder")?.layout.middle[0].label,
            "External Finder"
        )
        XCTAssertEqual(coordinator.dirtyFields, [.menuItems])
        guard case .saveFailed = coordinator.status else {
            return XCTFail("A concurrent typed edit to the same profile must fail closed")
        }
    }

    func testFreshBaseRejectsConcurrentEditToLocallyEditedGlobalMenu() async throws {
        let persistence = RecordingConfigurationPersistence(Configuration())
        let coordinator = makeCoordinator(persistence)
        await coordinator.load()
        coordinator.menuEditorModel.middle[0].label = "Local Global"
        coordinator.menuItemsDidChange()
        await persistence.mutateCurrent { $0.middle[0].label = "External Global" }

        let flushed = await coordinator.flush()
        let saveCount = await persistence.saveCount
        let saved = await persistence.current
        XCTAssertFalse(flushed)
        XCTAssertEqual(saveCount, 0)
        XCTAssertEqual(saved.middle[0].label, "External Global")
        XCTAssertEqual(coordinator.dirtyFields, [.menuItems])
        guard case .saveFailed = coordinator.status else {
            return XCTFail("A concurrent edit to the Global menu must fail closed")
        }
    }

    func testFreshBasePreservesExternalGlobalEditWhenOnlyAppProfileChanged() async throws {
        var initial = Configuration()
        _ = initial.setAppHUDProfile(
            appHUD(labeledLayout("Finder")),
            forBundleIdentifier: "com.apple.finder"
        )
        let persistence = RecordingConfigurationPersistence(initial)
        let coordinator = makeCoordinator(persistence)
        await coordinator.load()
        XCTAssertTrue(coordinator.selectHUDProfile(.app(bundleIdentifier: "com.apple.finder")))
        coordinator.menuEditorModel.middle[0].label = "Local Finder"
        coordinator.menuItemsDidChange()
        await persistence.mutateCurrent { $0.middle[0].label = "External Global" }

        let flushed = await coordinator.flush()
        XCTAssertTrue(flushed)
        let saved = await persistence.current
        XCTAssertEqual(saved.middle[0].label, "External Global")
        XCTAssertEqual(
            try appLayout(saved, "com.apple.finder").middle[0].label,
            "Local Finder"
        )
    }

    func testFreshBaseAcceptsGlobalEditWhenDiskAlreadyMatchesIt() async {
        let persistence = RecordingConfigurationPersistence(Configuration())
        let coordinator = makeCoordinator(persistence)
        await coordinator.load()
        coordinator.menuEditorModel.middle[0].label = "Same Edit"
        coordinator.menuItemsDidChange()
        await persistence.mutateCurrent { $0.middle[0].label = "Same Edit" }

        let flushed = await coordinator.flush()
        XCTAssertTrue(flushed)
        let saved = await persistence.current
        XCTAssertEqual(saved.middle[0].label, "Same Edit")
        XCTAssertTrue(coordinator.dirtyFields.isEmpty)
    }

    func testSelectingNoncanonicalStoredProfileDoesNotNormalizeDirtyOrSave() async {
        var nestedInner = labeledLayout("Finder").inner[0]
        nestedInner.subItems = [RingMenuItem(
            label: "Legacy child", icon: "circle", actionType: .custom
        )]
        let invalidSnap = RingMenuItem(
            label: "Legacy snap", icon: "rectangle", actionType: .windowSnap, actionData: ""
        )
        var initial = Configuration()
        _ = initial.setAppHUDProfile(
            appHUD(HUDActionLayout(inner: [nestedInner], middle: [invalidSnap])),
            forBundleIdentifier: "com.apple.finder"
        )
        let persistence = RecordingConfigurationPersistence(initial)
        let coordinator = makeCoordinator(persistence)
        await coordinator.load()

        XCTAssertTrue(coordinator.selectHUDProfile(.app(bundleIdentifier: "com.apple.finder")))
        coordinator.menuItemsDidChange() // mirrors a SwiftUI observation callback after selection

        XCTAssertNotNil(coordinator.menuEditorModel.inner[0].subItems)
        XCTAssertEqual(coordinator.menuEditorModel.middle[0].actionData, "")
        XCTAssertTrue(coordinator.dirtyFields.isEmpty)
        let saveCount = await persistence.saveCount
        XCTAssertEqual(saveCount, 0)
    }

    func testFreshBaseOpaqueCollectionRejectsProfileEditWithoutFalseSuccess() async throws {
        var initial = Configuration()
        _ = initial.setAppHUDProfile(
            appHUD(labeledLayout("Finder")),
            forBundleIdentifier: "com.apple.finder"
        )
        let persistence = RecordingConfigurationPersistence(initial)
        let recorder = LiveApplyRecorder()
        let coordinator = makeCoordinator(persistence, recorder: recorder)
        await coordinator.load()
        XCTAssertTrue(coordinator.selectHUDProfile(.app(bundleIdentifier: "com.apple.finder")))
        coordinator.menuEditorModel.middle[0].label = "Local Finder"
        coordinator.menuItemsDidChange()

        let external = try configuration(initial) { object in
            object["appHUDProfiles"] = ["future", ["version": 9]]
        }
        await persistence.mutateCurrent { $0 = external }

        let flushed = await coordinator.flush()
        XCTAssertFalse(flushed)
        let saveCount = await persistence.saveCount
        XCTAssertEqual(saveCount, 0)
        XCTAssertEqual(coordinator.dirtyFields, [.menuItems])
        XCTAssertTrue(recorder.events.isEmpty)
        let saved = await persistence.current
        XCTAssertTrue(saved.hasUnavailableAppHUDProfilesCollection)
        guard case .saveFailed = coordinator.status else {
            return XCTFail("An opaque fresh collection must fail closed")
        }
    }

    func testFreshBaseOpaqueTouchedEntryRejectsProfileEditWithoutOverwrite() async throws {
        var initial = Configuration()
        _ = initial.setAppHUDProfile(
            appHUD(labeledLayout("Finder")),
            forBundleIdentifier: "com.apple.finder"
        )
        let persistence = RecordingConfigurationPersistence(initial)
        let coordinator = makeCoordinator(persistence)
        await coordinator.load()
        XCTAssertTrue(coordinator.selectHUDProfile(.app(bundleIdentifier: "com.apple.finder")))
        coordinator.menuEditorModel.middle[0].label = "Local Finder"
        coordinator.menuItemsDidChange()

        let external = try configuration(initial) { object in
            object["appHUDProfiles"] = [
                "com.apple.finder": ["futurePayload": ["token": "keep-me"]],
            ]
        }
        await persistence.mutateCurrent { $0 = external }

        let flushed = await coordinator.flush()
        XCTAssertFalse(flushed)
        let saveCount = await persistence.saveCount
        XCTAssertEqual(saveCount, 0)
        XCTAssertEqual(coordinator.dirtyFields, [.menuItems])
        let saved = await persistence.current
        XCTAssertTrue(saved.hasUnavailableAppHUDProfile(forBundleIdentifier: "com.apple.finder"))
        let object = try encodedObject(saved)
        let profiles = try XCTUnwrap(object["appHUDProfiles"] as? [String: Any])
        let finder = try XCTUnwrap(profiles["com.apple.finder"] as? [String: Any])
        let payload = try XCTUnwrap(finder["futurePayload"] as? [String: Any])
        XCTAssertEqual(payload["token"] as? String, "keep-me")
    }

    func testFreshBaseTouchedProfilePreservesNewFutureFields() async throws {
        var initial = Configuration()
        _ = initial.setAppHUDProfile(
            appHUD(labeledLayout("Finder")),
            forBundleIdentifier: "com.apple.finder"
        )
        let persistence = RecordingConfigurationPersistence(initial)
        let coordinator = makeCoordinator(persistence)
        await coordinator.load()
        XCTAssertTrue(coordinator.selectHUDProfile(.app(bundleIdentifier: "com.apple.finder")))
        coordinator.menuEditorModel.middle[0].label = "Local Finder"
        coordinator.menuItemsDidChange()

        let external = try configuration(initial) { object in
            var profiles = object["appHUDProfiles"] as! [String: Any]
            var finder = profiles["com.apple.finder"] as! [String: Any]
            finder["futureProfile"] = ["token": "profile-v2"]
            var rings = finder["rings"] as! [String: Any]
            rings["futureLayout"] = ["token": "layout-v2"]
            var middle = rings["middle"] as! [String: Any]
            middle["futureRing"] = ["token": "ring-v2"]
            var overrides = middle["overrides"] as! [[String: Any]]
            overrides[0]["futureItem"] = ["token": "item-v2"]
            middle["overrides"] = overrides
            rings["middle"] = middle
            finder["rings"] = rings
            profiles["com.apple.finder"] = finder
            object["appHUDProfiles"] = profiles
        }
        await persistence.mutateCurrent { $0 = external }

        let flushed = await coordinator.flush()
        XCTAssertTrue(flushed)
        let saved = await persistence.current
        XCTAssertEqual(
            saved.resolvedAppLayout(forBundleIdentifier: "com.apple.finder")?.layout.middle[0].label,
            "Local Finder"
        )
        let object = try encodedObject(saved)
        let profiles = try XCTUnwrap(object["appHUDProfiles"] as? [String: Any])
        let finder = try XCTUnwrap(profiles["com.apple.finder"] as? [String: Any])
        XCTAssertEqual(
            ((finder["futureProfile"] as? [String: Any])?["token"] as? String),
            "profile-v2"
        )
        let rings = try XCTUnwrap(finder["rings"] as? [String: Any])
        XCTAssertEqual(
            ((rings["futureLayout"] as? [String: Any])?["token"] as? String),
            "layout-v2"
        )
        let middle = try XCTUnwrap(rings["middle"] as? [String: Any])
        XCTAssertEqual(
            ((middle["futureRing"] as? [String: Any])?["token"] as? String),
            "ring-v2"
        )
        let overrides = try XCTUnwrap(middle["overrides"] as? [[String: Any]])
        XCTAssertEqual(overrides.count, 1)
        XCTAssertEqual(overrides[0]["label"] as? String, "Local Finder")
        XCTAssertEqual(
            ((overrides[0]["futureItem"] as? [String: Any])?["token"] as? String),
            "item-v2"
        )
    }

    func testAppResetCopiesCurrentGlobalWithoutResettingCustomizationAndUndoRestoresProfiles() async throws {
        var initial = Configuration()
        initial.middle[0].label = "Current Global"
        initial.hudCustomization.middle.layout.angularOffset = 63
        _ = initial.setAppHUDProfile(
            appHUD(labeledLayout("Finder custom")),
            forBundleIdentifier: "com.apple.finder"
        )
        _ = initial.setAppHUDProfile(
            appHUD(labeledLayout("Safari custom")),
            forBundleIdentifier: "com.apple.Safari"
        )
        let persistence = RecordingConfigurationPersistence(initial)
        let coordinator = makeCoordinator(persistence)
        await coordinator.load()
        XCTAssertTrue(coordinator.selectHUDProfile(.app(bundleIdentifier: "com.apple.finder")))

        let reset = await coordinator.resetMenuItems()
        XCTAssertTrue(reset)
        var saved = await persistence.current
        XCTAssertEqual(saved.appHUDProfile(forBundleIdentifier: "com.apple.finder")?.rings, AppHUDRings())
        XCTAssertEqual(try appLayout(saved, "com.apple.finder").middle, initial.middle)
        XCTAssertEqual(coordinator.menuEditorModel.middle, initial.middle)
        XCTAssertEqual(coordinator.menuEditorModel.origin(of: initial.middle[0].id), .inherited)
        XCTAssertEqual(try appLayout(saved, "com.apple.Safari").middle[0].label, "Safari custom")
        XCTAssertEqual(saved.middle[0].label, "Current Global")
        XCTAssertEqual(saved.hudCustomization.middle.layout.angularOffset, 63)
        XCTAssertEqual(coordinator.selectedHUDProfile, .app(bundleIdentifier: "com.apple.finder"))

        let undone = await coordinator.undoMenuItemsReset()
        XCTAssertTrue(undone)
        saved = await persistence.current
        XCTAssertEqual(try appLayout(saved, "com.apple.finder").middle[0].label, "Finder custom")
        XCTAssertEqual(try appLayout(saved, "com.apple.Safari").middle[0].label, "Safari custom")
        XCTAssertEqual(saved.hudCustomization.middle.layout.angularOffset, 63)
    }

    func testNativeMotionEditsPersistReloadAndLiveApplyWithFreshUnrelatedFields() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ConfigurationStore(directoryURL: directory)
        let persistence = ConfigurationService(store: store)
        var initial = Configuration()
        initial.appearance.motion.baseDuration = 0.27
        try await persistence.save(initial)
        let recorder = LiveApplyRecorder()
        let coordinator = SettingsWorkspaceCoordinator(
            persistence: persistence, debounceClock: LongWorkspaceDebounceClock(),
            liveApply: { recorder.events.append($0) }
        )
        await coordinator.load()
        let host = MotionSettingsTestHost(coordinator)
        let slider: NSSlider = try host.control("appearance.motion.baseDuration")
        XCTAssertEqual(slider.doubleValue, 0.27, "Opening Settings must preserve the saved duration")

        // Exercise the actual pane's native actions, including every Off/effect pair.
        for (enabled, duration) in [(false, 0.05), (true, 0.5)] {
            for role in ["summon", "hover", "outerExpansion", "branchChange"] {
                let popup: NSPopUpButton = try host.control("appearance.motion.\(role)")
                popup.selectItem(at: enabled ? 1 : 0)
                XCTAssertTrue(popup.sendAction(popup.action, to: popup.target))
            }
            slider.doubleValue = duration
            XCTAssertTrue(slider.sendAction(slider.action, to: slider.target))
            let master: NSButton = try host.control("appearance.animationEnabled")
            master.state = enabled ? .on : .off
            XCTAssertTrue(master.sendAction(master.action, to: master.target))
            XCTAssertEqual(coordinator.dirtyFields, [.appearance])

            var external = try await persistence.load()
            external.behavior.dismissOnEscape = false
            external.middle[0].label = "External edit"
            try await persistence.save(external)

            let flushed = await coordinator.flush()
            XCTAssertTrue(flushed)
            let expected = HUDMotionConfiguration(
                isEnabled: enabled, baseDuration: duration,
                summon: enabled ? .fade : .off, hover: enabled ? .emphasis : .off,
                outerExpansion: enabled ? .radialReveal : .off,
                branchChange: enabled ? .crossfade : .off
            )
            let applied = try XCTUnwrap(recorder.events.last)
            XCTAssertEqual(applied.appearance.motion, expected)
            XCTAssertFalse(applied.behavior.dismissOnEscape)
            XCTAssertEqual(applied.middle[0].label, "External edit")

            let reloaded = SettingsWorkspaceCoordinator(persistence: ConfigurationService(store: store))
            await reloaded.load()
            XCTAssertEqual(reloaded.configuration.appearance.motion, expected)
            XCTAssertFalse(reloaded.configuration.behavior.dismissOnEscape)
            XCTAssertEqual(reloaded.configuration.middle[0].label, "External edit")
            if !enabled {
                // Re-enable via the user-facing master before changing disabled controls.
                master.performClick(nil)
                await host.waitUntil { slider.isEnabled }
            }
        }
        XCTAssertEqual(recorder.events.count, 2, "A burst of native edits must coalesce at flush")
    }

    func testEveryNativeOpeningChoicePersistsAndReplayDoesNotDirtyConfiguration() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ConfigurationStore(directoryURL: directory)
        let coordinator = SettingsWorkspaceCoordinator(
            persistence: ConfigurationService(store: store),
            debounceClock: LongWorkspaceDebounceClock()
        )
        await coordinator.load()
        let host = MotionSettingsTestHost(coordinator)
        let popup: NSPopUpButton = try host.control("appearance.motion.summon")
        let replay: NSButton = try host.control("appearance.motion.replayOpening")

        for (index, style) in HUDSummonMotionStyle.allCases.enumerated() {
            popup.selectItem(at: index)
            XCTAssertTrue(popup.sendAction(popup.action, to: popup.target))
            XCTAssertEqual(coordinator.configuration.appearance.motion.summon, style)
            let flushed = await coordinator.flush()
            XCTAssertTrue(flushed)

            let reloaded = SettingsWorkspaceCoordinator(
                persistence: ConfigurationService(store: store)
            )
            await reloaded.load()
            XCTAssertEqual(reloaded.configuration.appearance.motion.summon, style)

            await host.waitUntil { replay.isEnabled == (style != .off) }
            let dirtyBeforeReplay = coordinator.dirtyFields
            if replay.isEnabled {
                replay.performClick(nil)
            }
            XCTAssertEqual(coordinator.dirtyFields, dirtyBeforeReplay)
        }
    }

    func testResetAtomicallyDefaultsItemsLayoutAndAllColorOverridesOnly() async {
        var initial = customizedHUDConfiguration()
        _ = initial.setAppHUDProfile(
            appHUD(labeledLayout("Finder preserved")),
            forBundleIdentifier: "com.apple.finder"
        )
        let persistence = RecordingConfigurationPersistence(initial)
        let coordinator = makeCoordinator(persistence)
        await coordinator.load()

        let reset = await coordinator.resetMenuItems()

        XCTAssertTrue(reset)
        let saved = await persistence.current
        XCTAssertEqual(saved.inner, RingMenuItem.sampleInnerItems)
        XCTAssertEqual(saved.middle, RingMenuItem.sampleItems)
        XCTAssertEqual(saved.hudCustomization, .default)
        XCTAssertEqual(saved.triggers, initial.triggers)
        XCTAssertEqual(saved.appearance, initial.appearance)
        XCTAssertEqual(saved.behavior, initial.behavior)
        XCTAssertEqual(
            saved.appHUDProfile(forBundleIdentifier: "com.apple.finder"),
            initial.appHUDProfile(forBundleIdentifier: "com.apple.finder")
        )
        XCTAssertEqual(coordinator.workspaceState.reset, .undoAvailable)
        XCTAssertTrue(coordinator.workspaceState.durableBackupAvailable)
    }

    func testUndoResetAtomicallyRestoresLayoutAndInheritedAndPerItemColors() async {
        let initial = customizedHUDConfiguration()
        let persistence = RecordingConfigurationPersistence(initial)
        let coordinator = makeCoordinator(persistence)
        await coordinator.load()
        let reset = await coordinator.resetMenuItems()
        XCTAssertTrue(reset)

        let undone = await coordinator.undoMenuItemsReset()

        XCTAssertTrue(undone)
        let saved = await persistence.current
        assertHUDMenuState(saved, equals: initial)
        XCTAssertEqual(saved.triggers, initial.triggers)
        XCTAssertEqual(saved.appearance, initial.appearance)
        XCTAssertEqual(saved.behavior, initial.behavior)
        XCTAssertEqual(coordinator.workspaceState.reset, .idle)
    }

    func testFailedBackupLeavesEntirePreResetHUDStateUntouched() async {
        let initial = customizedHUDConfiguration()
        let persistence = RecordingConfigurationPersistence(initial)
        await persistence.setBackupFailure(TestFailure.write)
        let coordinator = makeCoordinator(persistence)
        await coordinator.load()

        let reset = await coordinator.resetMenuItems()

        XCTAssertFalse(reset)
        assertHUDMenuState(coordinator.configuration, equals: initial)
        let saved = await persistence.current
        assertHUDMenuState(saved, equals: initial)
        XCTAssertTrue(coordinator.dirtyFields.isEmpty)
        XCTAssertFalse(coordinator.workspaceState.durableBackupAvailable)
        guard case .failed = coordinator.workspaceState.reset else {
            return XCTFail("Backup failure must report a failed reset")
        }
    }

    func testFailedResetSaveAndCloseBarrierPreserveFullRecoverablePreResetHUDState() async throws {
        let initial = customizedHUDConfiguration()
        let persistence = RecordingConfigurationPersistence(initial)
        let coordinator = makeCoordinator(persistence)
        await coordinator.load()
        await persistence.setSaveFailure(TestFailure.write)

        let reset = await coordinator.resetMenuItems()
        XCTAssertFalse(reset)
        XCTAssertEqual(coordinator.configuration.inner, RingMenuItem.sampleInnerItems)
        XCTAssertEqual(coordinator.configuration.middle, RingMenuItem.sampleItems)
        XCTAssertEqual(coordinator.configuration.hudCustomization, .default)
        XCTAssertEqual(coordinator.dirtyFields, [.menuItems])
        XCTAssertTrue(coordinator.workspaceState.durableBackupAvailable)

        let mayClose = await coordinator.requestClose()
        XCTAssertFalse(mayClose)
        guard case .blocked = coordinator.workspaceState.closeBarrier else {
            return XCTFail("A failed reset write must block close")
        }
        let backup = try await persistence.loadBackup()
        assertHUDMenuState(backup, equals: initial)

        await persistence.setSaveFailure(nil)
        let restoredBackup = await coordinator.restoreMenuItemsFromBackup()
        XCTAssertTrue(restoredBackup)
        let restored = await persistence.current
        assertHUDMenuState(restored, equals: initial)
        XCTAssertTrue(coordinator.dirtyFields.isEmpty)
    }

    func testHUDCustomizationAndItemOverrideSurviveConcurrentFieldEditRetryAndReload() async throws {
        let persistence = RecordingConfigurationPersistence(Configuration())
        let recorder = LiveApplyRecorder()
        let coordinator = makeCoordinator(persistence, recorder: recorder)
        await coordinator.load()
        let itemID = try XCTUnwrap(coordinator.menuEditorModel.middle.first?.id)
        coordinator.menuEditorModel.selection = SlotSelection(band: .middle, itemID: itemID, subItemID: nil)
        coordinator.menuEditorModel.hudCustomization.middle.layout.angularOffset = 73
        coordinator.menuEditorModel.hudCustomization.middle.appearance.labelVisible = false
        coordinator.menuEditorModel.hudCustomization.middle.appearance.labelOrientation = .tangential
        coordinator.menuEditorModel.hudCustomization.labelOrientation = .radial
        let binding = try XCTUnwrap(coordinator.menuEditorModel.binding(forItem: itemID, band: .middle))
        binding.wrappedValue.iconColor = HUDColor(red: 0.8, green: 0.2, blue: 0.1)
        coordinator.menuItemsDidChange()
        coordinator.edit([.behavior]) { $0.behavior.dismissOnEscape = false }
        await persistence.setSaveFailure(TestFailure.write)

        let firstFlush = await coordinator.flush()
        XCTAssertFalse(firstFlush)
        XCTAssertEqual(coordinator.dirtyFields, [.menuItems, .behavior])
        XCTAssertEqual(coordinator.menuEditorModel.selection?.itemID, itemID)
        XCTAssertTrue(recorder.events.isEmpty)

        await persistence.setSaveFailure(nil)
        let retried = await coordinator.retry()
        XCTAssertTrue(retried)
        let saved = await persistence.current
        XCTAssertEqual(saved.hudCustomization.middle.layout.angularOffset, 73)
        XCTAssertFalse(saved.hudCustomization.middle.appearance.labelVisible, "a failed save + retry must not revert the label visibility edit")
        XCTAssertEqual(saved.hudCustomization.middle.appearance.labelOrientation, .tangential, "a failed save + retry must not revert the label orientation edit")
        XCTAssertEqual(saved.hudCustomization.labelOrientation, .radial)
        XCTAssertEqual(saved.middle.first(where: { $0.id == itemID })?.iconColor, HUDColor(red: 0.8, green: 0.2, blue: 0.1))
        XCTAssertFalse(saved.behavior.dismissOnEscape)
        XCTAssertEqual(recorder.events.last?.hudCustomization, saved.hudCustomization)
        XCTAssertEqual(coordinator.menuEditorModel.selection?.itemID, itemID)

        await coordinator.load()
        XCTAssertEqual(coordinator.menuEditorModel.hudCustomization.middle.layout.angularOffset, 73)
        XCTAssertFalse(coordinator.menuEditorModel.hudCustomization.middle.appearance.labelVisible, "a relaunch (reload) must not revert the persisted label visibility")
        XCTAssertEqual(coordinator.menuEditorModel.hudCustomization.middle.appearance.labelOrientation, .tangential, "a relaunch (reload) must not revert the persisted label orientation")
        XCTAssertEqual(coordinator.menuEditorModel.middle.first(where: { $0.id == itemID })?.iconColor, HUDColor(red: 0.8, green: 0.2, blue: 0.1))
    }

    func testBackupRestoreRestoresHUDCustomizationAndItemOverrides() async throws {
        var backup = Configuration()
        backup.hudCustomization.outerRingVisibility = .alwaysHidden
        backup.hudCustomization.inner.appearance.labelVisible = true
        backup.hudCustomization.inner.appearance.labelOrientation = .radial
        backup.middle[0].wedgeColor = HUDColor(red: 0.1, green: 0.4, blue: 0.7)
        _ = backup.setAppHUDProfile(
            appHUD(labeledLayout("Backed-up Finder")),
            forBundleIdentifier: "com.apple.finder"
        )
        let persistence = RecordingConfigurationPersistence(backup)
        let coordinator = makeCoordinator(persistence)
        await coordinator.load()
        try await persistence.createBackup()
        await coordinator.load()
        coordinator.menuEditorModel.hudCustomization.outerRingVisibility = .alwaysVisible
        coordinator.menuEditorModel.hudCustomization.inner.appearance.labelVisible = false
        coordinator.menuEditorModel.hudCustomization.inner.appearance.labelOrientation = .tangential
        coordinator.menuEditorModel.middle[0].wedgeColor = nil
        coordinator.menuItemsDidChange()
        XCTAssertTrue(coordinator.deleteAppHUD(forBundleIdentifier: "com.apple.finder"))
        XCTAssertEqual(
            coordinator.createAppHUD(forBundleIdentifier: "com.apple.Notes"),
            .created
        )
        let savedEdit = await coordinator.flush()
        XCTAssertTrue(savedEdit)

        let restoredBackup = await coordinator.restoreMenuItemsFromBackup()
        XCTAssertTrue(restoredBackup)
        let restored = await persistence.current
        XCTAssertEqual(restored.hudCustomization.outerRingVisibility, .alwaysHidden)
        XCTAssertTrue(restored.hudCustomization.inner.appearance.labelVisible, "backup restore must bring back the backed-up label visibility, not the intervening edit")
        XCTAssertEqual(restored.hudCustomization.inner.appearance.labelOrientation, .radial, "backup restore must bring back the backed-up label orientation, not the intervening edit")
        XCTAssertEqual(restored.middle[0].wedgeColor, HUDColor(red: 0.1, green: 0.4, blue: 0.7))
        XCTAssertEqual(
            try appLayout(restored, "com.apple.finder").middle[0].label,
            "Backed-up Finder"
        )
        XCTAssertNil(restored.appHUDProfile(forBundleIdentifier: "com.apple.Notes"))
    }

    func testRecoveryOperationsRestoreGlobalUnknownItemFieldsFromTheirSnapshot() async throws {
        func withToken(_ token: String, source: Configuration = Configuration()) throws -> Configuration {
            try configuration(source) { object in
                var middle = object["middle"] as? [[String: Any]] ?? []
                middle[0]["futureItem"] = ["token": token]
                object["middle"] = middle
            }
        }
        func token(in configuration: Configuration) throws -> String? {
            let middle = try XCTUnwrap(try encodedObject(configuration)["middle"] as? [[String: Any]])
            return (middle[0]["futureItem"] as? [String: Any])?["token"] as? String
        }

        let original = try withToken("undo-snapshot")
        let persistence = RecordingConfigurationPersistence(original)
        let coordinator = makeCoordinator(persistence)
        await coordinator.load()

        let reset = await coordinator.resetMenuItems()
        XCTAssertTrue(reset)
        let externalAfterReset = try withToken("external-after-reset", source: await persistence.current)
        await persistence.mutateCurrent { $0 = externalAfterReset }
        let undone = await coordinator.undoMenuItemsReset()
        XCTAssertTrue(undone)
        let afterUndo = await persistence.current
        XCTAssertEqual(try token(in: afterUndo), "undo-snapshot")

        let backup = try withToken("backup-snapshot")
        await persistence.setBackup(backup)
        let externalBeforeRestore = try withToken("external-before-restore", source: await persistence.current)
        await persistence.mutateCurrent { $0 = externalBeforeRestore }
        let restored = await coordinator.restoreMenuItemsFromBackup()
        XCTAssertTrue(restored)
        let afterRestore = await persistence.current
        XCTAssertEqual(try token(in: afterRestore), "backup-snapshot")
    }

    func testBackupRestorePreservesOpaqueFutureProfileCollectionExactly() async throws {
        var current = Configuration()
        _ = current.setAppHUDProfile(
            appHUD(labeledLayout("Current Finder")),
            forBundleIdentifier: "com.apple.finder"
        )
        let backup = try configuration(Configuration()) { object in
            object["appHUDProfiles"] = ["future-collection", ["version": 9]]
        }
        let persistence = RecordingConfigurationPersistence(current)
        await persistence.setBackup(backup)
        let coordinator = makeCoordinator(persistence)
        await coordinator.load()

        let restoredBackup = await coordinator.restoreMenuItemsFromBackup()
        XCTAssertTrue(restoredBackup)

        let restored = await persistence.current
        XCTAssertTrue(restored.hasUnavailableAppHUDProfilesCollection)
        XCTAssertNil(restored.appHUDProfile(forBundleIdentifier: "com.apple.finder"))
        let restoredProfiles = try XCTUnwrap(try encodedObject(restored)["appHUDProfiles"])
        let backupProfiles = try XCTUnwrap(try encodedObject(backup)["appHUDProfiles"])
        XCTAssertEqual(
            try JSONSerialization.data(withJSONObject: restoredProfiles, options: .sortedKeys),
            try JSONSerialization.data(withJSONObject: backupProfiles, options: .sortedKeys)
        )
        XCTAssertEqual(coordinator.status, .saved)
        XCTAssertTrue(coordinator.dirtyFields.isEmpty)
    }

    func testBackupRestorePreservesOpaqueFutureProfileEntryExactly() async throws {
        var backupSource = Configuration()
        _ = backupSource.setAppHUDProfile(
            appHUD(labeledLayout("Backed-up Safari")),
            forBundleIdentifier: "com.apple.Safari"
        )
        let backup = try configuration(backupSource) { object in
            var profiles = object["appHUDProfiles"] as? [String: Any] ?? [:]
            profiles["com.apple.finder"] = ["futurePayload": ["token": "recover-me"]]
            object["appHUDProfiles"] = profiles
        }
        let persistence = RecordingConfigurationPersistence(Configuration())
        await persistence.setBackup(backup)
        let coordinator = makeCoordinator(persistence)
        await coordinator.load()

        let restoredBackup = await coordinator.restoreMenuItemsFromBackup()
        XCTAssertTrue(restoredBackup)

        let restored = await persistence.current
        XCTAssertTrue(restored.hasUnavailableAppHUDProfile(forBundleIdentifier: "com.apple.finder"))
        XCTAssertEqual(
            restored.resolvedAppLayout(forBundleIdentifier: "com.apple.Safari")?.layout.middle[0].label,
            "Backed-up Safari"
        )
        let profiles = try XCTUnwrap(try encodedObject(restored)["appHUDProfiles"] as? [String: Any])
        let finder = try XCTUnwrap(profiles["com.apple.finder"] as? [String: Any])
        let payload = try XCTUnwrap(finder["futurePayload"] as? [String: Any])
        XCTAssertEqual(payload["token"] as? String, "recover-me")
        XCTAssertEqual(coordinator.status, .saved)
        XCTAssertTrue(coordinator.dirtyFields.isEmpty)
    }

    private func customizedHUDConfiguration() -> Configuration {
        var configuration = Configuration()
        configuration.triggers.mouseButton = .mouseButton(buttonNumber: 7, mode: .tapToggle)
        configuration.appearance.deadZone = 37
        configuration.behavior.dismissOnEscape = false
        configuration.hudCustomization.inner.layout = HUDRingLayout(
            slotCountMode: .fixed,
            fixedSlotCount: 7,
            angularOffset: 31
        )
        configuration.hudCustomization.middle.layout = HUDRingLayout(
            slotCountMode: .fixed,
            fixedSlotCount: 8,
            angularOffset: 73
        )
        configuration.hudCustomization.outerRingVisibility = .alwaysHidden
        configuration.hudCustomization.iconOrientation = .radial
        configuration.hudCustomization.wedgeColor = HUDColor(red: 0.1, green: 0.2, blue: 0.3)
        configuration.hudCustomization.iconColor = HUDColor(red: 0.9, green: 0.8, blue: 0.7)
        configuration.hudCustomization.inner.appearance.wedgeColor = HUDColor(red: 0.2, green: 0.3, blue: 0.4)
        configuration.hudCustomization.middle.appearance.iconColor = HUDColor(red: 0.7, green: 0.6, blue: 0.5)
        configuration.hudCustomization.outerAppearance.iconOrientation = .tangential
        configuration.hudCustomization.outerAppearance.wedgeColor = HUDColor(red: 0.4, green: 0.3, blue: 0.2)
        configuration.hudCustomization.labelOrientation = .tangential
        configuration.hudCustomization.inner.appearance.labelVisible = true
        configuration.hudCustomization.inner.appearance.labelOrientation = .radial
        configuration.hudCustomization.middle.appearance.labelVisible = false
        configuration.hudCustomization.middle.appearance.labelOrientation = .tangential
        configuration.hudCustomization.outerAppearance.labelVisible = false
        configuration.hudCustomization.outerAppearance.labelOrientation = .upright
        configuration.inner[0].wedgeColor = HUDColor(red: 0.3, green: 0.5, blue: 0.7)
        configuration.middle[0].iconColor = HUDColor(red: 0.8, green: 0.4, blue: 0.2)
        configuration.middle[0].subItems?[0].wedgeColor = HUDColor(red: 0.6, green: 0.2, blue: 0.4)
        return configuration
    }

    /// The encoded `appHUDProfiles` subtree, keys sorted, for byte comparison.
    private func appHUDProfilesData(_ configuration: Configuration) throws -> Data {
        let profiles = try XCTUnwrap(try encodedObject(configuration)["appHUDProfiles"])
        return try JSONSerialization.data(withJSONObject: profiles, options: [.sortedKeys])
    }

    /// The App HUD as shown (resolved against the configuration's Global).
    private func appLayout(
        _ configuration: Configuration,
        _ bundleIdentifier: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> HUDActionLayout {
        try XCTUnwrap(
            configuration.resolvedAppLayout(forBundleIdentifier: bundleIdentifier),
            file: file,
            line: line
        ).layout
    }

    private func labeledLayout(_ label: String) -> HUDActionLayout {
        var layout = Configuration().globalHUDActionLayout
        layout.middle[0].label = label
        return layout
    }

    private func assertHUDMenuState(
        _ actual: Configuration,
        equals expected: Configuration,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(actual.inner, expected.inner, file: file, line: line)
        XCTAssertEqual(actual.middle, expected.middle, file: file, line: line)
        XCTAssertEqual(actual.hudCustomization, expected.hudCustomization, file: file, line: line)
    }

    func testRapidEditsCoalesceIntoOneSave() async {
        let persistence = RecordingConfigurationPersistence(Configuration())
        let coordinator = makeCoordinator(persistence)
        await coordinator.load()

        coordinator.edit([.appearance]) { $0.appearance.deadZone = 30 }
        coordinator.edit([.appearance]) { $0.appearance.deadZone = 31 }
        coordinator.edit([.appearance]) { $0.appearance.deadZone = 32 }
        let flushed = await coordinator.flush()
        XCTAssertTrue(flushed)

        let saveCount = await persistence.saveCount
        let saved = await persistence.current
        XCTAssertEqual(saveCount, 1)
        XCTAssertEqual(saved.appearance.deadZone, 32)
        XCTAssertEqual(coordinator.status, .saved)
    }

    func testTeardownFlushesPendingEdit() async {
        let persistence = RecordingConfigurationPersistence(Configuration())
        let coordinator = makeCoordinator(persistence)
        await coordinator.load()
        coordinator.edit([.behavior]) { $0.behavior.dismissOnEscape.toggle() }

        let flushed = await coordinator.teardown()
        XCTAssertTrue(flushed)

        let saveCount = await persistence.saveCount
        XCTAssertEqual(saveCount, 1)
        XCTAssertTrue(coordinator.dirtyFields.isEmpty)
    }

    func testFreshBasePreservesOverlappingPaneAndExternalEdits() async {
        let persistence = RecordingConfigurationPersistence(Configuration())
        let coordinator = makeCoordinator(persistence)
        await coordinator.load()
        coordinator.edit([.appearance]) { $0.appearance.deadZone = 41 }
        coordinator.edit([.triggers]) { $0.triggers.mouseButton = .mouseButton(buttonNumber: 7, mode: .tapToggle) }

        await persistence.mutateCurrent { $0.behavior.dismissOnEscape = false }
        let flushed = await coordinator.flush()
        XCTAssertTrue(flushed)

        let saved = await persistence.current
        XCTAssertEqual(saved.appearance.deadZone, 41)
        XCTAssertEqual(saved.triggers.mouseButton, .mouseButton(buttonNumber: 7, mode: .tapToggle))
        XCTAssertFalse(saved.behavior.dismissOnEscape)
    }

    func testFreshBaseMergePreservesHUDLabelFieldsAlongsideExternalEdit() async {
        let persistence = RecordingConfigurationPersistence(Configuration())
        let coordinator = makeCoordinator(persistence)
        await coordinator.load()
        coordinator.menuEditorModel.hudCustomization.inner.appearance.labelVisible = true
        coordinator.menuEditorModel.hudCustomization.outerAppearance.labelOrientation = .radial
        coordinator.menuItemsDidChange()

        // Another writer (e.g. a concurrent Settings window save) changes an
        // unrelated field on disk between this edit and the debounced flush.
        await persistence.mutateCurrent { $0.appearance.deadZone = 66 }
        let flushed = await coordinator.flush()
        XCTAssertTrue(flushed)

        let saved = await persistence.current
        XCTAssertEqual(saved.appearance.deadZone, 66, "the fresh base must still carry the concurrent external edit")
        XCTAssertTrue(saved.hudCustomization.inner.appearance.labelVisible, "a fresh-base merge must not drop the label visibility edit")
        XCTAssertEqual(saved.hudCustomization.outerAppearance.labelOrientation, .radial, "a fresh-base merge must not drop the label orientation edit")
    }

    func testMidSessionCorruptionPreventsOverwrite() async {
        let persistence = RecordingConfigurationPersistence(Configuration())
        let coordinator = makeCoordinator(persistence)
        await coordinator.load()
        coordinator.edit([.appearance]) { $0.appearance.deadZone = 43 }
        await persistence.setLoadFailure(makeDecodingError())

        let flushed = await coordinator.flush()
        XCTAssertFalse(flushed)

        let saveCount = await persistence.saveCount
        XCTAssertEqual(saveCount, 0)
        XCTAssertEqual(coordinator.dirtyFields, [.appearance])
        guard case .loadFailed = coordinator.status else {
            return XCTFail("A corrupt fresh base must become Load Failed")
        }
    }

    func testFailedWriteStaysDirtyAndRetryAppliesAfterSuccess() async {
        let persistence = RecordingConfigurationPersistence(Configuration())
        let recorder = LiveApplyRecorder()
        let coordinator = makeCoordinator(persistence, recorder: recorder)
        await coordinator.load()
        await persistence.setSaveFailure(TestFailure.write)
        coordinator.edit([.appearance]) { $0.appearance.deadZone = 45 }

        let firstFlush = await coordinator.flush()
        XCTAssertFalse(firstFlush)
        XCTAssertEqual(coordinator.dirtyFields, [.appearance])
        XCTAssertTrue(recorder.events.isEmpty)
        guard case .saveFailed = coordinator.status else {
            return XCTFail("Expected Save Failed")
        }

        await persistence.setSaveFailure(nil)
        let retrySucceeded = await coordinator.retry()
        let saved = await persistence.current
        XCTAssertTrue(retrySucceeded)
        XCTAssertEqual(saved.appearance.deadZone, 45)
        XCTAssertEqual(recorder.events.count, 1)
        XCTAssertEqual(coordinator.status, .saved)
    }

    func testLiveApplyReceivesCompletePersistedRuntimeSnapshot() async throws {
        var initial = Configuration()
        initial.behavior.dismissOnEscape = false
        let persistence = RecordingConfigurationPersistence(initial)
        let recorder = LiveApplyRecorder()
        let coordinator = makeCoordinator(persistence, recorder: recorder)
        await coordinator.load()

        coordinator.edit([.appearance]) { $0.appearance.deadZone = 51 }
        let flushed = await coordinator.flush()
        XCTAssertTrue(flushed)

        let snapshot = try XCTUnwrap(recorder.events.last)
        XCTAssertEqual(snapshot.appearance.deadZone, 51)
        XCTAssertFalse(snapshot.behavior.dismissOnEscape)
        XCTAssertEqual(snapshot.inner, initial.inner)
        XCTAssertEqual(snapshot.middle, initial.middle)
        XCTAssertEqual(snapshot.triggers, initial.triggers)
        let persisted = await persistence.current
        XCTAssertEqual(snapshot.appearance, persisted.appearance)
        XCTAssertEqual(snapshot.behavior.holdToActivate, persisted.behavior.holdToActivate)
        XCTAssertEqual(snapshot.behavior.tapToActivate, persisted.behavior.tapToActivate)
        XCTAssertEqual(snapshot.behavior.dismissOnClickOutside, persisted.behavior.dismissOnClickOutside)
        XCTAssertEqual(snapshot.behavior.dismissOnEscape, persisted.behavior.dismissOnEscape)
        XCTAssertEqual(snapshot.inner, persisted.inner)
        XCTAssertEqual(snapshot.middle, persisted.middle)
        XCTAssertEqual(snapshot.triggers, persisted.triggers)
    }

    func testNoOpClosePerformsNoPersistenceWork() async {
        let persistence = RecordingConfigurationPersistence(Configuration())
        let coordinator = makeCoordinator(persistence)
        await coordinator.load()
        let loadsAfterOpen = await persistence.loadCount

        let closed = await coordinator.teardown()
        XCTAssertTrue(closed)

        let finalLoadCount = await persistence.loadCount
        let saveCount = await persistence.saveCount
        XCTAssertEqual(finalLoadCount, loadsAfterOpen)
        XCTAssertEqual(saveCount, 0)
    }

    func testCancelledDebounceNeverReportsSavedOrLiveApplies() async {
        let persistence = RecordingConfigurationPersistence(Configuration())
        let recorder = LiveApplyRecorder()
        let coordinator = makeCoordinator(persistence, recorder: recorder)
        await coordinator.load()
        coordinator.edit([.appearance]) { $0.appearance.deadZone = 46 }
        coordinator.edit([.appearance]) { $0.appearance.deadZone = 47 }
        await Task.yield()

        XCTAssertEqual(coordinator.status, .saving)
        let saveCountBeforeFlush = await persistence.saveCount
        XCTAssertEqual(saveCountBeforeFlush, 0)
        XCTAssertTrue(recorder.events.isEmpty)

        let flushed = await coordinator.flush()
        XCTAssertTrue(flushed)
        XCTAssertEqual(coordinator.status, .saved)
        let saveCountAfterFlush = await persistence.saveCount
        XCTAssertEqual(saveCountAfterFlush, 1)
        XCTAssertEqual(recorder.events.count, 1)
    }

    func testSuccessfulAutosavePreservesSelectedMenuItemIdentity() async throws {
        let persistence = RecordingConfigurationPersistence(Configuration())
        let coordinator = makeCoordinator(persistence)
        await coordinator.load()
        let itemID = try XCTUnwrap(coordinator.menuEditorModel.middle.first?.id)
        coordinator.menuEditorModel.selection = SlotSelection(
            band: .middle,
            itemID: itemID,
            subItemID: nil
        )

        let binding = try XCTUnwrap(
            coordinator.menuEditorModel.binding(forItem: itemID, band: .middle)
        )
        var edited = binding.wrappedValue
        edited.label = "Still selected after save"
        binding.wrappedValue = edited
        coordinator.menuItemsDidChange()

        let flushed = await coordinator.flush()
        XCTAssertTrue(flushed)
        XCTAssertEqual(coordinator.menuEditorModel.selection?.itemID, itemID)
        XCTAssertEqual(
            coordinator.menuEditorModel.middle.first(where: { $0.id == itemID })?.label,
            "Still selected after save"
        )
    }

    func testOverlappingFlushSharesInFlightFailureWithoutImplicitRetry() async {
        let persistence = RecordingConfigurationPersistence(Configuration())
        let coordinator = makeCoordinator(persistence)
        await coordinator.load()
        await persistence.gateNextSaveWithFailure(TestFailure.write)
        coordinator.edit([.appearance]) { $0.appearance.deadZone = 48 }

        let firstFlush = Task { @MainActor in await coordinator.flush() }
        while await persistence.saveCount == 0 {
            await Task.yield()
        }
        let overlappingFlush = Task { @MainActor in await coordinator.flush() }
        await Task.yield()
        await persistence.releaseGatedSave()

        let firstResult = await firstFlush.value
        let overlappingResult = await overlappingFlush.value
        let saveCount = await persistence.saveCount
        XCTAssertFalse(firstResult)
        XCTAssertFalse(overlappingResult)
        XCTAssertEqual(saveCount, 1)
        XCTAssertEqual(coordinator.dirtyFields, [.appearance])
        guard case .saveFailed = coordinator.status else {
            return XCTFail("The shared failed write must remain Save Failed")
        }
    }

    // MARK: - App HUD inheritance (task 3.1)

    func testWholeRingLockSavesAndUnlocksWithIdenticalVisibleItems() async throws {
        let bundleID = "com.apple.Safari"
        var initial = Configuration()
        _ = initial.setAppHUDProfile(AppHUDProfile(), forBundleIdentifier: bundleID)
        let persistence = RecordingConfigurationPersistence(initial)
        let coordinator = makeCoordinator(persistence)
        await coordinator.load()
        XCTAssertTrue(coordinator.selectHUDProfile(.app(bundleIdentifier: bundleID)))
        let editor = coordinator.menuEditorModel
        editor.setFollowsGlobal(true, for: .inner)
        coordinator.menuItemsDidChange()
        XCTAssertEqual(coordinator.dirtyFields, [.menuItems])
        var saved = await coordinator.flush()
        XCTAssertTrue(saved)
        await coordinator.load()
        XCTAssertTrue(editor.followsGlobal(.inner))
        XCTAssertFalse(editor.followsGlobal(.middle))
        XCTAssertEqual(editor.inner, initial.inner)

        // A stale editor write must never become an override on a locked ring.
        editor.inner[0].label = "Discard stale write"
        editor.middle[0].label = "Keep middle change"
        coordinator.menuItemsDidChange()
        saved = await coordinator.flush()
        XCTAssertTrue(saved)
        let persisted = await persistence.current
        let rings = try XCTUnwrap(persisted.appHUDProfile(forBundleIdentifier: bundleID)?.rings)
        XCTAssertTrue(rings.inner.followsGlobal)
        XCTAssertTrue(rings.inner.overrides.isEmpty)
        XCTAssertEqual(editor.inner, initial.inner)
        XCTAssertEqual(editor.middle[0].label, "Keep middle change")

        editor.setFollowsGlobal(false, for: .inner)
        coordinator.menuItemsDidChange()
        saved = await coordinator.flush()
        XCTAssertTrue(saved)
        await coordinator.load()
        XCTAssertFalse(editor.followsGlobal(.inner))
        XCTAssertEqual(editor.inner, initial.inner)
        XCTAssertEqual(editor.middle[0].label, "Keep middle change")
    }

    func testExternalWholeRingLockConflictsWithAnEditToTheSameProfile() async {
        let bundleID = "com.apple.Safari"
        var initial = Configuration()
        _ = initial.setAppHUDProfile(AppHUDProfile(), forBundleIdentifier: bundleID)
        let persistence = RecordingConfigurationPersistence(initial)
        let coordinator = makeCoordinator(persistence)
        await coordinator.load()
        XCTAssertTrue(coordinator.selectHUDProfile(.app(bundleIdentifier: bundleID)))
        coordinator.menuEditorModel.middle[0].label = "Pending edit"
        coordinator.menuItemsDidChange()
        await persistence.mutateCurrent { config in
            _ = config.setAppHUDInheritance(
                AppHUDRings(middle: RingInheritance(followsGlobal: true)), forBundleIdentifier: bundleID
            )
        }
        let saved = await coordinator.flush()
        XCTAssertFalse(saved)
        let disk = await persistence.current
        XCTAssertEqual(disk.appHUDProfile(forBundleIdentifier: bundleID)?.rings?.middle.followsGlobal, true)
    }

    func testGlobalOnlyEditLeavesAppHUDStorageByteEqual() async throws {
        var initial = Configuration()
        _ = initial.setAppHUDProfile(appHUD(labeledLayout("Finder")), forBundleIdentifier: "com.apple.finder")
        _ = initial.setAppHUDProfile(AppHUDProfile(), forBundleIdentifier: "com.apple.Safari")
        let persistence = RecordingConfigurationPersistence(initial)
        let coordinator = makeCoordinator(persistence)
        await coordinator.load()
        let loaded = await persistence.current
        let profilesBefore = try appHUDProfilesData(loaded)

        coordinator.menuEditorModel.middle[1].label = "Global only"
        coordinator.menuEditorModel.inner.swapAt(0, 1)
        coordinator.menuItemsDidChange()
        let flushed = await coordinator.flush()
        XCTAssertTrue(flushed)

        let saved = await persistence.current
        XCTAssertEqual(saved.middle[1].label, "Global only")
        XCTAssertEqual(try appHUDProfilesData(saved), profilesBefore)
        XCTAssertEqual(saved.validAppHUDProfiles, initial.validAppHUDProfiles)
        XCTAssertEqual(coordinator.configuration.validAppHUDProfiles, initial.validAppHUDProfiles)
        // Inherited items follow the Global edit without any App HUD storage change.
        XCTAssertEqual(try appLayout(saved, "com.apple.Safari").middle[1].label, "Global only")
        XCTAssertEqual(try appLayout(saved, "com.apple.Safari").inner, saved.inner)
    }

    func testGlobalOnlyEditKeepsExternalAppHUDEditInsteadOfOverwritingIt() async throws {
        var initial = Configuration()
        _ = initial.setAppHUDProfile(AppHUDProfile(), forBundleIdentifier: "com.apple.Safari")
        let persistence = RecordingConfigurationPersistence(initial)
        let coordinator = makeCoordinator(persistence)
        await coordinator.load()
        coordinator.menuEditorModel.middle[1].label = "Local Global"
        coordinator.menuItemsDidChange()
        await persistence.mutateCurrent { relabelAppMiddle(&$0, "com.apple.Safari", "External Safari") }

        let flushed = await coordinator.flush()
        XCTAssertTrue(flushed)
        let saved = await persistence.current
        XCTAssertEqual(saved.middle[1].label, "Local Global")
        XCTAssertEqual(try appLayout(saved, "com.apple.Safari").middle[0].label, "External Safari")
        XCTAssertEqual(try appLayout(saved, "com.apple.Safari").middle[1].label, "Local Global")
    }

    func testGlobalEditWithInheritingAppHUDsStillRefusesExternalGlobalChange() async throws {
        var initial = Configuration()
        _ = initial.setAppHUDProfile(appHUD(labeledLayout("Finder")), forBundleIdentifier: "com.apple.finder")
        let persistence = RecordingConfigurationPersistence(initial)
        let coordinator = makeCoordinator(persistence)
        await coordinator.load()
        let loaded = await persistence.current
        let profilesBefore = try appHUDProfilesData(loaded)
        coordinator.menuEditorModel.middle[1].label = "Local Global"
        coordinator.menuItemsDidChange()
        await persistence.mutateCurrent { $0.middle[1].label = "External Global" }

        let flushed = await coordinator.flush()
        let saveCount = await persistence.saveCount
        XCTAssertFalse(flushed)
        XCTAssertEqual(saveCount, 0)
        XCTAssertEqual(coordinator.dirtyFields, [.menuItems])
        let saved = await persistence.current
        XCTAssertEqual(saved.middle[1].label, "External Global")
        XCTAssertEqual(try appHUDProfilesData(saved), profilesBefore)
        guard case .saveFailed = coordinator.status else {
            return XCTFail("A concurrent Global edit must still fail closed")
        }
    }

    func testAppHUDEditRefusesExternalChangeToTheSameInheritingProfile() async throws {
        var initial = Configuration()
        _ = initial.setAppHUDProfile(AppHUDProfile(), forBundleIdentifier: "com.apple.Safari")
        let persistence = RecordingConfigurationPersistence(initial)
        let coordinator = makeCoordinator(persistence)
        await coordinator.load()
        XCTAssertTrue(coordinator.selectHUDProfile(.app(bundleIdentifier: "com.apple.Safari")))
        let hiddenID = coordinator.menuEditorModel.middle[1].id
        coordinator.menuEditorModel.selection = SlotSelection(band: .middle, itemID: hiddenID, subItemID: nil)
        coordinator.menuEditorModel.removeSelectedItem()
        coordinator.menuItemsDidChange()
        await persistence.mutateCurrent { relabelAppMiddle(&$0, "com.apple.Safari", "External Safari") }

        let flushed = await coordinator.flush()
        let saveCount = await persistence.saveCount
        XCTAssertFalse(flushed)
        XCTAssertEqual(saveCount, 0)
        let saved = await persistence.current
        XCTAssertEqual(try appLayout(saved, "com.apple.Safari").middle[0].label, "External Safari")
        XCTAssertEqual(saved.appHUDProfile(forBundleIdentifier: "com.apple.Safari")?.rings?.middle.hidden, [])
        guard case .saveFailed = coordinator.status else {
            return XCTFail("A concurrent edit to the same App HUD must fail closed")
        }
    }

    func testGlobalDeleteKeepsCustomizedItemsAsAppOnlyInEveryAppHUD() async throws {
        let persistence = RecordingConfigurationPersistence(Configuration())
        let coordinator = makeCoordinator(persistence)
        await coordinator.load()
        let deletedID = coordinator.configuration.middle[0].id
        XCTAssertEqual(coordinator.createAppHUD(forBundleIdentifier: "com.apple.Safari"), .created)
        coordinator.menuEditorModel.middle[0].label = "Safari Apps"
        coordinator.menuItemsDidChange()
        var flushed = await coordinator.flush()
        XCTAssertTrue(flushed)
        // Another writer adds a customized App HUD this workspace never loaded.
        await persistence.mutateCurrent {
            _ = $0.setAppHUDProfile($0.makeAppHUDProfileFromGlobal(), forBundleIdentifier: "com.apple.Notes")
            relabelAppMiddle(&$0, "com.apple.Notes", "Notes Apps")
        }

        XCTAssertTrue(coordinator.selectHUDProfile(.global))
        coordinator.menuEditorModel.middle.remove(at: 0)
        coordinator.menuItemsDidChange()
        // In memory, before any save, the Safari copy is already app-only.
        XCTAssertTrue(coordinator.selectHUDProfile(.app(bundleIdentifier: "com.apple.Safari")))
        XCTAssertEqual(coordinator.menuEditorModel.middle.first?.label, "Safari Apps")
        XCTAssertEqual(coordinator.menuEditorModel.origin(of: deletedID), .appOnly)
        flushed = await coordinator.flush()
        XCTAssertTrue(flushed)

        let saved = await persistence.current
        XCTAssertFalse(saved.middle.contains { $0.id == deletedID })
        for (bundleIdentifier, label) in [("com.apple.Safari", "Safari Apps"), ("com.apple.Notes", "Notes Apps")] {
            let resolved = try XCTUnwrap(saved.resolvedAppLayout(forBundleIdentifier: bundleIdentifier))
            XCTAssertEqual(resolved.layout.middle.first?.label, label, bundleIdentifier)
            XCTAssertEqual(resolved.origins[deletedID], .appOnly, bundleIdentifier)
            let rings = try XCTUnwrap(saved.appHUDProfile(forBundleIdentifier: bundleIdentifier)?.rings)
            XCTAssertNil(rings.middle.overrides[deletedID], bundleIdentifier)
            XCTAssertEqual(rings.middle.appOnly.map(\.id), [deletedID], bundleIdentifier)
        }
    }

    func testGlobalSavePublishesOverflowWarningsUntilTheAppHUDHidesAnItem() async throws {
        let globalMiddle = (0..<7).map { RingMenuItem(label: "G\($0)", icon: "circle", actionType: .custom) }
        var initial = Configuration(middle: globalMiddle)
        let safariOnly = RingMenuItem(label: "Safari only", icon: "safari", actionType: .custom)
        _ = initial.setAppHUDProfile(
            AppHUDProfile(rings: AppHUDRings(middle: RingInheritance(appOnly: [AppOnlyItem(item: safariOnly, after: nil)]))),
            forBundleIdentifier: "com.apple.Safari"
        )
        _ = initial.setAppHUDProfile(AppHUDProfile(), forBundleIdentifier: "com.apple.finder")
        let persistence = RecordingConfigurationPersistence(initial)
        let coordinator = makeCoordinator(persistence)
        await coordinator.load()
        XCTAssertEqual(coordinator.overflowWarnings, [])

        coordinator.menuEditorModel.addItem(to: .middle)
        coordinator.menuItemsDidChange()
        XCTAssertEqual(coordinator.overflowWarnings, [], "published after the save, not while editing")
        var flushed = await coordinator.flush()
        XCTAssertTrue(flushed)
        XCTAssertEqual(coordinator.overflowWarnings, [
            .init(bundleIdentifier: "com.apple.Safari", band: .middle, count: 1),
        ])
        let saved = await persistence.current
        XCTAssertEqual(saved.middle.count, 8, "the Global save goes ahead")

        XCTAssertTrue(coordinator.selectHUDProfile(.app(bundleIdentifier: "com.apple.Safari")))
        XCTAssertEqual(coordinator.menuEditorModel.notShown(band: .middle).map(\.id), [saved.middle[7].id])
        coordinator.menuEditorModel.selection = SlotSelection(band: .middle, itemID: globalMiddle[0].id, subItemID: nil)
        coordinator.menuEditorModel.removeSelectedItem()
        coordinator.menuItemsDidChange()
        flushed = await coordinator.flush()
        XCTAssertTrue(flushed)
        XCTAssertEqual(coordinator.overflowWarnings, [])
    }

    func testCreateAndResetLeaveEverythingInherited() async throws {
        var initial = Configuration()
        initial.middle[0].label = "Current Global"
        let persistence = RecordingConfigurationPersistence(initial)
        let coordinator = makeCoordinator(persistence)
        await coordinator.load()

        XCTAssertEqual(coordinator.createAppHUD(forBundleIdentifier: "com.apple.Safari"), .created)
        var flushed = await coordinator.flush()
        XCTAssertTrue(flushed)
        var saved = await persistence.current
        XCTAssertEqual(saved.appHUDProfile(forBundleIdentifier: "com.apple.Safari")?.rings, AppHUDRings())
        XCTAssertEqual(coordinator.menuEditorModel.middle, initial.middle)
        XCTAssertEqual(Set(coordinator.menuEditorModel.origins.values), [.inherited])

        let customizedID = coordinator.menuEditorModel.middle[1].id
        coordinator.menuEditorModel.customize(id: customizedID)
        coordinator.menuEditorModel.selection = SlotSelection(
            band: .middle, itemID: coordinator.menuEditorModel.middle[2].id, subItemID: nil
        )
        coordinator.menuEditorModel.removeSelectedItem()
        coordinator.menuItemsDidChange()
        flushed = await coordinator.flush()
        XCTAssertTrue(flushed)
        saved = await persistence.current
        XCTAssertNotEqual(saved.appHUDProfile(forBundleIdentifier: "com.apple.Safari")?.rings, AppHUDRings())

        let reset = await coordinator.resetMenuItems()
        XCTAssertTrue(reset)
        saved = await persistence.current
        XCTAssertEqual(saved.appHUDProfile(forBundleIdentifier: "com.apple.Safari")?.rings, AppHUDRings())
        XCTAssertEqual(coordinator.menuEditorModel.middle, initial.middle)
        XCTAssertEqual(Set(coordinator.menuEditorModel.origins.values), [.inherited])
        XCTAssertEqual(coordinator.menuEditorModel.hiddenItems, [])
        XCTAssertTrue(coordinator.dirtyFields.isEmpty)
    }

    func testEditingAndCustomizingInheritedItemsStoreOnlyOverrides() async throws {
        var initial = Configuration()
        _ = initial.setAppHUDProfile(AppHUDProfile(), forBundleIdentifier: "com.apple.Safari")
        let persistence = RecordingConfigurationPersistence(initial)
        let coordinator = makeCoordinator(persistence)
        await coordinator.load()
        XCTAssertTrue(coordinator.selectHUDProfile(.app(bundleIdentifier: "com.apple.Safari")))
        let editedID = coordinator.menuEditorModel.middle[0].id
        let customizedID = coordinator.menuEditorModel.inner[0].id
        coordinator.menuEditorModel.middle[0].label = "Safari edit"
        coordinator.menuEditorModel.customize(id: customizedID)
        coordinator.menuItemsDidChange()
        let flushed = await coordinator.flush()
        XCTAssertTrue(flushed)

        let saved = await persistence.current
        XCTAssertEqual(saved.middle, initial.middle, "Global is untouched")
        let rings = try XCTUnwrap(saved.appHUDProfile(forBundleIdentifier: "com.apple.Safari")?.rings)
        XCTAssertEqual(rings.middle.overrides.keys.sorted { $0.uuidString < $1.uuidString }, [editedID])
        XCTAssertEqual(rings.middle.overrides[editedID]?.label, "Safari edit")
        // An explicit Customize sticks even with content identical to Global (AC12a).
        XCTAssertEqual(rings.inner.overrides, [customizedID: initial.inner[0]])
        XCTAssertEqual(rings.middle.hidden, [])
        XCTAssertEqual(rings.inner.hidden, [])
        XCTAssertEqual(rings.middle.appOnly, [])
        XCTAssertEqual(rings.inner.appOnly, [])
        XCTAssertNil(rings.middle.customOrder)
        XCTAssertNil(rings.inner.customOrder)
        XCTAssertEqual(coordinator.menuEditorModel.origin(of: editedID), .customized)
        XCTAssertEqual(coordinator.menuEditorModel.origin(of: customizedID), .customized)
    }

    func testHidingAnInheritedItemStoresOnlyHidden() async throws {
        var initial = Configuration()
        _ = initial.setAppHUDProfile(AppHUDProfile(), forBundleIdentifier: "com.apple.Safari")
        let persistence = RecordingConfigurationPersistence(initial)
        let coordinator = makeCoordinator(persistence)
        await coordinator.load()
        XCTAssertTrue(coordinator.selectHUDProfile(.app(bundleIdentifier: "com.apple.Safari")))
        let hiddenID = coordinator.menuEditorModel.middle[1].id
        coordinator.menuEditorModel.selection = SlotSelection(band: .middle, itemID: hiddenID, subItemID: nil)
        coordinator.menuEditorModel.removeSelectedItem()
        coordinator.menuItemsDidChange()
        let flushed = await coordinator.flush()
        XCTAssertTrue(flushed)

        let saved = await persistence.current
        XCTAssertEqual(saved.middle, initial.middle, "hiding in an App HUD never deletes from Global")
        let rings = try XCTUnwrap(saved.appHUDProfile(forBundleIdentifier: "com.apple.Safari")?.rings)
        XCTAssertEqual(rings, AppHUDRings(middle: RingInheritance(hidden: [hiddenID])))
        XCTAssertEqual(coordinator.menuEditorModel.hiddenItems.map(\.id), [hiddenID])
    }

    func testRevealingAppHUDWithNoncanonicalInheritanceNeverDirties() async throws {
        let global = Configuration()
        let hiddenAnchor = global.middle[1].id
        let appOnly = RingMenuItem(label: "After hidden", icon: "star", actionType: .custom)
        var initial = global
        // `diff` would re-anchor this item to the visible predecessor; storage
        // must stay as it is unless the user actually changes something.
        _ = initial.setAppHUDProfile(
            AppHUDProfile(rings: AppHUDRings(middle: RingInheritance(
                hidden: [hiddenAnchor],
                appOnly: [AppOnlyItem(item: appOnly, after: hiddenAnchor)]
            ))),
            forBundleIdentifier: "com.apple.Safari"
        )
        let persistence = RecordingConfigurationPersistence(initial)
        let coordinator = makeCoordinator(persistence)
        await coordinator.load()

        XCTAssertTrue(coordinator.selectHUDProfile(.app(bundleIdentifier: "com.apple.Safari")))
        coordinator.menuItemsDidChange()
        XCTAssertTrue(coordinator.selectHUDProfile(.global))
        coordinator.menuItemsDidChange()
        let flushed = await coordinator.flush()
        XCTAssertTrue(flushed)
        XCTAssertTrue(coordinator.dirtyFields.isEmpty)
        let saveCount = await persistence.saveCount
        XCTAssertEqual(saveCount, 0)
    }

    func testBackupRestoreRoundTripsVersion2AppHUDsExactly() async throws {
        var source = Configuration()
        let appOnly = RingMenuItem(label: "Safari only", icon: "safari", actionType: .custom)
        var override = source.middle[0]
        override.label = "Safari Apps"
        _ = source.setAppHUDProfile(
            AppHUDProfile(rings: AppHUDRings(
                inner: RingInheritance(customOrder: source.inner.reversed().map(\.id)),
                middle: RingInheritance(
                    overrides: [override.id: override],
                    hidden: [source.middle[1].id],
                    appOnly: [AppOnlyItem(item: appOnly, after: source.middle[0].id)]
                )
            )),
            forBundleIdentifier: "com.apple.Safari"
        )
        // The backup as a real file round trip would produce it.
        let backup = try JSONDecoder().decode(Configuration.self, from: JSONEncoder().encode(source))
        let persistence = RecordingConfigurationPersistence(backup)
        await persistence.setBackup(backup)
        let coordinator = makeCoordinator(persistence)
        await coordinator.load()
        XCTAssertTrue(coordinator.selectHUDProfile(.app(bundleIdentifier: "com.apple.Safari")))
        let reset = await coordinator.resetMenuItems()
        XCTAssertTrue(reset)
        let afterReset = await persistence.current
        XCTAssertEqual(afterReset.appHUDProfile(forBundleIdentifier: "com.apple.Safari")?.rings, AppHUDRings())

        let restoredBackup = await coordinator.restoreMenuItemsFromBackup()
        XCTAssertTrue(restoredBackup)
        let restored = await persistence.current
        XCTAssertEqual(
            restored.appHUDProfile(forBundleIdentifier: "com.apple.Safari"),
            backup.appHUDProfile(forBundleIdentifier: "com.apple.Safari")
        )
        XCTAssertEqual(try appHUDProfilesData(restored), try appHUDProfilesData(backup))
        let profiles = try XCTUnwrap(try encodedObject(restored)["appHUDProfiles"] as? [String: Any])
        let safari = try XCTUnwrap(profiles["com.apple.Safari"] as? [String: Any])
        XCTAssertEqual(safari["schemaVersion"] as? Int, 2)
        XCTAssertNotNil(safari["rings"])
        XCTAssertNil(safari["layout"])
        XCTAssertEqual(
            coordinator.menuEditorModel.middle.map(\.label).prefix(2),
            ["Safari Apps", "Safari only"]
        )
        XCTAssertEqual(coordinator.menuEditorModel.inner.map(\.id), source.inner.reversed().map(\.id))
        XCTAssertTrue(coordinator.dirtyFields.isEmpty)
    }

    private func makeCoordinator(
        _ persistence: RecordingConfigurationPersistence,
        recorder: LiveApplyRecorder? = nil
    ) -> SettingsWorkspaceCoordinator {
        let recorder = recorder ?? LiveApplyRecorder()
        return SettingsWorkspaceCoordinator(
            persistence: persistence,
            debounceClock: LongWorkspaceDebounceClock(),
            liveApply: { configuration in recorder.events.append(configuration) }
        )
    }

    private func makeDecodingError() -> Error {
        do {
            _ = try JSONDecoder().decode(Configuration.self, from: Data("{".utf8))
            return TestFailure.expectedDecodeFailure
        } catch {
            return error
        }
    }

    private func configuration(
        _ source: Configuration,
        mutate: (inout [String: Any]) -> Void
    ) throws -> Configuration {
        var object = try encodedObject(source)
        mutate(&object)
        return try JSONDecoder().decode(
            Configuration.self,
            from: JSONSerialization.data(withJSONObject: object)
        )
    }

    private func encodedObject(_ configuration: Configuration) throws -> [String: Any] {
        try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(configuration))
                as? [String: Any]
        )
    }
}

/// A version 2 App HUD showing exactly `layout` against the default Global, as
/// the version 1 copy `layout` migrates to at load.
private func appHUD(_ layout: HUDActionLayout) -> AppHUDProfile {
    AppHUDProfile(rings: AppHUDResolver.migrate(
        v1Layout: layout,
        global: Configuration().globalHUDActionLayout
    ))
}

/// Another writer renaming an App HUD's first middle item through `diff`.
private func relabelAppMiddle(_ configuration: inout Configuration, _ bundleIdentifier: String, _ label: String) {
    guard let profile = configuration.appHUDProfile(forBundleIdentifier: bundleIdentifier),
          var layout = configuration.resolvedAppLayout(forBundleIdentifier: bundleIdentifier)?.layout else {
        return XCTFail("Missing App HUD \(bundleIdentifier)")
    }
    layout.middle[0].label = label
    _ = configuration.setAppHUDProfile(
        AppHUDResolver.diff(edited: layout, previous: profile, global: configuration.globalHUDActionLayout),
        forBundleIdentifier: bundleIdentifier
    )
}

private struct LongWorkspaceDebounceClock: WorkspaceDebounceClock {
    func sleep() async throws {
        try await Task.sleep(for: .seconds(60))
    }
}

@MainActor
private final class LiveApplyRecorder {
    var events: [Configuration] = []
}

private enum TestFailure: Error {
    case write
    case expectedDecodeFailure
}

private actor RecordingConfigurationPersistence: ConfigurationPersisting {
    private(set) var current: Configuration
    private(set) var loadCount = 0
    private(set) var saveCount = 0
    private var loadFailure: Error?
    private var saveFailure: Error?
    private var backupFailure: Error?
    private var gatedSaveFailure: Error?
    private var gatedSaveContinuation: CheckedContinuation<Void, Never>?
    private var backup: Configuration?

    init(_ configuration: Configuration) {
        current = configuration
    }

    func loadResult() throws -> ConfigurationService.LoadResult {
        loadCount += 1
        if let loadFailure { throw loadFailure }
        return .loaded(current)
    }

    func save(_ configuration: Configuration) async throws {
        saveCount += 1
        if let gatedSaveFailure {
            await withCheckedContinuation { continuation in
                gatedSaveContinuation = continuation
            }
            self.gatedSaveFailure = nil
            throw gatedSaveFailure
        }
        if let saveFailure { throw saveFailure }
        current = configuration
    }

    func hasBackup() async -> Bool {
        backup != nil
    }

    func createBackup() async throws {
        if let backupFailure { throw backupFailure }
        backup = current
    }

    func loadBackup() async throws -> Configuration {
        guard let backup else { throw TestFailure.write }
        return backup
    }

    func mutateCurrent(_ mutation: (inout Configuration) -> Void) {
        mutation(&current)
    }

    func setLoadFailure(_ error: Error?) {
        loadFailure = error
    }

    func setSaveFailure(_ error: Error?) {
        saveFailure = error
    }

    func setBackupFailure(_ error: Error?) {
        backupFailure = error
    }

    func setBackup(_ configuration: Configuration) {
        backup = configuration
    }

    func gateNextSaveWithFailure(_ error: Error) {
        gatedSaveFailure = error
    }

    func releaseGatedSave() {
        gatedSaveContinuation?.resume()
        gatedSaveContinuation = nil
    }
}
