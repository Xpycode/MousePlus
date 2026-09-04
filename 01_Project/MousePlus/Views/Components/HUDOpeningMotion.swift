import SwiftUI

/// Owns the single normalized clock for one menu entrance or Settings replay.
/// Removing this view cancels SwiftUI's presentation transaction; there are no
/// delayed callbacks or per-wedge tasks that can survive HUD teardown.
struct HUDOpeningMotion<Content: View>: View {
    let request: HUDOpeningMotionRequest
    let settleID: Int
    @ViewBuilder let content: (HUDOpeningMotionFrame) -> Content

    @State private var progress: CGFloat

    init(
        request: HUDOpeningMotionRequest,
        settleID: Int,
        @ViewBuilder content: @escaping (HUDOpeningMotionFrame) -> Content
    ) {
        self.request = request
        self.settleID = settleID
        self.content = content
        _progress = State(initialValue: request.shouldAnimate ? 0 : 1)
    }

    var body: some View {
        content(HUDOpeningMotionFrame.resolve(
            descriptor: request.descriptor,
            progress: progress
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
