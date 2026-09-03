import AppKit
import Foundation

/// A stable, JSON-friendly color representation in the sRGB color space.
struct HUDColor: Codable, Equatable, Hashable, Sendable {
    let red: Double
    let green: Double
    let blue: Double
    let alpha: Double

    init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = Self.bounded(red)
        self.green = Self.bounded(green)
        self.blue = Self.bounded(blue)
        self.alpha = Self.bounded(alpha)
    }

    /// Returns nil when AppKit cannot represent the source color as sRGB.
    init?(nsColor: NSColor) {
        guard let converted = nsColor.usingColorSpace(.sRGB) else { return nil }
        self.init(
            red: Double(converted.redComponent),
            green: Double(converted.greenComponent),
            blue: Double(converted.blueComponent),
            alpha: Double(converted.alphaComponent)
        )
    }

    var nsColor: NSColor {
        NSColor(
            srgbRed: CGFloat(red),
            green: CGFloat(green),
            blue: CGFloat(blue),
            alpha: CGFloat(alpha)
        )
    }

    static let black = HUDColor(red: 0, green: 0, blue: 0)
    static let white = HUDColor(red: 1, green: 1, blue: 1)
    static let clear = HUDColor(red: 0, green: 0, blue: 0, alpha: 0)

    private enum CodingKeys: String, CodingKey { case red, green, blue, alpha }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            red: try container.decode(Double.self, forKey: .red),
            green: try container.decode(Double.self, forKey: .green),
            blue: try container.decode(Double.self, forKey: .blue),
            alpha: try container.decodeIfPresent(Double.self, forKey: .alpha) ?? 1
        )
    }

    private static func bounded(_ component: Double) -> Double {
        guard component.isFinite else { return 0 }
        return min(max(component, 0), 1)
    }
}
