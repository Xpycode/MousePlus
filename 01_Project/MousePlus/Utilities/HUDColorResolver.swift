import Foundation

enum HUDColorResolver {
    static let iconContrastThreshold = 3.0
    static let smallLabelContrastThreshold = 4.5

    struct Overrides: Equatable, Sendable {
        var wedge: HUDColor?
        var icon: HUDColor?

        init(wedge: HUDColor? = nil, icon: HUDColor? = nil) {
            self.wedge = wedge
            self.icon = icon
        }
    }

    struct Resolution: Equatable, Sendable {
        let requestedWedge: HUDColor
        let renderedWedge: HUDColor
        let requestedIcon: HUDColor
        let renderedIcon: HUDColor
        let requestedLabel: HUDColor
        let renderedLabel: HUDColor
    }

    /// Resolves item -> ring -> menu -> application without mutating the requested values.
    static func resolve(
        application: Overrides,
        menu: Overrides = Overrides(),
        ring: Overrides = Overrides(),
        item: Overrides = Overrides(),
        label: HUDColor? = nil,
        backdrop: HUDColor = .clear
    ) -> Resolution {
        // Application colors are required at the rendering boundary. These defaults
        // are defensive and deterministic for callers assembling partial test data.
        let requestedWedge = item.wedge ?? ring.wedge ?? menu.wedge ?? application.wedge ?? .clear
        let requestedIcon = item.icon ?? ring.icon ?? menu.icon ?? application.icon ?? .white
        let requestedLabel = label ?? requestedIcon
        let renderedWedge = composite(requestedWedge, over: backdrop)

        return Resolution(
            requestedWedge: requestedWedge,
            renderedWedge: renderedWedge,
            requestedIcon: requestedIcon,
            renderedIcon: accessibleForeground(
                requestedIcon, against: renderedWedge, threshold: iconContrastThreshold
            ),
            requestedLabel: requestedLabel,
            renderedLabel: accessibleForeground(
                requestedLabel, against: renderedWedge, threshold: smallLabelContrastThreshold
            )
        )
    }

    /// WCAG 2.2 relative luminance for an sRGB color. Alpha is intentionally handled
    /// by `composite(_:over:)`, because luminance itself is defined for RGB channels.
    static func relativeLuminance(of color: HUDColor) -> Double {
        func linear(_ channel: Double) -> Double {
            channel <= 0.04045
                ? channel / 12.92
                : pow((channel + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(color.red)
            + 0.7152 * linear(color.green)
            + 0.0722 * linear(color.blue)
    }

    static func contrastRatio(_ first: HUDColor, _ second: HUDColor) -> Double {
        let firstLuminance = relativeLuminance(of: first)
        let secondLuminance = relativeLuminance(of: second)
        let lighter = max(firstLuminance, secondLuminance)
        let darker = min(firstLuminance, secondLuminance)
        return (lighter + 0.05) / (darker + 0.05)
    }

    /// Source-over alpha composition in sRGB component space.
    static func composite(_ foreground: HUDColor, over background: HUDColor) -> HUDColor {
        let outputAlpha = foreground.alpha + background.alpha * (1 - foreground.alpha)
        guard outputAlpha > 0 else { return .clear }
        func channel(_ foregroundChannel: Double, _ backgroundChannel: Double) -> Double {
            (foregroundChannel * foreground.alpha
                + backgroundChannel * background.alpha * (1 - foreground.alpha)) / outputAlpha
        }
        return HUDColor(
            red: channel(foreground.red, background.red),
            green: channel(foreground.green, background.green),
            blue: channel(foreground.blue, background.blue),
            alpha: outputAlpha
        )
    }

    static func accessibleForeground(
        _ requested: HUDColor,
        against background: HUDColor,
        threshold: Double
    ) -> HUDColor {
        let visibleRequested = composite(requested, over: background)
        guard contrastRatio(visibleRequested, background) < threshold else { return requested }

        let blackRatio = contrastRatio(.black, background)
        let whiteRatio = contrastRatio(.white, background)
        // Black wins an exact tie, making the fallback stable across platforms.
        return blackRatio >= whiteRatio ? .black : .white
    }
}
