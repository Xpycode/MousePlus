import AppKit
import SwiftUI

extension HUDSummonMotionStyle {
    var displayName: String {
        switch self {
        case .off: "Off"
        case .fade: "Fade"
        case .circularSweep: "Circular Sweep"
        case .irisReveal: "Iris Reveal"
        case .bloom: "Bloom"
        case .staggeredSegments: "Staggered Segments"
        }
    }

    var isSpatial: Bool {
        switch self {
        case .circularSweep, .irisReveal, .bloom, .staggeredSegments: true
        case .off, .fade: false
        }
    }
}

struct HUDOpeningPreviewPresentation: Equatable {
    let style: HUDSummonMotionStyle
    let motionEnabled: Bool
    let isLoaded: Bool
    let reduceMotion: Bool

    var canReplay: Bool {
        isLoaded && motionEnabled && style != .off
    }

    var selectedStyleTitle: String { style.displayName }

    var effectiveStyleTitle: String {
        guard motionEnabled, style != .off else { return HUDSummonMotionStyle.off.displayName }
        return reduceMotion && style.isSpatial
            ? HUDSummonMotionStyle.fade.displayName
            : style.displayName
    }

    var caption: String {
        guard isLoaded else { return "Preview unavailable" }
        if reduceMotion && motionEnabled && style.isSpatial {
            return "Reduce Motion preview: \(effectiveStyleTitle)"
        }
        return "Preview: \(effectiveStyleTitle)"
    }

    var accessibilityValue: String {
        if selectedStyleTitle == effectiveStyleTitle {
            return caption
        }
        return "Selected \(selectedStyleTitle). \(caption)"
    }
}

/// Noninteractive Settings surface that mirrors the saved top-level layout but
/// owns a private view model. It shares the production renderer without adding
/// action services, editable selection, branch expansion, or persistence.
@MainActor
struct HUDOpeningPreview: View {
    let configuration: Configuration
    let replayID: Int
    let playbackEnabled: Bool
    let presentation: HUDOpeningPreviewPresentation

    @State private var model = RingViewModel()

    private let canvasSide: CGFloat = 240
    private let bloomHeadroom: CGFloat = 1.015

    var body: some View {
        let logicalSide = model.radii.r3 * 2
        let visibleRingSide = model.radii.r2 * 2
        let scale = min(1, canvasSide / (visibleRingSide * bloomHeadroom))

        ZStack {
            RingMenuView(
                viewModel: model,
                interactionEnabled: false,
                presentationMode: .openingPreview,
                openingPlaybackEnabled: playbackEnabled,
                openingMotionConfiguration: configuration.appearance.motion,
                openingReplayID: replayID,
                commitsOnPointerRelease: false,
                accessibilityIdentifierPrefix: "appearance.motion.preview.wedge",
                exposesCenterSettings: false,
                exposesWedgeAccessibility: false
            )
            .allowsHitTesting(false)
            .frame(width: logicalSide, height: logicalSide)
            .scaleEffect(scale)
        }
        .frame(width: canvasSide, height: canvasSide)
        .clipped()
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.12)))
        .overlay {
            HUDOpeningPreviewAccessibilityElement(value: presentation.accessibilityValue)
                .allowsHitTesting(false)
        }
        .onChange(of: previewContent, initial: true) { _, content in
            model.load(from: content.configuration)
        }
    }

    private var previewContent: HUDOpeningPreviewContent {
        HUDOpeningPreviewContent(configuration)
    }
}

/// A concrete AppKit image element gives VoiceOver one stable preview node;
/// the shared renderer beneath it deliberately exposes no wedge actions.
private struct HUDOpeningPreviewAccessibilityElement: NSViewRepresentable {
    let value: String

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.setAccessibilityElement(true)
        view.setAccessibilityRole(.image)
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        view.setAccessibilityLabel("Opening animation preview")
        view.setAccessibilityValue(value)
        view.setAccessibilityIdentifier("appearance.motion.openingPreview")
    }
}

/// Excludes motion settings so style/speed edits can be handled by the opening
/// lifecycle itself rather than rebuilding the preview model and settling a
/// replay requested in the same native-control action.
private struct HUDOpeningPreviewContent: Equatable {
    let inner: [RingMenuItem]
    let middle: [RingMenuItem]
    let appearance: AppearanceConfig
    let hudCustomization: HUDCustomization

    init(_ configuration: Configuration) {
        inner = configuration.inner
        middle = configuration.middle
        var normalizedAppearance = configuration.appearance
        normalizedAppearance.motion = .default
        appearance = normalizedAppearance
        hudCustomization = configuration.hudCustomization
    }

    var configuration: Configuration {
        Configuration(
            inner: inner,
            middle: middle,
            appearance: appearance,
            hudCustomization: hudCustomization
        )
    }
}
