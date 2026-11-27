import CoreGraphics
import XCTest
@testable import MousePlus

final class ActionServiceTests: XCTestCase {
    func testLaunchErrorIsReported() async {
        let workspace = WorkspaceStub(result: .failure(TestError.launch))
        let service = ActionService(workspace: workspace)

        let result = await service.execute(item(.appSwitch, data: "com.example.missing"))

        XCTAssertFalse(result.isSuccess)
        XCTAssertEqual(result.userFacingText, "The application could not be launched.")
    }

    func testNonzeroCommandExitIsReportedAfterProcessCompletes() async {
        let process = ProcessStub(result: .success(17))
        let service = ActionService(processRunner: process)

        let result = await service.execute(item(.custom, data: "exit 17"))

        XCTAssertFalse(result.isSuccess)
        XCTAssertEqual(result.userFacingText, "The command exited with status 17.")
        let commands = await process.commands
        XCTAssertEqual(commands, ["exit 17"])
    }

    func testActivationFailureIsReported() async {
        let workspace = WorkspaceStub(result: .success(false))
        let service = ActionService(workspace: workspace)

        let result = await service.execute(item(.appSwitch, data: "com.apple.TextEdit"))

        XCTAssertFalse(result.isSuccess)
        XCTAssertEqual(result.userFacingText, "The application could not be activated.")
    }

    func testUnavailableAndInvalidPayloadAreRejectedBeforeSideEffects() async {
        let process = ProcessStub(result: .success(0))
        let workspace = WorkspaceStub(result: .success(true))
        let service = ActionService(processRunner: process, workspace: workspace)

        let unavailable = await service.execute(item(.unavailable("future.action")))
        let invalid = await service.execute(item(.appSwitch, data: "  "))

        XCTAssertFalse(unavailable.isSuccess)
        XCTAssertTrue(unavailable.userFacingText.contains("not supported"))
        XCTAssertFalse(invalid.isSuccess)
        XCTAssertTrue(invalid.userFacingText.contains("needs action details"))
        let commands = await process.commands
        let bundleIdentifiers = await workspace.bundleIdentifiers
        XCTAssertEqual(commands, [])
        XCTAssertEqual(bundleIdentifiers, [])
    }

    func testKeystrokePermissionDenialIsReported() async {
        let keystrokes = KeystrokeStub(error: KeystrokeError.postEventAccessDenied)
        let service = ActionService(keystrokeService: keystrokes)
        let payload = KeystrokePayload.key(keyCode: 8, modifiers: 1 << 20)

        let result = await service.execute(item(.sendKeystroke, payload: payload))

        XCTAssertFalse(result.isSuccess)
        XCTAssertEqual(result.userFacingText, "Permission to post keyboard events is required.")
        let calls = await keystrokes.calls
        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(calls.first?.0, 8)
        XCTAssertEqual(calls.first?.1, CGEventFlags.maskCommand)
    }

    func testValidKeystrokeIsForwardedAndCompletes() async {
        let keystrokes = KeystrokeStub()
        let service = ActionService(keystrokeService: keystrokes)
        let modifiers = (1 << 18) | (1 << 19) | (1 << 20)

        let result = await service.execute(item(
            .sendKeystroke,
            payload: .key(keyCode: 12, modifiers: UInt(modifiers))
        ))

        XCTAssertEqual(result, .completed)
        let calls = await keystrokes.calls
        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(calls.first?.0, 12)
        XCTAssertEqual(
            calls.first?.1,
            [.maskControl, .maskAlternate, .maskCommand]
        )
    }

    /// Regression (2026-11-21): clicking a ring wedge left MousePlus active, so
    /// the chord never reached Safari. Live-ring keystrokes hand focus back first.
    func testLiveRingKeystrokeReturnsFocusToTargetBeforeSending() async {
        let keystrokes = KeystrokeStub()
        let workspace = WorkspaceStub()
        let service = ActionService(workspace: workspace, keystrokeService: keystrokes)

        let result = await service.execute(
            item(.sendKeystroke, payload: .key(keyCode: 42, modifiers: 1 << 20)),
            context: ActionContext(frontmostPID: 4242, returnsFocusToTarget: true)
        )

        XCTAssertEqual(result, .completed)
        let returns = await workspace.focusReturns
        XCTAssertEqual(returns, [4242])
        let calls = await keystrokes.calls
        XCTAssertEqual(calls.count, 1)
    }

    func testKeystrokeWithoutFocusReturnRequestLeavesFocusAlone() async {
        let keystrokes = KeystrokeStub()
        let workspace = WorkspaceStub()
        let service = ActionService(workspace: workspace, keystrokeService: keystrokes)

        _ = await service.execute(
            item(.sendKeystroke, payload: .key(keyCode: 42, modifiers: 1 << 20)),
            context: ActionContext(frontmostPID: 4242)
        )

        let returns = await workspace.focusReturns
        XCTAssertEqual(returns, [])
    }

    func testMissingKeystrokePayloadIsRejectedWithoutSending() async {
        let keystrokes = KeystrokeStub()
        let service = ActionService(keystrokeService: keystrokes)

        let result = await service.execute(item(.sendKeystroke))

        XCTAssertFalse(result.isSuccess)
        XCTAssertTrue(result.userFacingText.contains("needs action details"))
        let calls = await keystrokes.calls
        XCTAssertTrue(calls.isEmpty)
    }

    func testUnresolvedLegacyKeystrokeIsRejectedWithoutSending() async {
        let keystrokes = KeystrokeStub()
        let service = ActionService(keystrokeService: keystrokes)

        let result = await service.execute(item(
            .sendKeystroke,
            payload: .unresolvedLegacy("⌘C")
        ))

        XCTAssertFalse(result.isSuccess)
        XCTAssertTrue(result.userFacingText.contains("Record it again"))
        let calls = await keystrokes.calls
        XCTAssertTrue(calls.isEmpty)
    }

    private func item(
        _ type: ActionType,
        data: String = "",
        payload: KeystrokePayload? = nil
    ) -> RingMenuItem {
        RingMenuItem(label: "Test", icon: "circle", actionType: type,
                     actionData: data, keystrokePayload: payload)
    }
}

private enum TestError: LocalizedError {
    case launch

    var errorDescription: String? { "The application could not be launched." }
}

private actor ProcessStub: ActionProcessRunning {
    let result: Result<Int32, Error>
    private(set) var commands: [String] = []

    init(result: Result<Int32, Error>) { self.result = result }

    func run(command: String) async throws -> Int32 {
        commands.append(command)
        return try result.get()
    }
}

private actor WorkspaceStub: ActionWorkspace {
    let result: Result<Bool, Error>
    private(set) var bundleIdentifiers: [String] = []

    init(result: Result<Bool, Error> = .success(true)) { self.result = result }

    func activateOrLaunch(bundleIdentifier: String) async throws -> Bool {
        bundleIdentifiers.append(bundleIdentifier)
        return try result.get()
    }

    private(set) var focusReturns: [pid_t] = []
    func returnFocusIfStolen(toPID pid: pid_t) async { focusReturns.append(pid) }
}

private actor KeystrokeStub: ActionKeystrokeSending {
    let error: Error?
    private(set) var calls: [(UInt16, CGEventFlags, KeystrokeDestination)] = []

    init(error: Error? = nil) { self.error = error }

    func send(keyCode: UInt16, flags: CGEventFlags, destination: KeystrokeDestination) async throws {
        calls.append((keyCode, flags, destination))
        if let error { throw error }
    }
}
