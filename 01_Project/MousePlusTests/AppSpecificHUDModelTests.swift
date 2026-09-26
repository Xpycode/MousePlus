import Foundation
import XCTest
@testable import MousePlus

final class AppSpecificHUDModelTests: XCTestCase {
    private let finderBundleID = "com.apple.finder"
    private let mousePlusBundleID = "com.xpycode.MousePlus"

    func testLegacyConfigurationKeepsGlobalLayoutAndAddsNoProfile() throws {
        let global = makeLayout("Global")
        let original = Configuration(
            inner: global.inner,
            middle: global.middle,
            behavior: BehaviorConfig(
                holdToActivate: false,
                tapToActivate: true,
                dismissOnClickOutside: false,
                dismissOnEscape: true
            )
        )
        let encoded = try JSONEncoder().encode(original)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "appHUDProfiles")
        var triggers = try XCTUnwrap(object["triggers"] as? [String: Any])
        triggers.removeValue(forKey: "globalHUDShortcut")
        object["triggers"] = triggers

        let loaded = try JSONDecoder().decode(
            Configuration.self,
            from: JSONSerialization.data(withJSONObject: object)
        )
        let decoded = try JSONDecoder().decode(
            Configuration.self,
            from: JSONEncoder().encode(loaded)
        )

        XCTAssertEqual(decoded.globalHUDActionLayout, global)
        XCTAssertTrue(decoded.validAppHUDProfiles.isEmpty)
        XCTAssertEqual(decoded.triggers.globalHUDShortcut, .none)
        XCTAssertEqual(decoded.behavior, original.behavior)
    }

    func testMalformedGlobalHUDShortcutDefaultsIndependently() throws {
        let encoded = try JSONEncoder().encode(Configuration())
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        var triggers = try XCTUnwrap(object["triggers"] as? [String: Any])
        let contextual = triggers["keyboard"]
        triggers["globalHUDShortcut"] = ["futureBinding": ["version": 3]]
        object["triggers"] = triggers

        let decoded = try JSONDecoder().decode(
            Configuration.self,
            from: JSONSerialization.data(withJSONObject: object)
        )

        XCTAssertEqual(decoded.triggers.globalHUDShortcut, .none)
        let roundTripped = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(decoded)) as? [String: Any]
        )
        let savedTriggers = try XCTUnwrap(roundTripped["triggers"] as? [String: Any])
        XCTAssertEqual(savedTriggers["keyboard"] as? NSDictionary, contextual as? NSDictionary)
    }

    func testExplicitNullMiddleRetainsLegacySampleFallback() throws {
        let data = Data(#"{"inner":[],"middle":null}"#.utf8)

        let decoded = try JSONDecoder().decode(Configuration.self, from: data)

        XCTAssertEqual(decoded.inner, [])
        XCTAssertEqual(decoded.middle, RingMenuItem.sampleItems)
    }

    func testProfileCreatedFromGlobalHasIndependentValueSemantics() {
        var configuration = Configuration(
            inner: makeLayout("Global").inner,
            middle: makeLayout("Global").middle
        )
        var finderProfile = configuration.makeAppHUDProfileFromGlobal()
        XCTAssertTrue(configuration.setAppHUDProfile(finderProfile, forBundleIdentifier: finderBundleID))

        finderProfile.inner[0].label = "Finder changed"
        XCTAssertTrue(configuration.setAppHUDProfile(finderProfile, forBundleIdentifier: finderBundleID))
        configuration.inner[0].label = "Global changed"

        XCTAssertEqual(configuration.inner[0].label, "Global changed")
        XCTAssertEqual(
            configuration.appHUDProfile(forBundleIdentifier: finderBundleID)?.inner[0].label,
            "Finder changed"
        )
    }

    func testGlobalUnknownItemFieldsSurviveSaveAndCreateByCopy() throws {
        let childID = UUID().uuidString
        let base = try JSONEncoder().encode(Configuration(
            inner: [RingMenuItem(label: "Inner", icon: "circle", actionType: .custom)],
            middle: [RingMenuItem(
                label: "Middle",
                icon: "square",
                actionType: .custom,
                subItems: [RingMenuItem(
                    id: UUID(uuidString: childID)!,
                    label: "Child",
                    icon: "triangle",
                    actionType: .custom
                )]
            )]
        ))
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: base) as? [String: Any])
        var inner = try XCTUnwrap(object["inner"] as? [[String: Any]])
        inner[0]["futureInner"] = ["token": "inner-v2"]
        object["inner"] = inner
        var middle = try XCTUnwrap(object["middle"] as? [[String: Any]])
        var children = try XCTUnwrap(middle[0]["subItems"] as? [[String: Any]])
        children[0]["futureChild"] = ["token": "child-v2"]
        middle[0]["subItems"] = children
        object["middle"] = middle

        var decoded = try JSONDecoder().decode(
            Configuration.self,
            from: JSONSerialization.data(withJSONObject: object)
        )
        decoded.behavior.dismissOnEscape.toggle()
        let copied = decoded.makeAppHUDProfileFromGlobal()
        XCTAssertTrue(decoded.setAppHUDProfile(copied, forBundleIdentifier: finderBundleID))

        let saved = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(decoded)) as? [String: Any]
        )
        let savedInner = try XCTUnwrap(saved["inner"] as? [[String: Any]])
        XCTAssertEqual(
            ((savedInner[0]["futureInner"] as? [String: Any])?["token"] as? String),
            "inner-v2"
        )
        let savedMiddle = try XCTUnwrap(saved["middle"] as? [[String: Any]])
        let savedChildren = try XCTUnwrap(savedMiddle[0]["subItems"] as? [[String: Any]])
        XCTAssertEqual(
            ((savedChildren[0]["futureChild"] as? [String: Any])?["token"] as? String),
            "child-v2"
        )
        let profiles = try XCTUnwrap(saved["appHUDProfiles"] as? [String: Any])
        let finder = try XCTUnwrap(profiles[finderBundleID] as? [String: Any])
        let layout = try XCTUnwrap(finder["layout"] as? [String: Any])
        let copiedInner = try XCTUnwrap(layout["inner"] as? [[String: Any]])
        XCTAssertEqual(
            ((copiedInner[0]["futureInner"] as? [String: Any])?["token"] as? String),
            "inner-v2"
        )
    }

    func testContextualResolutionUsesExactBundleMatchAndFreezesValues() throws {
        var configuration = Configuration(
            inner: makeLayout("Global").inner,
            middle: makeLayout("Global").middle
        )
        XCTAssertTrue(configuration.setAppHUDProfile(
            AppHUDProfile(layout: makeLayout("Finder")),
            forBundleIdentifier: finderBundleID
        ))
        let snapshot = FrontmostAppSnapshot(
            processIdentifier: 42,
            bundleIdentifier: finderBundleID,
            localizedName: "Finder"
        )

        let resolved = configuration.resolveHUD(
            route: .contextual,
            frontmostApp: snapshot,
            mousePlusBundleIdentifier: mousePlusBundleID
        )
        var changedProfile = try XCTUnwrap(
            configuration.appHUDProfile(forBundleIdentifier: finderBundleID)
        )
        changedProfile.inner[0].label = "Changed after resolution"
        XCTAssertTrue(configuration.setAppHUDProfile(changedProfile, forBundleIdentifier: finderBundleID))

        XCTAssertEqual(resolved.profileReference, .app(bundleIdentifier: finderBundleID))
        XCTAssertEqual(resolved.resolution, .exactAppMatch)
        XCTAssertEqual(resolved.actionLayout.inner[0].label, "Finder inner")
        XCTAssertEqual(resolved.targetApplication, snapshot)
    }

    func testGlobalRouteBypassesMatchingAppProfile() {
        var configuration = Configuration(
            inner: makeLayout("Global").inner,
            middle: makeLayout("Global").middle
        )
        XCTAssertTrue(configuration.setAppHUDProfile(
            AppHUDProfile(layout: makeLayout("Finder")),
            forBundleIdentifier: finderBundleID
        ))

        let resolved = configuration.resolveHUD(
            route: .global,
            frontmostApp: .init(
                processIdentifier: 42,
                bundleIdentifier: finderBundleID,
                localizedName: "Finder"
            ),
            mousePlusBundleIdentifier: mousePlusBundleID
        )

        XCTAssertEqual(resolved.profileReference, .global)
        XCTAssertEqual(resolved.resolution, .globalRoute)
        XCTAssertEqual(resolved.actionLayout.inner[0].label, "Global inner")
    }

    func testContextualFallbackReasonsAreDeterministic() throws {
        var configuration = try configurationWithUnreadableFinderProfile()
        XCTAssertTrue(configuration.setAppHUDProfile(
            AppHUDProfile(layout: makeLayout("Must not resolve self")),
            forBundleIdentifier: mousePlusBundleID
        ))
        let cases: [(String?, HUDProfileResolution)] = [
            (nil, .missingBundleIdentifier),
            (mousePlusBundleID, .mousePlusFrontmost),
            ("com.example.Unconfigured", .noMatchingProfile),
            (finderBundleID, .unavailableProfile),
        ]

        for (bundleIdentifier, reason) in cases {
            let resolved = resolve(configuration, bundleIdentifier: bundleIdentifier)
            XCTAssertEqual(resolved.resolution, reason)
            XCTAssertEqual(resolved.profileReference, .global)
            XCTAssertEqual(resolved.actionLayout, configuration.globalHUDActionLayout)
            XCTAssertEqual(resolved.targetApplication.processIdentifier, 42)
            XCTAssertEqual(resolved.targetApplication.bundleIdentifier, bundleIdentifier)
        }
    }

    func testMalformedProfileAndUnknownFutureDataRoundTripLosslessly() throws {
        let source = try configurationJSON(appProfiles: [
            finderBundleID: [
                "layout": ["inner": "not-an-array", "middle": []],
                "futureFlag": true,
                "futureNested": ["revision": 7, "values": [1, 2, 3]],
            ],
        ], topLevelFuture: ["keep": "opaque", "enabled": true])

        let decoded = try JSONDecoder().decode(Configuration.self, from: source)
        XCTAssertNil(decoded.appHUDProfile(forBundleIdentifier: finderBundleID))
        XCTAssertTrue(decoded.hasUnavailableAppHUDProfile(forBundleIdentifier: finderBundleID))

        var unrelatedEdit = decoded
        unrelatedEdit.behavior.dismissOnEscape.toggle()
        let encoded = try JSONEncoder().encode(unrelatedEdit)
        let original = try XCTUnwrap(JSONSerialization.jsonObject(with: source) as? [String: Any])
        let roundTripped = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])

        XCTAssertEqual(
            original["appHUDProfiles"] as? NSDictionary,
            roundTripped["appHUDProfiles"] as? NSDictionary
        )
        XCTAssertEqual(
            original["futureTopLevel"] as? NSDictionary,
            roundTripped["futureTopLevel"] as? NSDictionary
        )
    }

    func testMalformedProfileCollectionIsPreservedAndCannotBeOverwrittenByTypedMutation() throws {
        let base = try JSONEncoder().encode(Configuration(inner: [], middle: []))
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: base) as? [String: Any])
        let opaqueCollection: [Any] = ["future", ["revision": 5]]
        object["appHUDProfiles"] = opaqueCollection

        var decoded = try JSONDecoder().decode(
            Configuration.self,
            from: JSONSerialization.data(withJSONObject: object)
        )

        XCTAssertTrue(decoded.hasUnavailableAppHUDProfilesCollection)
        XCTAssertFalse(decoded.setAppHUDProfile(
            AppHUDProfile(layout: makeLayout("Finder")),
            forBundleIdentifier: finderBundleID
        ))
        decoded.behavior.dismissOnEscape.toggle()
        let encoded = try JSONEncoder().encode(decoded)
        let roundTripped = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        XCTAssertEqual(roundTripped["appHUDProfiles"] as? NSArray, opaqueCollection as NSArray)
    }

    func testTypedProfilePreservesUnknownFieldsAndUnknownActions() throws {
        let itemID = UUID().uuidString
        let childID = UUID().uuidString
        let profile: [String: Any] = [
            "layout": [
                "inner": [
                    [
                        "id": itemID,
                        "label": "Future A",
                        "icon": "sparkles",
                        "actionType": "futureAction",
                        "actionData": "opaque-payload",
                        "wedgeColor": ["red": 1, "green": 0, "blue": 0, "alpha": 1],
                        "futureItemSetting": ["slot": "first"],
                    ],
                    [
                        "id": itemID,
                        "label": "Future B",
                        "icon": "sparkles",
                        "actionType": "futureAction",
                        "actionData": "opaque-payload",
                        "futureItemSetting": ["slot": "second"],
                    ],
                ],
                "middle": [[
                    "id": UUID().uuidString,
                    "label": "Parent",
                    "icon": "folder",
                    "actionType": "none",
                    "actionData": "",
                    "subItems": [
                        [
                            "id": childID,
                            "label": "Child A",
                            "icon": "1.circle",
                            "actionType": "none",
                            "actionData": "",
                            "futureChildSetting": "first-child",
                        ],
                        [
                            "id": childID,
                            "label": "Child B",
                            "icon": "2.circle",
                            "actionType": "none",
                            "actionData": "",
                            "futureChildSetting": "second-child",
                        ],
                    ],
                ]],
                "futureLayoutSetting": ["spacing": 12],
            ],
            "futureProfileSetting": ["mode": "v3"],
        ]
        let source = try configurationJSON(appProfiles: [finderBundleID: profile])
        var decoded = try JSONDecoder().decode(Configuration.self, from: source)

        var typed = try XCTUnwrap(decoded.appHUDProfile(forBundleIdentifier: finderBundleID))
        XCTAssertEqual(typed.inner[0].actionType, .unavailable("futureAction"))
        XCTAssertEqual(typed.inner[0].actionData, "opaque-payload")
        typed.inner[0].label = "Edited Future A"
        typed.inner[0].wedgeColor = nil
        typed.middle[0].subItems?[1].label = "Edited Child B"
        XCTAssertTrue(decoded.setAppHUDProfile(typed, forBundleIdentifier: finderBundleID))

        let encoded = try JSONEncoder().encode(decoded)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        let profiles = try XCTUnwrap(object["appHUDProfiles"] as? [String: Any])
        let savedProfile = try XCTUnwrap(profiles[finderBundleID] as? [String: Any])
        XCTAssertEqual(savedProfile["futureProfileSetting"] as? NSDictionary, ["mode": "v3"] as NSDictionary)
        let savedLayout = try XCTUnwrap(savedProfile["layout"] as? [String: Any])
        XCTAssertEqual(savedLayout["futureLayoutSetting"] as? NSDictionary, ["spacing": 12] as NSDictionary)
        let savedInner = try XCTUnwrap(savedLayout["inner"] as? [[String: Any]])
        XCTAssertEqual(savedInner[0]["label"] as? String, "Edited Future A")
        XCTAssertNil(savedInner[0]["wedgeColor"])
        XCTAssertEqual(savedInner[0]["futureItemSetting"] as? NSDictionary, ["slot": "first"] as NSDictionary)
        XCTAssertEqual(savedInner[1]["futureItemSetting"] as? NSDictionary, ["slot": "second"] as NSDictionary)
        let savedMiddle = try XCTUnwrap(savedLayout["middle"] as? [[String: Any]])
        let savedChildren = try XCTUnwrap(savedMiddle[0]["subItems"] as? [[String: Any]])
        XCTAssertEqual(savedChildren[1]["label"] as? String, "Edited Child B")
        XCTAssertEqual(savedChildren[0]["futureChildSetting"] as? String, "first-child")
        XCTAssertEqual(savedChildren[1]["futureChildSetting"] as? String, "second-child")
    }

    func testReplacingExactUnreadableProfileIntentionallyDropsOpaquePayload() throws {
        var configuration = try configurationWithUnreadableFinderProfile()

        XCTAssertTrue(configuration.setAppHUDProfile(
            AppHUDProfile(layout: makeLayout("Replacement")),
            forBundleIdentifier: finderBundleID
        ))

        XCTAssertFalse(configuration.hasUnavailableAppHUDProfile(forBundleIdentifier: finderBundleID))
        XCTAssertEqual(
            configuration.appHUDProfile(forBundleIdentifier: finderBundleID)?.inner[0].label,
            "Replacement inner"
        )
    }

    func testRemovingAppProfileLeavesGlobalLayoutUnchanged() throws {
        let global = makeLayout("Global")
        var configuration = Configuration(inner: global.inner, middle: global.middle)
        XCTAssertTrue(configuration.setAppHUDProfile(
            AppHUDProfile(layout: makeLayout("Finder")),
            forBundleIdentifier: finderBundleID
        ))

        XCTAssertTrue(configuration.removeAppHUDProfile(forBundleIdentifier: finderBundleID))
        let reloaded = try JSONDecoder().decode(
            Configuration.self,
            from: JSONEncoder().encode(configuration)
        )

        XCTAssertNil(reloaded.appHUDProfile(forBundleIdentifier: finderBundleID))
        XCTAssertEqual(reloaded.globalHUDActionLayout, global)
        XCTAssertEqual(resolve(reloaded, bundleIdentifier: finderBundleID).resolution, .noMatchingProfile)
    }

    func testEmptyBundleIdentifierCannotCreateOrRemoveAProfile() {
        var configuration = Configuration()
        XCTAssertFalse(configuration.setAppHUDProfile(AppHUDProfile(layout: makeLayout("Bad")), forBundleIdentifier: ""))
        XCTAssertFalse(configuration.removeAppHUDProfile(forBundleIdentifier: ""))
        XCTAssertTrue(configuration.validAppHUDProfiles.isEmpty)
    }

    private func resolve(_ configuration: Configuration, bundleIdentifier: String?) -> ResolvedHUDProfile {
        configuration.resolveHUD(
            route: .contextual,
            frontmostApp: .init(
                processIdentifier: 42,
                bundleIdentifier: bundleIdentifier,
                localizedName: "Candidate"
            ),
            mousePlusBundleIdentifier: mousePlusBundleID
        )
    }

    private func configurationWithUnreadableFinderProfile() throws -> Configuration {
        let data = try configurationJSON(appProfiles: [
            finderBundleID: ["layout": ["inner": "bad", "middle": []]],
        ])
        return try JSONDecoder().decode(Configuration.self, from: data)
    }

    private func configurationJSON(
        appProfiles: [String: Any],
        topLevelFuture: [String: Any]? = nil
    ) throws -> Data {
        let base = try JSONEncoder().encode(Configuration(inner: [], middle: []))
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: base) as? [String: Any])
        object["appHUDProfiles"] = appProfiles
        if let topLevelFuture {
            object["futureTopLevel"] = topLevelFuture
        }
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    private func makeLayout(_ prefix: String) -> HUDActionLayout {
        HUDActionLayout(
            inner: [RingMenuItem(label: "\(prefix) inner", icon: "circle", actionType: .custom)],
            middle: [RingMenuItem(label: "\(prefix) middle", icon: "square", actionType: .custom)]
        )
    }
}
