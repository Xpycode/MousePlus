import AppKit

/// One captured input event, in a UI-friendly shape.
struct CapturedInput: Identifiable, Equatable {
    let id = UUID()
    let timestamp: Date
    let kind: Kind

    enum Kind: Equatable {
        case keyDown(keyCode: UInt16, characters: String?, modifiers: UInt)
        case keyUp(keyCode: UInt16, modifiers: UInt)
        case flagsChanged(modifiers: UInt)
        case mouseDown(buttonNumber: Int)
        case mouseUp(buttonNumber: Int)
    }

    var primary: String {
        switch kind {
        case .keyDown(let kc, let chars, _):
            return "Key \(kc)\(chars.flatMap { $0.isEmpty ? nil : " (\($0))" } ?? "") ▼"
        case .keyUp(let kc, _):
            return "Key \(kc) ▲"
        case .flagsChanged:
            return "Modifier change"
        case .mouseDown(let n):
            return "Mouse Button \(n) ▼"
        case .mouseUp(let n):
            return "Mouse Button \(n) ▲"
        }
    }

    var modifiers: String? {
        let raw: UInt
        switch kind {
        case .keyDown(_, _, let m), .keyUp(_, let m), .flagsChanged(let m): raw = m
        case .mouseDown, .mouseUp: return nil
        }
        let m = NSEvent.ModifierFlags(rawValue: raw)
        var parts: [String] = []
        if m.contains(.control)  { parts.append("⌃") }
        if m.contains(.option)   { parts.append("⌥") }
        if m.contains(.shift)    { parts.append("⇧") }
        if m.contains(.command)  { parts.append("⌘") }
        if m.contains(.capsLock) { parts.append("⇪") }
        return parts.isEmpty ? nil : parts.joined()
    }
}

/// Captures all keyboard and mouse events while running. Exposes the most
/// recent capture and a bounded history for live diagnostics. Reusable as the
/// foundation for W4's "press the trigger you want" Settings recorder.
@MainActor
@Observable
final class InputRecorderService {
    private(set) var lastInput: CapturedInput?
    private(set) var history: [CapturedInput] = []
    private let historyLimit = 12

    private var globalKey: Any?
    private var localKey: Any?
    private var globalMouse: Any?
    private var localMouse: Any?

    func start() {
        stop()

        let keyMask: NSEvent.EventTypeMask = [.keyDown, .keyUp, .flagsChanged]
        globalKey = NSEvent.addGlobalMonitorForEvents(matching: keyMask) { [weak self] e in
            Task { @MainActor in self?.record(e) }
        }
        localKey = NSEvent.addLocalMonitorForEvents(matching: keyMask) { [weak self] e in
            Task { @MainActor in self?.record(e) }
            return e
        }

        let mouseMask: NSEvent.EventTypeMask = [
            .leftMouseDown, .leftMouseUp,
            .rightMouseDown, .rightMouseUp,
            .otherMouseDown, .otherMouseUp
        ]
        globalMouse = NSEvent.addGlobalMonitorForEvents(matching: mouseMask) { [weak self] e in
            Task { @MainActor in self?.record(e) }
        }
        localMouse = NSEvent.addLocalMonitorForEvents(matching: mouseMask) { [weak self] e in
            Task { @MainActor in self?.record(e) }
            return e
        }
    }

    func stop() {
        for m in [globalKey, localKey, globalMouse, localMouse] {
            if let m { NSEvent.removeMonitor(m) }
        }
        globalKey = nil
        localKey = nil
        globalMouse = nil
        localMouse = nil
    }

    func clear() {
        lastInput = nil
        history.removeAll()
    }

    private func record(_ event: NSEvent) {
        let kind: CapturedInput.Kind
        switch event.type {
        case .keyDown:
            kind = .keyDown(
                keyCode: event.keyCode,
                characters: event.charactersIgnoringModifiers,
                modifiers: event.modifierFlags.rawValue
            )
        case .keyUp:
            kind = .keyUp(keyCode: event.keyCode, modifiers: event.modifierFlags.rawValue)
        case .flagsChanged:
            kind = .flagsChanged(modifiers: event.modifierFlags.rawValue)
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            kind = .mouseDown(buttonNumber: event.buttonNumber)
        case .leftMouseUp, .rightMouseUp, .otherMouseUp:
            kind = .mouseUp(buttonNumber: event.buttonNumber)
        default:
            return
        }

        let captured = CapturedInput(timestamp: Date(), kind: kind)
        lastInput = captured
        history.insert(captured, at: 0)
        if history.count > historyLimit {
            history = Array(history.prefix(historyLimit))
        }
    }
}
