import CoreGraphics
import XCTest
@testable import MousePlus

final class ActionValidationTests: XCTestCase {
    func testValidationTable() {
        let layout = ScreenLayout(
            screens: [.init(
                frame: CGRect(x: 0, y: 0, width: 1000, height: 800),
                visibleFrame: CGRect(x: 0, y: 0, width: 1000, height: 760)
            )],
            primaryMaxY: 800,
            cursorPoint: .zero
        )
        let completeContext = ActionContext(frontmostPID: 42, screenLayout: layout)
        let cases: [(String, RingMenuItem, ActionContext, ActionValidation)] = [
            ("container", item(.custom, data: "true", children: [item(.custom, data: "true")]), completeContext, .invalid(.container)),
            ("app payload", item(.appSwitch, data: "com.apple.finder"), completeContext, .valid),
            ("missing app payload", item(.appSwitch), completeContext, .invalid(.missingPayload(.appSwitch))),
            ("custom payload", item(.custom, data: "open -a Notes"), completeContext, .valid),
            ("whitespace command", item(.custom, data: "  \n"), completeContext, .invalid(.missingPayload(.custom))),
            ("snap payload", item(.windowSnap, data: SnapZone.left.rawValue), completeContext, .valid),
            ("invalid snap payload", item(.windowSnap, data: "diagonal-ish"), completeContext, .invalid(.invalidPayload(.windowSnap))),
            ("canonical keystroke", item(.sendKeystroke, payload: .key(keyCode: 8, modifiers: 0)), completeContext, .valid),
            ("missing keystroke", item(.sendKeystroke), completeContext, .invalid(.missingPayload(.sendKeystroke))),
            ("legacy keystroke", item(.sendKeystroke, payload: .unresolvedLegacy("⌘C")), completeContext, .invalid(.unresolvedLegacyKeystroke)),
            ("known unavailable", item(.menuBar), completeContext, .invalid(.knownUnavailable(.menuBar))),
            ("unknown unavailable", item(.unavailable("future.action")), completeContext, .invalid(.unknownUnavailable("future.action"))),
            ("missing target", item(.windowSnap, data: SnapZone.left.rawValue), ActionContext(frontmostPID: nil, screenLayout: layout), .invalid(.missingContext(.targetApplication))),
            ("missing screens", item(.windowSnap, data: SnapZone.left.rawValue), ActionContext(frontmostPID: 42, screenLayout: nil), .invalid(.missingContext(.screenLayout))),
        ]

        for (name, item, context, expected) in cases {
            XCTAssertEqual(ActionValidation.validate(item, context: context), expected, name)
        }
    }

    func testEveryInvalidIssueHasUserFacingTextAndExecutionResult() {
        let issues: [ActionValidationIssue] = [
            .container,
            .missingPayload(.custom),
            .invalidPayload(.windowSnap),
            .unresolvedLegacyKeystroke,
            .knownUnavailable(.screenshot),
            .unknownUnavailable("future.action"),
            .unknownUnavailable(""),
            .missingContext(.targetApplication),
            .missingContext(.screenLayout),
        ]

        for issue in issues {
            let validation = ActionValidation.invalid(issue)
            XCTAssertFalse(validation.isValid)
            XCTAssertFalse(issue.userFacingText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            XCTAssertEqual(validation.userFacingText, issue.userFacingText)

            let result = ActionExecutionResult(validation: validation)
            XCTAssertFalse(result.isSuccess)
            XCTAssertEqual(result.userFacingText, issue.userFacingText)
        }
    }

    func testSuccessfulExecutionResultHasUserFacingText() {
        let result = ActionExecutionResult(validation: .valid)
        XCTAssertTrue(result.isSuccess)
        XCTAssertFalse(result.userFacingText.isEmpty)
    }

    private func item(
        _ type: ActionType,
        data: String = "",
        payload: KeystrokePayload? = nil,
        children: [RingMenuItem]? = nil
    ) -> RingMenuItem {
        RingMenuItem(label: "Test", icon: "circle", actionType: type,
                     actionData: data, subItems: children, keystrokePayload: payload)
    }
}
