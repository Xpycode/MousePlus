import AppKit
import OSLog

@MainActor
protocol MouseButtonTriggerTapping: AnyObject {
    func start(handler: @escaping (CGEventType, CGEvent) -> Bool) throws
    func reenable()
    func stop()
}

/// An active tap is required: NSEvent global monitors cannot prevent the same
/// forward/back click from also navigating the foreground application.
@MainActor
final class SystemMouseButtonTriggerTap: MouseButtonTriggerTapping {
    private var port: CFMachPort?
    private var source: CFRunLoopSource?
    private var handler: ((CGEventType, CGEvent) -> Bool)?

    func start(handler: @escaping (CGEventType, CGEvent) -> Bool) throws {
        stop()
        self.handler = handler
        let mask = [CGEventType.otherMouseDown, .otherMouseDragged, .otherMouseUp]
            .reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, context in
                guard let context else { return Unmanaged.passUnretained(event) }
                return MainActor.assumeIsolated {
                    let tap = Unmanaged<SystemMouseButtonTriggerTap>
                        .fromOpaque(context).takeUnretainedValue()
                    return tap.handler?(type, event) == true ? nil : Unmanaged.passUnretained(event)
                }
            }, userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            self.handler = nil
            throw NSError(domain: "MousePlus.MouseButtonTriggerTap", code: 1)
        }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        self.port = port
        self.source = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
    }

    func reenable() {
        if let port { CGEvent.tapEnable(tap: port, enable: true) }
    }

    func stop() {
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        if let port {
            CGEvent.tapEnable(tap: port, enable: false)
            CFMachPortInvalidate(port)
        }
        source = nil
        port = nil
        handler = nil
    }
}

/// Owns the configured auxiliary button's down/drag/up sequence. Left/right and
/// unrelated auxiliary buttons pass through. Button 2 is the middle button.
@MainActor
final class MouseButtonTriggerMonitor {
    private let tap: any MouseButtonTriggerTapping
    private var buttonNumber = 0
    private var isPressed = false
    private var onDown: ((CGPoint) -> Void)?
    private var onDragged: ((CGPoint) -> Void)?
    private var onUp: ((CGPoint) -> Void)?

    init(tap: (any MouseButtonTriggerTapping)? = nil) {
        self.tap = tap ?? SystemMouseButtonTriggerTap()
    }

    func start(
        buttonNumber: Int,
        onDown: @escaping (CGPoint) -> Void,
        onDragged: @escaping (CGPoint) -> Void,
        onUp: @escaping (CGPoint) -> Void
    ) {
        stop()
        guard buttonNumber >= 2 else { return }
        self.buttonNumber = buttonNumber
        self.onDown = onDown
        self.onDragged = onDragged
        self.onUp = onUp
        do {
            try tap.start { [weak self] type, event in
                self?.handle(type: type, event: event) ?? false
            }
        } catch {
            // Do not fall back to a passive monitor that performs two actions
            // for one press. Permission restoration restarts the trigger service.
            Logger(subsystem: "com.xpycode.MousePlus", category: "MouseTrigger")
                .error("Could not install consuming mouse trigger tap: \(error.localizedDescription)")
            stop()
        }
    }

    func stop() {
        tap.stop()
        isPressed = false
        onDown = nil
        onDragged = nil
        onUp = nil
    }

    private func handle(type: CGEventType, event: CGEvent) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            tap.reenable()
            return false
        }
        guard event.getIntegerValueField(.mouseEventButtonNumber) == buttonNumber else { return false }
        // Let the Settings recorder see an existing binding without opening the
        // HUD. Still balance a press that we already consumed before recording.
        guard isPressed || !TriggerRecorderService.isRecordingMouseButton else { return false }
        let location = CGPoint(
            x: event.location.x,
            y: (NSScreen.screens.first?.frame.maxY ?? 0) - event.location.y
        )
        switch type {
        case .otherMouseDown:
            guard !isPressed else { return true }
            isPressed = true
            onDown?(location)
            return true
        case .otherMouseDragged where isPressed:
            onDragged?(location)
            return true
        case .otherMouseUp where isPressed:
            isPressed = false
            onUp?(location)
            return true
        default:
            return false
        }
    }
}
