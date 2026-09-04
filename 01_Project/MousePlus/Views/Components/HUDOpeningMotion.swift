import SwiftUI

/// Owns the single normalized clock for one menu entrance or Settings replay.
/// Removing this view cancels SwiftUI's presentation transaction; there are no
/// delayed callbacks or per-wedge tasks that can survive HUD teardown.
struct HUDOpeningMotion<Content: View>: View {
    let request: HUDOpeningMotionRequest
    let settleID: Int
    let deadZoneRadius: CGFloat
    let revealRadius: CGFloat
    @ViewBuilder let content: (HUDOpeningMotionFrame) -> Content

    @State private var progress: CGFloat

    init(
        request: HUDOpeningMotionRequest,
        settleID: Int,
        deadZoneRadius: CGFloat = 0,
        revealRadius: CGFloat = 0,
        @ViewBuilder content: @escaping (HUDOpeningMotionFrame) -> Content
    ) {
        self.request = request
        self.settleID = settleID
        self.deadZoneRadius = deadZoneRadius
        self.revealRadius = revealRadius
        self.content = content
        _progress = State(initialValue: request.shouldAnimate ? 0 : 1)
    }

    var body: some View {
        content(HUDOpeningMotionFrame.resolve(
            descriptor: request.descriptor,
            progress: progress,
            deadZoneRadius: deadZoneRadius,
            revealRadius: revealRadius
        ))
        .onAppear {
            apply(HUDOpeningMotionTransition.resolve(previous: nil, current: request))
        }
        .onChange(of: request) { previous, current in
            apply(HUDOpeningMotionTransition.resolve(previous: previous, current: current))
        }
        .onChange(of: settleID) { _, _ in settle() }
    }

    private var playbackAnimation: Animation? {
        switch request.descriptor.effect {
        case .fade:
            return .easeOut(duration: request.descriptor.duration)
        case .circularSweep, .irisReveal, .bloom, .staggeredSegments:
            // These effects derive their own easing from linear normalized time.
            return .linear(duration: request.descriptor.duration)
        case .instant, .emphasis, .radialReveal:
            return nil
        }
    }

    private func apply(_ transition: HUDOpeningMotionTransition) {
        switch transition {
        case .unchanged:
            break
        case .settle:
            settle()
        case .replay:
            var reset = Transaction()
            reset.disablesAnimations = true
            withTransaction(reset) { progress = 0 }
            withAnimation(playbackAnimation) { progress = 1 }
        }
    }

    private func settle() {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { progress = 1 }
    }
}

/// Applies opening-only visual transforms to artwork. Callers keep native
/// controls, pointer surfaces, and accessibility targets outside this view.
struct HUDOpeningArtwork<Content: View>: View {
    let frame: HUDOpeningMotionFrame
    let size: CGFloat
    @ViewBuilder let content: () -> Content

    var body: some View {
        switch frame.mask {
        case .none:
            renderedContent
        case .circularSweep(let progress):
            renderedContent
                .mask(HUDCircularSweepMask(progress: progress))
        case .iris(let radius):
            renderedContent
                .mask(Circle().frame(width: radius * 2, height: radius * 2))
        }
    }

    private var renderedContent: some View {
        content()
            .frame(width: size, height: size)
            .scaleEffect(frame.artworkScale, anchor: .center)
            .opacity(frame.artworkOpacity)
    }
}

/// Sector mask in the renderer's +y-down coordinate system: zero is empty,
/// then the path advances clockwise from 12 o'clock. Completion removes this
/// mask entirely via `HUDOpeningMotionFrame` instead of drawing a 360° arc.
struct HUDCircularSweepMask: Shape {
    var progress: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let progress = min(max(progress, 0), 1)
        guard progress > 0 else { return Path() }
        guard progress < 1 else { return Path(ellipseIn: rect) }

        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2 + 2
        var path = Path()
        path.move(to: center)
        path.addLine(to: CGPoint(x: center.x, y: center.y - radius))
        path.addArc(
            center: center,
            radius: radius,
            startAngle: .degrees(-90),
            endAngle: .degrees(-90 + 360 * Double(progress)),
            clockwise: false
        )
        path.closeSubpath()
        return path
    }
}
