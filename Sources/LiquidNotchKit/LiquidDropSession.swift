import SwiftUI
import Observation
import Foundation

@MainActor @Observable public final class LiquidDropSession {
    public enum Phase: Equatable { case idle, pulling, shelf, retracting, absorbing }
    public private(set) var phase: Phase = .idle
    public private(set) var pull: CGFloat = 0
    public private(set) var offsetX: CGFloat = 0
    public private(set) var targeted = false
    public private(set) var dwellProgress: CGFloat = 0
    public private(set) var absorbProgress: CGFloat = 0
    public private(set) var metrics = LiquidNotchMetrics(bodyWidth: 180, bodyHeight: 24)
    public private(set) var isExternalDragActive = false
    @ObservationIgnored private var desiredPull: CGFloat = 0
    @ObservationIgnored private var desiredX: CGFloat = 0
    @ObservationIgnored private var velocityY: CGFloat = 0
    @ObservationIgnored private var velocityX: CGFloat = 0
    @ObservationIgnored private var enteredTargetAt: TimeInterval?
    @ObservationIgnored private var settleStartedAt: TimeInterval = 0
    @ObservationIgnored private var latestPoint: CGPoint?

    public init() {}

    public var showsDroplet: Bool {
        phase == .pulling || phase == .retracting || phase == .absorbing
    }

    func begin(metrics: LiquidNotchMetrics, expanded: Bool) {
        if isExternalDragActive { return }
        self.metrics = metrics
        phase = expanded ? .shelf : .pulling
        isExternalDragActive = true
        absorbProgress = 0
        enteredTargetAt = nil
        targeted = false
        dwellProgress = 0
    }

    func track(_ point: CGPoint, bounds: CGRect, configuration: LiquidDropConfiguration) {
        latestPoint = point
        guard isExternalDragActive else { return }
        if configuration.isExpanded() || phase == .shelf {
            desiredPull = 0
            desiredX = 0
            return
        }
        guard configuration.captureContains(point, in: bounds) else {
            clearDwell()
            desiredPull = 0
            desiredX = 0
            return
        }
        let dx = point.x - bounds.midX
        let influence = pow(max(0, 1 - abs(dx) / max(1, configuration.captureHalfWidth)), 0.55)
        let dy = max(0, point.y - bounds.minY)
        let bulbRadius: CGFloat = 32
        let extra = min(configuration.maximumPull, max(18, dy - metrics.bodyHeight + bulbRadius))
        desiredPull = extra * influence
        desiredX = min(36, max(-36, dx * 0.65)) * influence
    }

    public func accepts(_ point: CGPoint, in bounds: CGRect, configuration: LiquidDropConfiguration) -> Bool {
        guard isExternalDragActive, configuration.canAcceptDrops() else { return false }
        if configuration.isExpanded() {
            let m = configuration.currentMetrics()
            return m.isVisible && m.interactiveRect(in: bounds).contains(point)
        }
        let shape = LiquidNotchDropletShape(metrics: metrics, pull: pull, offsetX: offsetX)
        if shape.path(in: bounds).contains(point) {
            return true
        }
        // Also accept within the active bulb area so targeted is reliable
        let amount = min(1, pull / 64)
        let radius: CGFloat = 32 * amount
        let cx = bounds.midX + offsetX * amount
        let baseY = bounds.minY + metrics.bodyHeight
        let bulbY = baseY + pull - radius
        let dist = hypot(point.x - cx, point.y - bulbY)
        return dist <= radius + 12
    }

    /// A single physics clock updates both the visible contour and its drop geometry.
    /// Dwell uses monotonic time; there is no sleeping task that can fire after cancellation.
    func advance(dt: TimeInterval, now: TimeInterval, bounds: CGRect,
                 nativeDragInside: Bool, buttonDown: Bool, configuration: LiquidDropConfiguration) {
        let delta = min(1.0 / 30, max(1.0 / 240, dt))
        if configuration.reduceMotion() {
            pull = desiredPull
            offsetX = desiredX
            velocityX = 0
            velocityY = 0
        } else {
            let frequency: CGFloat = phase == .absorbing || phase == .retracting ? 19 : 23
            let damping: CGFloat = phase == .absorbing ? 0.62 : 0.83
            // Small substeps keep the spring stable after a temporarily busy main thread.
            for _ in 0..<2 {
                let step = CGFloat(delta / 2)
                velocityY += ((desiredPull - pull) * frequency * frequency - 2 * damping * frequency * velocityY) * step
                velocityX += ((desiredX - offsetX) * frequency * frequency - 2 * damping * frequency * velocityX) * step
                pull = max(0, pull + velocityY * step)
                offsetX += velocityX * step
            }
        }

        if phase == .absorbing || phase == .retracting {
            absorbProgress = phase == .absorbing ? min(1, CGFloat((now - settleStartedAt) / 0.28)) : 0
            if now - settleStartedAt >= 0.55 {
                phase = .idle
                pull = 0
                offsetX = 0
                velocityX = 0
                velocityY = 0
            }
            return
        }
        guard isExternalDragActive, let point = latestPoint else { clearDwell(); return }
        targeted = nativeDragInside && accepts(point, in: bounds, configuration: configuration)
        guard phase == .pulling, targeted, nativeDragInside, buttonDown else {
            enteredTargetAt = nil
            dwellProgress = 0
            return
        }
        if enteredTargetAt == nil { enteredTargetAt = now }
        let elapsed = now - (enteredTargetAt ?? now)
        dwellProgress = min(1, CGFloat(elapsed / max(0.01, configuration.dwellDuration)))
        if elapsed >= configuration.dwellDuration {
            phase = .shelf
            clearDwell()
            desiredPull = 0
            desiredX = 0
            configuration.log("dwell completed; opening shelf")
            configuration.requestShelf()
        }
    }

    func clearDwell() {
        enteredTargetAt = nil
        if targeted { targeted = false }
        if dwellProgress != 0 { dwellProgress = 0 }
    }

    func finish(accepted: Bool, now: TimeInterval) {
        guard isExternalDragActive else { return }
        isExternalDragActive = false
        phase = accepted ? .absorbing : .retracting
        desiredPull = 0
        desiredX = 0
        settleStartedAt = now
        clearDwell()
    }
}
