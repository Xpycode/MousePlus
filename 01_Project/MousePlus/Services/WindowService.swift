import AppKit
import ApplicationServices

/// Snapshot of screen geometry, captured on the main actor and handed to the
/// `WindowService` as plain `Sendable` values (HUD_ACTIONS_PLAN §B "Threading").
///
/// `NSScreen` is main-thread-affine; the service never touches it. All rects are in
/// AppKit coordinates (bottom-left origin, `+y` up). `primaryMaxY` is the y-flip
/// pivot used to convert into Accessibility (top-left) space — it is the **primary**
/// screen's `frame.maxY` (`NSScreen.screens[0]`), not the target screen's.
struct ScreenLayout: Sendable {
    struct Screen: Sendable {
        let frame: CGRect          // full frame (for "which screen is the window on")
        let visibleFrame: CGRect   // menu bar / Dock excluded (snap target area)
    }

    let screens: [Screen]
    let primaryMaxY: CGFloat
    let cursorPoint: CGPoint       // NSEvent.mouseLocation, AppKit coords (tie-break)

    @MainActor
    static func capture() -> ScreenLayout {
        let screens = NSScreen.screens.map {
            Screen(frame: $0.frame, visibleFrame: $0.visibleFrame)
        }
        let primaryMaxY = NSScreen.screens.first?.frame.maxY ?? 0
        return ScreenLayout(screens: screens,
                            primaryMaxY: primaryMaxY,
                            cursorPoint: NSEvent.mouseLocation)
    }
}

enum WindowServiceError: LocalizedError {
    case notTrusted
    case noFocusedWindow
    case noScreen

    var errorDescription: String? {
        switch self {
        case .notTrusted:     "Accessibility permission is required to move windows."
        case .noFocusedWindow: "The frontmost app has no movable window."
        case .noScreen:        "No screen available to snap to."
        }
    }
}

/// Moves/resizes the frontmost app's focused window into a `SnapZone` via the
/// Accessibility API (HUD Feature B). AppKit's window coordinator requires AX
/// window mutations on the main thread, so the service is main-actor isolated.
/// The HUD is dismissed before execution, avoiding interaction jank while the
/// synchronous AX writes complete.
///
/// Uses the two Rectangle hacks verbatim (`HUD_ACTIONS_PLAN.md` §B):
///   1. Toggle the app's `AXEnhancedUserInterface` off around the move (some
///      Electron/Catalyst apps mis-animate or ignore moves while it is on),
///      restoring it after.
///   2. Set order = **size → position → size**: macOS clamps to the display and
///      min-size, so shrink first (unblocks the move), then position, then size
///      again to correct any min-size clamping.
@MainActor
final class WindowService {

    nonisolated init() {}

    func snap(_ zone: SnapZone, pid: pid_t, layout: ScreenLayout) throws {
        guard AXIsProcessTrusted() else { throw WindowServiceError.notTrusted }
        guard !layout.screens.isEmpty else { throw WindowServiceError.noScreen }

        let app = AXUIElementCreateApplication(pid)
        let window = try focusedWindow(of: app)

        // Current window frame (AX coords) → AppKit coords, to pick the target screen.
        guard let axPos = position(of: window), let axSize = size(of: window) else {
            throw WindowServiceError.noFocusedWindow
        }
        let currentAppKit = appKitRect(fromAXOrigin: axPos, size: axSize, primaryMaxY: layout.primaryMaxY)
        let screen = targetScreen(for: currentAppKit, layout: layout)

        // Destination rect (AppKit coords) → AX coords.
        let targetAppKit = zone.rect(in: screen.visibleFrame)
        let targetAX = axRect(fromAppKit: targetAppKit, primaryMaxY: layout.primaryMaxY)

        // --- Apply, wrapped in the AXEnhancedUserInterface toggle. ---
        let hadEnhancedUI = enhancedUserInterface(of: app)
        if hadEnhancedUI == true { setEnhancedUserInterface(of: app, false) }
        defer { if hadEnhancedUI == true { setEnhancedUserInterface(of: app, true) } }

        // size → position → size.
        setSize(of: window, targetAX.size)
        setPosition(of: window, targetAX.origin)
        setSize(of: window, targetAX.size)
    }

