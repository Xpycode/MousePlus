import CoreGraphics
import Foundation

/// A target zone for window snapping (HUD Feature B, `HUD_ACTIONS_PLAN.md`).
///
/// Stored as the `actionData` of a `.windowSnap` `RingMenuItem` (the raw string).
/// `rect(in:)` returns the destination rect **in AppKit coordinates** (bottom-left
/// origin, `+y` up) for a given screen `visibleFrame` (menu bar / Dock already
/// excluded). `WindowService` flips it into Accessibility (top-left) coordinates
/// before applying it.
enum SnapZone: String, Codable, CaseIterable, Sendable {
    // Halves (cardinals)
    case left, right, top, bottom
    // Corners (diagonals)
    case topLeft, topRight, bottomLeft, bottomRight
    // Whole-screen / center
    case maximize, center

    /// Destination rect within `vf` (a screen's `visibleFrame`, AppKit coords).
    ///
    /// AppKit `+y` is up, so the "top" half is the **upper** half (`y = vf.midY`)
    /// and "bottom" the lower half (`y = vf.minY`).
    func rect(in vf: CGRect) -> CGRect {
        let halfW = vf.width / 2
        let halfH = vf.height / 2
        switch self {
        case .left:        return CGRect(x: vf.minX, y: vf.minY, width: halfW, height: vf.height)
        case .right:       return CGRect(x: vf.midX, y: vf.minY, width: halfW, height: vf.height)
        case .top:         return CGRect(x: vf.minX, y: vf.midY, width: vf.width, height: halfH)
        case .bottom:      return CGRect(x: vf.minX, y: vf.minY, width: vf.width, height: halfH)
        case .topLeft:     return CGRect(x: vf.minX, y: vf.midY, width: halfW, height: halfH)
        case .topRight:    return CGRect(x: vf.midX, y: vf.midY, width: halfW, height: halfH)
        case .bottomLeft:  return CGRect(x: vf.minX, y: vf.minY, width: halfW, height: halfH)
        case .bottomRight: return CGRect(x: vf.midX, y: vf.minY, width: halfW, height: halfH)
        case .maximize:    return vf
        case .center:
            let w = vf.width * 0.6
            let h = vf.height * 0.6
            return CGRect(x: vf.midX - w / 2, y: vf.midY - h / 2, width: w, height: h)
        }
    }

    var displayName: String {
        switch self {
        case .left: "Left"
        case .right: "Right"
        case .top: "Top"
        case .bottom: "Bottom"
        case .topLeft: "Top Left"
        case .topRight: "Top Right"
        case .bottomLeft: "Bottom Left"
        case .bottomRight: "Bottom Right"
        case .maximize: "Maximize"
        case .center: "Center"
        }
    }

    var systemImage: String {
        switch self {
        case .left: "rectangle.lefthalf.filled"
        case .right: "rectangle.righthalf.filled"
        case .top: "rectangle.tophalf.filled"
        case .bottom: "rectangle.bottomhalf.filled"
        case .topLeft: "arrow.up.left"
        case .topRight: "arrow.up.right"
        case .bottomLeft: "arrow.down.left"
        case .bottomRight: "arrow.down.right"
        case .maximize: "arrow.up.left.and.arrow.down.right"
        case .center: "rectangle.center.inset.filled"
        }
    }
}
