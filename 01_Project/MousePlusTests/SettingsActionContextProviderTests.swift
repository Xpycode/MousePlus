import XCTest
@testable import MousePlus

@MainActor
final class SettingsActionContextProviderTests: XCTestCase {
    private let mousePlusPID: pid_t = 10
    private let mousePlusBundleID = "com.example.MousePlus"

    func testFirstOpenCapturesExternalAppBeforeSettingsActivation() {
        let workspace = WorkspaceStub(frontmost: .external(pid: 20, name: "Notes"))
        let provider = makeProvider(workspace: workspace)

        provider.recordFrontmostApplicationBeforeSettingsActivation()

        assertAvailable(provider, name: "Notes", pid: 20)
    }

    func testFocusReturnRefreshesTargetToMostRecentlyActivatedExternalApp() {
        let workspace = WorkspaceStub(frontmost: .external(pid: 20, name: "Notes"))
        let provider = makeProvider(workspace: workspace)
        provider.recordFrontmostApplicationBeforeSettingsActivation()

        workspace.activate(.external(pid: 30, name: "Safari"))
        workspace.activate(.mousePlus(pid: mousePlusPID, bundleID: mousePlusBundleID))

        assertAvailable(provider, name: "Safari", pid: 30)
    }

    func testTerminatedTargetBecomesUnavailableInsteadOfReturningStalePID() {
        let workspace = WorkspaceStub(frontmost: .external(pid: 20, name: "Notes"))
        let provider = makeProvider(workspace: workspace)
        provider.recordFrontmostApplicationBeforeSettingsActivation()
        workspace.terminate(pid: 20)

        guard case .unavailable(let reason) = provider.availability else {
            return XCTFail("Expected unavailable context")
        }
        XCTAssertEqual(reason, SettingsActionContextProvider.staleTargetReason)
        XCTAssertNil(provider.target)
    }

    func testMousePlusOnlyStateHasAnExplanatoryUnavailableReason() {
        let workspace = WorkspaceStub(
            frontmost: .mousePlus(pid: mousePlusPID, bundleID: mousePlusBundleID)
        )
        let provider = makeProvider(workspace: workspace)

        provider.recordFrontmostApplicationBeforeSettingsActivation()

        guard case .unavailable(let reason) = provider.availability else {
            return XCTFail("Expected unavailable context")
        }
        XCTAssertEqual(reason, SettingsActionContextProvider.noExternalTargetReason)
        XCTAssertNil(provider.target)
    }

    private func makeProvider(workspace: WorkspaceStub) -> SettingsActionContextProvider {
        SettingsActionContextProvider(
            workspace: workspace,
            ownProcessIdentifier: mousePlusPID,
            ownBundleIdentifier: mousePlusBundleID,
            captureScreens: {
                ScreenLayout(
                    screens: [.init(frame: CGRect(x: 0, y: 0, width: 100, height: 100),
                                    visibleFrame: CGRect(x: 0, y: 0, width: 100, height: 90))],
                    primaryMaxY: 100,
                    cursorPoint: CGPoint(x: 50, y: 50)
                )
            }
        )
    }

    private func assertAvailable(
        _ provider: SettingsActionContextProvider,
        name: String,
        pid: pid_t,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .available(let target, let context) = provider.availability else {
            return XCTFail("Expected available context", file: file, line: line)
        }
        XCTAssertEqual(target, SettingsActionTarget(name: name, processIdentifier: pid), file: file, line: line)
        XCTAssertEqual(context.frontmostPID, pid, file: file, line: line)
        XCTAssertEqual(context.screenLayout?.screens.count, 1, file: file, line: line)
    }
}

@MainActor
private final class WorkspaceStub: SettingsWorkspaceProviding {
    var frontmostApplication: SettingsRunningApplication?
    private var applications: [pid_t: SettingsRunningApplication] = [:]
    private var activationHandler: ((SettingsRunningApplication) -> Void)?

    init(frontmost: SettingsRunningApplication?) {
        frontmostApplication = frontmost
        if let frontmost { applications[frontmost.processIdentifier] = frontmost }
    }

    func runningApplication(processIdentifier: pid_t) -> SettingsRunningApplication? {
        applications[processIdentifier]
    }

    func observeApplicationActivations(
        _ handler: @escaping (SettingsRunningApplication) -> Void
    ) -> AnyObject {
        activationHandler = handler
        return ObserverToken()
    }

    func activate(_ app: SettingsRunningApplication) {
        frontmostApplication = app
        applications[app.processIdentifier] = app
        activationHandler?(app)
    }

    func terminate(pid: pid_t) {
        guard let app = applications[pid] else { return }
        applications[pid] = SettingsRunningApplication(
            name: app.name,
            bundleIdentifier: app.bundleIdentifier,
            processIdentifier: app.processIdentifier,
            isTerminated: true
        )
    }
}

private final class ObserverToken: NSObject {}

private extension SettingsRunningApplication {
    static func external(pid: pid_t, name: String) -> Self {
        .init(name: name, bundleIdentifier: "com.example.\(name)", processIdentifier: pid, isTerminated: false)
    }

    static func mousePlus(pid: pid_t, bundleID: String) -> Self {
        .init(name: "MousePlus", bundleIdentifier: bundleID, processIdentifier: pid, isTerminated: false)
    }
}
