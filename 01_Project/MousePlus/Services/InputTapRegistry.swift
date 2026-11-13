import CoreGraphics
import Foundation
import OSLog

/// Why macOS disabled an event tap. A disabled tap stays disabled until its
/// owner calls `resume()`; nothing re-enables it implicitly.
enum InputTapDisableReason: Equatable, Sendable {
    /// kCGEventTapDisabledByTimeout
    case timeout
    /// kCGEventTapDisabledByUserInput
    case userInput

    init?(eventType: CGEventType) {
        switch eventType {
        case .tapDisabledByTimeout: self = .timeout
        case .tapDisabledByUserInput: self = .userInput
        default: return nil
        }
    }
}

/// One system event tap: its mach port and any run-loop source attached to it.
@MainActor
protocol InputTapHandle: AnyObject {
    var isEnabled: Bool { get }
    func setEnabled(_ enabled: Bool)
    /// Removes the run-loop source and invalidates the port. Idempotent.
    func invalidate()
}

/// Production handle over a `CFMachPort` created by `CGEvent.tapCreate`.
@MainActor
final class SystemEventTapHandle: InputTapHandle {
    private var port: CFMachPort?
    private var source: CFRunLoopSource?

    init(port: CFMachPort) {
        self.port = port
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        self.source = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
    }

    var isEnabled: Bool {
        guard let port else { return false }
        return CGEvent.tapIsEnabled(tap: port)
    }

    func setEnabled(_ enabled: Bool) {
        guard let port else { return }
        CGEvent.tapEnable(tap: port, enable: enabled)
    }

    func invalidate() {
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        if let port {
            CGEvent.tapEnable(tap: port, enable: false)
            // Disabling leaves the connection registered with WindowServer;
            // invalidating releases it.
            CFMachPortInvalidate(port)
        }
        source = nil
        port = nil
    }

    /// Creates a session-level, head-insert, active tap. Returns nil when
    /// macOS refuses (no permission) or when the registry is sealed after a
    /// trust loss: a fresh tap in an untrusted process can hang system input.
    static func create(
        mask: CGEventMask,
        callback: @escaping CGEventTapCallBack,
        userInfo: UnsafeMutableRawPointer,
        registry: InputTapRegistry? = nil
    ) -> (any InputTapHandle)? {
        let registry = registry ?? .shared
        guard !registry.isSealed else {
            InputTapRegistry.log.error("tap creation refused: registry sealed")
            return nil
        }
        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: mask, callback: callback, userInfo: userInfo
        ) else { return nil }
        return SystemEventTapHandle(port: port)
    }
}

typealias InputTapFactory = @MainActor (
    CGEventMask, @escaping CGEventTapCallBack, UnsafeMutableRawPointer
) -> (any InputTapHandle)?

/// Tracks every live system event tap so they can all be destroyed in one
/// synchronous call. A tap that outlives lost Accessibility / Input Monitoring
/// trust can hang system-wide input, so teardown must not depend on owners.
@MainActor
final class InputTapRegistry {
    static let shared = InputTapRegistry()
    fileprivate static let log = Logger(subsystem: "com.xpycode.MousePlus", category: "RuntimeSafety")

    private var handles: [ObjectIdentifier: any InputTapHandle] = [:]

    /// Set by `seal()` / `teardownAll()` and never cleared: after a trust loss
    /// this process must not create or keep another system tap.
    private(set) var isSealed = false

    var registeredCount: Int { handles.count }
    var enabledCount: Int { handles.values.filter(\.isEnabled).count }

    func seal() {
        isSealed = true
    }

    func register(_ handle: any InputTapHandle) {
        guard !isSealed else {
            // Defense in depth for factories that bypass `SystemEventTapHandle.create`.
            Self.log.error("tap registration refused: registry sealed; invalidating handle")
            handle.setEnabled(false)
            handle.invalidate()
            return
        }
        handles[ObjectIdentifier(handle)] = handle
    }

    func unregister(_ handle: any InputTapHandle) {
        handles[ObjectIdentifier(handle)] = nil
    }

    /// Seals the registry, then disables and invalidates every registered tap
    /// and forgets them. Owners that later call `stop()` find their handle
    /// already invalidated.
    func teardownAll() {
        isSealed = true
        let all = Array(handles.values)
        handles.removeAll()
        for handle in all {
            handle.setEnabled(false)
            handle.invalidate()
        }
    }
}