    // MARK: - Window lookup

    private func focusedWindow(of app: AXUIElement) throws -> AXUIElement {
        if let focused = copyElement(app, kAXFocusedWindowAttribute) {
            return focused
        }
        // Fallback: first window in the app's window list.
        var ref: CFTypeRef?
        if AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &ref) == .success,
           let windows = ref as? [AXUIElement], let first = windows.first {
            return first
        }
        throw WindowServiceError.noFocusedWindow
    }

    // MARK: - Target screen

    /// Pick the screen the window mostly overlaps; tie-break to the cursor's screen
    /// (the ring is pointer-anchored), then the primary screen.
    private func targetScreen(for windowFrame: CGRect, layout: ScreenLayout) -> ScreenLayout.Screen {
        let best = layout.screens.max { a, b in
            overlapArea(windowFrame, a.frame) < overlapArea(windowFrame, b.frame)
        }
        if let best, overlapArea(windowFrame, best.frame) > 0 { return best }
        if let cursorScreen = layout.screens.first(where: { $0.frame.contains(layout.cursorPoint) }) {
            return cursorScreen
        }
        return layout.screens[0]
    }

    private func overlapArea(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let r = a.intersection(b)
        return r.isNull ? 0 : r.width * r.height
    }

    // MARK: - Coordinate flips (the #1 bug source — see §B)

    /// AX (top-left origin) origin+size → AppKit (bottom-left origin) rect,
    /// flipped about the **primary** screen's `frame.maxY`.
    private func appKitRect(fromAXOrigin origin: CGPoint, size: CGSize, primaryMaxY: CGFloat) -> CGRect {
        CGRect(x: origin.x,
               y: primaryMaxY - (origin.y + size.height),
               width: size.width,
               height: size.height)
    }

    /// AppKit rect → AX origin+size, flipped about the primary screen's `frame.maxY`.
    private func axRect(fromAppKit rect: CGRect, primaryMaxY: CGFloat) -> CGRect {
        CGRect(x: rect.origin.x,
               y: primaryMaxY - rect.maxY,
               width: rect.width,
               height: rect.height)
    }

    // MARK: - AX attribute helpers

    private func copyElement(_ element: AXUIElement, _ attr: String) -> AXUIElement? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attr as CFString, &ref) == .success,
              let value = ref else { return nil }
        guard CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    private func position(of element: AXUIElement) -> CGPoint? {
        axValue(element, kAXPositionAttribute, .cgPoint, default: CGPoint.zero)
    }

    private func size(of element: AXUIElement) -> CGSize? {
        axValue(element, kAXSizeAttribute, .cgSize, default: CGSize.zero)
    }

    private func axValue<T>(_ element: AXUIElement, _ attr: String, _ type: AXValueType, default fallback: T) -> T? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attr as CFString, &ref) == .success,
              let value = ref, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var out = fallback
        guard AXValueGetValue(value as! AXValue, type, &out) else { return nil }
        return out
    }

    private func setPosition(of element: AXUIElement, _ point: CGPoint) {
        var p = point
        guard let value = AXValueCreate(.cgPoint, &p) else { return }
        AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, value)
    }

    private func setSize(of element: AXUIElement, _ size: CGSize) {
        var s = size
        guard let value = AXValueCreate(.cgSize, &s) else { return }
        AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, value)
    }

    private func enhancedUserInterface(of app: AXUIElement) -> Bool? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, "AXEnhancedUserInterface" as CFString, &ref) == .success,
              let value = ref else { return nil }
        return (value as? NSNumber)?.boolValue
    }

    private func setEnhancedUserInterface(of app: AXUIElement, _ on: Bool) {
        AXUIElementSetAttributeValue(app, "AXEnhancedUserInterface" as CFString, (on ? kCFBooleanTrue : kCFBooleanFalse))
    }
}
