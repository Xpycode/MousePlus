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
    private var hoverStages: Set<String> = []

    init(invocation: Int, configuration: HUDMotionConfiguration, triggerPoint: CGPoint,
         source: TriggerSource, commitsOnPointerRelease: Bool) {
        self.invocation = invocation
        let sourceName = String(describing: source)
        Self.logger.notice("Opening \(invocation): source=\(sourceName, privacy: .public) tapToggle=\(commitsOnPointerRelease)")
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

    /// At most two samples per invocation: initial hover and first valid aim.
    /// Compare deltas from each center; the host includes panel padding while
    /// the SwiftUI hit surface does not. Absolute local points differ normally.
    func hover(point: CGPoint, center: CGPoint, hasSelection: Bool,
               screenPoint: CGPoint, nativeCoordinates: (point: CGPoint, center: CGPoint)?,
               deadZoneRadius: CGFloat) {
        let stage = hasSelection ? "first selected hover" : "first unselected hover"
        guard hoverStages.insert(stage).inserted else { return }
        Self.logger.notice("Opening \(self.invocation): \(stage, privacy: .public) local=(\(Double(point.x)),\(Double(point.y))) center=(\(Double(center.x)),\(Double(center.y))) deadZone=\(Double(deadZoneRadius))")
        Self.logger.notice("Opening \(self.invocation): hover screen=(\(Double(screenPoint.x)),\(Double(screenPoint.y)))")
        if let nativeCoordinates {
            let delta = CGPoint(x: nativeCoordinates.point.x - nativeCoordinates.center.x,
                                y: nativeCoordinates.point.y - nativeCoordinates.center.y)
            Self.logger.notice("Opening \(self.invocation): hover nativeDelta=(\(Double(delta.x)),\(Double(delta.y)))")
        }
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
