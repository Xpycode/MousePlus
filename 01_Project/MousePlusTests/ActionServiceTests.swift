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

    init(result: Result<Bool, Error>) { self.result = result }

    func activateOrLaunch(bundleIdentifier: String) async throws -> Bool {
        bundleIdentifiers.append(bundleIdentifier)
        return try result.get()
    }
}

private actor KeystrokeStub: ActionKeystrokeSending {
    let error: Error?
    private(set) var calls: [(UInt16, CGEventFlags)] = []

    init(error: Error? = nil) { self.error = error }

    func send(keyCode: UInt16, flags: CGEventFlags) async throws {
        calls.append((keyCode, flags))
        if let error { throw error }
    }
}
