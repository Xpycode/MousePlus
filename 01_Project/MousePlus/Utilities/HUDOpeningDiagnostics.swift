#if DEBUG
import Foundation
import AppKit
import OSLog

/// Bounded diagnostics for the runtime-only opening regression. One instance
/// belongs to one panel; no timers, observable state, item labels, or actions
/// are recorded. Release builds contain no logging owner.
@MainActor
final class HUDOpeningDiagnostics {
    private static let logger = Logger(subsystem: "com.xpycode.MousePlus", category: "HUDOpening")
    private let invocation: Int
    private var stages: Set<String> = []
    private var recordedInterruption = false
    private var sawIntermediateFrame = false
    private var latestProgress: CGFloat = 0

    init(invocation: Int, configuration: HUDMotionConfiguration, triggerPoint: CGPoint) {
        self.invocation = invocation
        Self.logger.notice("Opening \(invocation): mount selected=\(configuration.summon.rawValue, privacy: .public) enabled=\(configuration.isEnabled) duration=\(configuration.baseDuration)")
        let pointer = NSEvent.mouseLocation
        Self.logger.notice("Opening \(invocation): trigger=(\(Double(triggerPoint.x)),\(Double(triggerPoint.y))) pointer=(\(Double(pointer.x)),\(Double(pointer.y)))")
    }

    func mounted(point: CGPoint, center: CGPoint) {
        Self.logger.notice("Opening \(self.invocation): mounted pointerLocal=(\(Double(point.x)),\(Double(point.y))) center=(\(Double(center.x)),\(Double(center.y)))")
    }

    func replay() {
        Self.logger.notice("Opening \(self.invocation): post-mount replay requested")
    }

    func record(_ frame: HUDOpeningMotionFrame) {
        latestProgress = frame.progress
        let stage: String
        if frame.artworkOpacity == 0 && frame.centerOpacity == 0 {
            stage = "concealed"
        } else if frame.progress == 0 {
            stage = "start"
        } else if frame.progress < 1 {
            stage = "intermediate"
            sawIntermediateFrame = true
        } else {
            // SwiftUI can evaluate the target before interpolated frames.
            // This event is not evidence that visible playback has finished.
            stage = "endpoint evaluation"
        }
        guard stages.insert(stage).inserted else { return }
        let effect = String(describing: frame.effect)
        Self.logger.notice("Opening \(self.invocation): \(stage, privacy: .public) effect=\(effect, privacy: .public) progress=\(Double(frame.progress)) intermediateSeen=\(self.sawIntermediateFrame)")
    }

    func settle(_ reason: String) {
        guard !recordedInterruption else { return }
        recordedInterruption = true
        let pointer = NSEvent.mouseLocation
        Self.logger.notice("Opening \(self.invocation): settle reason=\(reason, privacy: .public) progress=\(Double(self.latestProgress)) intermediateSeen=\(self.sawIntermediateFrame)")
        Self.logger.notice("Opening \(self.invocation): settle pointer=(\(Double(pointer.x)),\(Double(pointer.y)))")
    }
}
#endif
