import SwiftUI
import AppKit

public struct LiquidNotchMetrics {
    public var bodyWidth: CGFloat
    public var bodyHeight: CGFloat
    public var cornerRadius: CGFloat
    public var shoulderWidth: CGFloat
    public var additionalHitHeight: CGFloat
    public var isVisible: Bool

    public init(bodyWidth: CGFloat, bodyHeight: CGFloat, cornerRadius: CGFloat = 12,
                shoulderWidth: CGFloat = 16, additionalHitHeight: CGFloat = 0, isVisible: Bool = true) {
        self.bodyWidth = max(1, bodyWidth)
        self.bodyHeight = max(1, bodyHeight)
        self.cornerRadius = max(0, cornerRadius)
        self.shoulderWidth = max(0, shoulderWidth)
        self.additionalHitHeight = max(0, additionalHitHeight)
        self.isVisible = isVisible
    }

    public func interactiveRect(in bounds: CGRect) -> CGRect {
        CGRect(x: bounds.midX - (bodyWidth + shoulderWidth * 2) / 2, y: bounds.minY,
               width: bodyWidth + shoulderWidth * 2, height: bodyHeight + additionalHitHeight)
    }
}

@MainActor public struct LiquidDropConfiguration {
    /// Preallocate the full drag field and the largest normal panel. Do not shrink during a drag.
    public var receiverSize = CGSize(width: 640, height: 480)
    public var captureHalfWidth: CGFloat = 280
    public var captureHeight: CGFloat = 300
    public var maximumPull: CGFloat = 220
    public var dwellDuration: TimeInterval = 0.5
    /// A very low alpha keeps the armed drag surface nonempty for window-server hit testing.
    public var receiverPaintAlpha: CGFloat = 0.02
    public var currentMetrics: () -> LiquidNotchMetrics
    public var isExpanded: () -> Bool
    public var canAcceptDrops: () -> Bool = { true }
    public var requestShelf: () -> Void
    public var receiveFiles: ([URL]) -> Void
    public var activityChanged: (Bool) -> Void = { _ in }
    public var reportError: (Error) -> Void = { _ in }
    public var log: (String) -> Void = { _ in }
    public var reduceMotion: () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    public init(currentMetrics: @escaping () -> LiquidNotchMetrics,
                isExpanded: @escaping () -> Bool,
                requestShelf: @escaping () -> Void,
                receiveFiles: @escaping ([URL]) -> Void) {
        self.currentMetrics = currentMetrics
        self.isExpanded = isExpanded
        self.requestShelf = requestShelf
        self.receiveFiles = receiveFiles
    }

    public func captureContains(_ point: CGPoint, in bounds: CGRect) -> Bool {
        let metrics = currentMetrics()
        let halfWidth = isExpanded() ? max(captureHalfWidth, metrics.bodyWidth / 2 + metrics.shoulderWidth) : captureHalfWidth
        let height = isExpanded() ? max(captureHeight, metrics.bodyHeight + metrics.additionalHitHeight) : captureHeight
        return abs(point.x - bounds.midX) <= min(halfWidth, bounds.width / 2)
            && point.y >= bounds.minY && point.y <= min(bounds.maxY, bounds.minY + height)
    }
}

/// The same path is used for painting and for the actual drop test.
/// All segments remain present at zero pull, so the contour never switches topology.
public struct LiquidNotchDropletShape: Shape {
    public var bodyWidth: CGFloat
    public var bodyHeight: CGFloat
    public var cornerRadius: CGFloat
    public var shoulderWidth: CGFloat
    public var pull: CGFloat
    public var offsetX: CGFloat

    public init(metrics: LiquidNotchMetrics, pull: CGFloat, offsetX: CGFloat) {
        bodyWidth = metrics.bodyWidth
        bodyHeight = metrics.bodyHeight
        cornerRadius = metrics.cornerRadius
        shoulderWidth = metrics.shoulderWidth
        self.pull = pull
        self.offsetX = offsetX
    }

