import SwiftUI

struct HUDOpeningPlaybackSeed: Equatable {
    let progress: CGFloat
    let isPlaybackPending: Bool
    let isConcealed: Bool

    init(request: HUDOpeningMotionRequest) {
        progress = request.shouldAnimate ? 0 : 1
        isPlaybackPending = request.shouldAnimate && !request.isAwaitingMount
        isConcealed = request.shouldAnimate && request.isAwaitingMount
    }
}

/// Owns the single normalized clock for one menu entrance or Settings replay.
/// Removing this view cancels the one view-scoped playback task; there are no
/// per-wedge tasks that can survive HUD teardown.
struct HUDOpeningMotion<Content: View>: View {
    let request: HUDOpeningMotionRequest
    let settleID: Int
    let deadZoneRadius: CGFloat
    let revealRadius: CGFloat
    @ViewBuilder let content: (HUDOpeningMotionFrame) -> Content

    @State private var progress: CGFloat
    @State private var playbackGeneration = 0
    @State private var playbackPending = false
    @State private var isConcealed: Bool
    @State private var mountWasInterrupted = false

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
        let seed = HUDOpeningPlaybackSeed(request: request)
        _progress = State(initialValue: seed.progress)
        // Runtime mounts concealed with no clock running. Only the guarded
        // post-mount request arms playback; previews can still start directly.
        _playbackPending = State(initialValue: seed.isPlaybackPending)
        _isConcealed = State(initialValue: seed.isConcealed)
    }

    var body: some View {
        HUDOpeningMotionContent(
            descriptor: request.descriptor,
            progress: progress,
            deadZoneRadius: deadZoneRadius,
            revealRadius: revealRadius,
            isConcealed: isConcealed,
            content: content
        )
        .onChange(of: request) { previous, current in
            // Aiming or a preference change can settle the HUD before its
            // mount callback arrives. That callback must not hide it again.
            if previous.isAwaitingMount, mountWasInterrupted, !current.isAwaitingMount {
                settle()
                return
            }
            apply(HUDOpeningMotionTransition.resolve(previous: previous, current: current))
        }
        .onChange(of: settleID) { _, _ in settle() }
        .task(id: playbackGeneration) {
            guard playbackPending else { return }

            // Let SwiftUI commit the reset frame before starting the animation.
            // Without this boundary, the 0 -> 1 writes can be coalesced and every
            // opening style appears to be the same already-settled ring.
            do {
                try await Task.sleep(for: .milliseconds(16))
            } catch {
                return
            }
            guard !Task.isCancelled, playbackPending else { return }

            playbackPending = false
            withAnimation(playbackAnimation) { progress = 1 }
        }
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
        case .awaitMount:
            playbackPending = false
            playbackGeneration &+= 1
            mountWasInterrupted = false
            var reset = Transaction()
            reset.disablesAnimations = true
            withTransaction(reset) {
                progress = 0
                isConcealed = true
            }
        case .settle:
            settle()
        case .replay:
            playbackPending = true
            playbackGeneration &+= 1
            var reset = Transaction()
            reset.disablesAnimations = true
            withTransaction(reset) {
                progress = 0
                isConcealed = false
            }
        }
    }

    private func settle() {
        playbackPending = false
        playbackGeneration &+= 1
        mountWasInterrupted = true
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            progress = 1
            isConcealed = false
        }
    }
}

/// Makes normalized opening progress itself animatable. Resolving the frame in
/// the parent body only evaluates the two endpoint frames; SwiftUI then blends
/// their modifiers, which causes masks to disappear immediately and makes all
/// segment opacities animate in lockstep. This view resolves every interpolated
/// progress value so each opening style retains its own cadence and silhouette.
struct HUDOpeningMotionContent<Content: View>: View, Animatable {
    let descriptor: HUDMotionPresentationDescriptor
    var progress: CGFloat
    let deadZoneRadius: CGFloat
    let revealRadius: CGFloat
    var isConcealed = false
    let content: (HUDOpeningMotionFrame) -> Content

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    var resolvedFrame: HUDOpeningMotionFrame {
        HUDOpeningMotionFrame.resolve(
            descriptor: descriptor,
            progress: progress,
            deadZoneRadius: deadZoneRadius,
            revealRadius: revealRadius,
            isConcealed: isConcealed
        )
    }

    var body: some View {
        content(resolvedFrame)
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
