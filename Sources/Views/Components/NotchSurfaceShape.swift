import SwiftUI

public struct NotchSurfaceShape: Shape {
    public var cornerRadius: CGFloat
    public var shoulderWidth: CGFloat
    public var shoulderHeight: CGFloat

    public var animatableData: AnimatablePair<CGFloat, AnimatablePair<CGFloat, CGFloat>> {
        get { AnimatablePair(cornerRadius, AnimatablePair(shoulderWidth, shoulderHeight)) }
        set {
            cornerRadius = newValue.first
            shoulderWidth = newValue.second.first
            shoulderHeight = newValue.second.second
        }
    }

    public init(cornerRadius: CGFloat = 30, shoulderWidth: CGFloat = 16, shoulderHeight: CGFloat = 14) {
        self.cornerRadius = cornerRadius
        self.shoulderWidth = shoulderWidth
        self.shoulderHeight = shoulderHeight
    }

    public func path(in rect: CGRect) -> Path {
        guard rect.width > 0, rect.height > 0 else { return Path() }
        let sw = min(max(0, shoulderWidth), rect.width * 0.24)
        let sh = min(max(0, shoulderHeight), rect.height * 0.5)
        let left = rect.minX + sw
        let right = rect.maxX - sw
        let top = rect.minY
        let bottom = rect.maxY
        let radius = min(max(0, cornerRadius), (right - left) * 0.5, rect.height - sh)
        let c: CGFloat = 0.55228475

        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: top))
        path.addCurve(
            to: CGPoint(x: left, y: top + sh),
            control1: CGPoint(x: rect.minX + sw * 0.60, y: top),
            control2: CGPoint(x: left, y: top + sh * 0.08)
        )
        path.addLine(to: CGPoint(x: left, y: bottom - radius))
        path.addCurve(
            to: CGPoint(x: left + radius, y: bottom),
            control1: CGPoint(x: left, y: bottom - radius + radius * c),
            control2: CGPoint(x: left + radius - radius * c, y: bottom)
        )
        path.addLine(to: CGPoint(x: right - radius, y: bottom))
        path.addCurve(
            to: CGPoint(x: right, y: bottom - radius),
            control1: CGPoint(x: right - radius + radius * c, y: bottom),
            control2: CGPoint(x: right, y: bottom - radius + radius * c)
        )
        path.addLine(to: CGPoint(x: right, y: top + sh))
        path.addCurve(
            to: CGPoint(x: rect.maxX, y: top),
            control1: CGPoint(x: right, y: top + sh * 0.08),
            control2: CGPoint(x: rect.maxX - sw * 0.60, y: top)
        )
        path.closeSubpath()
        return path
    }
}