    public func path(in rect: CGRect) -> Path {
        guard rect.width > 0, rect.height > 0 else { return Path() }
        let sw = min(shoulderWidth, rect.width * 0.20)
        let width = min(max(1, bodyWidth), rect.width - sw * 2)
        let height = min(max(1, bodyHeight), rect.height)
        let sh = min(14, height * 0.5)
        let radius = min(cornerRadius, width / 2, height - sh)
        let extensionY = min(max(0, pull), max(0, rect.height - height))
        let amount = min(1, extensionY / 64)
        let bulbRadius = 28 * amount
        let join = min(width / 2 - radius, 44) * amount
        let waist = 10 * amount
        let cx = rect.midX
        let baseY = rect.minY + height
        let left = cx - width / 2
        let right = cx + width / 2
        let shift = offsetX * amount
        let bulbX = cx + shift
        let bulbY = baseY + extensionY - bulbRadius
        let waistY = baseY + max(0, bulbY - baseY) * 0.46
        let rise = waistY - baseY
        let fall = bulbY - waistY
        let waistX = cx + shift * 0.52
        let c: CGFloat = 0.55228475

        var p = Path()
        p.move(to: CGPoint(x: left - sw, y: rect.minY))
        p.addCurve(to: CGPoint(x: left, y: rect.minY + sh),
                   control1: CGPoint(x: left - sw * 0.4, y: rect.minY),
                   control2: CGPoint(x: left, y: rect.minY + sh * 0.08))
        p.addLine(to: CGPoint(x: left, y: baseY - radius))
        p.addCurve(to: CGPoint(x: left + radius, y: baseY),
                   control1: CGPoint(x: left, y: baseY - radius + radius * c),
                   control2: CGPoint(x: left + radius - radius * c, y: baseY))
        p.addLine(to: CGPoint(x: cx - join, y: baseY))
        p.addCurve(to: CGPoint(x: waistX - waist, y: waistY),
                   control1: CGPoint(x: cx - join * 0.40, y: baseY),
                   control2: CGPoint(x: waistX - waist, y: waistY - rise * 0.35))
        p.addCurve(to: CGPoint(x: bulbX - bulbRadius, y: bulbY),
                   control1: CGPoint(x: waistX - waist, y: waistY + fall * 0.35),
                   control2: CGPoint(x: bulbX - bulbRadius, y: bulbY - fall * 0.60))
        p.addCurve(to: CGPoint(x: bulbX, y: bulbY + bulbRadius),
                   control1: CGPoint(x: bulbX - bulbRadius, y: bulbY + bulbRadius * c),
                   control2: CGPoint(x: bulbX - bulbRadius * c, y: bulbY + bulbRadius))
        p.addCurve(to: CGPoint(x: bulbX + bulbRadius, y: bulbY),
                   control1: CGPoint(x: bulbX + bulbRadius * c, y: bulbY + bulbRadius),
                   control2: CGPoint(x: bulbX + bulbRadius, y: bulbY + bulbRadius * c))
        p.addCurve(to: CGPoint(x: waistX + waist, y: waistY),
                   control1: CGPoint(x: bulbX + bulbRadius, y: bulbY - fall * 0.60),
                   control2: CGPoint(x: waistX + waist, y: waistY + fall * 0.35))
        p.addCurve(to: CGPoint(x: cx + join, y: baseY),
                   control1: CGPoint(x: waistX + waist, y: waistY - rise * 0.35),
                   control2: CGPoint(x: cx + join * 0.40, y: baseY))
        p.addLine(to: CGPoint(x: right - radius, y: baseY))
        p.addCurve(to: CGPoint(x: right, y: baseY - radius),
                   control1: CGPoint(x: right - radius + radius * c, y: baseY),
                   control2: CGPoint(x: right, y: baseY - radius + radius * c))
        p.addLine(to: CGPoint(x: right, y: rect.minY + sh))
        p.addCurve(to: CGPoint(x: right + sw, y: rect.minY),
                   control1: CGPoint(x: right, y: rect.minY + sh * 0.08),
                   control2: CGPoint(x: right + sw * 0.4, y: rect.minY))
        p.closeSubpath()
        return p
    }
}
